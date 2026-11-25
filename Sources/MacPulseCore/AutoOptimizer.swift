import Foundation
import Darwin

public struct AutoOptimizeConfig: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var intervalHours: Int                  // 2, 6, 12, 24
    public var staleCacheDays: Int                 // 3, 7, 14
    public var lowDiskTriggerGB: Double            // 20, 30, 40
    public var autoCleanStaleCaches: Bool          // Browser + AI + Dev stale files > N days
    public var autoCleanUpdaterGarbage: Bool       // ShipIt, openmausbot-updater, QuickLook (> 24h)
    public var autoTruncateOversizedLogs: Bool     // LocalWP logs > 15 MB
    public var autoCleanOrphanTempProfiles: Bool   // Dead /tmp playwright/puppeteer/agent-browser dirs

    public init(
        isEnabled: Bool = true,
        intervalHours: Int = 6,
        staleCacheDays: Int = 7,
        lowDiskTriggerGB: Double = 30.0,
        autoCleanStaleCaches: Bool = true,
        autoCleanUpdaterGarbage: Bool = true,
        autoTruncateOversizedLogs: Bool = true,
        autoCleanOrphanTempProfiles: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.intervalHours = intervalHours
        self.staleCacheDays = staleCacheDays
        self.lowDiskTriggerGB = lowDiskTriggerGB
        self.autoCleanStaleCaches = autoCleanStaleCaches
        self.autoCleanUpdaterGarbage = autoCleanUpdaterGarbage
        self.autoTruncateOversizedLogs = autoTruncateOversizedLogs
        self.autoCleanOrphanTempProfiles = autoCleanOrphanTempProfiles
    }
}

public enum AutoOptimizeTrigger: String, Codable, Sendable, Equatable {
    case scheduled = "Định kỳ"
    case lowDisk = "SSD thấp"
    case manual = "Thủ công"
}

public struct AutoOptimizeRunRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let trigger: AutoOptimizeTrigger
    public let freedBytes: UInt64
    public let removedFilesCount: Int
    public let truncatedLogsCount: Int
    public let cleanedOrphanProfilesCount: Int
    public let summary: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        trigger: AutoOptimizeTrigger,
        freedBytes: UInt64,
        removedFilesCount: Int,
        truncatedLogsCount: Int,
        cleanedOrphanProfilesCount: Int,
        summary: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.trigger = trigger
        self.freedBytes = freedBytes
        self.removedFilesCount = removedFilesCount
        self.truncatedLogsCount = truncatedLogsCount
        self.cleanedOrphanProfilesCount = cleanedOrphanProfilesCount
        self.summary = summary
    }
}

public struct PersistedAutoOptimizeState: Codable, Sendable, Equatable {
    public var config: AutoOptimizeConfig
    public var lastRunAt: Date?
    public var totalLifetimeFreedBytes: UInt64
    public var history: [AutoOptimizeRunRecord]

    public init(
        config: AutoOptimizeConfig = AutoOptimizeConfig(),
        lastRunAt: Date? = nil,
        totalLifetimeFreedBytes: UInt64 = 0,
        history: [AutoOptimizeRunRecord] = []
    ) {
        self.config = config
        self.lastRunAt = lastRunAt
        self.totalLifetimeFreedBytes = totalLifetimeFreedBytes
        self.history = history
    }
}

