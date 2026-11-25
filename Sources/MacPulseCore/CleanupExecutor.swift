import Foundation
import Darwin

public struct ReplaydResetReport: Sendable, Equatable {
    public let restartedPIDs: [Int32]
    public let previousCPUPercent: Double
    public let postRestartCPUPercent: Double
    public let didRestart: Bool
    public let throttledNice: Bool
    public let stillStormingFromClients: Bool
    public let stormingClients: [String]
    public let error: String?

    public init(
        restartedPIDs: [Int32] = [],
        previousCPUPercent: Double = 0,
        postRestartCPUPercent: Double = 0,
        didRestart: Bool = false,
        throttledNice: Bool = false,
        stillStormingFromClients: Bool = false,
        stormingClients: [String] = [],
        error: String? = nil
    ) {
        self.restartedPIDs = restartedPIDs
        self.previousCPUPercent = previousCPUPercent
        self.postRestartCPUPercent = postRestartCPUPercent
        self.didRestart = didRestart
        self.throttledNice = throttledNice
        self.stillStormingFromClients = stillStormingFromClients
        self.stormingClients = stormingClients
        self.error = error
    }
}

public struct ChromeRescueReport: Sendable, Equatable {
    public let stoppedChromePIDs: [Int32]
    public let removedLockFiles: [String]
    public let freedBytes: UInt64
    public let cleanedPathCount: Int
    public let relaunchedChrome: Bool
    public let restartedReplayd: Bool
    public let errors: [String]

    public init(
        stoppedChromePIDs: [Int32],
        removedLockFiles: [String],
        freedBytes: UInt64,
        cleanedPathCount: Int,
        relaunchedChrome: Bool,
        restartedReplayd: Bool = false,
        errors: [String]
    ) {
        self.stoppedChromePIDs = stoppedChromePIDs
        self.removedLockFiles = removedLockFiles
        self.freedBytes = freedBytes
        self.cleanedPathCount = cleanedPathCount
        self.relaunchedChrome = relaunchedChrome
        self.restartedReplayd = restartedReplayd
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
                        var removedAny = false
                        var childFailCount = 0
                        var lastChildError: String?
                        for child in children {
                            do {
                                try fm.removeItem(at: child)
                                removedAny = true
                            } catch {
                                childFailCount += 1
                                lastChildError = error.localizedDescription
                            }
                        }
                        let after = CleanupScanner.directorySize(at: dirURL)
                        freed += before >= after ? before - after : 0
                        if removedAny || children.isEmpty {
                            count += 1
                        }
                        if childFailCount > 0 && !removedAny, let errDesc = lastChildError {
                            errors.append("\(item.title): \(errDesc)")
                        }
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

            // 2. Wait up to 2.4s for clean exit so Chrome flushes all open tabs & extension state
            for _ in 0..<16 {
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
                    try? fm.removeItem(at: child)
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

        var didRestartReplayd = false
        if !skipProcessTermination {
            let r = restartStuckReplayd(minCPUPercent: 25.0, forceAlways: false)
            didRestartReplayd = r.didRestart
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
            restartedReplayd: didRestartReplayd,
            errors: errors
        )
    }

    /// Checks whether user-owned `replayd` PIDs have already been reniced (>= +15)
    /// to prevent CPU starvation during persistent client-side `RPDaemonProxy` XPC storms.
    public static func isReplaydThrottled(pids: [Int32]) -> Bool {
        guard !pids.isEmpty else { return false }
        for pid in pids where pid > 1 {
            errno = 0
            let prio = getpriority(PRIO_PROCESS, id_t(pid))
            if errno == 0 && prio >= 15 {
                return true
            }
        }
        return false
    }

    /// Safely restarts a wedged user-owned `/usr/libexec/replayd` daemon spinning on XPC
    /// (`_Xmach_notify_port_destroyed`).
    /// - Uses `launchctl kickstart -k gui/<uid>/com.apple.replayd` first (clean Mach job reset) with `SIGTERM`/`SIGKILL` fallback.
    /// - Verifies post-restart CPU after 1.2s: if existing clients (Chrome / headless Chrome / ChatGPT / Codex)
    ///   immediately re-storm `RPDaemonProxy`, applies `nice +20` to `replayd` so interactive apps stay responsive
    ///   and reports the storming client apps honestly.
    public static func restartStuckReplayd(
        minCPUPercent: Double = 20.0,
        forceAlways: Bool = false,
        liveProcesses: [RawProcessInfo]? = nil
    ) -> ReplaydResetReport {
        let isMocked = liveProcesses != nil
        let procs = liveProcesses ?? ((try? ProcessScanner.scanLiveProcesses()) ?? [])
        let targets = procs.filter { proc in
            guard ProcessScanner.isReplaydProcess(proc) else { return false }
            return forceAlways || proc.cpuPercent >= minCPUPercent
        }
        guard !targets.isEmpty else {
            return ReplaydResetReport(didRestart: false)
        }

        let pids = Array(Set(targets.map(\.pid)))
        let totalCPU = targets.reduce(0.0) { $0 + $1.cpuPercent }
        var restartedPIDs: [Int32] = []

        // 1. Clean LaunchAgent kickstart when running against the live OS
        if !isMocked {
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "-k", "gui/\(getuid())/com.apple.replayd"]
            kickstart.standardOutput = Pipe()
            kickstart.standardError = Pipe()
            try? kickstart.run()
            kickstart.waitUntilExit()
            usleep(250_000)

            let exitedByKickstart = pids.filter { kill($0, 0) != 0 }
            restartedPIDs.append(contentsOf: exitedByKickstart)
        }

        // 2. Fallback polite SIGTERM -> SIGKILL for any original PID still wedged
        let remaining = pids.filter { !restartedPIDs.contains($0) }
        if !remaining.isEmpty {
            let termRes = terminatePIDs(remaining, force: false)
            if !termRes.killed.isEmpty {
                for _ in 0..<8 {
                    let stillAlive = termRes.killed.contains { kill($0, 0) == 0 }
                    if !stillAlive { break }
                    usleep(50_000)
                }
                let stubborn = termRes.killed.filter { kill($0, 0) == 0 }
                if !stubborn.isEmpty {
                    _ = terminatePIDs(stubborn, force: true)
                }
                restartedPIDs.append(contentsOf: termRes.killed)
            }
        }

        guard !restartedPIDs.isEmpty else {
            return ReplaydResetReport(
                restartedPIDs: [],
                previousCPUPercent: totalCPU,
                didRestart: false,
                error: "Không đủ quyền khởi động lại replayd (cần tiến trình thuộc user hiện tại)."
            )
        }

        if isMocked {
            return ReplaydResetReport(
                restartedPIDs: restartedPIDs,
                previousCPUPercent: totalCPU,
                postRestartCPUPercent: 0,
                didRestart: true
            )
        }

        // 3. Post-restart verification: check if clients immediately re-storm RPDaemonProxy
        usleep(1_200_000)
        let afterProcs = (try? ProcessScanner.scanLiveProcesses()) ?? []
        let afterReplayd = afterProcs.filter { ProcessScanner.isReplaydProcess($0) }
        let afterCPU = afterReplayd.reduce(0.0) { $0 + $1.cpuPercent }

        var throttledNice = false
        var stormingClients: [String] = []

        if afterCPU >= 25.0 {
            // Deprioritize wedged replayd to nice +20 so interactive Chrome UI, typing, and WindowServer never starve
            for proc in afterReplayd where proc.pid > 1 {
                if setpriority(PRIO_PROCESS, id_t(proc.pid), 20) == 0 {
                    throttledNice = true
                }
            }
            // Identify likely RPDaemonProxy client apps actively burning CPU right now
            let afterGroups = ProcessScanner.aggregate(afterProcs)
            let suspectIDs: Set<String> = [
                "app:Google Chrome",
                "orphan:puppeteer-chrome",
                "app:ChatGPT",
                "app:Codex",
                "app:Codex Computer Use",
                "app:Loom",
                "app:Slack"
            ]
            stormingClients = afterGroups
                .filter { suspectIDs.contains($0.id) && $0.totalCPUPercent >= 8.0 }
                .sorted { $0.totalCPUPercent > $1.totalCPUPercent }
                .prefix(4)
                .map(\.displayName)
        }

        return ReplaydResetReport(
            restartedPIDs: restartedPIDs,
            previousCPUPercent: totalCPU,
            postRestartCPUPercent: afterCPU,
            didRestart: true,
            throttledNice: throttledNice,
            stillStormingFromClients: afterCPU >= 25.0,
            stormingClients: stormingClients,
            error: nil
        )
    }

