import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import MacPulseCore

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

    private static let terminalOrEditorBundles: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92"
    ]

    private static let conflictBundleMap: [(bundleID: String, label: String)] = [
        ("com.lamquangminh.EVKey", "EVKey"),
        ("org.vielotus.inputmethod.VieLotusIM", "BeVie (VieLotusIM)"),
        ("com.tuyenmai.OpenKey", "OpenKey"),
        ("com.trankynam.GoTiengViet", "GoTiengViet")
    ]

    private let stateLock = NSLock()
    private let engine: VietnameseEngine
    private var settings: VietnameseSettings
    private var perAppEnabled: [String: Bool]
    private var currentBundleID: String
    private var currentAppName: String

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
        let front = NSWorkspace.shared.frontmostApplication
        self.currentBundleID = front?.bundleIdentifier ?? ""
        self.currentAppName = front?.localizedName ?? ""
        self.eventSource = CGEventSource(stateID: .privateState)
    }

    deinit {
        stop()
    }

    public func start() {
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
        stateLock.lock()
        let prevEnabled = settings.isEnabled
        settings = newSettings
        engine.settings = newSettings
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
        if newSettings.smartSwitchPerApp && !currentBundleID.isEmpty && currentBundleID != selfBid && prevEnabled != newSettings.isEnabled {
            perAppEnabled[currentBundleID] = newSettings.isEnabled
        }
        engine.reset()
        stateLock.unlock()
    }

    public func currentPerAppMap() -> [String: Bool] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return perAppEnabled
    }

    public func setPerAppEnabledMap(_ map: [String: Bool]) {
        stateLock.lock()
        perAppEnabled = map
        stateLock.unlock()
    }

    public func resetWordBuffer() {
        stateLock.lock()
        engine.reset()
        stateLock.unlock()
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
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier else { continue }
            if conflictBundleMap.contains(where: { $0.bundleID.caseInsensitiveCompare(bid) == .orderedSame }) {
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

            self.stateLock.lock()
            self.currentBundleID = bid
            self.currentAppName = name
            self.engine.reset()
            var switchedLanguage: Bool?
            if self.settings.smartSwitchPerApp && !bid.isEmpty && bid != selfBid,
               let saved = self.perAppEnabled[bid],
               saved != self.settings.isEnabled {
                self.settings.isEnabled = saved
                self.engine.settings = self.settings
                switchedLanguage = saved
            }
            self.stateLock.unlock()

            DispatchQueue.main.async {
                self.onFrontmostAppChanged?(bid, name)
                if let lang = switchedLanguage {
                    self.onLanguageToggled?(lang, bid)
                }
            }
        }
    }

    private func setTapState(_ newState: TapRuntimeState) {
        stateLock.lock()
        let changed = (tapState != newState)
        tapState = newState
        stateLock.unlock()
        if changed {
            let trusted = Self.isAccessibilityTrusted(prompt: false)
            DispatchQueue.main.async { [weak self] in
                self?.onRuntimeStateChanged?(newState, trusted)
            }
        }
    }

    private func launchTapThread() {
        stateLock.lock()
        if tapThread != nil {
            stateLock.unlock()
            return
        }
        let thread = Thread { [weak self] in
            self?.runTapLoop()
        }
        thread.name = "com.macpulse.inputtap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        stateLock.unlock()
        thread.start()
    }

    private func teardownTapThread() {
        stateLock.lock()
        let rl = tapRunLoop
        let port = eventTap
        let src = tapRunLoopSource
        tapRunLoop = nil
        eventTap = nil
        tapRunLoopSource = nil
        tapThread = nil
        stateLock.unlock()

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
            stateLock.lock()
            tapThread = nil
            stateLock.unlock()
            setTapState(.failedToCreateTap)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let currentRL = CFRunLoopGetCurrent()
        CFRunLoopAddSource(currentRL, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        stateLock.lock()
        self.eventTap = port
        self.tapRunLoopSource = source
        self.tapRunLoop = currentRL
        stateLock.unlock()

        setTapState(.running)
        CFRunLoopRun()
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stateLock.lock()
            let port = eventTap
            engine.reset()
            stateLock.unlock()
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMagic {
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .rightMouseDown {
            stateLock.lock()
            engine.reset()
            stateLock.unlock()
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
        stateLock.lock()
        let hotkey = settings.hotkey
        stateLock.unlock()

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
        case .optionZ, .ctrlSpace:
            comboActive = false
        }
    }

    private func handleKeyDown(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        stateLock.lock()
        let hotkey = settings.hotkey
        stateLock.unlock()

        if hotkey == .optionZ && keyCode == 0x06 && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
            toggleLanguageFromHotkey()
            return nil
        }
        if hotkey == .ctrlSpace && keyCode == 0x31 && flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate) {
            toggleLanguageFromHotkey()
            return nil
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn) {
            stateLock.lock()
            engine.reset()
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        }

        switch keyCode {
        case 0x24, 0x4C, 0x30, 0x75, 0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79:
            stateLock.lock()
            engine.reset()
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        case 0x33:
            stateLock.lock()
            let action = engine.processBackspace()
            let bundleID = currentBundleID
            let fixChrome = settings.fixChromiumAutocomplete
            stateLock.unlock()
            return applyAction(action, proxy: proxy, originalEvent: event, bundleID: bundleID, fixChrome: fixChrome)
        case 0x35:
            stateLock.lock()
            let action = engine.processEscape()
            let bundleID = currentBundleID
            let fixChrome = settings.fixChromiumAutocomplete
            stateLock.unlock()
            if case .replace = action {
                return applyAction(action, proxy: proxy, originalEvent: event, bundleID: bundleID, fixChrome: fixChrome)
            }
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            stateLock.lock()
            engine.reset()
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        }

        var actualLength = 0
        var uniChars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &actualLength, unicodeString: &uniChars)
        guard actualLength > 0 else {
            stateLock.lock()
            engine.reset()
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        }

        let inputStr = String(utf16CodeUnits: Array(uniChars.prefix(actualLength)), count: actualLength)
        guard inputStr.count == 1, let ch = inputStr.first else {
            stateLock.lock()
            engine.reset()
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        }

        stateLock.lock()
        guard settings.isEnabled else {
            engine.reset()
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        }
        let action = engine.processCharacter(ch)
        let bundleID = currentBundleID
        let fixChrome = settings.fixChromiumAutocomplete
        stateLock.unlock()

        return applyAction(action, proxy: proxy, originalEvent: event, bundleID: bundleID, fixChrome: fixChrome)
    }

    private func toggleLanguageFromHotkey() {
        stateLock.lock()
        let nextEnabled = !settings.isEnabled
        settings.isEnabled = nextEnabled
        engine.settings = settings
        engine.reset()
        let bid = currentBundleID
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
        if settings.smartSwitchPerApp && !bid.isEmpty && bid != selfBid {
            perAppEnabled[bid] = nextEnabled
        }
        let playSound = settings.soundOnSwitch
        stateLock.unlock()

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
        var totalBackspaces = backspaceCount
        if fixChrome && backspaceCount > 0 && Self.chromiumOrOmniboxBundles.contains(bundleID) {
            if focusedSelectionLength() > 0 {
                totalBackspaces += 1
            }
        }

        let isTargetHeavyApp = Self.chromiumOrOmniboxBundles.contains(bundleID)
            || Self.terminalOrEditorBundles.contains(bundleID)
            || Self.chatAndMessagingBundles.contains(bundleID)

        let bsDelayUsec: useconds_t = isTargetHeavyApp ? 1_800 : 1_200
        let settleDelayUsec: useconds_t = isTargetHeavyApp ? 3_000 : 2_000
        let charDelayUsec: useconds_t = isTargetHeavyApp ? 600 : 300

        if totalBackspaces > 0 {
            for _ in 0..<totalBackspaces {
                if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x33, keyDown: true) {
                    down.flags = []
                    down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    down.tapPostEvent(proxy)
                }
                if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x33, keyDown: false) {
                    up.flags = []
                    up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    up.tapPostEvent(proxy)
                }
                usleep(bsDelayUsec)
            }
            // Settle pause: allow the target application (Zalo, Telegram, Chrome, etc.)
            // to update its text storage layout and selection position before injecting characters
            usleep(settleDelayUsec)
        }

        for char in text {
            var utf16 = Array(String(char).utf16)
            if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) {
                down.flags = []
                down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                down.tapPostEvent(proxy)
            }
            if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) {
                up.flags = []
                up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                up.tapPostEvent(proxy)
            }
            usleep(charDelayUsec)
        }
    }

    private func focusedSelectionLength() -> Int {
        let sysWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return 0
        }
        let axElement = focused as! AXUIElement
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef,
              CFGetTypeID(rangeVal) == AXValueGetTypeID() else {
            return 0
        }
        var cfRange = CFRange(location: 0, length: 0)
        if AXValueGetValue(rangeVal as! AXValue, .cfRange, &cfRange) {
            return max(0, cfRange.length)
        }
        return 0
    }
}
