import AppKit
import Carbon
import Combine
import Foundation
import MacPulseCore

public enum AppTab: String, CaseIterable, Identifiable {
    case overview = "Tổng quan"
    case vietnamese = "Bộ gõ"
    case benchmark = "Đo tốc độ"
    case cleaner = "Dọn dẹp"
    public var id: String { rawValue }
}

public enum CleanerFocusSection: String, Sendable {
    case all
    case ram
    case cache
    case storage
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var selectedTab: AppTab = .overview {
        didSet {
            if selectedTab == .cleaner && Date().timeIntervalSince(lastCleanupScanAt) > 60 {
                scanCleanup()
            }
        }
    }
    private var lastCleanupScanAt: Date = .distantPast
    @Published public var isPopoverVisible: Bool = false
    @Published public var cleanerFocus: CleanerFocusSection = .all

    @Published public var snapshot: SystemSnapshot?
    @Published public var processGroups: [ProcessGroupSummary] = []
    @Published public var healthReport: HealthReport?
    @Published public var lastUpdated: Date = Date()

    @Published public var isBenchmarkRunning: Bool = false
    @Published public var benchmarkStatus: String = "Sẵn sàng"
    @Published public var latestBenchmark: BenchmarkResult?
    @Published public var benchmarkHistory: [BenchmarkResult] = []
    @Published public var benchmarkError: String?

    @Published public var cleanupCandidates: [CleanupCandidate] = []
    @Published public var selectedCleanupIDs: Set<String> = []
    @Published public var isCleaning: Bool = false
    @Published public var isRescuingChrome: Bool = false
    @Published public var cleanupOutcomeMessage: String?

    @Published public var openBrowserTabs: [BrowserTabItem] = []
    @Published public var duplicateTabs: [DuplicateTabGroup] = []
    @Published public var tabWarnings: [String] = []
    @Published public var isScanningTabs: Bool = false
    @Published public var showTabInspector: Bool = false
    @Published public var actionNotice: String?

    @Published public var pendingTerminationGroup: ProcessGroupSummary?
    @Published public var inspectedGuidanceGroup: ProcessGroupSummary?

    // MARK: - EVKey-style Vietnamese Input State
    @Published public var imeSettings: VietnameseSettings {
        didSet {
            guard !isApplyingProgrammaticIMEUpdate else { return }
            inputTapService.updateSettings(imeSettings)
            persistIMEConfig()
        }
    }
    @Published public var isAccessibilityTrusted: Bool = false
    @Published public var tapRuntimeState: TapRuntimeState = .stopped
    @Published public var conflictingApps: [ActiveInputConflict] = []
    @Published public var systemInputSourceID: String = ""
    @Published public var isSystemVietnameseInputSourceActive: Bool = false
    @Published public var frontmostBundleID: String = ""
    @Published public var frontmostAppName: String = ""
    @Published public var perAppCount: Int = 0
    @Published public var imeScratchpad: String = ""

    private let telemetry = SystemTelemetryReader()
    private let benchmarkRunner = BenchmarkRunner()
    private let cleanupScanner = CleanupScanner()
    private let imeStore = VietnameseSettingsStore()
    private let inputTapService: MacInputTapService

    private var schedulerTimer: Timer?
    private var lastProcessScanDate: Date = .distantPast
    private var isRefreshing: Bool = false
    private var isApplyingProgrammaticIMEUpdate = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distObservers: [NSObjectProtocol] = []

    public init() {
        let loaded = imeStore.load()
        if !FileManager.default.fileExists(atPath: imeStore.fileURL.path) {
            try? imeStore.save(loaded)
        }
        self.imeSettings = loaded.settings
        self.perAppCount = loaded.perAppEnabled.count
        self.inputTapService = MacInputTapService(
            settings: loaded.settings,
            perAppEnabled: loaded.perAppEnabled
        )

        self.benchmarkHistory = benchmarkRunner.loadHistory()
        self.latestBenchmark = benchmarkHistory.first

        wireInputTapCallbacks()
        wireEnvironmentObservers()
        refreshIMEEnvironment()
        inputTapService.start()
        refreshNow(includeProcesses: true)
        scanCleanup()
        startAdaptiveScheduler()
    }

