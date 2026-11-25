import AppKit
import Carbon
import Combine
import Foundation
import MacPulseCore
import ServiceManagement

public enum AppTab: String, CaseIterable, Identifiable {
    case overview = "Tổng quan"
    case aiPulse = "AI & OC"
    case cleaner = "Dọn dẹp"
    case vietnamese = "Bộ gõ"
    case benchmark = "Đo tốc độ"
    public var id: String { rawValue }
}

public enum CleanerFocusSection: String, CaseIterable, Identifiable, Sendable {
    case all = "Tất cả"
    case ai = "Rác AI"
    case browser = "Trình duyệt"
    case developer = "Lập trình"
    case logs = "Log & Rác"
    case storage = "Bộ nhớ lớn"
    case ram = "RAM (Đang chạy)"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .ai: return "sparkles"
        case .browser: return "globe"
        case .developer: return "hammer.fill"
        case .logs: return "doc.text.fill"
        case .storage: return "internaldrive"
        case .ram: return "memorychip"
        }
    }
}

public enum ProcessFilterCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "Tất cả"
    case apps = "Ứng dụng"
    case background = "Dịch vụ ngầm"
    case heavy = "Tốn CPU/RAM"
    public var id: String { rawValue }
}

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case standard = "CPU • RAM"
    case withAI = "CPU • AI"
    case minimal = "Gọn (VI/EN)"
    public var id: String { rawValue }
}

public enum AppAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case darkCockpit = "Dark Cockpit"
    case system = "Theo macOS"
    public var id: String { rawValue }
}

public enum NoticeKind: Sendable, Equatable {
    case success
    case info
    case warning
    case error
}

@MainActor
public final class AppViewModel: ObservableObject {
    private enum PrefKeys {
        static let menuBarMode = "macpulse.menuBarDisplayMode"
        static let appearanceMode = "macpulse.appearanceMode"
        static let selectedLocalSite = "macpulse.selectedLocalSite"
    }

    @Published public var selectedTab: AppTab = .overview {
        didSet {
            if selectedTab == .cleaner && Date().timeIntervalSince(lastCleanupScanAt) > 60 {
                scanCleanup()
            } else if selectedTab == .aiPulse {
                openCodeUnreadCompletions = 0
                pollOpenCode(forceRead: true)
                if aiSnapshot == nil || Date().timeIntervalSince(aiSnapshot?.timestamp ?? .distantPast) > 45 {
                    refreshAIQuota()
                }
            }
        }
    }
    private var lastCleanupScanAt: Date = .distantPast
    @Published public var isPopoverVisible: Bool = false
    @Published public var cleanerFocus: CleanerFocusSection = .all

