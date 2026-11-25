import Foundation
import Darwin

public struct TrackedGUIApp: Identifiable, Codable, Sendable, Equatable {
    public let id: String          // bundleID
    public let bundleID: String
    public let name: String
    public let pid: pid_t
    public let isFrontmost: Bool
    public let lastActiveAt: Date
    public let rssBytes: UInt64
    public let cpuPercent: Double

    public init(
        bundleID: String,
        name: String,
        pid: pid_t,
        isFrontmost: Bool,
        lastActiveAt: Date,
        rssBytes: UInt64,
        cpuPercent: Double
    ) {
        self.id = bundleID
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
        self.isFrontmost = isFrontmost
        self.lastActiveAt = lastActiveAt
        self.rssBytes = rssBytes
        self.cpuPercent = cpuPercent
    }

    public func idleMinutes(relativeTo now: Date = Date()) -> Int {
        if isFrontmost { return 0 }
        return max(0, Int(now.timeIntervalSince(lastActiveAt) / 60.0))
    }
}

public struct AutoOptimizeConfig: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var intervalHours: Int                  // 1, 2, 6, 12, 24
    public var staleCacheDays: Int                 // 1, 3, 7, 14
    public var lowDiskTriggerGB: Double            // 20, 30, 40
    public var autoCleanStaleCaches: Bool          // Browser + AI + Dev stale files > N days
    public var autoCleanUpdaterGarbage: Bool       // ShipIt, openmausbot-updater, QuickLook
    public var autoTruncateOversizedLogs: Bool     // LocalWP logs > 15 MB
    public var autoCleanOrphanTempProfiles: Bool   // Dead /tmp playwright/puppeteer/agent-browser dirs
    public var autoCloseIdleApps: Bool             // Politely Cmd+Q unused background GUI apps
    public var idleAppTimeoutMinutes: Int          // 30, 60, 120, 240
    public var autoThrottleBackgroundHogs: Bool    // Politely nice +10 noisy Spotlight/iCloud/Photos indexers
    public var autoHealStuckReplayd: Bool          // Automatically restart wedged macOS replayd spinning on XPC
    public var customProtectedBundleIDs: [String]  // Extra apps user locked from auto-close
    public var unlockedDefaultBundleIDs: [String]  // Default-protected apps user explicitly allowed to auto-close

    /// Built-in Work-Safe apps that Autopilot NEVER auto-closes unless explicitly unlocked by the user.
    public static let defaultProtectedBundleIDs: Set<String> = [
        // Core macOS & MacPulse
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.ActivityMonitor",
        "com.apple.ScreenSharing",
        "com.ducdung.MacPulse",
        "com.skillbrains.lightshot",
        // Terminals, IDEs & Dev Servers
        "dev.warp.Warp-Stable",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.google.antigravity",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.apple.dt.Xcode",
        "com.getflywheel.lightning.local", // LocalWP
        "com.docker.docker",
        "com.openmausbot.app",
        "ai.opencode.desktop",
        "com.opencode.app",
        // Primary Browser
        "com.google.Chrome",
        // Active Work Communication
        "com.tinyspeck.slackmacgap",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.vng.zalo",
        "com.hnc.Discord",
        "com.apple.MobileSMS"
    ]

    public init(
        isEnabled: Bool = true,
        intervalHours: Int = 1,
        staleCacheDays: Int = 3,
        lowDiskTriggerGB: Double = 30.0,
        autoCleanStaleCaches: Bool = true,
        autoCleanUpdaterGarbage: Bool = true,
        autoTruncateOversizedLogs: Bool = true,
        autoCleanOrphanTempProfiles: Bool = true,
        autoCloseIdleApps: Bool = true,
        idleAppTimeoutMinutes: Int = 60,
        autoThrottleBackgroundHogs: Bool = true,
        autoHealStuckReplayd: Bool = true,
        customProtectedBundleIDs: [String] = [],
        unlockedDefaultBundleIDs: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.intervalHours = intervalHours
        self.staleCacheDays = staleCacheDays
        self.lowDiskTriggerGB = lowDiskTriggerGB
        self.autoCleanStaleCaches = autoCleanStaleCaches
        self.autoCleanUpdaterGarbage = autoCleanUpdaterGarbage
        self.autoTruncateOversizedLogs = autoTruncateOversizedLogs
        self.autoCleanOrphanTempProfiles = autoCleanOrphanTempProfiles
        self.autoCloseIdleApps = autoCloseIdleApps
        self.idleAppTimeoutMinutes = idleAppTimeoutMinutes
        self.autoThrottleBackgroundHogs = autoThrottleBackgroundHogs
        self.autoHealStuckReplayd = autoHealStuckReplayd
        self.customProtectedBundleIDs = customProtectedBundleIDs
        self.unlockedDefaultBundleIDs = unlockedDefaultBundleIDs
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, intervalHours, staleCacheDays, lowDiskTriggerGB
        case autoCleanStaleCaches, autoCleanUpdaterGarbage, autoTruncateOversizedLogs, autoCleanOrphanTempProfiles
        case autoCloseIdleApps, idleAppTimeoutMinutes, autoThrottleBackgroundHogs, autoHealStuckReplayd
        case customProtectedBundleIDs, unlockedDefaultBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.intervalHours = try c.decodeIfPresent(Int.self, forKey: .intervalHours) ?? 1
        self.staleCacheDays = try c.decodeIfPresent(Int.self, forKey: .staleCacheDays) ?? 3
        self.lowDiskTriggerGB = try c.decodeIfPresent(Double.self, forKey: .lowDiskTriggerGB) ?? 30.0
        self.autoCleanStaleCaches = try c.decodeIfPresent(Bool.self, forKey: .autoCleanStaleCaches) ?? true
        self.autoCleanUpdaterGarbage = try c.decodeIfPresent(Bool.self, forKey: .autoCleanUpdaterGarbage) ?? true
        self.autoTruncateOversizedLogs = try c.decodeIfPresent(Bool.self, forKey: .autoTruncateOversizedLogs) ?? true
        self.autoCleanOrphanTempProfiles = try c.decodeIfPresent(Bool.self, forKey: .autoCleanOrphanTempProfiles) ?? true
        self.autoCloseIdleApps = try c.decodeIfPresent(Bool.self, forKey: .autoCloseIdleApps) ?? true
        self.idleAppTimeoutMinutes = try c.decodeIfPresent(Int.self, forKey: .idleAppTimeoutMinutes) ?? 60
        self.autoThrottleBackgroundHogs = try c.decodeIfPresent(Bool.self, forKey: .autoThrottleBackgroundHogs) ?? true
        self.autoHealStuckReplayd = try c.decodeIfPresent(Bool.self, forKey: .autoHealStuckReplayd) ?? true
        self.customProtectedBundleIDs = try c.decodeIfPresent([String].self, forKey: .customProtectedBundleIDs) ?? []
        self.unlockedDefaultBundleIDs = try c.decodeIfPresent([String].self, forKey: .unlockedDefaultBundleIDs) ?? []
    }
}

