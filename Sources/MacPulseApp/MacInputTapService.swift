import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import MacPulseCore
import os

public struct ActiveInputConflict: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String
    public let pid: pid_t
}

public enum TapRuntimeState: Equatable, Sendable {
    case stopped
    case waitingAccessibility
    case running
    case failedToCreateTap
}

public final class MacInputTapService {
    public static let syntheticMagic: Int64 = 0x4D50_5649 // "MPVI"

    private static let chromiumOrOmniboxBundles: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.apple.Safari",
        "com.apple.Spotlight",
        "org.mozilla.firefox",
        "com.raycast.macos"
    ]

    private static let chatAndMessagingBundles: Set<String> = [
        "com.vng.zalo",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.facebook.archon",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.apple.MobileSMS",
        "com.apple.Notes",
        "com.skype.skype",
        "com.microsoft.Word",
        "com.microsoft.teams",
        "com.microsoft.teams2"
    ]

    public static var vpsAndRemoteDesktopBundles: Set<String> { VietnameseAppDetector.vpsAndRemoteDesktopBundles }
    public static var terminalAndShellBundles: Set<String> { VietnameseAppDetector.terminalAndShellBundles }

    public static func isVPSOrRemoteApp(bundleID: String, appName: String = "") -> Bool {
        VietnameseAppDetector.isVPSOrRemoteApp(bundleID: bundleID, appName: appName)
    }

    public static func isTerminalApp(bundleID: String, appName: String = "") -> Bool {
        VietnameseAppDetector.isTerminalApp(bundleID: bundleID, appName: appName)
    }

    public static func computeIsAppExcluded(bundleID: String, appName: String, settings: VietnameseSettings, perAppEnabled: [String: Bool] = [:]) -> Bool {
        VietnameseAppDetector.computeIsAppExcluded(bundleID: bundleID, appName: appName, settings: settings, perAppEnabled: perAppEnabled)
    }

    private static let conflictBundleMap: [(bundleID: String, label: String)] = [
        ("com.lamquangminh.EVKey", "EVKey"),
        ("org.vielotus.inputmethod.VieLotusIM", "BeVie (VieLotusIM)"),
        ("com.tuyenmai.OpenKey", "OpenKey"),
        ("com.trankynam.GoTiengViet", "GoTiengViet")
    ]

    private var stateLock = os_unfair_lock()
    private let engine: VietnameseEngine
    private var settings: VietnameseSettings
    private var perAppEnabled: [String: Bool]
    private var currentBundleID: String
    private var currentAppName: String

    // Fast-path cached copies for the tap thread (read lock-free or via unfair lock)
    private var fastIsEnabled: Bool
    private var fastHotkey: VietnameseHotkey
    private var fastUseCapsLock: Bool
    private var fastFixChrome: Bool
    private var fastIsExcludedApp: Bool

    private var eventSource: CGEventSource?

    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?
    private var tapState: TapRuntimeState = .stopped

    private var comboActive = false
    private var comboCancelledByKey = false

    private var workspaceObserver: NSObjectProtocol?
    private var trustPollTimer: Timer?

    public var onLanguageToggled: ((Bool, String) -> Void)?
    public var onRuntimeStateChanged: ((TapRuntimeState, Bool) -> Void)?
    public var onFrontmostAppChanged: ((String, String) -> Void)?

    public init(settings: VietnameseSettings, perAppEnabled: [String: Bool] = [:]) {
        self.settings = settings
        self.perAppEnabled = perAppEnabled
        self.engine = VietnameseEngine(settings: settings)
        self.fastIsEnabled = settings.isEnabled
        self.fastHotkey = settings.hotkey
        self.fastUseCapsLock = settings.useCapsLockToSwitch
        self.fastFixChrome = settings.fixChromiumAutocomplete
        let front = NSWorkspace.shared.frontmostApplication
        let frontBid = front?.bundleIdentifier ?? ""
        let frontName = front?.localizedName ?? frontBid
        self.currentBundleID = frontBid
        self.currentAppName = frontName
        let isExcluded = Self.computeIsAppExcluded(bundleID: frontBid, appName: frontName, settings: settings, perAppEnabled: perAppEnabled)
        self.fastIsExcludedApp = isExcluded
        if settings.smartSwitchPerApp && !frontBid.isEmpty {
            if let saved = perAppEnabled[frontBid] {
                self.fastIsEnabled = saved
                self.settings.isEnabled = saved
            } else if isExcluded {
                self.fastIsEnabled = false
                self.settings.isEnabled = false
            }
        }
        // Use private state event source so synthetic events NEVER contaminate hardware HID device state
        self.eventSource = CGEventSource(stateID: .privateState)
    }

    deinit {
        stop()
    }

    public func start() {
        Self.terminateConflictingApps()
        observeWorkspaceIfNeeded()
        updateTrustAndTapLifecycle(promptIfNeeded: false)
    }

    public func stop() {
        stopTrustPolling()
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
        teardownTapThread()
        setTapState(.stopped)
    }

    public func updateSettings(_ newSettings: VietnameseSettings) {
        os_unfair_lock_lock(&stateLock)
        let prevEnabled = settings.isEnabled
        settings = newSettings
        engine.settings = newSettings
        fastIsEnabled = newSettings.isEnabled
        fastHotkey = newSettings.hotkey
        fastUseCapsLock = newSettings.useCapsLockToSwitch
        fastFixChrome = newSettings.fixChromiumAutocomplete
        fastIsExcludedApp = Self.computeIsAppExcluded(bundleID: currentBundleID, appName: currentAppName, settings: newSettings, perAppEnabled: perAppEnabled)
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
        if newSettings.smartSwitchPerApp && !currentBundleID.isEmpty && currentBundleID != selfBid && prevEnabled != newSettings.isEnabled {
            perAppEnabled[currentBundleID] = newSettings.isEnabled
        }
        engine.reset()
        os_unfair_lock_unlock(&stateLock)
    }

    public func currentPerAppMap() -> [String: Bool] {
        os_unfair_lock_lock(&stateLock)
        let map = perAppEnabled
        os_unfair_lock_unlock(&stateLock)
        return map
    }

    public func setPerAppEnabledMap(_ map: [String: Bool]) {
        os_unfair_lock_lock(&stateLock)
        perAppEnabled = map
        os_unfair_lock_unlock(&stateLock)
    }

    public func resetWordBuffer() {
        os_unfair_lock_lock(&stateLock)
        engine.reset()
        os_unfair_lock_unlock(&stateLock)
    }

    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let opts = [key: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func activeSystemInputSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        let cfStr = unsafeBitCast(rawPtr, to: CFString.self)
        return cfStr as String
    }

    public static func isSystemVietnameseInputSourceActive() -> Bool {
        let id = activeSystemInputSourceID().lowercased()
        return id.contains("vietnameseim") || id.contains("vielotus") || id.contains("bevie")
    }

    public static func detectConflictingApps() -> [ActiveInputConflict] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var results: [ActiveInputConflict] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != selfPID,
                  let bid = app.bundleIdentifier else { continue }
            if let match = conflictBundleMap.first(where: { $0.bundleID.caseInsensitiveCompare(bid) == .orderedSame }) {
                results.append(ActiveInputConflict(
                    id: "\(bid)-\(app.processIdentifier)",
                    name: match.label,
                    bundleIdentifier: bid,
                    pid: app.processIdentifier
                ))
            }
        }
        return results
    }

    @discardableResult
    public static func terminateConflictingApps() -> Int {
        var terminated = 0
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != selfPID else { continue }
            let bid = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? app.executableURL?.lastPathComponent ?? ""
            let isConflict = conflictBundleMap.contains(where: {
                $0.bundleID.caseInsensitiveCompare(bid) == .orderedSame ||
                $0.label.caseInsensitiveCompare(name) == .orderedSame
            }) || bid.lowercased().contains("evkey") || name.lowercased().contains("evkey")
               || bid.lowercased().contains("openkey") || name.lowercased().contains("openkey")
               || bid.lowercased().contains("gotiengviet") || name.lowercased().contains("gotiengviet")
            if isConflict {
                if app.terminate() || app.forceTerminate() {
                    terminated += 1
                }
            }
        }
        return terminated
    }

    public func requestAccessibilityAndStart() {
        let trusted = Self.isAccessibilityTrusted(prompt: true)
        if trusted {
            updateTrustAndTapLifecycle(promptIfNeeded: false)
        } else {
            setTapState(.waitingAccessibility)
            startTrustPollingIfNeeded()
        }
    }

    public func checkAccessibilityStatusNow() {
        updateTrustAndTapLifecycle(promptIfNeeded: false)
    }

    private func updateTrustAndTapLifecycle(promptIfNeeded: Bool) {
        let trusted = Self.isAccessibilityTrusted(prompt: promptIfNeeded)
        if trusted {
            stopTrustPolling()
            if tapThread == nil {
                launchTapThread()
            }
        } else {
            teardownTapThread()
            setTapState(.waitingAccessibility)
            startTrustPollingIfNeeded()
        }
    }

    private func stopTrustPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.trustPollTimer?.invalidate()
            self?.trustPollTimer = nil
        }
    }

    private func startTrustPollingIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.trustPollTimer == nil else { return }
            self.trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                let trusted = Self.isAccessibilityTrusted(prompt: false)
                if trusted {
                    self.stopTrustPolling()
                    self.launchTapThread()
                }
            }
        }
    }

    private func observeWorkspaceIfNeeded() {
        guard workspaceObserver == nil else { return }
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bid = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? bid

            os_unfair_lock_lock(&self.stateLock)
            self.currentBundleID = bid
            self.currentAppName = name
            self.engine.reset()
            let isExcluded = Self.computeIsAppExcluded(bundleID: bid, appName: name, settings: self.settings, perAppEnabled: self.perAppEnabled)
            self.fastIsExcludedApp = isExcluded
            var switchedLanguage: Bool?
            if self.settings.smartSwitchPerApp && !bid.isEmpty && bid != selfBid {
                if let saved = self.perAppEnabled[bid] {
                    if saved != self.settings.isEnabled {
                        self.settings.isEnabled = saved
                        self.fastIsEnabled = saved
                        self.engine.settings = self.settings
                        switchedLanguage = saved
                    }
                } else if isExcluded {
                    // VPS, Remote Desktop or Terminal app without explicit override defaults to English!
                    if self.settings.isEnabled {
                        self.settings.isEnabled = false
                        self.fastIsEnabled = false
                        self.engine.settings = self.settings
                        switchedLanguage = false
                    }
                }
            }
            os_unfair_lock_unlock(&self.stateLock)

            DispatchQueue.main.async {
                self.onFrontmostAppChanged?(bid, name)
                if let lang = switchedLanguage {
                    self.onLanguageToggled?(lang, bid)
                }
            }

            DispatchQueue.global(qos: .utility).async {
                Self.terminateConflictingApps()
            }
        }
    }

    private func setTapState(_ newState: TapRuntimeState) {
        os_unfair_lock_lock(&stateLock)
        let changed = (tapState != newState)
        tapState = newState
        os_unfair_lock_unlock(&stateLock)
        if changed {
            let trusted = Self.isAccessibilityTrusted(prompt: false)
            DispatchQueue.main.async { [weak self] in
                self?.onRuntimeStateChanged?(newState, trusted)
            }
        }
    }

    private func launchTapThread() {
        os_unfair_lock_lock(&stateLock)
        if tapThread != nil {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        let thread = Thread { [weak self] in
            pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
            self?.runTapLoop()
        }
        thread.name = "com.macpulse.inputtap"
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        tapThread = thread
        os_unfair_lock_unlock(&stateLock)
        thread.start()
    }

    private func teardownTapThread() {
        os_unfair_lock_lock(&stateLock)
        let rl = tapRunLoop
        let port = eventTap
        let src = tapRunLoopSource
        tapRunLoop = nil
        eventTap = nil
        tapRunLoopSource = nil
        tapThread = nil
        os_unfair_lock_unlock(&stateLock)

        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let rl, let src {
            CFRunLoopRemoveSource(rl, src, .commonModes)
        }
        if let rl {
            CFRunLoopStop(rl)
        }
    }

    private func runTapLoop() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MacInputTapService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            os_unfair_lock_lock(&stateLock)
            tapThread = nil
            os_unfair_lock_unlock(&stateLock)
            setTapState(.failedToCreateTap)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let currentRL = CFRunLoopGetCurrent()
        CFRunLoopAddSource(currentRL, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        os_unfair_lock_lock(&stateLock)
        self.eventTap = port
        self.tapRunLoopSource = source
        self.tapRunLoop = currentRL
        os_unfair_lock_unlock(&stateLock)

        setTapState(.running)
        CFRunLoopRun()
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            os_unfair_lock_lock(&stateLock)
            let port = eventTap
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMagic {
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .rightMouseDown {
            if fastIsEnabled {
                os_unfair_lock_lock(&stateLock)
                engine.reset()
                os_unfair_lock_unlock(&stateLock)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        comboCancelledByKey = true
        return handleKeyDown(proxy: proxy, event: event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        if fastIsExcludedApp { return }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let hotkey = fastHotkey
        let useCaps = fastUseCapsLock

        if (hotkey == .capsLock || useCaps) && keyCode == 0x39 {
            toggleLanguageFromHotkey()
            return
        }

        let flags = event.flags
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasOpt = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)

        switch hotkey {
        case .ctrlShift:
            let pressed = hasCtrl && hasShift && !hasCmd && !hasOpt
            if pressed {
                if !comboActive {
                    comboActive = true
                    comboCancelledByKey = false
                }
            } else if comboActive {
                let shouldToggle = !comboCancelledByKey && (!hasCtrl || !hasShift) && !hasCmd && !hasOpt
                comboActive = false
                comboCancelledByKey = false
                if shouldToggle {
                    toggleLanguageFromHotkey()
                }
            }
        case .cmdShift:
            let pressed = hasCmd && hasShift && !hasCtrl && !hasOpt
            if pressed {
                if !comboActive {
                    comboActive = true
                    comboCancelledByKey = false
                }
            } else if comboActive {
                let shouldToggle = !comboCancelledByKey && (!hasCmd || !hasShift) && !hasCtrl && !hasOpt
                comboActive = false
                comboCancelledByKey = false
                if shouldToggle {
                    toggleLanguageFromHotkey()
                }
            }
        case .optionZ, .ctrlSpace, .capsLock:
            comboActive = false
        }
    }

    private func handleKeyDown(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Fast-path bypass for excluded applications (Windows App, Remote Desktop, VPS clients):
        // Pass all keystrokes through immediately with 0 delay, 0 backspaces, 0 state mutation.
        // Also preserves Windows shortcuts (Ctrl+Space for IntelliSense, Alt+keys, etc.) without swallowing!
        if fastIsExcludedApp {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let hotkey = fastHotkey
        let isEnabled = fastIsEnabled

        if hotkey == .optionZ && keyCode == 0x06 && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
            toggleLanguageFromHotkey()
            return nil
        }
        if hotkey == .ctrlSpace && keyCode == 0x31 && flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate) {
            toggleLanguageFromHotkey()
            return nil
        }

        // Master switch guard: if Vietnamese IME is disabled, pass all keystrokes through immediately.
        // Zero delay, zero state lock, zero backspace or escape interception.
        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn) {
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
            return Unmanaged.passUnretained(event)
        }

        switch keyCode {
        case 0x24, 0x4C, 0x30, 0x75, 0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79:
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
            return Unmanaged.passUnretained(event)
        case 0x33:
            os_unfair_lock_lock(&stateLock)
            let action = engine.processBackspace()
            let bundleID = currentBundleID
            let fixChrome = fastFixChrome
            os_unfair_lock_unlock(&stateLock)
            return applyAction(action, proxy: proxy, originalEvent: event, bundleID: bundleID, fixChrome: fixChrome)
        case 0x35:
            os_unfair_lock_lock(&stateLock)
            let action = engine.processEscape()
            let bundleID = currentBundleID
            let fixChrome = fastFixChrome
            os_unfair_lock_unlock(&stateLock)
            if case .replace = action {
                return applyAction(action, proxy: proxy, originalEvent: event, bundleID: bundleID, fixChrome: fixChrome)
            }
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
            return Unmanaged.passUnretained(event)
        }

        var actualLength = 0
        var uniChars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &actualLength, unicodeString: &uniChars)
        guard actualLength > 0 else {
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
            return Unmanaged.passUnretained(event)
        }

        let inputStr = String(utf16CodeUnits: Array(uniChars.prefix(actualLength)), count: actualLength)
        guard inputStr.count == 1, let ch = inputStr.first else {
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
            return Unmanaged.passUnretained(event)
        }

        os_unfair_lock_lock(&stateLock)
        let action = engine.processCharacter(ch)
        let bundleID = currentBundleID
        let fixChrome = fastFixChrome
        os_unfair_lock_unlock(&stateLock)

        return applyAction(action, proxy: proxy, originalEvent: event, bundleID: bundleID, fixChrome: fixChrome)
    }

    private func toggleLanguageFromHotkey() {
        os_unfair_lock_lock(&stateLock)
        let nextEnabled = !settings.isEnabled
        settings.isEnabled = nextEnabled
        fastIsEnabled = nextEnabled
        engine.settings = settings
        engine.reset()
        let bid = currentBundleID
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
        if settings.smartSwitchPerApp && !bid.isEmpty && bid != selfBid {
            perAppEnabled[bid] = nextEnabled
        }
        let playSound = settings.soundOnSwitch
        os_unfair_lock_unlock(&stateLock)

        DispatchQueue.main.async { [weak self] in
            if playSound {
                let soundName = nextEnabled ? "Tink" : "Pop"
                NSSound(named: NSSound.Name(soundName))?.play()
            }
            self?.onLanguageToggled?(nextEnabled, bid)
        }
    }

    private func applyAction(
        _ action: KeyAction,
        proxy: CGEventTapProxy,
        originalEvent: CGEvent,
        bundleID: String,
        fixChrome: Bool
    ) -> Unmanaged<CGEvent>? {
        switch action {
        case .passthrough:
            return Unmanaged.passUnretained(originalEvent)
        case .replace(let backspaceCount, let text):
            if backspaceCount == 0, text.count == 1 {
                // In-place replacement: override Unicode string of current keyDown directly!
                // Zero synthetic events, zero backspaces, zero delay, works 100% natively in all text fields!
                var utf16 = Array(text.utf16)
                originalEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                return Unmanaged.passUnretained(originalEvent)
            }
            postReplacement(
                proxy: proxy,
                backspaceCount: backspaceCount,
                text: text,
                bundleID: bundleID,
                fixChrome: fixChrome
            )
            return nil
        }
    }

    private func postReplacement(
        proxy: CGEventTapProxy,
        backspaceCount: Int,
        text: String,
        bundleID: String,
        fixChrome: Bool
    ) {
        guard let src = eventSource else { return }

        let isBrowser = fixChrome && VietnameseAppDetector.isBrowserOrSearchApp(bundleID: bundleID)

        if backspaceCount > 0 && isBrowser {
            // Cancel / collapse active browser Omnibox, Safari address bar, or Spotlight
            // inline autocomplete prediction highlight by inserting a Zero-Width Non-Joiner (U+200C).
            // This replaces the highlighted suggestion without deleting the user's typed stem.
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                down.flags = []
                down.timestamp = mach_absolute_time()
                down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                var zwnj: [UniChar] = [0x200C]
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &zwnj)
                down.tapPostEvent(proxy)
            }
            usleep(600)
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.flags = []
                up.timestamp = mach_absolute_time()
                up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                var zwnj: [UniChar] = [0x200C]
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &zwnj)
                up.tapPostEvent(proxy)
            }
            usleep(600)
        }

        let totalBackspaces = (backspaceCount > 0 && isBrowser) ? (backspaceCount + 1) : backspaceCount

        // Inject backspaces with paced inter-event intervals and strictly monotonic timestamps
        // so Chromium/Electron/WebKit DOM input loops cleanly process each deletion without dropping events.
        if totalBackspaces > 0 {
            for _ in 0..<totalBackspaces {
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true) {
                    down.flags = []
                    down.timestamp = mach_absolute_time()
                    down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    down.tapPostEvent(proxy)
                }
                usleep(800)
                if let up = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false) {
                    up.flags = []
                    up.timestamp = mach_absolute_time()
                    up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    up.tapPostEvent(proxy)
                }
                usleep(800)
            }
        }

        // Inject replacement characters one character at a time (never pack multiple Unicode
        // characters into a single key event, which causes Chromium Omnibox and native NSTextViews
        // to drop subsequent characters or fail composition).
        if !text.isEmpty {
            for ch in text {
                var utf16 = Array(String(ch).utf16)
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                    down.flags = []
                    down.timestamp = mach_absolute_time()
                    down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    down.tapPostEvent(proxy)
                }
                usleep(600)
                if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                    up.flags = []
                    up.timestamp = mach_absolute_time()
                    up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    up.tapPostEvent(proxy)
                }
                usleep(600)
            }
        }
    }
}
