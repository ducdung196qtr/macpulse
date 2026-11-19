import Foundation
import Darwin

public struct ChromeRescueReport: Sendable, Equatable {
    public let stoppedChromePIDs: [Int32]
    public let removedLockFiles: [String]
    public let freedBytes: UInt64
    public let cleanedPathCount: Int
    public let relaunchedChrome: Bool
    public let errors: [String]

    public init(
        stoppedChromePIDs: [Int32],
        removedLockFiles: [String],
        freedBytes: UInt64,
        cleanedPathCount: Int,
        relaunchedChrome: Bool,
        errors: [String]
    ) {
        self.stoppedChromePIDs = stoppedChromePIDs
        self.removedLockFiles = removedLockFiles
        self.freedBytes = freedBytes
        self.cleanedPathCount = cleanedPathCount
        self.relaunchedChrome = relaunchedChrome
        self.errors = errors
    }
}

public enum CleanupExecutor {
    public static func execute(
        candidates: [CleanupCandidate],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CleanupOutcome {
        let fm = FileManager.default
        let canonicalHome = homeDirectory.resolvingSymlinksInPath().path
        var freed: UInt64 = 0
        var count = 0
        var errors: [String] = []

        for item in candidates {
            guard item.tier == .safeAutoClean, item.method != .inspectInFinderOnly else {
                continue
            }

            switch item.method {
            case .clearDirectoryContents, .emptyTrash:
                let paths = item.path.split(separator: "|").map(String.init)
                for p in paths {
                    let dirURL = URL(fileURLWithPath: p)
                    guard isInsideAllowedHome(url: dirURL, canonicalHome: canonicalHome) else {
                        errors.append("Từ chối đường dẫn ngoài home: \(p)")
                        continue
                    }
                    let before = CleanupScanner.directorySize(at: dirURL)
                    do {
                        let children = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [])
                        for child in children {
                            try fm.removeItem(at: child)
                        }
                        let after = CleanupScanner.directorySize(at: dirURL)
                        freed += before >= after ? before - after : 0
                        count += 1
                    } catch {
                        errors.append("\(item.title): \(error.localizedDescription)")
                    }
                }

            case .truncateLogFile:
                let fileURL = URL(fileURLWithPath: item.path)
                guard isInsideAllowedHome(url: fileURL, canonicalHome: canonicalHome),
                      fileURL.path.contains("/Local Sites/") else {
                    errors.append("Từ chối truncate ngoài Local Sites: \(item.path)")
                    continue
                }
                let before = CleanupScanner.fileSize(at: fileURL)
                do {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.truncate(atOffset: 0)
                    try handle.close()
                    freed += before
                    count += 1
                } catch {
                    errors.append("\(item.title): \(error.localizedDescription)")
                }

            case .inspectInFinderOnly:
                break
            }
        }

        if candidates.contains(where: { $0.id == "cache-chrome" }) {
            // Unblock Chrome: clean broken SingletonLock/DevToolsActivePort and terminate orphan headless Chrome blockers
            for lockURL in chromeLockPaths(homeDirectory: homeDirectory) {
                guard isInsideAllowedHome(url: lockURL, canonicalHome: canonicalHome) else { continue }
                var st = Darwin.stat()
                if lstat(lockURL.path, &st) == 0 {
                    _ = Darwin.unlink(lockURL.path)
                    try? fm.removeItem(at: lockURL)
                }
            }
            _ = terminateOrphanPuppeteerProcesses(force: false)
        }

        return CleanupOutcome(freedBytes: freed, processedCount: count, errors: errors)
    }


    public static func chromeLockPaths(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let base = homeDirectory.appendingPathComponent("Library/Application Support/Google/Chrome")
        return [
            base.appendingPathComponent("SingletonLock"),
            base.appendingPathComponent("SingletonCookie"),
            base.appendingPathComponent("SingletonSocket"),
            base.appendingPathComponent("DevToolsActivePort")
        ]
    }

