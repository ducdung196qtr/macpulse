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

    private struct TapFastState {
        var isEnabled: Bool
        var hotkey: VietnameseHotkey
        var useCapsLock: Bool
        var fixChrome: Bool
        var isExcludedApp: Bool
        var isBrowserApp: Bool
        var isOmniboxFocused: Bool
    }

    private var stateLock = os_unfair_lock()
    private let engine: VietnameseEngine
    private var settings: VietnameseSettings
    private var perAppEnabled: [String: Bool]
    private var currentBundleID: String
    private var currentAppName: String
    private var currentAppPID: pid_t = 0
    private var focusCheckGeneration: UInt64 = 0
    private let focusCheckQueue = DispatchQueue(label: "com.macpulse.ime.focus", qos: .utility)

    // Snapshot of hot-path settings accessed under os_unfair_lock (~15ns, zero data race)
    private var fastState: TapFastState

    private func readFastState() -> TapFastState {
        os_unfair_lock_lock(&stateLock)
        let s = fastState
        os_unfair_lock_unlock(&stateLock)
        return s
    }

    private var eventSource: CGEventSource?
    private var lastSyntheticTimestamp: UInt64 = 0

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
        let frontBid = front?.bundleIdentifier ?? ""
        let frontName = front?.localizedName ?? frontBid
        let frontPID = front?.processIdentifier ?? 0
        self.currentBundleID = frontBid
        self.currentAppName = frontName
        self.currentAppPID = frontPID
        let isExcluded = Self.computeIsAppExcluded(bundleID: frontBid, appName: frontName, settings: settings, perAppEnabled: perAppEnabled)
        let isBrowser = VietnameseAppDetector.isBrowserOrSearchApp(bundleID: frontBid, appName: frontName)
        let alwaysOmnibox = Self.isAlwaysSearchBarApp(bundleID: frontBid)
        var initialEnabled = settings.isEnabled
        if settings.smartSwitchPerApp && !frontBid.isEmpty {
            if let saved = perAppEnabled[frontBid] {
                initialEnabled = saved
                self.settings.isEnabled = saved
            } else if isExcluded {
                initialEnabled = false
                self.settings.isEnabled = false
            }
        }
        self.fastState = TapFastState(
            isEnabled: initialEnabled,
            hotkey: settings.hotkey,
            useCapsLock: settings.useCapsLockToSwitch,
            fixChrome: settings.fixChromiumAutocomplete,
            isExcludedApp: isExcluded,
            isBrowserApp: isBrowser,
            isOmniboxFocused: alwaysOmnibox
        )
        // Use private state event source so synthetic events NEVER contaminate hardware HID device state
        self.eventSource = CGEventSource(stateID: .privateState)
        if isBrowser && !alwaysOmnibox && frontPID > 0 {
            scheduleOmniboxFocusRefresh(pid: frontPID, bundleID: frontBid, delayMs: 0)
        }
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
        let isExcluded = Self.computeIsAppExcluded(bundleID: currentBundleID, appName: currentAppName, settings: newSettings, perAppEnabled: perAppEnabled)
        let isBrowser = VietnameseAppDetector.isBrowserOrSearchApp(bundleID: currentBundleID, appName: currentAppName)
        let prevOmnibox = fastState.isOmniboxFocused
        fastState = TapFastState(
            isEnabled: newSettings.isEnabled,
            hotkey: newSettings.hotkey,
            useCapsLock: newSettings.useCapsLockToSwitch,
            fixChrome: newSettings.fixChromiumAutocomplete,
            isExcludedApp: isExcluded,
            isBrowserApp: isBrowser,
            isOmniboxFocused: isBrowser ? prevOmnibox : false
        )
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

    @discardableResult
    public static func switchSystemInputSourceToABC() -> Bool {
        let preferredIDs = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US"
        ]
        for targetID in preferredIDs {
            let filter = [kTISPropertyInputSourceID as String: targetID] as CFDictionary
            if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
               let src = list.first {
                if TISSelectInputSource(src) == noErr {
                    return true
                }
            }
        }
        return false
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
            let pid = app.processIdentifier
            let isBrowser = VietnameseAppDetector.isBrowserOrSearchApp(bundleID: bid, appName: name)
            let alwaysOmnibox = Self.isAlwaysSearchBarApp(bundleID: bid)

            os_unfair_lock_lock(&self.stateLock)
            self.currentBundleID = bid
            self.currentAppName = name
            self.currentAppPID = pid
            self.engine.reset()
            let isExcluded = Self.computeIsAppExcluded(bundleID: bid, appName: name, settings: self.settings, perAppEnabled: self.perAppEnabled)
            self.fastState.isExcludedApp = isExcluded
            self.fastState.isBrowserApp = isBrowser
            self.fastState.isOmniboxFocused = alwaysOmnibox
            let shouldCheckFocus = isBrowser && !alwaysOmnibox && self.fastState.fixChrome && pid > 0
            var switchedLanguage: Bool?
            if self.settings.smartSwitchPerApp && !bid.isEmpty && bid != selfBid {
                if let saved = self.perAppEnabled[bid] {
                    if saved != self.settings.isEnabled {
                        self.settings.isEnabled = saved
                        self.fastState.isEnabled = saved
                        self.engine.settings = self.settings
                        switchedLanguage = saved
                    }
                } else if isExcluded {
                    // VPS, Remote Desktop or Terminal app without explicit override defaults to English!
                    if self.settings.isEnabled {
                        self.settings.isEnabled = false
                        self.fastState.isEnabled = false
                        self.engine.settings = self.settings
                        switchedLanguage = false
                    }
                }
            }
            os_unfair_lock_unlock(&self.stateLock)

            if shouldCheckFocus {
                self.scheduleOmniboxFocusRefresh(pid: pid, bundleID: bid, delayMs: 30)
            }

            DispatchQueue.main.async {
                self.onFrontmostAppChanged?(bid, name)
                if let lang = switchedLanguage {
                    self.onLanguageToggled?(lang, bid)
                }
            }
        }
    }

    private static func isAlwaysSearchBarApp(bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        return lower == "com.apple.spotlight" || lower == "com.raycast.macos"
    }

    private func scheduleOmniboxFocusRefresh(pid: pid_t, bundleID: String, delayMs: Int) {
        guard pid > 0 else { return }
        os_unfair_lock_lock(&stateLock)
        focusCheckGeneration &+= 1
        let gen = focusCheckGeneration
        os_unfair_lock_unlock(&stateLock)

        let work = { [weak self] in
            guard let self else { return }
            let focusedOmnibox = Self.isFocusedElementBrowserOmnibox(pid: pid, bundleID: bundleID)
            os_unfair_lock_lock(&self.stateLock)
            if self.focusCheckGeneration == gen && self.currentAppPID == pid && self.fastState.isBrowserApp {
                self.fastState.isOmniboxFocused = focusedOmnibox
            }
            os_unfair_lock_unlock(&self.stateLock)
        }

        if delayMs > 0 {
            focusCheckQueue.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: work)
        } else {
            focusCheckQueue.async(execute: work)
        }
    }

    /// Runs strictly off the EventTap thread on `.utility` QoS to detect whether focus in a browser
    /// is inside the native Omnibox/address bar (needs autocomplete collapse) vs inside a web page DOM
    /// (zero extra chars, zero extra backspaces).
    private static func isFocusedElementBrowserOmnibox(pid: pid_t, bundleID: String) -> Bool {
        if isAlwaysSearchBarApp(bundleID: bundleID) {
            return true
        }
        let appEl = AXUIElementCreateApplication(pid)
        var focusedObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedObj) == .success,
              let focusedObj,
              CFGetTypeID(focusedObj) == AXUIElementGetTypeID() else {
            return false
        }
        let focused = focusedObj as! AXUIElement

        var roleObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleObj) == .success,
              let role = roleObj as? String else {
            return false
        }

        // Address bar / Omnibox is always AXTextField or AXComboBox — never AXTextArea, AXWebArea, AXGroup
        guard role == "AXTextField" || role == "AXComboBox" else {
            return false
        }

        // Chromium & WebKit DOM inputs expose AXDOMClassList; native Omnibox chrome does not
        var domClassObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, "AXDOMClassList" as CFString, &domClassObj) == .success,
           domClassObj != nil {
            return false
        }

        // Walk up parent chain (bounded) — anything inside AXWebArea is a webpage input, not the Omnibox
        var cursor = focused
        for _ in 0..<14 {
            var parentObj: CFTypeRef?
            guard AXUIElementCopyAttributeValue(cursor, kAXParentAttribute as CFString, &parentObj) == .success,
                  let parentObj,
                  CFGetTypeID(parentObj) == AXUIElementGetTypeID() else {
                break
            }
            let parent = parentObj as! AXUIElement
            var pRoleObj: CFTypeRef?
            if AXUIElementCopyAttributeValue(parent, kAXRoleAttribute as CFString, &pRoleObj) == .success,
               let pRole = pRoleObj as? String {
                if pRole == "AXWebArea" {
                    return false
                }
                if pRole == "AXWindow" || pRole == "AXApplication" {
                    break
                }
            }
            cursor = parent
        }

        return true
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
            os_unfair_lock_lock(&stateLock)
            let snap = fastState
            let pid = currentAppPID
            let bid = currentBundleID
            if snap.isEnabled {
                engine.reset()
            }
            os_unfair_lock_unlock(&stateLock)

            if type == .leftMouseDown && snap.isBrowserApp && snap.fixChrome && !Self.isAlwaysSearchBarApp(bundleID: bid) && pid > 0 {
                scheduleOmniboxFocusRefresh(pid: pid, bundleID: bid, delayMs: 45)
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
        let snap = readFastState()
        if snap.isExcludedApp { return }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let hotkey = snap.hotkey
        let useCaps = snap.useCapsLock

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
        let snap = readFastState()
        if snap.isExcludedApp {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let hotkey = snap.hotkey
        let isEnabled = snap.isEnabled

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
            let pid = currentAppPID
            let bid = currentBundleID
            let refreshFocus = fastState.isBrowserApp && fastState.fixChrome
                && flags.contains(.maskCommand)
                && (keyCode == 0x25 || keyCode == 0x11 || keyCode == 0x28 || keyCode == 0x2D) // Cmd+L, T, K, N
            os_unfair_lock_unlock(&stateLock)
            if refreshFocus && pid > 0 {
                scheduleOmniboxFocusRefresh(pid: pid, bundleID: bid, delayMs: 45)
            }
            return Unmanaged.passUnretained(event)
        }

        switch keyCode {
        case 0x24, 0x4C, 0x30, 0x75, 0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79:
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            let pid = currentAppPID
            let bid = currentBundleID
            let refreshFocus = fastState.isBrowserApp && fastState.fixChrome
                && (keyCode == 0x24 || keyCode == 0x4C || keyCode == 0x30) // Return, Enter, Tab
            os_unfair_lock_unlock(&stateLock)
            if refreshFocus && pid > 0 {
                scheduleOmniboxFocusRefresh(pid: pid, bundleID: bid, delayMs: 45)
            }
            return Unmanaged.passUnretained(event)
        case 0x33:
            os_unfair_lock_lock(&stateLock)
            let action = engine.processBackspace()
            let needsOmniboxFix = fastState.fixChrome && fastState.isOmniboxFocused
            os_unfair_lock_unlock(&stateLock)
            return applyAction(action, proxy: proxy, originalEvent: event, needsOmniboxFix: needsOmniboxFix)
        case 0x35:
            os_unfair_lock_lock(&stateLock)
            let action = engine.processEscape()
            let needsOmniboxFix = fastState.fixChrome && fastState.isOmniboxFocused
            let pid = currentAppPID
            let bid = currentBundleID
            let refreshFocus = fastState.isBrowserApp && fastState.fixChrome
            os_unfair_lock_unlock(&stateLock)
            if refreshFocus && pid > 0 {
                scheduleOmniboxFocusRefresh(pid: pid, bundleID: bid, delayMs: 45)
            }
            if case .replace = action {
                return applyAction(action, proxy: proxy, originalEvent: event, needsOmniboxFix: needsOmniboxFix)
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

        // Zero-allocation stack buffer extraction for single UTF-16 character (99.9% of keypresses)
        var actualLength = 0
        var stackBuf: (UniChar, UniChar, UniChar, UniChar) = (0, 0, 0, 0)
        withUnsafeMutablePointer(to: &stackBuf) { ptr in
            ptr.withMemoryRebound(to: UniChar.self, capacity: 4) { uniPtr in
                event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualLength, unicodeString: uniPtr)
            }
        }
        guard actualLength > 0 else {
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
            return Unmanaged.passUnretained(event)
        }

        let ch: Character
        if actualLength == 1, let scalar = UnicodeScalar(stackBuf.0) {
            ch = Character(scalar)
        } else {
            let units: [UniChar] = [stackBuf.0, stackBuf.1, stackBuf.2, stackBuf.3]
            let inputStr = String(utf16CodeUnits: units, count: min(actualLength, 4))
            guard inputStr.count == 1, let first = inputStr.first else {
                os_unfair_lock_lock(&stateLock)
                engine.reset()
                os_unfair_lock_unlock(&stateLock)
                return Unmanaged.passUnretained(event)
            }
            ch = first
        }

        os_unfair_lock_lock(&stateLock)
        let action = engine.processCharacter(ch)
        let needsOmniboxFix = fastState.fixChrome && fastState.isOmniboxFocused
        os_unfair_lock_unlock(&stateLock)

        return applyAction(action, proxy: proxy, originalEvent: event, needsOmniboxFix: needsOmniboxFix)
    }

    private func toggleLanguageFromHotkey() {
        os_unfair_lock_lock(&stateLock)
        let nextEnabled = !settings.isEnabled
        settings.isEnabled = nextEnabled
        fastState.isEnabled = nextEnabled
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
        needsOmniboxFix: Bool
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
                needsOmniboxFix: needsOmniboxFix
            )
            return nil
        }
    }

    @inline(__always)
    private func nextMonotonicTimestamp() -> UInt64 {
        let now = mach_absolute_time()
        let next = now > lastSyntheticTimestamp ? now : (lastSyntheticTimestamp &+ 1)
        lastSyntheticTimestamp = next
        return next
    }

    /// Zero-usleep instant HID event injection via synchronous FIFO `tapPostEvent(proxy)`.
    /// Eliminates 15–45ms callback stalls and `.tapDisabledByTimeout` drops during rapid typing.
    private func postReplacement(
        proxy: CGEventTapProxy,
        backspaceCount: Int,
        text: String,
        needsOmniboxFix: Bool
    ) {
        guard let src = eventSource else { return }

        if backspaceCount > 0 && needsOmniboxFix {
            // Collapse active Omnibox / Spotlight inline autocomplete highlight using U+202F
            // (Narrow No-Break Space, Grapheme_Cluster_Break=Other — NEVER fuses with the preceding
            // character into a grapheme cluster like U+200C ZWNJ does).
            var nbsp: UniChar = 0x202F
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                down.flags = []
                down.timestamp = nextMonotonicTimestamp()
                down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &nbsp)
                down.tapPostEvent(proxy)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.flags = []
                up.timestamp = nextMonotonicTimestamp()
                up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &nbsp)
                up.tapPostEvent(proxy)
            }
        }

        let totalBackspaces = (backspaceCount > 0 && needsOmniboxFix) ? (backspaceCount + 1) : backspaceCount

        if totalBackspaces > 0 {
            for _ in 0..<totalBackspaces {
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true) {
                    down.flags = []
                    down.timestamp = nextMonotonicTimestamp()
                    down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    down.tapPostEvent(proxy)
                }
                if let up = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false) {
                    up.flags = []
                    up.timestamp = nextMonotonicTimestamp()
                    up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    up.tapPostEvent(proxy)
                }
            }
        }

        if !text.isEmpty {
            for ch in text {
                var utf16 = Array(String(ch).utf16)
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                    down.flags = []
                    down.timestamp = nextMonotonicTimestamp()
                    down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    down.tapPostEvent(proxy)
                }
                if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                    up.flags = []
                    up.timestamp = nextMonotonicTimestamp()
                    up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
                    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    up.tapPostEvent(proxy)
                }
            }
        }
    }
}