    /// Soft-resets ONLY normal GUI Google Chrome's GPU process (`--type=gpu-process`).
    /// Chromium auto-respawns its GPU helper in <0.5s with zero closed tabs, zero lost forms, and clears VRAM/compositor loops.
    public static func resetChromeGPUProcess() -> (restartedPIDs: [Int32], totalCPUFreed: Double) {
        guard let live = try? ProcessScanner.scanLiveProcesses() else { return ([], 0) }
        let gpus = live.filter { ProcessScanner.isNormalChromeGPUProcess($0) }
        let pids = Array(Set(gpus.map(\.pid)))
        guard !pids.isEmpty else { return ([], 0) }
        let totalCPU = gpus.reduce(0.0) { $0 + $1.cpuPercent }
        let res = terminatePIDs(pids, force: true)
        return (res.killed, totalCPU)
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

    /// Kills stuck normal Chrome helper renderers (tabs pegged on high CPU or JS/DOM leak loops)
    /// without closing the Chrome app or touching headless automation bots, preserving other windows, tabs, DevTools, and extensions.
    public static func killStuckChromeRenderers(minCPUPercent: Double = 10.0, forceAllRenderers: Bool = false) -> (killedPIDs: [Int32], totalCPUFreed: Double) {
        guard let live = try? ProcessScanner.scanLiveProcesses() else { return ([], 0) }
        let targetRenderers = live.filter { proc in
            guard ProcessScanner.isNormalChromeRendererProcess(proc) else { return false }
            if forceAllRenderers { return true }
            let isHighCPU = proc.cpuPercent >= minCPUPercent
            let isLeakingLoop = proc.cpuPercent >= 8.0 && proc.rssBytes >= 250 * 1_048_576
            return isHighCPU || isLeakingLoop
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