    public static func rescueAndCleanChrome(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        relaunch: Bool = true,
        skipProcessTermination: Bool = false
    ) -> ChromeRescueReport {
        let fm = FileManager.default
        let canonicalHome = homeDirectory.resolvingSymlinksInPath().path
        var stoppedPIDs: [Int32] = []
        var removedLocks: [String] = []
        var freed: UInt64 = 0
        var cleanedCount = 0
        var errors: [String] = []

        if !skipProcessTermination {
            if let live = try? ProcessScanner.scanLiveProcesses() {
                let chromeProcs = live.filter { ProcessScanner.isAnyGoogleChromeProcess($0) }
                let pids = Array(Set(chromeProcs.map(\.pid)))
                if !pids.isEmpty {
                    let termRes = terminatePIDs(pids, force: false)
                    stoppedPIDs.append(contentsOf: termRes.killed)

                    for _ in 0..<10 {
                        let remaining = pids.filter { kill($0, 0) == 0 }
                        if remaining.isEmpty { break }
                        usleep(150_000)
                    }
                    let stubborn = pids.filter { kill($0, 0) == 0 }
                    if !stubborn.isEmpty {
                        let killRes = terminatePIDs(stubborn, force: true)
                        for pid in killRes.killed where !stoppedPIDs.contains(pid) {
                            stoppedPIDs.append(pid)
                        }
                        usleep(200_000)
                    }
                }
            }
        }

        for lockURL in chromeLockPaths(homeDirectory: homeDirectory) {
            guard isInsideAllowedHome(url: lockURL, canonicalHome: canonicalHome) else { continue }
            var st = Darwin.stat()
            if lstat(lockURL.path, &st) == 0 {
                if Darwin.unlink(lockURL.path) == 0 {
                    removedLocks.append(lockURL.lastPathComponent)
                } else {
                    do {
                        try fm.removeItem(at: lockURL)
                        removedLocks.append(lockURL.lastPathComponent)
                    } catch {
                        errors.append("Không gỡ được \(lockURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }

        for cacheURL in CleanupScanner.chromeCachePaths(homeDirectory: homeDirectory) {
            guard isInsideAllowedHome(url: cacheURL, canonicalHome: canonicalHome) else { continue }
            guard fm.fileExists(atPath: cacheURL.path) else { continue }
            let before = CleanupScanner.directorySize(at: cacheURL)
            do {
                let children = try fm.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil, options: [])
                for child in children {
                    try fm.removeItem(at: child)
                }
                let after = CleanupScanner.directorySize(at: cacheURL)
                freed += before >= after ? before - after : 0
                cleanedCount += 1
            } catch {
                errors.append("\(cacheURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !skipProcessTermination {
            let tmpDir = FileManager.default.temporaryDirectory
            if let tmpEntries = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for entry in tmpEntries {
                    let name = entry.lastPathComponent
                    if name.hasPrefix("playwright_chromiumdev_profile-") || name.hasPrefix("puppeteer_dev_chrome_profile-") {
                        let sz = CleanupScanner.directorySize(at: entry)
                        if (try? fm.removeItem(at: entry)) != nil {
                            freed += sz
                        }
                    }
                }
            }
        }

        var didRelaunch = false
        if relaunch && !skipProcessTermination {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Google Chrome"]
            do {
                try proc.run()
                proc.waitUntilExit()
                didRelaunch = (proc.terminationStatus == 0)
                if !didRelaunch {
                    errors.append("Không thể mở lại Google Chrome (mã lỗi \(proc.terminationStatus)).")
                }
            } catch {
                errors.append("Không thể mở lại Google Chrome: \(error.localizedDescription)")
            }
        }

        return ChromeRescueReport(
            stoppedChromePIDs: stoppedPIDs,
            removedLockFiles: removedLocks,
            freedBytes: freed,
            cleanedPathCount: cleanedCount,
            relaunchedChrome: didRelaunch,
            errors: errors
        )
    }

    public static func terminateOrphanPuppeteerProcesses(force: Bool = false) -> (killed: [Int32], failed: [Int32]) {
        guard let raw = try? ProcessScanner.scanLiveProcesses() else { return ([], []) }
        let groups = ProcessScanner.aggregate(raw)
        let orphanPIDs = groups.filter(\.isOrphanAutomation).flatMap(\.pids)
        let sig: Int32 = force ? SIGKILL : SIGTERM
        var killed: [Int32] = []
        var failed: [Int32] = []
        for pid in orphanPIDs {
            if kill(pid, sig) == 0 {
                killed.append(pid)
            } else {
                failed.append(pid)
            }
        }
        return (killed, failed)
    }

    public static func terminatePIDs(_ pids: [Int32], force: Bool = false) -> (killed: [Int32], failed: [Int32]) {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let selfUID = getuid()
        let sig: Int32 = force ? SIGKILL : SIGTERM
        var killed: [Int32] = []
        var failed: [Int32] = []

        for pid in pids {
            guard pid > 1, pid != selfPID else {
                failed.append(pid)
                continue
            }
            var bsdInfo = proc_bsdinfo()
            let bsdSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.stride))
            guard bsdSize == Int32(MemoryLayout<proc_bsdinfo>.stride), bsdInfo.pbi_uid == selfUID else {
                failed.append(pid)
                continue
            }
            if kill(pid, sig) == 0 {
                killed.append(pid)
            } else {
                failed.append(pid)
            }
        }
        return (killed, failed)
    }

    private static func isInsideAllowedHome(url: URL, canonicalHome: String) -> Bool {
        let resolved = url.resolvingSymlinksInPath().path
        return resolved.hasPrefix(canonicalHome + "/") && resolved.count > canonicalHome.count + 2
    }
}