    // MARK: - App Preferences & System Integration
    @Published public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: PrefKeys.menuBarMode) }
    }
    @Published public var appearanceMode: AppAppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: PrefKeys.appearanceMode) }
    }
    @Published public var launchAtLoginEnabled: Bool = false

    // MARK: - AI Pulse & OpenCode Task Monitor State
    @Published public var aiSnapshot: AITokenSnapshot?
    @Published public var isScanningAI: Bool = false
    private let aiTokenMonitor = AITokenMonitor()

    @Published public var openCodeConfig: OpenCodeNotifyConfig {
        didSet {
            guard !isApplyingProgrammaticOpenCodeUpdate else { return }
            persistOpenCodeState()
            if openCodeConfig.isEnabled && openCodeConfig.showSystemNotification {
                OpenCodeAlertManager.shared.requestNotificationPermissionIfNeeded()
            }
            pollOpenCode(forceRead: true)
        }
    }
    @Published public var isOpenCodeAvailable: Bool = false
    @Published public var openCodeRunningSessions: [OpenCodeSessionItem] = []
    @Published public var openCodeRecentSessions: [OpenCodeSessionItem] = []
    @Published public var openCodeRecentAlerts: [OpenCodeCompletionEvent] = []
    @Published public var openCodeUnreadCompletions: Int = 0
    private let openCodeMonitor = OpenCodeMonitor()
    private let openCodeStore = OpenCodeMonitorStore()
    private var openCodePollTimer: Timer?
    private var isPollingOpenCode: Bool = false
    private var isApplyingProgrammaticOpenCodeUpdate = false

    // MARK: - System Telemetry & Sparkline History
    @Published public var snapshot: SystemSnapshot?
    @Published public var cpuHistory: [Double] = []
    @Published public var ramHistory: [Double] = []
    @Published public var processGroups: [ProcessGroupSummary] = []
    @Published public var rawProcesses: [RawProcessInfo] = []
    @Published public var healthReport: HealthReport?
    @Published public var lastUpdated: Date = Date()
    @Published public var hardwareSpecs: HardwareSpecs = SystemTelemetryReader.getHardwareSpecs()
    @Published public var hardwareModelName: String = SystemTelemetryReader.getHardwareModelName()

    // MARK: - Benchmark State
    @Published public var isBenchmarkRunning: Bool = false
    @Published public var benchmarkStatus: String = "Sẵn sàng"
    @Published public var latestBenchmark: BenchmarkResult?
    @Published public var benchmarkHistory: [BenchmarkResult] = []
    @Published public var benchmarkError: String?
    @Published public var availableLocalSites: [String] = []
    @Published public var selectedLocalSiteForBench: String = "" {
        didSet { UserDefaults.standard.set(selectedLocalSiteForBench, forKey: PrefKeys.selectedLocalSite) }
    }

    // MARK: - Cleaner & Chrome Rescue State
    @Published public var cleanupCandidates: [CleanupCandidate] = []
    @Published public var selectedCleanupIDs: Set<String> = []
    @Published public var isScanningCleanup: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var isRescuingChrome: Bool = false
    @Published public var cleanupOutcomeMessage: String?

    // MARK: - Autopilot Auto-Optimizer State
    @Published public var autoOptimizeConfig: AutoOptimizeConfig {
        didSet {
            guard !isApplyingProgrammaticAutoOptUpdate else { return }
            persistAutoOptimizeState()
        }
    }
    @Published public var autoOptimizeLastRunAt: Date?
    @Published public var autoOptimizeLifetimeFreedBytes: UInt64 = 0
    @Published public var autoOptimizeLifetimeReclaimedRAMBytes: UInt64 = 0
    @Published public var autoOptimizeTotalIdleAppsClosed: Int = 0
    @Published public var autoOptimizeHistory: [AutoOptimizeRunRecord] = []
    @Published public var isAutoOptimizing: Bool = false
    @Published public var trackedGUIApps: [TrackedGUIApp] = []
    private var appLastActiveAt: [String: Date] = [:]
    private var lastTrackedFrontmostBid: String = ""

    // MARK: - Browser Tabs Inspector State
    @Published public var openBrowserTabs: [BrowserTabItem] = []
    @Published public var duplicateTabs: [DuplicateTabGroup] = []
    @Published public var tabWarnings: [String] = []
    @Published public var isScanningTabs: Bool = false
    @Published public var showTabInspector: Bool = false
    @Published public var tabSearchQuery: String = ""
    @Published public var showAllTabs: Bool = false

    // MARK: - Smart Action Toast
    @Published public var actionNotice: String?
    @Published public var actionNoticeKind: NoticeKind = .info
    private var noticeDismissTask: Task<Void, Never>?

    // MARK: - Process List Filtering & Sorting
    @Published public var processSearchQuery: String = ""
    @Published public var processCategoryFilter: ProcessFilterCategory = .all
    @Published public var processSortOrder: ProcessSortOrder = .smart
    @Published public var showAllProcesses: Bool = false

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
    private let autoOptStore = AutoOptimizerStore()
    private let imeStore = VietnameseSettingsStore()
    private let inputTapService: MacInputTapService

    private var schedulerTimer: Timer?
    private var autoOptimizeTimer: Timer?
    private var lastProcessScanDate: Date = .distantPast
    private var isRefreshing: Bool = false
    private var isApplyingProgrammaticIMEUpdate = false
    private var isApplyingProgrammaticAutoOptUpdate = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distObservers: [NSObjectProtocol] = []

    public init() {
        let savedMenuRaw = UserDefaults.standard.string(forKey: PrefKeys.menuBarMode) ?? MenuBarDisplayMode.standard.rawValue
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedMenuRaw) ?? .standard

        let savedAppRaw = UserDefaults.standard.string(forKey: PrefKeys.appearanceMode) ?? AppAppearanceMode.darkCockpit.rawValue
        self.appearanceMode = AppAppearanceMode(rawValue: savedAppRaw) ?? .darkCockpit

        let discoveredSites = BenchmarkRunner.discoverLocalWPSites()
        let rawSavedSite = UserDefaults.standard.string(forKey: PrefKeys.selectedLocalSite) ?? ""
        self.availableLocalSites = discoveredSites
        self.selectedLocalSiteForBench = discoveredSites.contains(rawSavedSite) ? rawSavedSite : ""

        let loadedAutoOpt = autoOptStore.load()
        if !FileManager.default.fileExists(atPath: autoOptStore.fileURL.path) {
            try? autoOptStore.save(loadedAutoOpt)
        }
        self.autoOptimizeConfig = loadedAutoOpt.config
        self.autoOptimizeLastRunAt = loadedAutoOpt.lastRunAt
        self.autoOptimizeLifetimeFreedBytes = loadedAutoOpt.totalLifetimeFreedBytes
        self.autoOptimizeLifetimeReclaimedRAMBytes = loadedAutoOpt.totalLifetimeReclaimedRAMBytes
        self.autoOptimizeTotalIdleAppsClosed = loadedAutoOpt.totalIdleAppsClosed
        self.autoOptimizeHistory = loadedAutoOpt.history

        // Seed initial activity timestamps for all open GUI apps so nothing gets auto-closed right after launch
        let launchNow = Date()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let bid = app.bundleIdentifier, !bid.isEmpty {
                self.appLastActiveAt[bid] = launchNow
                if app.isActive {
                    self.lastTrackedFrontmostBid = bid
                }
            }
        }

        let loadedOpenCode = openCodeStore.load()
        if !FileManager.default.fileExists(atPath: openCodeStore.fileURL.path) {
            try? openCodeStore.save(loadedOpenCode)
        }
        self.openCodeConfig = loadedOpenCode.config
        self.openCodeRecentAlerts = loadedOpenCode.recentAlerts

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
        self.launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)

        wireInputTapCallbacks()
        wireEnvironmentObservers()
        refreshIMEEnvironment()
        inputTapService.start()
        refreshNow(includeProcesses: true)
        startAdaptiveScheduler()
        startAutoOptimizeScheduler()
        startOpenCodeWatcher()

        // Defer non-critical background scans slightly so app launch is instant (<100ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.pollOpenCode(forceRead: true)
            if self?.openCodeConfig.isEnabled == true && self?.openCodeConfig.showSystemNotification == true {
                OpenCodeAlertManager.shared.requestNotificationPermissionIfNeeded()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refreshAIQuota()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.lastCleanupScanAt == .distantPast else { return }
            self.scanCleanup()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            self?.checkAndRunAutoOptimizeIfNeeded()
        }
    }

    deinit {
        schedulerTimer?.invalidate()
        autoOptimizeTimer?.invalidate()
        openCodePollTimer?.invalidate()
        noticeDismissTask?.cancel()
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        for obs in distObservers {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
    }

    // MARK: - Smart Notice Helper
    public func showNotice(_ message: String, kind: NoticeKind = .success, autoDismissSeconds: Double? = 6.0) {
        noticeDismissTask?.cancel()
        actionNotice = message
        actionNoticeKind = kind
        if let delay = autoDismissSeconds, kind != .error {
            noticeDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if self?.actionNotice == message {
                    self?.actionNotice = nil
                }
            }
        }
    }

    public func dismissNotice() {
        noticeDismissTask?.cancel()
        actionNotice = nil
    }

    // MARK: - Launch at Login (SMAppService)
    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            showNotice(
                launchAtLoginEnabled
                    ? "Đã bật Tự khởi động MacPulse cùng macOS."
                    : "Đã tắt Tự khởi động cùng macOS.",
                kind: .success
            )
        } catch {
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            showNotice("Không thể thay đổi Khởi động cùng macOS: \(error.localizedDescription)", kind: .warning)
        }
    }

    public func toggleAppearanceMode() {
        appearanceMode = (appearanceMode == .darkCockpit) ? .system : .darkCockpit
    }

    public func cycleMenuBarDisplayMode() {
        let all = MenuBarDisplayMode.allCases
        if let idx = all.firstIndex(of: menuBarDisplayMode) {
            menuBarDisplayMode = all[(idx + 1) % all.count]
        }
    }

    public func setPopoverVisible(_ visible: Bool) {
        guard isPopoverVisible != visible else { return }
        isPopoverVisible = visible
        if visible {
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            inputTapService.checkAccessibilityStatusNow()
            refreshIMEEnvironment()
            refreshTrackedGUIApps()
            refreshNow(includeProcesses: true)
            if aiSnapshot == nil || Date().timeIntervalSince(aiSnapshot?.timestamp ?? .distantPast) > 90 {
                refreshAIQuota()
            }
            if lastCleanupScanAt == .distantPast {
                scanCleanup()
            }
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
                let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
                if !bid.isEmpty && bid != selfBid {
                    self.frontmostBundleID = bid
                    self.frontmostAppName = name
                }
            }
        }
    }

    private func wireEnvironmentObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let launchObs = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let launchedBid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let bid = launchedBid, !bid.isEmpty {
                    self.appLastActiveAt[bid] = Date()
                }
                self.refreshIMEEnvironment()
                self.refreshTrackedGUIApps()
            }
        }
        let activateObs = nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let activeBid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                if !self.lastTrackedFrontmostBid.isEmpty {
                    self.appLastActiveAt[self.lastTrackedFrontmostBid] = now
                }
                if let bid = activeBid, !bid.isEmpty {
                    self.appLastActiveAt[bid] = now
                    self.lastTrackedFrontmostBid = bid
                }
            }
        }
        let termObs = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let termBid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let bid = termBid {
                    self.appLastActiveAt.removeValue(forKey: bid)
                }
                self.refreshIMEEnvironment()
                self.refreshTrackedGUIApps()
                if self.isPopoverVisible {
                    self.refreshNow(includeProcesses: true)
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
        workspaceObservers = [launchObs, activateObs, termObs]
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

    public func switchSystemInputSourceToABC() {
        let ok = MacInputTapService.switchSystemInputSourceToABC()
        refreshIMEEnvironment()
        if ok {
            showNotice("Đã chuyển nguồn gõ macOS về ABC — MacPulse sẵn sàng gõ mượt.", kind: .success)
        } else {
            showNotice("Không tìm thấy bàn phím ABC/U.S. trong hệ thống macOS.", kind: .warning)
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
            showNotice("Đã tắt \(count) bộ gõ trùng để MacPulse hoạt động ổn định.", kind: .success)
        }
    }

    public func clearPerAppMemory() {
        inputTapService.setPerAppEnabledMap([:])
        perAppCount = 0
        persistIMEConfig()
        showNotice("Đã xoá danh sách nhớ Việt/Anh theo từng ứng dụng.", kind: .info)
    }

    public func addAppToExcluded(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        guard !imeSettings.excludedBundleIDs.contains(bundleID) else { return }
        imeSettings.excludedBundleIDs.append(bundleID)
        inputTapService.updateSettings(imeSettings)
        persistIMEConfig()
    }

    public func removeAppFromExcluded(_ bundleID: String) {
        imeSettings.excludedBundleIDs.removeAll(where: { $0 == bundleID })
        inputTapService.updateSettings(imeSettings)
        persistIMEConfig()
    }

    public func refreshIMEEnvironment() {
        isAccessibilityTrusted = MacInputTapService.isAccessibilityTrusted(prompt: false)
        conflictingApps = MacInputTapService.detectConflictingApps()
        systemInputSourceID = MacInputTapService.activeSystemInputSourceID()
        isSystemVietnameseInputSourceActive = MacInputTapService.isSystemVietnameseInputSourceActive()
        perAppCount = inputTapService.currentPerAppMap().count
    }

    public var isFrontmostAppBypassed: Bool {
        VietnameseAppDetector.computeIsAppExcluded(
            bundleID: frontmostBundleID,
            appName: frontmostAppName,
            settings: imeSettings,
            perAppEnabled: inputTapService.currentPerAppMap()
        )
    }

    public func refreshAIQuota() {
        guard !isScanningAI else { return }
        isScanningAI = true
        Task.detached(priority: .utility) { [aiTokenMonitor] in
            let snap = aiTokenMonitor.scanAll()
            await MainActor.run {
                self.aiSnapshot = snap
                self.isScanningAI = false
            }
        }
    }

    // MARK: - OpenCode Task Completion Monitor & Notifier
    private func persistOpenCodeState() {
        let state = PersistedOpenCodeNotifyState(
            config: openCodeConfig,
            recentAlerts: Array(openCodeRecentAlerts.prefix(15))
        )
        try? openCodeStore.save(state)
    }

    private func startOpenCodeWatcher() {
        openCodePollTimer?.invalidate()
        openCodePollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollOpenCode(forceRead: false)
            }
        }
    }

    public func pollOpenCode(forceRead: Bool = false) {
        guard !isPollingOpenCode else { return }
        isPollingOpenCode = true
        let cfg = openCodeConfig
        Task.detached(priority: .utility) { [openCodeMonitor] in
            let res = openCodeMonitor.poll(config: cfg, forceRead: forceRead)
            await MainActor.run {
                self.isPollingOpenCode = false
                if !res.didReadDatabase && self.isOpenCodeAvailable == res.isDatabaseAvailable {
                    return
                }
                self.isOpenCodeAvailable = res.isDatabaseAvailable
                self.openCodeRunningSessions = res.runningSessions
                self.openCodeRecentSessions = res.recentSessions

                if !res.newlyCompleted.isEmpty {
                    for ev in res.newlyCompleted {
                        self.openCodeRecentAlerts.insert(ev, at: 0)
                        OpenCodeAlertManager.shared.deliverAlert(for: ev, config: self.openCodeConfig)
                    }
                    if self.openCodeRecentAlerts.count > 15 {
                        self.openCodeRecentAlerts = Array(self.openCodeRecentAlerts.prefix(15))
                    }
                    if !(self.isPopoverVisible && self.selectedTab == .aiPulse) {
                        self.openCodeUnreadCompletions += res.newlyCompleted.count
                    }
                    self.persistOpenCodeState()
                }
            }
        }
    }

    public func testOpenCodeAlert() {
        let sample = OpenCodeCompletionEvent(
            sessionID: "test-\(UUID().uuidString.prefix(8))",
            title: "Responsive plan for section two desktop",
            promptSummary: "Hoàn tất code & kiểm tra responsive — bấm Mở OpenCode để xem ngay",
            modeLabel: "CODE",
            projectName: "alonepro",
            directory: NSHomeDirectory(),
            outcome: .succeeded,
            durationSeconds: 47,
            completedAt: Date()
        )
        OpenCodeAlertManager.shared.deliverAlert(for: sample, config: openCodeConfig)
        showNotice("Đã gửi thông báo thử nghiệm OpenCode (âm thanh + HUD nổi).", kind: .success)
    }

    public func previewOpenCodeSound(_ soundName: String) {
        openCodeConfig.soundName = soundName
        OpenCodeAlertManager.shared.playPreviewSound(soundName)
    }

    public func focusOpenCodeHost() {
        OpenCodeAlertManager.shared.focusOpenCodeHostApp()
    }

    public func clearOpenCodeAlertHistory() {
        openCodeRecentAlerts = []
        openCodeUnreadCompletions = 0
        persistOpenCodeState()
    }

    public var menuBarCompactLabel: String {
        switch menuBarDisplayMode {
        case .minimal:
            return ""
        case .standard:
            guard let snap = snapshot else { return "--%" }
            let cpu = Int(snap.cpu.totalBusyPercent.rounded())
            let freeG = snap.memory.availableGB
            return String(format: "%d%% • %.1fG", cpu, freeG)
        case .withAI:
            let cpu = Int((snapshot?.cpu.totalBusyPercent ?? 0).rounded())
            if !openCodeRunningSessions.isEmpty {
                return "\(cpu)% • OC \(openCodeRunningSessions.count)⚡"
            }
            if openCodeUnreadCompletions > 0 {
                return "\(cpu)% • OC ✓"
            }
            if let gptRem = aiSnapshot?.chatGPT?.fiveHourQuota?.remainingPercent {
                return "\(cpu)% • GPT \(Int(gptRem.rounded()))%"
            }
            guard let snap = snapshot else { return "--%" }
            return String(format: "%d%% • %.1fG", cpu, snap.memory.availableGB)
        }
    }

    public var menuBarSymbolName: String {
        imeSettings.isEnabled ? "v.square.fill" : "e.square"
    }

    public var imeStatusSummary: String {
        if !isAccessibilityTrusted { return "Chưa cấp quyền Trợ năng" }
        if !conflictingApps.isEmpty { return "Đang chạy song song: \(conflictingApps.map(\.name).joined(separator: ", "))" }
        if tapRuntimeState == .running {
            return imeSettings.isEnabled ? "EventTap Active • Tiếng Việt (\(imeSettings.inputMethod.displayName))" : "EventTap Active • Chế độ English"
        }
        return "Đang khởi tạo bộ gõ..."
    }

    public var imeConfigPath: String { imeStore.storagePath }

    private func startAdaptiveScheduler() {
        schedulerTimer?.invalidate()
        let interval: TimeInterval = isPopoverVisible ? 4.0 : 12.0
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
        let cachedRaw = self.rawProcesses

        Task.detached(priority: .utility) { [telemetry] in
            let snap = try? telemetry.captureSnapshot()
            var groups = cachedGroups
            var scannedProcs = false
            var scannedRaw = cachedRaw
            if includeProcesses || cachedGroups.isEmpty {
                let procs = (try? ProcessScanner.scanLiveProcesses()) ?? []
                groups = ProcessScanner.aggregate(procs)
                scannedRaw = procs
                scannedProcs = true
            }

            let stuckRenderers = scannedRaw.filter {
                ProcessScanner.isNormalChromeRendererProcess($0)
                && ($0.cpuPercent >= 10.0 || ($0.cpuPercent >= 8.0 && $0.rssBytes >= 250 * 1_048_576))
            }
            let stuckCount = stuckRenderers.count
            let stuckCPU = stuckRenderers.reduce(0.0) { $0 + $1.cpuPercent }
            let chromeGPUCPU = scannedRaw
                .filter { ProcessScanner.isNormalChromeGPUProcess($0) }
                .reduce(0.0) { $0 + $1.cpuPercent }

            let report = snap.map {
                HealthAnalyzer.analyze(
                    snapshot: $0,
                    processGroups: groups,
                    stuckChromeRendererCount: stuckCount,
                    stuckChromeRendererCPU: stuckCPU,
                    chromeGPUCPU: chromeGPUCPU
                )
            }
            let didScanProcs = scannedProcs
            let finalGroups = groups
            let finalRaw = scannedRaw

            await MainActor.run {
                if let snap {
                    self.snapshot = snap
                    self.cpuHistory.append(snap.cpu.totalBusyPercent)
                    if self.cpuHistory.count > 30 { self.cpuHistory.removeFirst() }
                    self.ramHistory.append(snap.memory.usedPercent)
                    if self.ramHistory.count > 30 { self.ramHistory.removeFirst() }
                }
                if didScanProcs {
                    self.processGroups = finalGroups
                    self.rawProcesses = finalRaw
                    self.lastProcessScanDate = Date()
                    self.refreshTrackedGUIApps()
                }
                if let report { self.healthReport = report }
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }

    // MARK: - Benchmark
    public func refreshLocalSites() {
        availableLocalSites = BenchmarkRunner.discoverLocalWPSites()
        if !selectedLocalSiteForBench.isEmpty && !availableLocalSites.contains(selectedLocalSiteForBench) {
            selectedLocalSiteForBench = ""
        }
    }

    public func runBenchmark() {
        guard !isBenchmarkRunning else { return }
        isBenchmarkRunning = true
        benchmarkError = nil
        benchmarkStatus = "Đang đo CPU, RAM và SSD..."

        let probeURL: URL? = selectedLocalSiteForBench.isEmpty
            ? nil
            : URL(string: "http://\(selectedLocalSiteForBench).local/")

        Task.detached(priority: .userInitiated) { [benchmarkRunner] in
            do {
                // runSync already persists the result once — no duplicate saveResult()!
                let res = try benchmarkRunner.runSync(localURLToProbe: probeURL) { stage in
                    Task { @MainActor in
                        self.benchmarkStatus = stage
                    }
                }
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

    public var previousBenchmark: BenchmarkResult? {
        benchmarkHistory.count >= 2 ? benchmarkHistory[1] : nil
    }

    // MARK: - Autopilot Auto-Optimizer (Zero-Lag Background Sweeper + Idle App Auto-Sleeper)
    private func persistAutoOptimizeState() {
        let state = PersistedAutoOptimizeState(
            config: autoOptimizeConfig,
            lastRunAt: autoOptimizeLastRunAt,
            totalLifetimeFreedBytes: autoOptimizeLifetimeFreedBytes,
            totalLifetimeReclaimedRAMBytes: autoOptimizeLifetimeReclaimedRAMBytes,
            totalIdleAppsClosed: autoOptimizeTotalIdleAppsClosed,
            history: Array(autoOptimizeHistory.prefix(20))
        )
        try? autoOptStore.save(state)
    }

    public func refreshTrackedGUIApps() {
        let now = Date()
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
        var groupByBid: [String: ProcessGroupSummary] = [:]
        var groupByName: [String: ProcessGroupSummary] = [:]
        for g in processGroups {
            if let bid = g.bundleIdentifier, !bid.isEmpty {
                groupByBid[bid] = g
            }
            groupByName[g.displayName.lowercased()] = g
        }

        var list: [TrackedGUIApp] = []
        var seenBids = Set<String>()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, !bid.isEmpty, bid != selfBid else { continue }
            guard seenBids.insert(bid).inserted else { continue }
            let name = app.localizedName ?? bid
            let isFront = app.isActive
            if isFront {
                appLastActiveAt[bid] = now
            } else if appLastActiveAt[bid] == nil {
                appLastActiveAt[bid] = now
            }
            let lastActive = appLastActiveAt[bid] ?? now
            let matchedGroup = groupByBid[bid] ?? groupByName[name.lowercased()]
            list.append(TrackedGUIApp(
                bundleID: bid,
                name: name,
                pid: app.processIdentifier,
                isFrontmost: isFront,
                lastActiveAt: lastActive,
                rssBytes: matchedGroup?.totalRSSBytes ?? 0,
                cpuPercent: matchedGroup?.totalCPUPercent ?? 0
            ))
        }

        // Sort: non-protected idle candidates first (longest idle / highest RAM), then protected apps
        trackedGUIApps = list.sorted { lhs, rhs in
            let lProt = AutoOptimizerEngine.isProtectedWorkApp(bundleID: lhs.bundleID, appName: lhs.name, config: autoOptimizeConfig)
            let rProt = AutoOptimizerEngine.isProtectedWorkApp(bundleID: rhs.bundleID, appName: rhs.name, config: autoOptimizeConfig)
            if lProt != rProt { return !lProt }
            let lIdle = lhs.idleMinutes(relativeTo: now)
            let rIdle = rhs.idleMinutes(relativeTo: now)
            if lIdle != rIdle { return lIdle > rIdle }
            return lhs.rssBytes > rhs.rssBytes
        }
    }

    public func isAppWorkProtected(_ app: TrackedGUIApp) -> Bool {
        AutoOptimizerEngine.isProtectedWorkApp(bundleID: app.bundleID, appName: app.name, config: autoOptimizeConfig)
    }

    public func toggleAppWorkProtection(bundleID: String) {
        guard !bundleID.isEmpty, bundleID != "com.ducdung.MacPulse", bundleID != "com.apple.finder" else { return }
        var cfg = autoOptimizeConfig
        let currentlyProtected = AutoOptimizerEngine.isProtectedWorkApp(bundleID: bundleID, config: cfg)
        if currentlyProtected {
            cfg.customProtectedBundleIDs.removeAll { $0 == bundleID }
            if !cfg.unlockedDefaultBundleIDs.contains(bundleID) {
                cfg.unlockedDefaultBundleIDs.append(bundleID)
            }
        } else {
            cfg.unlockedDefaultBundleIDs.removeAll { $0 == bundleID }
            if !cfg.customProtectedBundleIDs.contains(bundleID) {
                cfg.customProtectedBundleIDs.append(bundleID)
            }
        }
        autoOptimizeConfig = cfg
        refreshTrackedGUIApps()
    }

    public var eligibleIdleAppsNow: [TrackedGUIApp] {
        AutoOptimizerEngine.selectIdleAppsToClose(runningApps: trackedGUIApps, config: autoOptimizeConfig)
    }

    /// Politely sends Cmd+Q (`terminate()`) to eligible idle, non-protected apps (CPU < 2%, idle >= timeout).
    /// NEVER uses forceTerminate so unsaved documents prompt to save instead of losing work.
    private func politelyCloseEligibleIdleApps() -> (names: [String], reclaimedRAMBytes: UInt64) {
        refreshTrackedGUIApps()
        let eligible = AutoOptimizerEngine.selectIdleAppsToClose(
            runningApps: trackedGUIApps,
            config: autoOptimizeConfig
        )
        guard !eligible.isEmpty else { return ([], 0) }

        var closedNames: [String] = []
        var reclaimedRAM: UInt64 = 0
        for item in eligible {
            let instances = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID)
            var requestedQuit = false
            for app in instances where !app.isActive {
                if app.terminate() {
                    requestedQuit = true
                }
            }
            if requestedQuit {
                closedNames.append(item.name)
                reclaimedRAM += item.rssBytes
            }
        }
        return (closedNames, reclaimedRAM)
    }

    public func closeIdleAppsNow() {
        let res = politelyCloseEligibleIdleApps()
        if res.names.isEmpty {
            showNotice("Không có ứng dụng rảnh nào (quá \(autoOptimizeConfig.idleAppTimeoutMinutes)p & CPU < 2%) cần đóng.", kind: .info)
            return
        }
        autoOptimizeLifetimeReclaimedRAMBytes += res.reclaimedRAMBytes
        autoOptimizeTotalIdleAppsClosed += res.names.count
        let rec = AutoOptimizeRunRecord(
            trigger: .manual,
            freedBytes: 0,
            removedFilesCount: 0,
            truncatedLogsCount: 0,
            cleanedOrphanProfilesCount: 0,
            closedIdleApps: res.names,
            reclaimedRAMBytes: res.reclaimedRAMBytes,
            throttledBackgroundCount: 0,
            summary: "Tắt êm \(res.names.joined(separator: ", ")) (~\(Formatters.bytes(res.reclaimedRAMBytes)) RAM)"
        )
        autoOptimizeHistory.insert(rec, at: 0)
        if autoOptimizeHistory.count > 20 {
            autoOptimizeHistory = Array(autoOptimizeHistory.prefix(20))
        }
        persistAutoOptimizeState()
        let msg = "Đã đóng êm \(res.names.count) app rảnh (\(res.names.joined(separator: ", "))) — thu hồi ~\(Formatters.bytes(res.reclaimedRAMBytes)) RAM!"
        cleanupOutcomeMessage = msg
        showNotice(msg, kind: .success)
        refreshAfterDelay()
    }

    private func startAutoOptimizeScheduler() {
        autoOptimizeTimer?.invalidate()
        autoOptimizeTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndRunAutoOptimizeIfNeeded()
            }
        }
    }

    public func checkAndRunAutoOptimizeIfNeeded() {
        guard !isAutoOptimizing && !isCleaning && !isRescuingChrome else { return }
        guard let snap = snapshot else { return }
        let availableGB = Double(snap.disk.availableBytes) / 1_073_741_824.0
        let cpuBusy = snap.cpu.totalBusyPercent
        let compressedGB = snap.memory.compressedGB
        let replaydCPU = replaydProcessGroup?.totalCPUPercent ?? 0.0
        guard let trigger = AutoOptimizerEngine.evaluateTrigger(
            config: autoOptimizeConfig,
            lastRunAt: autoOptimizeLastRunAt,
            availableDiskGB: availableGB,
            cpuBusyPercent: cpuBusy,
            compressedRAMGB: compressedGB,
            replaydCPUPercent: replaydCPU,
            replaydAlreadyThrottled: isReplaydThrottled
        ) else { return }
        executeAutoOptimize(trigger: trigger, priority: .background, announceIfZero: false)
    }

    public func runAutoOptimizeNow() {
        guard !isAutoOptimizing && !isCleaning && !isRescuingChrome else { return }
        executeAutoOptimize(trigger: .manual, priority: .userInitiated, announceIfZero: true)
    }

    private func executeAutoOptimize(trigger: AutoOptimizeTrigger, priority: TaskPriority, announceIfZero: Bool) {
        isAutoOptimizing = true
        let cfg = autoOptimizeConfig
        let idleResult: (names: [String], reclaimedRAMBytes: UInt64) = cfg.autoCloseIdleApps
            ? politelyCloseEligibleIdleApps()
            : ([], 0)

        Task.detached(priority: priority) { [cleanupScanner, autoOptStore] in
            let record = AutoOptimizerEngine.runPass(
                config: cfg,
                trigger: trigger,
                closedIdleAppNames: idleResult.names,
                reclaimedRAMBytes: idleResult.reclaimedRAMBytes
            )
            let didOptimizeAnything = record.freedBytes > 0
                || !record.closedIdleApps.isEmpty
                || record.throttledBackgroundCount > 0
                || record.restartedReplayd
            let shouldRescan = record.freedBytes > 0 || trigger == .manual
            let rescanned: [CleanupCandidate]? = shouldRescan ? cleanupScanner.scan() : nil

            await MainActor.run {
                self.autoOptimizeLastRunAt = record.timestamp
                self.autoOptimizeLifetimeFreedBytes += record.freedBytes
                self.autoOptimizeLifetimeReclaimedRAMBytes += record.reclaimedRAMBytes
                self.autoOptimizeTotalIdleAppsClosed += record.closedIdleApps.count
                self.autoOptimizeHistory.insert(record, at: 0)
                if self.autoOptimizeHistory.count > 20 {
                    self.autoOptimizeHistory = Array(self.autoOptimizeHistory.prefix(20))
                }

                let state = PersistedAutoOptimizeState(
                    config: self.autoOptimizeConfig,
                    lastRunAt: self.autoOptimizeLastRunAt,
                    totalLifetimeFreedBytes: self.autoOptimizeLifetimeFreedBytes,
                    totalLifetimeReclaimedRAMBytes: self.autoOptimizeLifetimeReclaimedRAMBytes,
                    totalIdleAppsClosed: self.autoOptimizeTotalIdleAppsClosed,
                    history: self.autoOptimizeHistory
                )
                try? autoOptStore.save(state)

                if let rescanned {
                    self.cleanupCandidates = rescanned
                    self.lastCleanupScanAt = Date()
                    self.selectedCleanupIDs = Set(rescanned.filter { $0.defaultSelected && $0.tier == .safeAutoClean }.map(\.id))
                }

                self.isAutoOptimizing = false

                if didOptimizeAnything {
                    let msg = "Autopilot (\(trigger.rawValue)): \(record.summary)"
                    self.cleanupOutcomeMessage = msg
                    self.showNotice(msg, kind: .success)
                    self.refreshNow(includeProcesses: !record.closedIdleApps.isEmpty)
                } else if announceIfZero {
                    let msg = "Autopilot: \(record.summary)"
                    self.cleanupOutcomeMessage = msg
                    self.showNotice(msg, kind: .info)
                }
            }
        }
    }

    public var autoOptimizeLastRunLabel: String {
        guard let last = autoOptimizeLastRunAt else { return "Chưa chạy" }
        let elapsed = max(0, Date().timeIntervalSince(last))
        if elapsed < 60 { return "Vừa xong" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) phút trước" }
        if elapsed < 86400 {
            let h = Int(elapsed / 3600)
            let m = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
            return m > 0 ? "\(h)h \(m)p trước" : "\(h) giờ trước"
        }
        return "\(Int(elapsed / 86400)) ngày trước"
    }

    public var autoOptimizeNextRunLabel: String {
        guard autoOptimizeConfig.isEnabled else { return "Đang tắt" }
        guard let last = autoOptimizeLastRunAt else { return "Tự động theo dõi" }
        let target = last.addingTimeInterval(TimeInterval(max(1, autoOptimizeConfig.intervalHours) * 3600))
        let rem = target.timeIntervalSinceNow
        if rem <= 60 { return "Sắp chạy" }
        let h = Int(rem / 3600)
        let m = Int((rem.truncatingRemainder(dividingBy: 3600)) / 60)
        return h > 0 ? "Sau \(h)h \(m)p" : "Sau \(m) phút"
    }

    // MARK: - Cleanup & Chrome Rescue
    public func scanCleanup() {
        guard !isScanningCleanup else { return }
        isScanningCleanup = true
        Task.detached(priority: .utility) { [cleanupScanner] in
            let found = cleanupScanner.scan()
            let defaults = Set(found.filter { $0.defaultSelected && $0.tier == .safeAutoClean }.map(\.id))
            await MainActor.run {
                self.cleanupCandidates = found
                self.lastCleanupScanAt = Date()
                self.selectedCleanupIDs = defaults
                self.isScanningCleanup = false
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

    public var aiCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .aiGarbage }
    }

    public var browserCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .cache }
    }

    public var developerCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .developerBuild }
    }

    public var cacheCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .cache || $0.category == .aiGarbage || $0.category == .developerBuild }
    }

    public var logAndTrashCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .logsAndTrash }
    }

    public var storageHeavyCandidates: [CleanupCandidate] {
        cleanupCandidates.filter { $0.category == .storageHeavyData }
    }

    public var maxCandidateSizeBytes: UInt64 {
        max(1, cleanupCandidates.map(\.sizeBytes).max() ?? 1)
    }

    public var totalAIGarbageBytes: UInt64 {
        aiCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalBrowserCacheBytes: UInt64 {
        browserCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalDeveloperBuildBytes: UInt64 {
        developerCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalLogsAndTrashBytes: UInt64 {
        logAndTrashCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalSelectedCleanupBytes: UInt64 {
        cleanupCandidates
            .filter { selectedCleanupIDs.contains($0.id) && $0.tier == .safeAutoClean }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalSafeCacheBytes: UInt64 {
        cleanupCandidates
            .filter { $0.tier == .safeAutoClean }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalHeavyStorageBytes: UInt64 {
        cleanupCandidates
            .filter { $0.category == .storageHeavyData }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    public func selectAllSafe() {
        let safeIDs = Set(cleanupCandidates.filter { $0.tier == .safeAutoClean }.map(\.id))
        selectedCleanupIDs = safeIDs
    }

    public func deselectAll() {
        selectedCleanupIDs = []
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

    public var stuckChromeRenderers: [RawProcessInfo] {
        rawProcesses.filter {
            ProcessScanner.isNormalChromeRendererProcess($0) &&
            ($0.cpuPercent >= 10.0 || ($0.cpuPercent >= 8.0 && $0.rssBytes >= 250 * 1_048_576))
        }
    }

    public var totalChromeRenderers: [RawProcessInfo] {
        rawProcesses.filter { ProcessScanner.isNormalChromeRendererProcess($0) }
    }

    public var chromeGPUProcesses: [RawProcessInfo] {
        rawProcesses.filter { ProcessScanner.isNormalChromeGPUProcess($0) }
    }

    public var chromeGPUTotalCPU: Double {
        chromeGPUProcesses.reduce(0.0) { $0 + $1.cpuPercent }
    }

    public var replaydProcessGroup: ProcessGroupSummary? {
        processGroups.first(where: { $0.id == "sys:replayd" })
    }

    public var isReplaydStuck: Bool {
        (replaydProcessGroup?.totalCPUPercent ?? 0) >= 25.0
    }

    public var isReplaydThrottled: Bool {
        guard let pids = replaydProcessGroup?.pids, !pids.isEmpty else { return false }
        return CleanupExecutor.isReplaydThrottled(pids: pids)
    }

    public var orphanAutomationGroup: ProcessGroupSummary? {
        processGroups.first(where: { $0.isOrphanAutomation })
    }

    public func resetBrowserAutomation() {
        guard !isRescuingChrome && !isCleaning else { return }
        isRescuingChrome = true
        cleanupOutcomeMessage = nil

        Task.detached(priority: .userInitiated) {
            let report = CleanupExecutor.rescueAndResetBrowserAutomation()
            let rescanned = self.cleanupScanner.scan()
            let remainingDefaults = Set(rescanned.filter { $0.defaultSelected && $0.tier == .safeAutoClean }.map(\.id))
            await MainActor.run {
                self.cleanupCandidates = rescanned
                self.selectedCleanupIDs = remainingDefaults
                self.isRescuingChrome = false
                var msg = "Đã dừng & reset \(report.stoppedPIDs.count) tiến trình automation ngầm (headless Chrome / agent-browser)."
                if !report.removedLockFiles.isEmpty {
                    msg += " Gỡ kẹt \(report.removedLockFiles.count) file locks."
                }
                if report.freedBytes > 0 {
                    msg += " Thu hồi \(Formatters.bytes(report.freedBytes))."
                }
                let finalMsg = report.errors.isEmpty
                    ? msg
                    : "\(msg) (Lưu ý: \(report.errors.joined(separator: "; ")))"
                self.cleanupOutcomeMessage = finalMsg
                self.showNotice(finalMsg, kind: report.errors.isEmpty ? .success : .warning)
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func killStuckChromeRenderers(forceAll: Bool = false) {
        guard !isRescuingChrome else { return }
        Task.detached(priority: .userInitiated) {
            let (killed, cpuFreed) = CleanupExecutor.killStuckChromeRenderers(minCPUPercent: 10.0, forceAllRenderers: forceAll)
            await MainActor.run {
                if killed.isEmpty {
                    self.showNotice("Không phát hiện tab/task Chrome thường nào đang bị kẹt vòng lặp JS/DOM hoặc ngốn CPU.", kind: .info)
                } else {
                    let cpuStr = String(format: "%.1f%%", cpuFreed)
                    let msg = "Đã gỡ kẹt \(killed.count) tab/task Chrome treo (thu hồi \(cpuStr) CPU). Trình duyệt đã mượt trở lại!"
                    self.cleanupOutcomeMessage = msg
                    self.showNotice(msg, kind: .success)
                }
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func restartStuckReplayd(forceAlways: Bool = true) {
        guard !isRescuingChrome else { return }
        Task.detached(priority: .userInitiated) {
            let report = CleanupExecutor.restartStuckReplayd(minCPUPercent: 20.0, forceAlways: forceAlways)
            await MainActor.run {
                if report.didRestart {
                    let prevStr = String(format: "%.0f%%", report.previousCPUPercent)
                    if report.stillStormingFromClients {
                        let niceNote = report.throttledNice ? " & hạ ưu tiên nice +20" : ""
                        let clientsNote = report.stormingClients.isEmpty
                            ? "Chrome / app dùng ScreenCaptureKit"
                            : report.stormingClients.joined(separator: ", ")
                        let msg = "Đã reset\(niceNote) replayd (\(prevStr) CPU), nhưng \(clientsNote) vẫn kẹt vòng lặp XPC RPDaemonProxy. Hãy bấm 'Khởi động lại sạch Chrome' + 'Reset Automation' (hoặc restart app trên) để cắt hẳn bão XPC."
                        self.cleanupOutcomeMessage = msg
                        self.showNotice(msg, kind: .warning)
                    } else {
                        let msg = "Đã reset sạch macOS replayd (vừa ngốn \(prevStr) CPU → 0%)! Bão XPC bóp nghẹt Chrome đã chấm dứt — giữ nguyên toàn bộ tab."
                        self.cleanupOutcomeMessage = msg
                        self.showNotice(msg, kind: .success)
                    }
                    self.refreshNow(includeProcesses: true)
                    self.refreshAfterDelay()
                } else if let err = report.error {
                    self.showNotice(err, kind: .warning)
                } else {
                    self.showNotice("macOS replayd đang hoạt động bình thường (0% CPU), không cần khởi động lại.", kind: .info)
                }
            }
        }
    }

    public func resetChromeGPUProcess() {
        guard !isRescuingChrome else { return }
        Task.detached(priority: .userInitiated) {
            let (restarted, cpuFreed) = CleanupExecutor.resetChromeGPUProcess()
            await MainActor.run {
                if restarted.isEmpty {
                    self.showNotice("Không tìm thấy tiến trình GPU của Google Chrome thường đang chạy.", kind: .info)
                } else {
                    let cpuStr = String(format: "%.1f%%", cpuFreed)
                    let msg = "Đã reset tiến trình GPU Chrome (vừa ngốn \(cpuStr) CPU). Chrome tự khôi phục GPU trong <0.5s — 0 tab bị đóng!"
                    self.cleanupOutcomeMessage = msg
                    self.showNotice(msg, kind: .success)
                    self.refreshNow(includeProcesses: true)
                    self.refreshAfterDelay()
                }
            }
        }
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
                let replaydNote = report.restartedReplayd ? " Đã reset replayd XPC." : ""
                let relaunchNote = report.relaunchedChrome ? " Đã mở lại Chrome." : ""
                let msg = "Đã sửa & dọn sạch Chrome: tắt \(stoppedCount) tiến trình, gỡ \(lockCount) lock, xoá \(freedText) cache.\(replaydNote)\(relaunchNote)"
                let finalMsg = report.errors.isEmpty
                    ? msg
                    : "\(msg) (Cảnh báo: \(report.errors.joined(separator: "; ")))"
                self.cleanupOutcomeMessage = finalMsg
                self.showNotice(finalMsg, kind: report.errors.isEmpty ? .success : .warning)
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
                let msg = outcome.errors.isEmpty
                    ? "Đã giải phóng \(Formatters.bytes(outcome.freedBytes)) ổ cứng SSD (\(outcome.processedCount) mục)."
                    : "Giải phóng \(Formatters.bytes(outcome.freedBytes)), còn \(outcome.errors.count) mục đang bị app giữ khoá."
                self.cleanupOutcomeMessage = msg
                self.showNotice(msg, kind: outcome.errors.isEmpty ? .success : .warning)
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    // MARK: - Process Actions
    public func requestCloseProcess(_ group: ProcessGroupSummary) {
        if group.isOrphanAutomation {
            resetBrowserAutomation()
            return
        }

        if group.actionKind == .restartReplayd {
            restartStuckReplayd(forceAlways: true)
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
            resetBrowserAutomation()
            return
        }

        guard group.guidance.safetyLevel != .systemProtected && group.guidance.safetyLevel != .remoteKeepAlive else {
            showNotice("Đã chặn đóng \(group.displayName) để bảo vệ hệ thống / phiên kết nối từ xa.", kind: .warning)
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
                showNotice(
                    force
                        ? "Đã ép tắt \(group.displayName) (giải phóng ~\(Formatters.bytes(group.totalRSSBytes)) RAM)."
                        : "Đã gửi lệnh đóng nhẹ (Cmd+Q) tới \(group.displayName).",
                    kind: .success
                )
            } else {
                showNotice("Không thể gửi lệnh đóng tới \(group.displayName) — thử chọn Ép tắt.", kind: .warning)
            }
            refreshAfterDelay()
            return
        }

        let res = CleanupExecutor.terminatePIDs(group.pids, force: force)
        if !res.killed.isEmpty {
            showNotice("Đã tắt \(group.displayName) (\(res.killed.count) tiến trình, ~\(Formatters.bytes(group.totalRSSBytes)) RAM).", kind: .success)
        } else {
            showNotice("Không đủ quyền hoặc tiến trình \(group.displayName) đã thoát.", kind: .warning)
        }
        refreshAfterDelay()
    }

    public func performRecommendedAction(_ action: ProcessActionKind, targetID: String?) {
        switch action {
        case .none:
            break
        case .killOrphanPuppeteer:
            resetBrowserAutomation()
        case .killStuckChromeRenderers:
            killStuckChromeRenderers(forceAll: false)
        case .resetChromeGPU:
            resetChromeGPUProcess()
        case .restartReplayd:
            restartStuckReplayd(forceAlways: true)
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
                cleanerFocus = .all
            }
            selectedTab = .cleaner
        }
    }

    private func refreshAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.refreshNow(includeProcesses: true)
        }
    }

    // MARK: - Browser Tabs Inspector
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

    public var filteredBrowserTabs: [BrowserTabItem] {
        guard !tabSearchQuery.isEmpty else { return openBrowserTabs }
        let q = tabSearchQuery.lowercased()
        return openBrowserTabs.filter {
            $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) || $0.browser.lowercased().contains(q)
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
                self.showNotice(
                    ok ? "Đã đóng tab: \(tab.title)" : "Không khớp tab (có thể bạn đã chuyển hoặc đóng tab này).",
                    kind: ok ? .success : .warning
                )
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func closeDuplicateExtras() {
        let rawToClose = duplicateTabs.flatMap { Array($0.tabs.dropFirst()) }
        guard !rawToClose.isEmpty else { return }
        let orderedToClose = BrowserTabInspector.sortForSafeBatchClosing(rawToClose)
        Task.detached(priority: .userInitiated) {
            var closed = 0
            for tab in orderedToClose {
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
                self.showNotice("Đã đóng an toàn \(closedCount) tab mở trùng.", kind: .success)
                self.refreshNow(includeProcesses: true)
            }
        }
    }

    public func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    public var filteredProcessGroups: [ProcessGroupSummary] {
        let filtered = processGroups.filter { group in
            if !processSearchQuery.isEmpty {
                let q = processSearchQuery.lowercased()
                let matchesName = group.displayName.lowercased().contains(q)
                let matchesID = group.id.lowercased().contains(q)
                let matchesPIDs = group.pids.contains { String($0).contains(q) }
                if !matchesName && !matchesID && !matchesPIDs {
                    return false
                }
            }
            switch processCategoryFilter {
            case .all:
                return true
            case .apps:
                return group.bundleIdentifier != nil && !group.isOrphanAutomation
            case .background:
                return group.bundleIdentifier == nil || group.isOrphanAutomation
            case .heavy:
                return group.totalCPUPercent >= 15.0 || group.totalRSSBytes >= 500_000_000
            }
        }

        switch processSortOrder {
        case .smart:
            return filtered
        case .cpu:
            return filtered.sorted { $0.totalCPUPercent > $1.totalCPUPercent }
        case .ram:
            return filtered.sorted { $0.totalRSSBytes > $1.totalRSSBytes }
        }
    }

    public func cleanAllSafeCaches() {
        let safeIDs = Set(cleanupCandidates.filter { $0.tier == .safeAutoClean && $0.category == .cache }.map(\.id))
        guard !safeIDs.isEmpty else { return }
        selectedCleanupIDs = safeIDs
        runSelectedCleanup()
    }

    public func addMacro(key: String, value: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanVal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanVal.isEmpty else { return }
        imeSettings.macroTable[cleanKey] = cleanVal
    }

    public func removeMacro(key: String) {
        imeSettings.macroTable.removeValue(forKey: key.lowercased())
    }

    public func resetMacrosToDefault() {
        imeSettings.macroTable = VietnameseSettings.defaultMacroTable
    }

    public func clearBenchmarkHistory() {
        try? benchmarkRunner.clearHistory()
        benchmarkHistory = []
        latestBenchmark = nil
        showNotice("Đã xoá lịch sử kết quả đo benchmark.", kind: .info)
    }
}