public enum AutoOptimizeTrigger: String, Codable, Sendable, Equatable {
    case scheduled = "Định kỳ"
    case lowDisk = "SSD thấp"
    case ramPressure = "RAM đầy"
    case replaydStorm = "Bão replayd"
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
    public let closedIdleApps: [String]
    public let reclaimedRAMBytes: UInt64
    public let throttledBackgroundCount: Int
    public let restartedReplayd: Bool
    public let summary: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        trigger: AutoOptimizeTrigger,
        freedBytes: UInt64,
        removedFilesCount: Int,
        truncatedLogsCount: Int,
        cleanedOrphanProfilesCount: Int,
        closedIdleApps: [String] = [],
        reclaimedRAMBytes: UInt64 = 0,
        throttledBackgroundCount: Int = 0,
        restartedReplayd: Bool = false,
        summary: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.trigger = trigger
        self.freedBytes = freedBytes
        self.removedFilesCount = removedFilesCount
        self.truncatedLogsCount = truncatedLogsCount
        self.cleanedOrphanProfilesCount = cleanedOrphanProfilesCount
        self.closedIdleApps = closedIdleApps
        self.reclaimedRAMBytes = reclaimedRAMBytes
        self.throttledBackgroundCount = throttledBackgroundCount
        self.restartedReplayd = restartedReplayd
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, trigger, freedBytes, removedFilesCount, truncatedLogsCount, cleanedOrphanProfilesCount
        case closedIdleApps, reclaimedRAMBytes, throttledBackgroundCount, restartedReplayd, summary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.trigger = try c.decodeIfPresent(AutoOptimizeTrigger.self, forKey: .trigger) ?? .scheduled
        self.freedBytes = try c.decodeIfPresent(UInt64.self, forKey: .freedBytes) ?? 0
        self.removedFilesCount = try c.decodeIfPresent(Int.self, forKey: .removedFilesCount) ?? 0
        self.truncatedLogsCount = try c.decodeIfPresent(Int.self, forKey: .truncatedLogsCount) ?? 0
        self.cleanedOrphanProfilesCount = try c.decodeIfPresent(Int.self, forKey: .cleanedOrphanProfilesCount) ?? 0
        self.closedIdleApps = try c.decodeIfPresent([String].self, forKey: .closedIdleApps) ?? []
        self.reclaimedRAMBytes = try c.decodeIfPresent(UInt64.self, forKey: .reclaimedRAMBytes) ?? 0
        self.throttledBackgroundCount = try c.decodeIfPresent(Int.self, forKey: .throttledBackgroundCount) ?? 0
        self.restartedReplayd = try c.decodeIfPresent(Bool.self, forKey: .restartedReplayd) ?? false
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
    }
}