public final class AutoOptimizerStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            self.fileURL = appSupport
                .appendingPathComponent("MacPulse", isDirectory: true)
                .appendingPathComponent("auto-optimize.json")
        }
    }

    public func load() -> PersistedAutoOptimizeState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PersistedAutoOptimizeState.self, from: data) else {
            return PersistedAutoOptimizeState()
        }
        return decoded
    }

    public func save(_ state: PersistedAutoOptimizeState) throws {
        lock.lock()
        defer { lock.unlock() }
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum AutoOptimizerEngine {
    /// Determines whether Autopilot should run right now based on schedule or low-disk pressure.
    /// Enforces a minimum 60-minute cooldown so it never thrashes the SSD.
    public static func evaluateTrigger(
        config: AutoOptimizeConfig,
        lastRunAt: Date?,
        availableDiskGB: Double,
        cpuBusyPercent: Double,
        now: Date = Date()
    ) -> AutoOptimizeTrigger? {
        guard config.isEnabled else { return nil }
        // Never compete with heavy user workload (building, rendering, etc.)
        if cpuBusyPercent >= 65.0 { return nil }

        let elapsedSinceLast = lastRunAt.map { now.timeIntervalSince($0) } ?? .infinity
        let minCooldown: TimeInterval = 3600 // 60 mins minimum between automatic runs
        guard elapsedSinceLast >= minCooldown else { return nil }

        if availableDiskGB > 0 && availableDiskGB < config.lowDiskTriggerGB {
            return .lowDisk
        }

        let intervalSecs = TimeInterval(max(1, config.intervalHours) * 3600)
        if elapsedSinceLast >= intervalSecs {
            return .scheduled
        }

        return nil
    }

    /// Runs a 100% safe, non-destructive background optimization pass:
    /// - Removes stale cache files not accessed/modified within `staleCacheDays`
    /// - Removes old updater/ShipIt/QuickLook garbage (> 24h)
    /// - Truncates oversized LocalWP logs (> 15 MB) in-place
    /// - Removes dead /tmp automation profile directories not used by any live process
    /// NEVER touches Trash, Cookies, Chrome Extensions, Sessions, Databases, or AI models.
    public static func runPass(
        config: AutoOptimizeConfig,
        trigger: AutoOptimizeTrigger,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        tempDirectory: URL = URL(fileURLWithPath: "/tmp"),
        liveProcessArgs: [String]? = nil,
        now: Date = Date()
    ) -> AutoOptimizeRunRecord {
        let fm = FileManager.default
        let canonicalHome = homeDirectory.resolvingSymlinksInPath().path
        var totalFreed: UInt64 = 0
        var removedFiles = 0
        var truncatedLogs = 0
        var cleanedProfiles = 0

        // 1. Safe updater & ephemeral OS/AI garbage (always safe even when apps are open)
        // Automatic runs wait 24h; manual "Tối ưu ngay" waits 2h so actively downloading updates stay untouched.
        if config.autoCleanUpdaterGarbage {
            let updaterBuffer: TimeInterval = (trigger == .manual) ? 7200 : 86400
            let updaterCutoff = now.addingTimeInterval(-updaterBuffer)
            let updaterDirs = [
                "Library/Caches/com.google.antigravity.ShipIt",
                "Library/Caches/com.google.antigravity/pending",
                "Library/Caches/openmausbot-updater",
                "Library/Caches/com.microsoft.VSCode.ShipIt",
                "Library/Caches/com.anthropic.claudedesktop.ShipIt",
                "Library/Caches/com.apple.QuickLook.thumbnailcache",
                ".codex/tmp",
                ".gemini/logs"
            ]
            for rel in updaterDirs {
                let dirURL = homeDirectory.appendingPathComponent(rel)
                let res = sweepStaleFiles(
                    in: dirURL,
                    cutoffDate: updaterCutoff,
                    canonicalHome: canonicalHome,
                    includePackages: true,
                    fm: fm
                )
                totalFreed += res.freedBytes
                removedFiles += res.removedCount
            }
        }

        // 2. Stale cache files older than N days across browsers, AI tools, and dev package caches
        if config.autoCleanStaleCaches {
            let days = max(1, config.staleCacheDays)
            let staleCutoff = now.addingTimeInterval(-TimeInterval(days * 86400))
            // Pure OS caches (~/Library/Caches/...) never contain Extensions, Cookies, or user logins
            var staleTargets = [
                "Library/Caches/Google/Chrome",
                "Library/Caches/BraveSoftware",
                "Library/Caches/Microsoft Edge",
                "Library/Caches/com.apple.Safari",
                "Library/Caches/company.thebrowser.Browser",
                "Library/Caches/Firefox",
                "Library/Caches/com.google.antigravity",
                "Library/Caches/com.microsoft.VSCode",
                "Library/Caches/Homebrew",
                "Library/Caches/pip",
                "Library/Caches/composer",
                "Library/Caches/bun",
                "Library/Caches/Yarn",
                "Library/Caches/org.swift.swiftpm",
                "Library/Application Support/Cursor/CachedData",
                "Library/Application Support/Cursor/GPUCache",
                "Library/Application Support/Cursor/logs",
                "Library/Caches/cursor-compile-cache",
                "Library/Caches/Codex",
                "Library/Caches/com.openai.codex",
                "Library/Caches/com.anthropic.claudedesktop",
                ".npm/_cacache",
                ".cache/uv",
                ".cache/pip",
                ".cache/opencode-antigravity-npm",
                ".cache/opencode",
                ".claude/logs"
            ]
            staleTargets.append(contentsOf: CleanupScanner.openMausBotSafeCacheRelativePaths(homeDirectory: homeDirectory))

            var visited = Set<String>()
            for rel in staleTargets where visited.insert(rel).inserted {
                let dirURL = homeDirectory.appendingPathComponent(rel)
                let res = sweepStaleFiles(
                    in: dirURL,
                    cutoffDate: staleCutoff,
                    canonicalHome: canonicalHome,
                    includePackages: false,
                    fm: fm
                )
                totalFreed += res.freedBytes
                removedFiles += res.removedCount
            }
        }

        // 3. Truncate oversized LocalWP logs (> 15 MB) safely in-place
        if config.autoTruncateOversizedLogs {
            let logThreshold: UInt64 = 15 * 1_048_576
            let localSitesURL = homeDirectory.appendingPathComponent("Local Sites")
            if let siteDirs = try? fm.contentsOfDirectory(at: localSitesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for site in siteDirs {
                    let logsDir = site.appendingPathComponent("logs")
                    guard fm.fileExists(atPath: logsDir.path) else { continue }
                    if let en = fm.enumerator(at: logsDir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey]) {
                        for case let fileURL as URL in en {
                            guard fileURL.pathExtension.lowercased() == "log" || fileURL.lastPathComponent.contains("error.log") else { continue }
                            guard isInsideAllowedHome(url: fileURL, canonicalHome: canonicalHome) else { continue }
                            let sz = CleanupScanner.fileSize(at: fileURL)
                            if sz >= logThreshold {
                                if let handle = try? FileHandle(forWritingTo: fileURL) {
                                    do {
                                        try handle.truncate(atOffset: 0)
                                        try handle.close()
                                        totalFreed += sz
                                        truncatedLogs += 1
                                    } catch {
                                        try? handle.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 4. Clean dead /tmp automation profile dirs older than 30 mins and NOT referenced by any live process
        if config.autoCleanOrphanTempProfiles {
            let activeArgs: [String]
            if let injected = liveProcessArgs {
                activeArgs = injected.map { $0.lowercased() }
            } else {
                let live = (try? ProcessScanner.scanLiveProcesses()) ?? []
                activeArgs = live.map { $0.args.lowercased() }
            }
            let orphanCutoff = now.addingTimeInterval(-1800) // 30 mins

            if let tmpEntries = try? fm.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for entry in tmpEntries {
                    let name = entry.lastPathComponent
                    guard name.hasPrefix("playwright_chromiumdev_profile-")
                        || name.hasPrefix("puppeteer_dev_chrome_profile-")
                        || name.hasPrefix("agent-browser-") else { continue }

                    let lowerName = name.lowercased()
                    let inUse = activeArgs.contains { $0.contains(lowerName) }
                    if inUse { continue }

                    let mtime = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
                    guard mtime < orphanCutoff else { continue }

                    let sz = CleanupScanner.directorySize(at: entry)
                    if (try? fm.removeItem(at: entry)) != nil {
                        totalFreed += sz
                        cleanedProfiles += 1
                    }
                }
            }
        }

        var parts: [String] = []
        if totalFreed > 0 {
            parts.append("Giải phóng \(Formatters.bytes(totalFreed))")
        }
        if removedFiles > 0 {
            parts.append("\(removedFiles) tệp cache cũ")
        }
        if truncatedLogs > 0 {
            parts.append("\(truncatedLogs) file log lớn")
        }
        if cleanedProfiles > 0 {
            parts.append("\(cleanedProfiles) profile tạm mồ côi")
        }

        let summary = parts.isEmpty
            ? "Hệ thống đã sạch — không có cache cũ hoặc rác thừa cần dọn."
            : parts.joined(separator: " • ")

        return AutoOptimizeRunRecord(
            timestamp: now,
            trigger: trigger,
            freedBytes: totalFreed,
            removedFilesCount: removedFiles,
            truncatedLogsCount: truncatedLogs,
            cleanedOrphanProfilesCount: cleanedProfiles,
            summary: summary
        )
    }

    /// Recursively sweeps regular files (and optionally stale .app updater packages) whose latest
    /// activity (max of access & modification date) is strictly older than `cutoffDate`.
    /// Skips symlinks and locked files safely, then prunes any strictly empty child folders left behind.
    public static func sweepStaleFiles(
        in dirURL: URL,
        cutoffDate: Date,
        canonicalHome: String,
        includePackages: Bool = false,
        fm: FileManager = .default
    ) -> (freedBytes: UInt64, removedCount: Int) {
        guard isInsideAllowedHome(url: dirURL, canonicalHome: canonicalHome),
              fm.fileExists(atPath: dirURL.path) else {
            return (0, 0)
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]

        guard let en = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        var freed: UInt64 = 0
        var count = 0
        var subdirs: [URL] = []

        for case let fileURL as URL in en {
            guard let vals = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if vals.isSymbolicLink == true { continue }

            // Handle unpacked .app packages inside ShipIt/updater directories
            if includePackages && vals.isPackage == true {
                let mDate = vals.contentModificationDate ?? .distantPast
                let aDate = vals.contentAccessDate ?? mDate
                let lastTouched = max(mDate, aDate)
                if lastTouched < cutoffDate {
                    let sz = CleanupScanner.directorySize(at: fileURL)
                    do {
                        try fm.removeItem(at: fileURL)
                        freed += sz
                        count += 1
                    } catch {
                        // Locked by live app — skip safely
                    }
                }
                continue
            }

            if vals.isDirectory == true {
                if vals.isPackage != true {
                    subdirs.append(fileURL)
                }
                continue
            }

            guard vals.isRegularFile == true else { continue }

            let mDate = vals.contentModificationDate ?? .distantPast
            let aDate = vals.contentAccessDate ?? mDate
            // Conservative: use the NEWER of modification & access time so actively read caches stay intact
            let lastTouched = max(mDate, aDate)
            guard lastTouched < cutoffDate else { continue }

            let sz = UInt64(max(0, vals.totalFileAllocatedSize ?? vals.fileSize ?? 0))
            do {
                try fm.removeItem(at: fileURL)
                freed += sz
                count += 1
            } catch {
                // File currently locked by a live app — safely skip
                continue
            }
        }

        // Prune strictly empty leaf subdirectories left behind (deepest paths first, never dirURL itself)
        if count > 0 && !subdirs.isEmpty {
            let sortedSubdirs = subdirs.sorted { $0.pathComponents.count > $1.pathComponents.count }
            for sub in sortedSubdirs {
                guard isInsideAllowedHome(url: sub, canonicalHome: canonicalHome),
                      let entries = try? fm.contentsOfDirectory(atPath: sub.path),
                      entries.isEmpty else { continue }
                try? fm.removeItem(at: sub)
            }
        }

        return (freed, count)
    }

    private static func isInsideAllowedHome(url: URL, canonicalHome: String) -> Bool {
        let resolved = url.resolvingSymlinksInPath().path
        return resolved.hasPrefix(canonicalHome + "/") && resolved.count > canonicalHome.count + 2
    }
}
