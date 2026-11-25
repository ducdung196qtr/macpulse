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

public struct AutomationResetReport: Sendable, Equatable {
    public let stoppedPIDs: [Int32]
    public let removedLockFiles: [String]
    public let cleanedProfileDirs: [String]
    public let freedBytes: UInt64
    public let errors: [String]

    public init(
        stoppedPIDs: [Int32] = [],
        removedLockFiles: [String] = [],
        cleanedProfileDirs: [String] = [],
        freedBytes: UInt64 = 0,
        errors: [String] = []
    ) {
        self.stoppedPIDs = stoppedPIDs
        self.removedLockFiles = removedLockFiles
        self.cleanedProfileDirs = cleanedProfileDirs
        self.freedBytes = freedBytes
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

    public static func automationProfileLockPaths(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let fm = FileManager.default
        var lockURLs: [URL] = []
        let lockNames = ["SingletonLock", "SingletonCookie", "SingletonSocket", "DevToolsActivePort"]

        let checkProfileDir = { (dirURL: URL) in
            for name in lockNames {
                let lockURL = dirURL.appendingPathComponent(name)
                var st = Darwin.stat()
                if lstat(lockURL.path, &st) == 0 {
                    lockURLs.append(lockURL)
                }
            }
        }

        // 1. ~/.openmausbot/agent-browser-profiles/*
        let openMausProfiles = homeDirectory.appendingPathComponent(".openmausbot/agent-browser-profiles")
        if let subs = try? fm.contentsOfDirectory(at: openMausProfiles, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for sub in subs {
                checkProfileDir(sub)
            }
        }

        // 2. ~/.agent-browser/*
        let agentBrowserDir = homeDirectory.appendingPathComponent(".agent-browser")
        if let subs = try? fm.contentsOfDirectory(at: agentBrowserDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for sub in subs {
                checkProfileDir(sub)
                let subProfiles = sub.appendingPathComponent("profiles")
                if let nested = try? fm.contentsOfDirectory(at: subProfiles, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for n in nested {
                        checkProfileDir(n)
                    }
                }
            }
        }

        // 3. /tmp/ profiles
        let tmpDir = URL(fileURLWithPath: "/tmp")
        if let tmpSubs = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for sub in tmpSubs {
                let name = sub.lastPathComponent
                if name.hasPrefix("playwright_chromiumdev_profile-")
                    || name.hasPrefix("puppeteer_dev_chrome_profile-")
                    || name.hasPrefix("agent-browser-") {
                    checkProfileDir(sub)
                }
            }
        }

        return lockURLs
    }

    public static func rescueAndResetBrowserAutomation(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AutomationResetReport {
        let fm = FileManager.default
        let canonicalHome = homeDirectory.resolvingSymlinksInPath().path
        var stopped: [Int32] = []
        var removedLocks: [String] = []
        var cleanedDirs: [String] = []
        var freed: UInt64 = 0
        var errors: [String] = []

        // 1. Gracefully terminate orphan puppeteer & agent-browser processes first
        let killRes = terminateOrphanPuppeteerProcesses(force: false)
        stopped.append(contentsOf: killRes.killed)

        // 2. Wait up to 300ms
        usleep(300_000)

        // 3. Force kill any remaining orphan automation processes
        if let live = try? ProcessScanner.scanLiveProcesses() {
            let groups = ProcessScanner.aggregate(live)
            let remainingPIDs = groups.filter(\.isOrphanAutomation).flatMap(\.pids)
            if !remainingPIDs.isEmpty {
                let forceRes = terminatePIDs(remainingPIDs, force: true)
                for pid in forceRes.killed where !stopped.contains(pid) {
                    stopped.append(pid)
                }
            }
        }

        // 4. Clean lock files from all automation profiles
        let locks = automationProfileLockPaths(homeDirectory: homeDirectory)
        for lockURL in locks {
            guard isInsideAllowedHome(url: lockURL, canonicalHome: canonicalHome) || lockURL.path.hasPrefix("/tmp/") else { continue }
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

        // 5. Clean ephemeral /tmp profile dirs (playwright_*, puppeteer_*, agent-browser-*)
        let tmpDir = URL(fileURLWithPath: "/tmp")
        if let tmpEntries = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for entry in tmpEntries {
                let name = entry.lastPathComponent
                if name.hasPrefix("playwright_chromiumdev_profile-")
                    || name.hasPrefix("puppeteer_dev_chrome_profile-")
                    || name.hasPrefix("agent-browser-") {
                    let sz = CleanupScanner.directorySize(at: entry)
                    if (try? fm.removeItem(at: entry)) != nil {
                        freed += sz
                        cleanedDirs.append(name)
                    }
                }
            }
        }

        return AutomationResetReport(
            stoppedPIDs: stopped,
            removedLockFiles: removedLocks,
            cleanedProfileDirs: cleanedDirs,
            freedBytes: freed,
            errors: errors
        )
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
            // 1. Gracefully tell Chrome to quit so it can flush state and save active tabs
            let tellQuit = Process()
            tellQuit.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            tellQuit.arguments = ["-e", "tell application \"Google Chrome\" to quit"]
            try? tellQuit.run()
            tellQuit.waitUntilExit()

            // 2. Wait up to 1.2s for clean exit
            for _ in 0..<8 {
                if let live = try? ProcessScanner.scanLiveProcesses(),
                   !live.contains(where: { ProcessScanner.isAnyGoogleChromeProcess($0) }) {
                    break
                }
                usleep(150_000)
            }

            // 3. Force terminate stubborn hung renderers or orphan helpers
            if let live = try? ProcessScanner.scanLiveProcesses() {
                let remainingChrome = live.filter { ProcessScanner.isAnyGoogleChromeProcess($0) }
                let pids = Array(Set(remainingChrome.map(\.pid)))
                if !pids.isEmpty {
                    let killRes = terminatePIDs(pids, force: true)
                    stoppedPIDs.append(contentsOf: killRes.killed)
                    usleep(150_000)
                }
            }
        }

        // Only remove locks if Chrome is not running or if skipProcessTermination is true (e.g. testing)
        let isStillRunning = !skipProcessTermination && ((try? ProcessScanner.scanLiveProcesses())?.contains(where: { ProcessScanner.isAnyGoogleChromeProcess($0) }) ?? false)
        if !isStillRunning {
            let allLocks = chromeLockPaths(homeDirectory: homeDirectory) + automationProfileLockPaths(homeDirectory: homeDirectory)
            for lockURL in allLocks {
                guard isInsideAllowedHome(url: lockURL, canonicalHome: canonicalHome) || lockURL.path.hasPrefix("/tmp/") else { continue }
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

    /// Kills stuck Chrome helper renderers (tabs pegged on high CPU or hung during local dev tasks)
    /// without closing the Chrome app, preserving other windows, tabs, DevTools, and extensions.
    public static func killStuckChromeRenderers(minCPUPercent: Double = 12.0, forceAllRenderers: Bool = false) -> (killedPIDs: [Int32], totalCPUFreed: Double) {
        guard let live = try? ProcessScanner.scanLiveProcesses() else { return ([], 0) }
        let targetRenderers = live.filter { proc in
            guard ProcessScanner.isChromeRendererProcess(proc) else { return false }
            if forceAllRenderers { return true }
            return proc.cpuPercent >= minCPUPercent
        }
        let pids = Array(Set(targetRenderers.map(\.pid)))
        guard !pids.isEmpty else { return ([], 0) }
        let totalCPU = targetRenderers.reduce(0.0) { $0 + $1.cpuPercent }
        let res = terminatePIDs(pids, force: true)
        return (res.killed, totalCPU)
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