    deinit {
        schedulerTimer?.invalidate()
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        for obs in distObservers {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
    }

    public func setPopoverVisible(_ visible: Bool) {
        guard isPopoverVisible != visible else { return }
        isPopoverVisible = visible
        if visible {
            inputTapService.checkAccessibilityStatusNow()
            refreshIMEEnvironment()
            refreshNow(includeProcesses: true)
        } else {
            pendingTerminationGroup = nil
            inspectedGuidanceGroup = nil
        }
        startAdaptiveScheduler()
    }

    private func wireInputTapCallbacks() {
        inputTapService.onLanguageToggled = { [weak self] enabled, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isApplyingProgrammaticIMEUpdate = true
                self.imeSettings.isEnabled = enabled
                self.isApplyingProgrammaticIMEUpdate = false
                self.perAppCount = self.inputTapService.currentPerAppMap().count
                self.persistIMEConfig()
            }
        }
        inputTapService.onRuntimeStateChanged = { [weak self] state, trusted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tapRuntimeState = state
                self.isAccessibilityTrusted = trusted
            }
        }
        inputTapService.onFrontmostAppChanged = { [weak self] bid, name in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.frontmostBundleID = bid
                self.frontmostAppName = name
            }
        }
    }

    private func wireEnvironmentObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let launchObs = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshIMEEnvironment() }
        }
        let termObs = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIMEEnvironment()
                if self?.isPopoverVisible == true {
                    self?.refreshNow(includeProcesses: true)
                }
            }
        }
        let tisObs = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshIMEEnvironment() }
        }
        workspaceObservers = [launchObs, termObs]
        distObservers = [tisObs]
    }

    private func persistIMEConfig() {
        let cfg = PersistedVietnameseConfig(
            settings: imeSettings,
            perAppEnabled: inputTapService.currentPerAppMap()
        )
        try? imeStore.save(cfg)
    }

    public func toggleVietnameseEnabled() {
        imeSettings.isEnabled.toggle()
        perAppCount = inputTapService.currentPerAppMap().count
        if imeSettings.soundOnSwitch {
            let soundName = imeSettings.isEnabled ? "Tink" : "Pop"
            NSSound(named: NSSound.Name(soundName))?.play()
        }
    }

    public func requestAccessibilityPermission() {
        inputTapService.requestAccessibilityAndStart()
        refreshIMEEnvironment()
    }

    public func openAccessibilitySettings() {
        MacInputTapService.openAccessibilitySettings()
    }

    public func terminateConflictingInputApps() {
        let count = MacInputTapService.terminateConflictingApps()
        refreshIMEEnvironment()
        if count > 0 {
            actionNotice = "Đã tắt \(count) bộ gõ trùng để MacPulse hoạt động ổn định."
        }
    }

    public func clearPerAppMemory() {
        inputTapService.setPerAppEnabledMap([:])
        perAppCount = 0
        persistIMEConfig()
        actionNotice = "Đã xoá danh sách nhớ Việt/Anh theo từng ứng dụng."
    }

    public func refreshIMEEnvironment() {
        isAccessibilityTrusted = MacInputTapService.isAccessibilityTrusted(prompt: false)
        conflictingApps = MacInputTapService.detectConflictingApps()
        systemInputSourceID = MacInputTapService.activeSystemInputSourceID()
        isSystemVietnameseInputSourceActive = MacInputTapService.isSystemVietnameseInputSourceActive()
        perAppCount = inputTapService.currentPerAppMap().count
    }

    public var menuBarCompactLabel: String {
        guard let snap = snapshot else { return "--%" }
        let cpu = Int(snap.cpu.totalBusyPercent.rounded())
        let freeG = snap.memory.availableGB
        return String(format: "%d%% • %.1fG", cpu, freeG)
    }

    public var menuBarSymbolName: String {
        imeSettings.isEnabled ? "v.square.fill" : "e.square"
    }

    public var imeStatusSummary: String {
        if !isAccessibilityTrusted { return "Chưa cấp quyền Trợ năng" }
        if !conflictingApps.isEmpty { return "Đang chạy song song: \(conflictingApps.map(\.name).joined(separator: ", "))" }
        if tapRuntimeState == .running {
            return imeSettings.isEnabled ? "Đang bật • Gõ tiếng Việt (\(imeSettings.inputMethod.displayName))" : "Đang bật • Chế độ English"
        }
        return "Đang khởi tạo bộ gõ..."
    }

    public var imeConfigPath: String { imeStore.storagePath }

    private func startAdaptiveScheduler() {
        schedulerTimer?.invalidate()
        let interval: TimeInterval = isPopoverVisible ? 3.0 : 10.0
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                let sinceProc = now.timeIntervalSince(self.lastProcessScanDate)
                let highLoad = (self.snapshot?.cpu.totalBusyPercent ?? 0) >= 55.0 || (self.snapshot?.memory.compressedGB ?? 0) >= 4.5
                let needProc = self.isPopoverVisible || sinceProc >= 30.0 || (highLoad && sinceProc >= 10.0)
                self.refreshNow(includeProcesses: needProc)
            }
        }
    }

    public func refreshNow(includeProcesses: Bool = true) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let cachedGroups = self.processGroups

        Task.detached(priority: .utility) { [telemetry] in
            let snap = try? telemetry.captureSnapshot()
            var groups = cachedGroups
            var scannedProcs = false
            if includeProcesses || cachedGroups.isEmpty {
                let procs = (try? ProcessScanner.scanLiveProcesses()) ?? []
                groups = ProcessScanner.aggregate(procs)
                scannedProcs = true
            }
            let report = snap.map { HealthAnalyzer.analyze(snapshot: $0, processGroups: groups) }
            let didScanProcs = scannedProcs
            let finalGroups = groups

            await MainActor.run {
                if let snap { self.snapshot = snap }
                if didScanProcs {
                    self.processGroups = finalGroups
                    self.lastProcessScanDate = Date()
                }
                if let report { self.healthReport = report }
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }

    public func runBenchmark() {
        guard !isBenchmarkRunning else { return }
        isBenchmarkRunning = true
        benchmarkError = nil
        benchmarkStatus = "Đang đo CPU, RAM và SSD..."

        Task.detached(priority: .userInitiated) { [benchmarkRunner] in
            do {
                let res = try benchmarkRunner.runSync { stage in
                    Task { @MainActor in
                        self.benchmarkStatus = stage
                    }
                }
                try benchmarkRunner.saveResult(res)
                let updatedHistory = benchmarkRunner.loadHistory()
                await MainActor.run {
                    self.latestBenchmark = res
                    self.benchmarkHistory = updatedHistory
                    self.benchmarkStatus = "Hoàn tất trong \(String(format: "%.2fs", res.totalDurationSeconds))"
                    self.isBenchmarkRunning = false
                }
            } catch {
                await MainActor.run {
                    self.benchmarkError = error.localizedDescription
                    self.benchmarkStatus = "Đo thất bại"
                    self.isBenchmarkRunning = false
                }
            }
        }
    }

    public func scanCleanup() {
        Task.detached(priority: .utility) { [cleanupScanner] in
            let found = cleanupScanner.scan()
            let defaults = Set(found.filter { $0.defaultSelected && $0.tier == .safeAutoClean }.map(\.id))
            await MainActor.run {
                self.cleanupCandidates = found
                self.lastCleanupScanAt = Date()
                self.selectedCleanupIDs = defaults
            }
        }
    }

    public func toggleCleanupSelection(_ id: String) {
        if selectedCleanupIDs.contains(id) {
            selectedCleanupIDs.remove(id)
        } else {
            selectedCleanupIDs.insert(id)
        }
    }

    public var cacheCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .cache }
    }

    public var logAndTrashCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .logsAndTrash }
    }

    public var storageHeavyCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .storageHeavyData }
    }

    public var totalSelectedCleanupBytes: UInt64 {
        cleanupCandidates
            .filter { selectedCleanupIDs.contains($0.id) && $0.tier == .safeAutoClean }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalSafeCacheBytes: UInt64 {
        cleanupCandidates
            .filter { $0.tier == .safeAutoClean && $0.category == .cache }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalHeavyStorageBytes: UInt64 {
        cleanupCandidates
            .filter { $0.category == .storageHeavyData }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    public var ramReclaimableGroups: [ProcessGroupSummary] {
        processGroups
            .filter { group in
                guard group.guidance.safetyLevel == .safeNow || group.guidance.safetyLevel == .cautionSaveFirst else {
                    return false
                }
                return group.isOrphanAutomation || group.totalRSSBytes >= 100_000_000 || group.totalCPUPercent >= 25.0
            }
            .sorted { lhs, rhs in
                if lhs.isOrphanAutomation != rhs.isOrphanAutomation {
                    return lhs.isOrphanAutomation
                }
                return lhs.totalRSSBytes > rhs.totalRSSBytes
            }
            .prefix(8)
            .map { $0 }
    }

    public var estimatedReclaimableRAMBytes: UInt64 {
        ramReclaimableGroups.reduce(0) { $0 + $1.totalRSSBytes }
    }


    public func rescueAndCleanChrome(relaunch: Bool = true) {
        guard !isRescuingChrome && !isCleaning else { return }
        isRescuingChrome = true
        cleanupOutcomeMessage = nil

        Task.detached(priority: .userInitiated) {
            let report = CleanupExecutor.rescueAndCleanChrome(relaunch: relaunch)
            let rescanned = self.cleanupScanner.scan()
            let remainingDefaults = Set(rescanned.filter { $0.defaultSelected && $0.tier == .safeAutoClean }.map(\.id))
            await MainActor.run {
                self.cleanupCandidates = rescanned
                self.selectedCleanupIDs = remainingDefaults
                self.isRescuingChrome = false
                let freedText = Formatters.bytes(report.freedBytes)
                let stoppedCount = report.stoppedChromePIDs.count
                let lockCount = report.removedLockFiles.count
                let relaunchNote = report.relaunchedChrome ? " Đã mở lại Chrome." : ""
                let msg = "Đã sửa & dọn sạch Chrome: tắt \(stoppedCount) tiến trình, gỡ \(lockCount) lock, xoá \(freedText) cache.\(relaunchNote)"
                self.cleanupOutcomeMessage = report.errors.isEmpty
                    ? msg
                    : "\(msg) (Cảnh báo: \(report.errors.joined(separator: "; ")))"
                self.actionNotice = self.cleanupOutcomeMessage
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func runSelectedCleanup() {
        guard !isCleaning else { return }
        let chosen = cleanupCandidates.filter { selectedCleanupIDs.contains($0.id) && $0.tier == .safeAutoClean }
        guard !chosen.isEmpty else { return }
        isCleaning = true
        cleanupOutcomeMessage = nil

        Task.detached(priority: .userInitiated) {
            let outcome = CleanupExecutor.execute(candidates: chosen)
            let rescanned = self.cleanupScanner.scan()
            let remainingDefaults = Set(rescanned.filter { $0.defaultSelected && $0.tier == .safeAutoClean }.map(\.id))
            await MainActor.run {
                self.cleanupCandidates = rescanned
                self.selectedCleanupIDs = remainingDefaults
                self.isCleaning = false
                if outcome.errors.isEmpty {
                    self.cleanupOutcomeMessage = "Đã giải phóng \(Formatters.bytes(outcome.freedBytes)) ổ cứng SSD (\(outcome.processedCount) mục)."
                } else {
                    self.cleanupOutcomeMessage = "Giải phóng \(Formatters.bytes(outcome.freedBytes)), còn \(outcome.errors.count) lỗi nhỏ."
                }
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func requestCloseProcess(_ group: ProcessGroupSummary) {
        if group.isOrphanAutomation {
            let res = CleanupExecutor.terminateOrphanPuppeteerProcesses(force: false)
            actionNotice = "Đã dọn \(res.killed.count) tiến trình Chrome automation ngầm (không ảnh hưởng Chrome chính)."
            refreshAfterDelay()
            return
        }

        if group.guidance.safetyLevel == .systemProtected || group.guidance.safetyLevel == .remoteKeepAlive {
            inspectedGuidanceGroup = group
            return
        }

        if group.actionKind == .inspectBrowserTabs {
            showTabInspector = true
            scanBrowserTabs()
        }
        pendingTerminationGroup = group
    }

    public func confirmTermination(for group: ProcessGroupSummary, force: Bool) {
        pendingTerminationGroup = nil

        if group.isOrphanAutomation {
            let res = CleanupExecutor.terminateOrphanPuppeteerProcesses(force: force)
            actionNotice = "Đã dọn \(res.killed.count) tiến trình automation ngầm."
            refreshAfterDelay()
            return
        }

        guard group.guidance.safetyLevel != .systemProtected && group.guidance.safetyLevel != .remoteKeepAlive else {
            actionNotice = "Đã chặn đóng \(group.displayName) để bảo vệ hệ thống / phiên kết nối từ xa."
            return
        }

        if let bundleID = group.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            var sent = false
            for app in running {
                if force {
                    sent = app.forceTerminate() || sent
                } else {
                    sent = app.terminate() || sent
                }
            }
            if !sent && !group.pids.isEmpty {
                let res = CleanupExecutor.terminatePIDs(group.pids, force: force)
                if !res.killed.isEmpty { sent = true }
            }
            if sent {
                actionNotice = force
                    ? "Đã ép tắt \(group.displayName) (giải phóng ~\(Formatters.bytes(group.totalRSSBytes)) RAM)."
                    : "Đã gửi lệnh đóng nhẹ (Cmd+Q) tới \(group.displayName). Nếu app đơ chưa tắt, bấm Đóng lần nữa để chọn Ép tắt."
            } else {
                actionNotice = "Không thể gửi lệnh đóng tới \(group.displayName) — thử chọn Ép tắt."
            }
            refreshAfterDelay()
            return
        }

        let res = CleanupExecutor.terminatePIDs(group.pids, force: force)
        if !res.killed.isEmpty {
            actionNotice = "Đã tắt \(group.displayName) (\(res.killed.count) tiến trình, ~\(Formatters.bytes(group.totalRSSBytes)) RAM)."
        } else {
            actionNotice = "Không đủ quyền hoặc tiến trình \(group.displayName) đã thoát."
        }
        refreshAfterDelay()
    }

    public func performRecommendedAction(_ action: ProcessActionKind, targetID: String?) {
        switch action {
        case .none:
            break
        case .killOrphanPuppeteer:
            let res = CleanupExecutor.terminateOrphanPuppeteerProcesses()
            actionNotice = "Đã tắt \(res.killed.count) tiến trình Chrome headless dư thừa."
            refreshAfterDelay()
        case .quitAppGracefully, .terminateUserProcess:
            if let group = processGroups.first(where: { $0.id == targetID }) {
                requestCloseProcess(group)
            }
        case .inspectBrowserTabs:
            showTabInspector = true
            scanBrowserTabs()
        case .openCleanerTab:
            if targetID == "ram" {
                cleanerFocus = .ram
            } else if targetID == "ssd" {
                cleanerFocus = .storage
            } else {
                cleanerFocus = .cache
            }
            selectedTab = .cleaner
        }
    }

    private func refreshAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.refreshNow(includeProcesses: true)
        }
    }

    public func scanDuplicateTabs() {
        scanBrowserTabs()
    }

    public func scanBrowserTabs() {
        guard !isScanningTabs else { return }
        isScanningTabs = true
        showTabInspector = true
        Task.detached(priority: .utility) {
            let res = BrowserTabInspector.fetchRunningBrowserTabs()
            let dups = BrowserTabInspector.findDuplicates(in: res.tabs)
            await MainActor.run {
                self.openBrowserTabs = res.tabs
                self.duplicateTabs = dups
                self.tabWarnings = res.warnings
                self.isScanningTabs = false
            }
        }
    }

    public func closeSingleBrowserTab(_ tab: BrowserTabItem) {
        Task.detached(priority: .userInitiated) {
            let ok = BrowserTabInspector.closeTab(tab)
            let res = BrowserTabInspector.fetchRunningBrowserTabs()
            let dups = BrowserTabInspector.findDuplicates(in: res.tabs)
            await MainActor.run {
                self.openBrowserTabs = res.tabs
                self.duplicateTabs = dups
                self.tabWarnings = res.warnings
                self.actionNotice = ok ? "Đã đóng tab: \(tab.title)" : "Không khớp tab (có thể bạn đã chuyển hoặc đóng tab này)."
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func closeDuplicateExtras() {
        let toClose = duplicateTabs.flatMap { Array($0.tabs.dropFirst()) }
        guard !toClose.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            var closed = 0
            for tab in toClose.reversed() {
                if BrowserTabInspector.closeTab(tab) {
                    closed += 1
                }
            }
            let closedCount = closed
            let res = BrowserTabInspector.fetchRunningBrowserTabs()
            let dups = BrowserTabInspector.findDuplicates(in: res.tabs)
            await MainActor.run {
                self.openBrowserTabs = res.tabs
                self.duplicateTabs = dups
                self.tabWarnings = res.warnings
                self.actionNotice = "Đã đóng \(closedCount) tab trùng lặp."
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