public struct PersistedAutoOptimizeState: Codable, Sendable, Equatable {
    public var config: AutoOptimizeConfig
    public var lastRunAt: Date?
    public var totalLifetimeFreedBytes: UInt64
    public var totalLifetimeReclaimedRAMBytes: UInt64
    public var totalIdleAppsClosed: Int
    public var history: [AutoOptimizeRunRecord]

    public init(
        config: AutoOptimizeConfig = AutoOptimizeConfig(),
        lastRunAt: Date? = nil,
        totalLifetimeFreedBytes: UInt64 = 0,
        totalLifetimeReclaimedRAMBytes: UInt64 = 0,
        totalIdleAppsClosed: Int = 0,
        history: [AutoOptimizeRunRecord] = []
    ) {
        self.config = config
        self.lastRunAt = lastRunAt
        self.totalLifetimeFreedBytes = totalLifetimeFreedBytes
        self.totalLifetimeReclaimedRAMBytes = totalLifetimeReclaimedRAMBytes
        self.totalIdleAppsClosed = totalIdleAppsClosed
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case config, lastRunAt, totalLifetimeFreedBytes, totalLifetimeReclaimedRAMBytes, totalIdleAppsClosed, history
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.config = try c.decodeIfPresent(AutoOptimizeConfig.self, forKey: .config) ?? AutoOptimizeConfig()
        self.lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        self.totalLifetimeFreedBytes = try c.decodeIfPresent(UInt64.self, forKey: .totalLifetimeFreedBytes) ?? 0
        self.totalLifetimeReclaimedRAMBytes = try c.decodeIfPresent(UInt64.self, forKey: .totalLifetimeReclaimedRAMBytes) ?? 0
        self.totalIdleAppsClosed = try c.decodeIfPresent(Int.self, forKey: .totalIdleAppsClosed) ?? 0
        self.history = try c.decodeIfPresent([AutoOptimizeRunRecord].self, forKey: .history) ?? []
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
    /// Safe macOS background indexer/analyzer processes that can be politely reniced (+10)
    /// when burning CPU so foreground work stays 100% smooth without killing anything.
    public static let safeThrottleableHelperNames: Set<String> = [
        "mdworker_shared",
        "mdworker",
        "mds_stores",
        "photoanalysisd",
        "mediaanalysisd",
        "photolibraryd",
        "cloudd",
        "bird",
        "parsecd",
        "suggestd",
        "triald",
        "duetexpertd",
        "knowledge-agent",
        "corespotlightservice",
        "biomeagent"
    ]

    /// Determines whether an app is protected from Idle Auto-Close.
    /// Protects macOS essentials, VPS/Remote Desktop, Terminals, IDEs, LocalWP, primary Chrome, and user-locked apps.
    public static func isProtectedWorkApp(
        bundleID: String,
        appName: String = "",
        config: AutoOptimizeConfig
    ) -> Bool {
        if bundleID.isEmpty { return true }
        // Always protect MacPulse, Finder, and active Remote/VPS apps unconditionally unless explicitly unlocked
        if bundleID == "com.ducdung.MacPulse" || bundleID == "com.apple.finder" {
            return true
        }
        if config.customProtectedBundleIDs.contains(bundleID) {
            return true
        }
        if config.unlockedDefaultBundleIDs.contains(bundleID) {
            return false
        }
        if AutoOptimizeConfig.defaultProtectedBundleIDs.contains(bundleID) {
            return true
        }
        if VietnameseAppDetector.isVPSOrRemoteApp(bundleID: bundleID, appName: appName) {
            return true
        }
        if VietnameseAppDetector.isTerminalApp(bundleID: bundleID, appName: appName) {
            return true
        }
        return false
    }

    /// Selects genuinely idle, non-protected GUI apps eligible for polite Cmd+Q termination.
    /// Safety gates: NOT frontmost, NOT protected, CPU < 2.0% (not doing active work), idle >= timeout.
    public static func selectIdleAppsToClose(
        runningApps: [TrackedGUIApp],
        config: AutoOptimizeConfig,
        now: Date = Date()
    ) -> [TrackedGUIApp] {
        guard config.autoCloseIdleApps else { return [] }
        let thresholdSeconds = TimeInterval(max(10, config.idleAppTimeoutMinutes) * 60)

        return runningApps
            .filter { app in
                guard !app.isFrontmost else { return false }
                guard !isProtectedWorkApp(bundleID: app.bundleID, appName: app.name, config: config) else { return false }
                guard app.cpuPercent < 2.0 else { return false }
                return now.timeIntervalSince(app.lastActiveAt) >= thresholdSeconds
            }
            .sorted { $0.rssBytes > $1.rssBytes }
    }

    /// Politely lowers CPU priority (nice +10) of noisy user-owned background indexers/analyzers
    /// currently consuming >= 5% CPU. Zero process killing, zero data loss.
    public static func throttleNoisyBackgroundHelpers(
        liveProcesses: [RawProcessInfo]? = nil
    ) -> (count: Int, names: [String]) {
        let procs = liveProcesses ?? ((try? ProcessScanner.scanLiveProcesses()) ?? [])
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var throttled = 0
        var seenNames: [String] = []

        for proc in procs {
            guard proc.pid > 1 && proc.pid != selfPID else { continue }
            guard proc.cpuPercent >= 5.0 else { continue }
            let commLower = URL(fileURLWithPath: proc.comm).lastPathComponent.lowercased()
            guard safeThrottleableHelperNames.contains(commLower) else { continue }

            // Check current nice value so we don't recount processes already reniced >= 10
            errno = 0
            let currentNice = getpriority(PRIO_PROCESS, id_t(proc.pid))
            if errno == 0 && currentNice >= 10 { continue }

            if setpriority(PRIO_PROCESS, id_t(proc.pid), 10) == 0 {
                throttled += 1
                if !seenNames.contains(commLower) {
                    seenNames.append(commLower)
                }
            }
        }
        return (throttled, seenNames)
    }

    /// Determines whether Autopilot should run right now based on schedule (1h..24h), low disk,
    /// high RAM compression, or an emergency wedged macOS `replayd` XPC storm (>= 75% CPU).
    public static func evaluateTrigger(
        config: AutoOptimizeConfig,
        lastRunAt: Date?,
        availableDiskGB: Double,
        cpuBusyPercent: Double,
        compressedRAMGB: Double = 0.0,
        replaydCPUPercent: Double = 0.0,
        replaydAlreadyThrottled: Bool = false,
        now: Date = Date()
    ) -> AutoOptimizeTrigger? {
        guard config.isEnabled else { return nil }
        let elapsedSinceLast = lastRunAt.map { now.timeIntervalSince($0) } ?? .infinity

        // Emergency self-healing: a wedged replayd (>= 75% CPU) is the *cause* of high system CPU,
        // so heal it even when cpuBusyPercent >= 65% (with 10-min cooldown).
        // Skip repeated auto-restarts if replayd is already reniced to +20 (meaning client apps are re-storming it).
        if config.autoHealStuckReplayd && replaydCPUPercent >= 75.0 && !replaydAlreadyThrottled && elapsedSinceLast >= 600 {
            return .replaydStorm
        }

        // Never compete with heavy user workload (building, rendering, etc.)
        if cpuBusyPercent >= 65.0 { return nil }

        let intervalSecs = TimeInterval(max(1, config.intervalHours) * 3600)
        // Use 55m cooldown when scheduled for 1h so a 5-min timer tick never slips to 1h05m;
        // otherwise keep 60m cooldown for SSD safety.
        let diskCooldown: TimeInterval = (config.intervalHours <= 1) ? 3300 : 3600

        if elapsedSinceLast >= diskCooldown {
            if availableDiskGB > 0 && availableDiskGB < config.lowDiskTriggerGB {
                return .lowDisk
            }
            if elapsedSinceLast >= intervalSecs {
                return .scheduled
            }
        }

        // High RAM compression relief (e.g. >= 5.0 GB compressed) with 30-min cooldown when Idle Auto-Close is enabled
        if config.autoCloseIdleApps && compressedRAMGB >= 5.0 && elapsedSinceLast >= 1800 {
            return .ramPressure
        }

        return nil
    }

    /// Runs a 100% safe, non-destructive background optimization pass:
    /// - Removes stale cache files not accessed/modified within `staleCacheDays`
    /// - Removes old updater/ShipIt/QuickLook garbage
    /// - Truncates oversized LocalWP logs (> 15 MB) in-place
    /// - Removes dead /tmp automation profile directories not used by any live process
    /// - Politely renices (+10) noisy background macOS indexers/analyzers
    /// NEVER touches Trash, Cookies, Chrome Extensions, Sessions, Databases, or AI models.
    public static func runPass(
        config: AutoOptimizeConfig,
        trigger: AutoOptimizeTrigger,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        tempDirectory: URL = URL(fileURLWithPath: "/tmp"),
        liveProcessArgs: [String]? = nil,
        liveProcessesForThrottle: [RawProcessInfo]? = nil,
        closedIdleAppNames: [String] = [],
        reclaimedRAMBytes: UInt64 = 0,
        now: Date = Date()
    ) -> AutoOptimizeRunRecord {
        let fm = FileManager.default
        let canonicalHome = homeDirectory.resolvingSymlinksInPath().path
        var totalFreed: UInt64 = 0
        var removedFiles = 0
        var truncatedLogs = 0
        var cleanedProfiles = 0
        var throttledCount = 0

        // 1. Safe updater & ephemeral OS/AI garbage (always safe even when apps are open)
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
                let live = liveProcessesForThrottle ?? ((try? ProcessScanner.scanLiveProcesses()) ?? [])
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

        // 5. Politely throttle noisy background macOS indexers/analyzers (+10 nice, zero killing)
        if config.autoThrottleBackgroundHogs {
            let throttleRes = throttleNoisyBackgroundHelpers(liveProcesses: liveProcessesForThrottle)
            throttledCount = throttleRes.count
        }

        // 6. Auto-heal wedged macOS /usr/libexec/replayd spinning on XPC (only when real system pass, not mock empty proc test)
        var didRestartReplayd = false
        var replaydThrottledNice = false
        if config.autoHealStuckReplayd && liveProcessArgs == nil {
            let threshold: Double = (trigger == .manual || trigger == .replaydStorm) ? 25.0 : 45.0
            let rep = CleanupExecutor.restartStuckReplayd(
                minCPUPercent: threshold,
                forceAlways: false,
                liveProcesses: liveProcessesForThrottle
            )
            didRestartReplayd = rep.didRestart
            replaydThrottledNice = rep.throttledNice
        }

        let summary = buildSummary(
            freedBytes: totalFreed,
            removedFiles: removedFiles,
            truncatedLogs: truncatedLogs,
            cleanedProfiles: cleanedProfiles,
            closedIdleApps: closedIdleAppNames,
            reclaimedRAMBytes: reclaimedRAMBytes,
            throttledCount: throttledCount,
            restartedReplayd: didRestartReplayd,
            replaydThrottledNice: replaydThrottledNice
        )

        return AutoOptimizeRunRecord(
            timestamp: now,
            trigger: trigger,
            freedBytes: totalFreed,
            removedFilesCount: removedFiles,
            truncatedLogsCount: truncatedLogs,
            cleanedOrphanProfilesCount: cleanedProfiles,
            closedIdleApps: closedIdleAppNames,
            reclaimedRAMBytes: reclaimedRAMBytes,
            throttledBackgroundCount: throttledCount,
            restartedReplayd: didRestartReplayd,
            summary: summary
        )
    }

    public static func buildSummary(
        freedBytes: UInt64,
        removedFiles: Int,
        truncatedLogs: Int,
        cleanedProfiles: Int,
        closedIdleApps: [String],
        reclaimedRAMBytes: UInt64,
        throttledCount: Int,
        restartedReplayd: Bool = false,
        replaydThrottledNice: Bool = false
    ) -> String {
        var parts: [String] = []
        if restartedReplayd {
            parts.append(replaydThrottledNice ? "Reset + hạ nice +20 replayd XPC" : "Reset replayd XPC bị treo")
        }
        if freedBytes > 0 {
            parts.append("Dọn \(Formatters.bytes(freedBytes)) SSD")
        }
        if !closedIdleApps.isEmpty {
            let ramNote = reclaimedRAMBytes > 0 ? " (~\(Formatters.bytes(reclaimedRAMBytes)) RAM)" : ""
            parts.append("Tắt êm \(closedIdleApps.count) app rảnh\(ramNote)")
        }
        if throttledCount > 0 {
            parts.append("Hạ ưu tiên \(throttledCount) tiến trình nền")
        }
        if removedFiles > 0 && freedBytes == 0 {
            parts.append("\(removedFiles) tệp cache cũ")
        }
        if truncatedLogs > 0 {
            parts.append("\(truncatedLogs) log lớn")
        }
        if cleanedProfiles > 0 {
            parts.append("\(cleanedProfiles) profile /tmp")
        }
        return parts.isEmpty
            ? "Hệ thống đã mượt & sạch — không có cache cũ hay app rảnh cần xử lý."
            : parts.joined(separator: " • ")
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
            let lastTouched = max(mDate, aDate)
            guard lastTouched < cutoffDate else { continue }

            let sz = UInt64(max(0, vals.totalFileAllocatedSize ?? vals.fileSize ?? 0))
            do {
                try fm.removeItem(at: fileURL)
                freed += sz
                count += 1
            } catch {
                continue
            }
        }

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
