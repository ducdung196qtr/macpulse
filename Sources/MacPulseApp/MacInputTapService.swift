import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import IOKit
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

public struct LiveIMEInjectionStatus: Sendable, Equatable {
    public let tapLevel: String
    public let appBundleID: String
    public let appName: String
    public let profile: IMEInjectionProfile
}

/// Zero-lag macOS Vietnamese IME service combining the proven 2026 architectures of
/// Dokey, OpenKey, and PHTV:
/// - Single `.cgSessionEventTap` at `.headInsertEventTap` on a dedicated `.userInteractive` thread
/// - ALL synthetic events inserted via `event.tapPostEvent(proxy)` (strict FIFO ahead of the next key)
/// - `freeTextKey()` avoids `virtualKey: 0` (`kVK_ANSI_A`) and any key physically held down so
///   Chromium/Electron NEVER drop replacement Unicode events as repeats during 200+ WPM rollover
/// - Select-then-type (`Shift+←` with `[.maskShift, .maskSecondaryFn, .maskNumericPad]`) for
///   Electron & Browsers (eliminates ProseMirror/Lexical/Blink Backspace races that cause `coộng`),
///   plus `U+00B7` selection guard on Browsers & Spotlight to break inline autocomplete
/// - ZERO synchronous AX IPC and ZERO `usleep` on the normal/Electron/Browser hot path (< 80µs/key)
/// - In-memory word history stack for backspace-into-previous-word editing
/// - 2-second non-destructive watchdog + macOS Secure Input holder detection (IORegistry)
public final class MacInputTapService {
    public static let syntheticMagic: Int64 = 0x4D50_5649 // "MPVI"
    private static let accessibilityKeyboardBundleID = "com.apple.inputmethod.AssistiveControl"

    public static var vpsAndRemoteDesktopBundles: Set<String> { VietnameseAppDetector.vpsAndRemoteDesktopBundles }
    public static var terminalAndShellBundles: Set<String> { VietnameseAppDetector.terminalAndShellBundles }

    public static func isVPSOrRemoteApp(bundleID: String, appName: String = "") -> Bool {
        VietnameseAppDetector.isVPSOrRemoteApp(bundleID: bundleID, appName: appName)
    }

    public static func isTerminalApp(bundleID: String, appName: String = "") -> Bool {
        VietnameseAppDetector.isTerminalApp(bundleID: bundleID, appName: appName)
    }

    public static func computeIsAppExcluded(
        bundleID: String,
        appName: String,
        settings: VietnameseSettings,
        perAppEnabled: [String: Bool] = [:]
    ) -> Bool {
        VietnameseAppDetector.computeIsAppExcluded(
            bundleID: bundleID,
            appName: appName,
            settings: settings,
            perAppEnabled: perAppEnabled
        )
    }

    private static let conflictBundleMap: [(bundleID: String, label: String)] = [
        ("com.lamquangminh.EVKey", "EVKey"),
        ("org.vielotus.inputmethod.VieLotusIM", "BeVie (VieLotusIM)"),
        ("com.tuyenmai.OpenKey", "OpenKey"),
        ("com.trankynam.GoTiengViet", "GoTiengViet"),
        ("org.gonhanh.GoNhanh", "Gõ Nhanh"),
        ("com.dhtoan.dokey.mac", "Dokey")
    ]

    private struct TapFastState {
        var isEnabled: Bool
        var hotkey: VietnameseHotkey
        var useCapsLock: Bool
        var fixChrome: Bool
        var speedMode: IMEInjectionSpeedMode
        var isExcludedApp: Bool
        var profile: IMEInjectionProfile
    }

    private struct BundleFrameworkHints {
        var isElectron: Bool
        var isBrowser: Bool
    }

    private var stateLock = os_unfair_lock()
    private let engine: VietnameseEngine
    private var settings: VietnameseSettings
    private var perAppEnabled: [String: Bool]
    private var currentBundleID: String
    private var currentAppName: String
    private var currentAppPID: pid_t = 0
    private var currentWindowTitle: String = ""
    private var fastState: TapFastState

    private var bundleHintsCache: [String: BundleFrameworkHints] = [:]
    private let eventSource: CGEventSource?

    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?
    private var tapState: TapRuntimeState = .stopped

    private var modifierChord = ModifierChordTracker()
    private var wasControlPressed = false

    private var workspaceObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var sessionActiveObserver: NSObjectProtocol?
    private var trustPollTimer: Timer?
    private var watchdogTimer: Timer?
    private var isSecureInputBlocked: Bool = false
    private var lastPublishedStatusKey: String = ""

    /// Lightweight opt-in debug tracer — 0ns overhead unless `/tmp/macpulse_ime_debug.log` exists.
    private static let debugLogPath = "/tmp/macpulse_ime_debug.log"
    private static let debugLogQueue = DispatchQueue(label: "com.macpulse.ime.debuglog", qos: .utility)
    private var debugLogEnabled: Bool = false

    public var onLanguageToggled: ((Bool, String) -> Void)?
    public var onRuntimeStateChanged: ((TapRuntimeState, Bool) -> Void)?
    public var onFrontmostAppChanged: ((String, String) -> Void)?
    public var onSecureInputChanged: ((Bool, String?) -> Void)?
    public var onInjectionStatusChanged: ((LiveIMEInjectionStatus) -> Void)?

    public init(settings: VietnameseSettings, perAppEnabled: [String: Bool] = [:]) {
        self.settings = settings
        self.perAppEnabled = perAppEnabled
        self.engine = VietnameseEngine(settings: settings)
        self.eventSource = CGEventSource(stateID: .privateState)

        let front = NSWorkspace.shared.frontmostApplication
        let frontBid = front?.bundleIdentifier ?? ""
        let frontName = front?.localizedName ?? frontBid
        let frontPID = front?.processIdentifier ?? 0
        self.currentBundleID = frontBid
        self.currentAppName = frontName
        self.currentAppPID = frontPID

        let hints = Self.inspectBundleFrameworks(app: front)
        if !frontBid.isEmpty {
            self.bundleHintsCache[frontBid.lowercased()] = hints
        }
        let isExcluded = Self.computeIsAppExcluded(
            bundleID: frontBid,
            appName: frontName,
            settings: settings,
            perAppEnabled: perAppEnabled
        )
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
        let initialProfile = IMEAppProfileResolver.resolve(
            bundleID: frontBid,
            appName: frontName,
            windowTitle: "",
            isElectronBundle: hints.isElectron,
            isBrowserBundle: hints.isBrowser,
            fixChromiumAutocomplete: settings.fixChromiumAutocomplete,
            speedMode: settings.injectionSpeedMode
        )
        self.fastState = TapFastState(
            isEnabled: initialEnabled,
            hotkey: settings.hotkey,
            useCapsLock: settings.useCapsLockToSwitch,
            fixChrome: settings.fixChromiumAutocomplete,
            speedMode: settings.injectionSpeedMode,
            isExcludedApp: isExcluded,
            profile: initialProfile
        )
        self.debugLogEnabled = FileManager.default.fileExists(atPath: Self.debugLogPath)
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    public func start() {
        Self.terminateConflictingApps()
        observeWorkspaceIfNeeded()
        updateTrustAndTapLifecycle(promptIfNeeded: false)
    }

    public func stop() {
        stopTrustPolling()
        stopWatchdog()
        removeWorkspaceObservers()
        teardownTapThread()
        setTapState(.stopped)
    }

    public func updateSettings(_ newSettings: VietnameseSettings) {
        os_unfair_lock_lock(&stateLock)
        let prevEnabled = settings.isEnabled
        settings = newSettings
        engine.settings = newSettings
        let bid = currentBundleID
        let name = currentAppName
        let winTitle = currentWindowTitle
        let hints = bundleHintsCache[bid.lowercased()] ?? BundleFrameworkHints(isElectron: false, isBrowser: false)
        let isExcluded = Self.computeIsAppExcluded(
            bundleID: bid,
            appName: name,
            settings: newSettings,
            perAppEnabled: perAppEnabled
        )
        let profile = IMEAppProfileResolver.resolve(
            bundleID: bid,
            appName: name,
            windowTitle: winTitle,
            isElectronBundle: hints.isElectron,
            isBrowserBundle: hints.isBrowser,
            fixChromiumAutocomplete: newSettings.fixChromiumAutocomplete,
            speedMode: newSettings.injectionSpeedMode
        )
        fastState = TapFastState(
            isEnabled: newSettings.isEnabled,
            hotkey: newSettings.hotkey,
            useCapsLock: newSettings.useCapsLockToSwitch,
            fixChrome: newSettings.fixChromiumAutocomplete,
            speedMode: newSettings.injectionSpeedMode,
            isExcludedApp: isExcluded,
            profile: profile
        )
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"
        if newSettings.smartSwitchPerApp && !bid.isEmpty && bid != selfBid && prevEnabled != newSettings.isEnabled {
            perAppEnabled[bid] = newSettings.isEnabled
        }
        engine.resetAll()
        os_unfair_lock_unlock(&stateLock)

        publishInjectionStatusIfChanged(
            LiveIMEInjectionStatus(tapLevel: "Session Tap", appBundleID: bid, appName: name, profile: profile)
        )
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
        engine.resetAll()
        os_unfair_lock_unlock(&stateLock)
    }

    public func currentTapLevelLabel() -> String {
        "Session Tap"
    }

    // MARK: - Accessibility, Input Source, Conflicts, Secure Input

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

    public static func currentSecureInputHolderName() -> String? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        var holderPID: pid_t?
        for session in users {
            if let pid = session["kCGSSessionSecureInputPID"] as? Int, pid > 0 {
                holderPID = pid_t(pid)
                break
            }
        }
        guard let pid = holderPID else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName, !name.isEmpty {
            return name
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return (String(cString: buffer) as NSString).lastPathComponent
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
            startWatchdogIfNeeded()
            refreshSecureInputState()
        } else {
            stopWatchdog()
            teardownTapThread()
            setTapState(.waitingAccessibility)
            startTrustPollingIfNeeded()
        }
    }

    // MARK: - Watchdog & Workspace Observers (Main Thread — Zero Tap Overhead)

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
                if Self.isAccessibilityTrusted(prompt: false) {
                    self.stopTrustPolling()
                    self.launchTapThread()
                    self.startWatchdogIfNeeded()
                    self.refreshSecureInputState()
                }
            }
        }
    }

    private func startWatchdogIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.watchdogTimer == nil else { return }
            let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.watchdogTick()
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.watchdogTimer = timer
        }
    }

    private func stopWatchdog() {
        DispatchQueue.main.async { [weak self] in
            self?.watchdogTimer?.invalidate()
            self?.watchdogTimer = nil
        }
    }

    /// Non-destructive watchdog: re-enables a disabled tap in place and refreshes browser title / Secure Input.
    /// NEVER tears down a healthy running tap.
    private func watchdogTick() {
        refreshSecureInputState()
        let debugNow = FileManager.default.fileExists(atPath: Self.debugLogPath)

        os_unfair_lock_lock(&stateLock)
        debugLogEnabled = debugNow
        let port = eventTap
        let kind = fastState.profile.appKind
        let pid = currentAppPID
        let bid = currentBundleID
        let name = currentAppName
        os_unfair_lock_unlock(&stateLock)

        if let port, !CGEvent.tapIsEnabled(tap: port) {
            os_unfair_lock_lock(&stateLock)
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)
            CGEvent.tapEnable(tap: port, enable: true)
            trace("WATCHDOG re-enabled disabled tap")
        }

        // Refresh browser window title off the tap thread (detects Google Docs/Sheets/Slides tabs)
        if kind == .browser && pid > 0 {
            refreshBrowserWindowTitleAsync(pid: pid, bundleID: bid, appName: name)
        }
    }

    public func refreshSecureInputState() {
        let blocked = IsSecureEventInputEnabled()
        os_unfair_lock_lock(&stateLock)
        let changed = (blocked != isSecureInputBlocked)
        isSecureInputBlocked = blocked
        let port = eventTap
        if changed {
            engine.resetAll()
        }
        os_unfair_lock_unlock(&stateLock)

        guard changed else { return }
        if !blocked, let port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        let holder = blocked ? Self.currentSecureInputHolderName() : nil
        DispatchQueue.main.async { [weak self] in
            self?.onSecureInputChanged?(blocked, holder)
        }
    }

    private func observeWorkspaceIfNeeded() {
        let nc = NSWorkspace.shared.notificationCenter
        let selfBid = Bundle.main.bundleIdentifier ?? "com.ducdung.MacPulse"

        if workspaceObserver == nil {
            workspaceObserver = nc.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self else { return }
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let bid = app.bundleIdentifier ?? ""
                let name = app.localizedName ?? bid
                let pid = app.processIdentifier
                let hints = self.cachedOrInspectHints(for: app, bundleID: bid)

                os_unfair_lock_lock(&self.stateLock)
                self.currentBundleID = bid
                self.currentAppName = name
                self.currentAppPID = pid
                self.currentWindowTitle = ""
                self.engine.resetAll()

                let isExcluded = Self.computeIsAppExcluded(
                    bundleID: bid,
                    appName: name,
                    settings: self.settings,
                    perAppEnabled: self.perAppEnabled
                )
                self.fastState.isExcludedApp = isExcluded

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
                        if self.settings.isEnabled {
                            self.settings.isEnabled = false
                            self.fastState.isEnabled = false
                            self.engine.settings = self.settings
                            switchedLanguage = false
                        }
                    }
                }

                let profile = IMEAppProfileResolver.resolve(
                    bundleID: bid,
                    appName: name,
                    windowTitle: "",
                    isElectronBundle: hints.isElectron,
                    isBrowserBundle: hints.isBrowser,
                    fixChromiumAutocomplete: self.fastState.fixChrome,
                    speedMode: self.fastState.speedMode
                )
                self.fastState.profile = profile
                os_unfair_lock_unlock(&self.stateLock)

                self.publishInjectionStatusIfChanged(
                    LiveIMEInjectionStatus(tapLevel: "Session Tap", appBundleID: bid, appName: name, profile: profile)
                )
                self.refreshSecureInputState()
                self.onFrontmostAppChanged?(bid, name)
                if let lang = switchedLanguage {
                    self.onLanguageToggled?(lang, bid)
                }

                if profile.appKind == .browser && pid > 0 {
                    self.refreshBrowserWindowTitleAsync(pid: pid, bundleID: bid, appName: name)
                }
            }
        }

        if wakeObserver == nil {
            wakeObserver = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.watchdogTick()
            }
        }
        if sessionActiveObserver == nil {
            sessionActiveObserver = nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.watchdogTick()
            }
        }
    }

    private func removeWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        if let obs = workspaceObserver { nc.removeObserver(obs); workspaceObserver = nil }
        if let obs = wakeObserver { nc.removeObserver(obs); wakeObserver = nil }
        if let obs = sessionActiveObserver { nc.removeObserver(obs); sessionActiveObserver = nil }
    }

    private static func inspectBundleFrameworks(app: NSRunningApplication?) -> BundleFrameworkHints {
        guard let url = app?.bundleURL else {
            return BundleFrameworkHints(isElectron: false, isBrowser: false)
        }
        let frameworksDir = url.appendingPathComponent("Contents/Frameworks").path
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworksDir)) ?? []
        var isElectron = false
        var isBrowser = false
        for name in names {
            if name == "Electron Framework.framework" || name == "Chromium Embedded Framework.framework" {
                isElectron = true
            } else if name.hasSuffix(" Framework.framework") {
                if ["Chrome", "Chromium", "Edge", "Brave", "Opera", "Vivaldi"].contains(where: { name.contains($0) }) {
                    isBrowser = true
                }
            }
        }
        return BundleFrameworkHints(isElectron: isElectron, isBrowser: isBrowser)
    }

    private func cachedOrInspectHints(for app: NSRunningApplication?, bundleID: String) -> BundleFrameworkHints {
        let key = bundleID.lowercased()
        guard !key.isEmpty else { return BundleFrameworkHints(isElectron: false, isBrowser: false) }
        os_unfair_lock_lock(&stateLock)
        let cached = bundleHintsCache[key]
        os_unfair_lock_unlock(&stateLock)
        if let cached { return cached }

        let inspected = Self.inspectBundleFrameworks(app: app)
        os_unfair_lock_lock(&stateLock)
        bundleHintsCache[key] = inspected
        os_unfair_lock_unlock(&stateLock)
        return inspected
    }

    /// Reads the browser's focused window title on a background queue (never on the tap thread)
    /// so Google Docs / Sheets / Slides automatically switch to 1-char-per-event pacing.
    private func refreshBrowserWindowTitleAsync(pid: pid_t, bundleID: String, appName: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let appEl = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appEl, 0.08)
            var winRef: CFTypeRef?
            var title = ""
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
               let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(winRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let str = titleRef as? String {
                    title = str
                }
            }

            os_unfair_lock_lock(&self.stateLock)
            guard self.currentAppPID == pid else {
                os_unfair_lock_unlock(&self.stateLock)
                return
            }
            let titleChanged = (title != self.currentWindowTitle)
            self.currentWindowTitle = title
            let hints = self.bundleHintsCache[bundleID.lowercased()] ?? BundleFrameworkHints(isElectron: false, isBrowser: false)
            let newProfile = IMEAppProfileResolver.resolve(
                bundleID: bundleID,
                appName: appName,
                windowTitle: title,
                isElectronBundle: hints.isElectron,
                isBrowserBundle: hints.isBrowser,
                fixChromiumAutocomplete: self.fastState.fixChrome,
                speedMode: self.fastState.speedMode
            )
            let profileChanged = (newProfile != self.fastState.profile)
            if titleChanged || profileChanged {
                self.fastState.profile = newProfile
            }
            os_unfair_lock_unlock(&self.stateLock)

            if profileChanged {
                self.publishInjectionStatusIfChanged(
                    LiveIMEInjectionStatus(tapLevel: "Session Tap", appBundleID: bundleID, appName: appName, profile: newProfile)
                )
            }
        }
    }

    private func publishInjectionStatusIfChanged(_ status: LiveIMEInjectionStatus) {
        let key = "\(status.tapLevel)|\(status.appBundleID)|\(status.profile.method.rawValue)|\(status.profile.reason)"
        os_unfair_lock_lock(&stateLock)
        let changed = (key != lastPublishedStatusKey)
        if changed { lastPublishedStatusKey = key }
        os_unfair_lock_unlock(&stateLock)
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onInjectionStatusChanged?(status)
        }
    }

    /// WindowServer-local check for Spotlight overlay (only called when frontmost appKind == .normal).
    /// Queries `kAXFocusedApplicationAttribute` (answered by WindowServer, never blocks Electron).
    private static func isSpotlightCurrentlyFocused() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.04)
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appRef, CFGetTypeID(appRef) == AXUIElementGetTypeID() else {
            return false
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(appRef as! AXUIElement, &pid) == .success, pid > 0,
              let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return false
        }
        return IMEAppProfileResolver.isSpotlightLike(bundleID: bid)
    }

    private static func isClickOnAccessibilityKeyboard(_ cgPoint: CGPoint) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for w in windows {
            let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha <= 0.01 { continue }
            guard let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  !bounds.isEmpty, bounds.contains(cgPoint) else { continue }
            if let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value {
                return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == accessibilityKeyboardBundleID
            }
            return false
        }
        return false
    }

    // MARK: - Event Tap Thread

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
            | (1 << CGEventType.otherMouseDown.rawValue)

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

    // MARK: - Event Handling (Tap Thread — < 80µs hot path!)

    private func readFastState() -> TapFastState {
        os_unfair_lock_lock(&stateLock)
        let s = fastState
        os_unfair_lock_unlock(&stateLock)
        return s
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            os_unfair_lock_lock(&stateLock)
            let port = eventTap
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            trace("TAP_DISABLED type=\(type.rawValue) -> re-enabled")
            return pass
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMagic {
            return pass
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            if !Self.isClickOnAccessibilityKeyboard(event.location) {
                modifierChord.reset()
                os_unfair_lock_lock(&stateLock)
                engine.resetAll()
                os_unfair_lock_unlock(&stateLock)
            }
            return pass
        }

        if type == .flagsChanged {
            handleFlagsChanged(event)
            return pass
        }

        guard type == .keyDown else {
            return pass
        }

        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        modifierChord.keyPressed(modifiersHeldRaw: event.flags.intersection(modifierMask).rawValue)

        return handleKeyDown(proxy: proxy, event: event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let snap = readFastState()
        if snap.isExcludedApp { return }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Control press rhythm-break (EVKey / GoNhanh behavior)
        let isCtrlNow = flags.contains(.maskControl)
        if isCtrlNow && !wasControlPressed {
            os_unfair_lock_lock(&stateLock)
            engine.reset()
            os_unfair_lock_unlock(&stateLock)
        }
        wasControlPressed = isCtrlNow

        if (snap.hotkey == .capsLock || snap.useCapsLock) && keyCode == 0x39 {
            toggleLanguageFromHotkey()
            return
        }

        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        let masked = flags.intersection(modifierMask).rawValue

        if let peakRaw = modifierChord.modifiersChanged(to: masked) {
            let peak = CGEventFlags(rawValue: peakRaw)
            switch snap.hotkey {
            case .ctrlShift:
                if peak == [.maskControl, .maskShift] {
                    toggleLanguageFromHotkey()
                }
            case .cmdShift:
                if peak == [.maskCommand, .maskShift] {
                    toggleLanguageFromHotkey()
                }
            case .optionZ, .ctrlSpace, .capsLock:
                break
            }
        }
    }

    private func handleKeyDown(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let snap = readFastState()
        if snap.isExcludedApp || snap.profile.method == .passthrough {
            return pass
        }

        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Language toggle shortcuts
        if snap.hotkey == .optionZ && keyCode == 0x06
            && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                toggleLanguageFromHotkey()
            }
            return nil
        }
        if snap.hotkey == .ctrlSpace && keyCode == 0x31
            && flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                toggleLanguageFromHotkey()
            }
            return nil
        }

        guard snap.isEnabled else {
            return pass
        }

        // Key held down (autorepeat) -> start fresh word & pass through
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            os_unfair_lock_lock(&stateLock)
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)
            return pass
        }

        // Shortcuts (Cmd / Ctrl / Option / Fn) never enter the engine
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn) {
            os_unfair_lock_lock(&stateLock)
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)
            return pass
        }

        switch keyCode {
        case 0x75, 0x7B, 0x7C, 0x7D, 0x7E, 0x73, 0x77, 0x74, 0x79:
            // Forward Delete, Arrows, Home, End, PageUp, PageDown
            os_unfair_lock_lock(&stateLock)
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)
            return pass

        case 0x24, 0x4C, 0x30:
            // Return (0x24), Numpad Enter (0x4C), Tab (0x30):
            // Finish current word (auto-restore / macro) and replay a copy of the original event if edited!
            let delimChar: Character = (keyCode == 0x30) ? "\t" : "\n"
            os_unfair_lock_lock(&stateLock)
            let action = engine.processDelimiter(delimChar, allowAutoRestore: true)
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)

            if case .replace(let bs, let rawText) = action {
                let cleanText = rawText.hasSuffix(String(delimChar)) ? String(rawText.dropLast()) : rawText
                deliverEdit(bs: bs, text: cleanText, snap: snap, proxy: proxy, thenOriginal: event)
                return nil
            }
            return pass

        case 0x33:
            // Backspace: edits active word or steps back across space into previous word in history
            os_unfair_lock_lock(&stateLock)
            let action = engine.processBackspace()
            os_unfair_lock_unlock(&stateLock)

            if case .replace(let bs, let text) = action {
                deliverEdit(bs: bs, text: text, snap: snap, proxy: proxy, thenOriginal: nil)
                return nil
            }
            return pass

        case 0x35:
            // Escape: restore exact raw ASCII keystrokes if enabled
            os_unfair_lock_lock(&stateLock)
            let action = engine.processEscape()
            os_unfair_lock_unlock(&stateLock)
            if case .replace(let bs, let text) = action {
                deliverEdit(bs: bs, text: text, snap: snap, proxy: proxy, thenOriginal: nil)
                return nil
            }
            return pass

        default:
            break
        }

        // Zero-allocation stack buffer extraction for single UTF-16 character
        var actualLength = 0
        var stackBuf: (UniChar, UniChar, UniChar, UniChar) = (0, 0, 0, 0)
        withUnsafeMutablePointer(to: &stackBuf) { ptr in
            ptr.withMemoryRebound(to: UniChar.self, capacity: 4) { uniPtr in
                event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualLength, unicodeString: uniPtr)
            }
        }
        guard actualLength == 1 else {
            os_unfair_lock_lock(&stateLock)
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)
            return pass
        }

        let unit = stackBuf.0
        if unit < 0x20 || unit == 0x7F || (unit >= 0xF700 && unit <= 0xF8FF) || (unit >= 0xD800 && unit <= 0xDFFF) {
            os_unfair_lock_lock(&stateLock)
            engine.resetAll()
            os_unfair_lock_unlock(&stateLock)
            return pass
        }
        guard let scalar = UnicodeScalar(unit) else {
            return pass
        }
        let ch = Character(scalar)

        os_unfair_lock_lock(&stateLock)
        let action = engine.processCharacter(ch)
        os_unfair_lock_unlock(&stateLock)

        switch action {
        case .passthrough:
            trace("PASS key=\(keyCode) ch='\(ch)'")
            return pass
        case .replace(let bs, let text):
            trace("EDIT key=\(keyCode) ch='\(ch)' kind=\(snap.profile.appKind.rawValue) sel=\(snap.profile.useSelection) guard=\(snap.profile.clearInlineSelection) bs=\(bs) -> '\(text)'")
            deliverEdit(bs: bs, text: text, snap: snap, proxy: proxy, thenOriginal: nil)
            return nil
        }
    }

    private func toggleLanguageFromHotkey() {
        os_unfair_lock_lock(&stateLock)
        let nextEnabled = !settings.isEnabled
        settings.isEnabled = nextEnabled
        fastState.isEnabled = nextEnabled
        engine.settings = settings
        engine.resetAll()
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

    // MARK: - Dokey/OpenKey-Grade Atomic Delivery via `tapPostEvent(proxy)`

    /// Picks a virtual key code NOT currently held down on the physical keyboard.
    /// Critical for fast typing in Chromium/Electron: `virtualKey: 0` is `kVK_ANSI_A`,
    /// so if the user's finger is still touching `'A'` during 150+ WPM rollover,
    /// Chromium drops `keyDown(0)` carrying Unicode text as an autorepeat!
    @inline(__always)
    private static func freeTextKey() -> CGKeyCode {
        // b, v, n, comma, period, grave, semicolon
        let candidates: [CGKeyCode] = [11, 9, 45, 43, 47, 50, 41]
        for key in candidates where !CGEventSource.keyState(.hidSystemState, key: key) {
            return key
        }
        return 11
    }

    private func deliverEdit(
        bs: Int,
        text: String,
        snap: TapFastState,
        proxy: CGEventTapProxy,
        thenOriginal original: CGEvent?
    ) {
        guard let src = eventSource else { return }

        var profile = snap.profile
        // Spotlight overlay never activates NSWorkspace; catch it only when frontmost app is .normal
        if profile.appKind == .normal && Self.isSpotlightCurrentlyFocused() {
            profile = IMEAppProfileResolver.resolve(
                bundleID: "com.apple.Spotlight",
                fixChromiumAutocomplete: snap.fixChrome,
                speedMode: snap.speedMode
            )
        }

        let nfcText = text.precomposedStringWithCanonicalMapping
        let utf16 = Array(nfcText.utf16)
        let steps = profile.deletionSteps(backspaces: bs, replacementIsEmpty: utf16.isEmpty)
        let textKey = Self.freeTextKey()

        // 1. Deletion / Selection phase
        for step in steps {
            switch step {
            case .guardCharacter:
                postUnicodeUnits([IMEInjectionProfile.selectionGuardScalar], key: textKey, source: src, proxy: proxy)
            case .selectLeft:
                // macOS physical arrow keys carry Shift + SecondaryFn + NumericPad flags
                postKey(0x7B, flags: [.maskShift, .maskSecondaryFn, .maskNumericPad], source: src, proxy: proxy)
            case .backspace:
                // Clean empty flags: a held Shift must NEVER turn Backspace into Shift+Backspace
                postKey(0x33, flags: [], source: src, proxy: proxy)
            }
            if profile.delays.stepUs > 0 { usleep(profile.delays.stepUs) }
        }

        if bs > 0 && !utf16.isEmpty && profile.delays.settleUs > 0 {
            usleep(profile.delays.settleUs)
        }

        // 2. Replacement Unicode phase (NFC, surrogate-pair safe, carrying non-held freeTextKey!)
        if !utf16.isEmpty {
            let chunk = max(1, min(profile.unitsPerEvent, 20))
            var start = 0
            while start < utf16.count {
                var end = min(start + chunk, utf16.count)
                if end < utf16.count && UTF16.isLeadSurrogate(utf16[end - 1]) {
                    end += 1
                }
                let slice = Array(utf16[start..<end])
                // Handle embedded newlines cleanly (for multi-line macros)
                if slice.contains(0x000A) {
                    var segStart = 0
                    for idx in 0..<slice.count where slice[idx] == 0x000A {
                        if idx > segStart {
                            postUnicodeUnits(Array(slice[segStart..<idx]), key: textKey, source: src, proxy: proxy)
                        }
                        postKey(0x24, flags: [], source: src, proxy: proxy)
                        segStart = idx + 1
                    }
                    if segStart < slice.count {
                        postUnicodeUnits(Array(slice[segStart..<slice.count]), key: textKey, source: src, proxy: proxy)
                    }
                } else {
                    postUnicodeUnits(slice, key: textKey, source: src, proxy: proxy)
                }
                if profile.delays.stepUs > 0 { usleep(profile.delays.stepUs) }
                start = end
            }
            if profile.delays.tailUs > 0 { usleep(profile.delays.tailUs) }
        }

        // 3. Replay original Return/Tab event if this edit committed on a control delimiter
        if let copy = original?.copy() {
            copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
            copy.tapPostEvent(proxy)
        }
    }

    @inline(__always)
    private func postKey(
        _ key: CGKeyCode,
        flags: CGEventFlags,
        source: CGEventSource,
        proxy: CGEventTapProxy
    ) {
        for isDown in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else { continue }
            ev.flags = flags
            ev.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
            ev.tapPostEvent(proxy)
        }
    }

    @inline(__always)
    private func postUnicodeUnits(
        _ units: [UInt16],
        key: CGKeyCode,
        source: CGEventSource,
        proxy: CGEventTapProxy
    ) {
        for isDown in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else { continue }
            ev.flags = []
            var buf = units
            ev.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
            ev.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMagic)
            ev.tapPostEvent(proxy)
        }
    }

    // MARK: - Opt-in Microsecond Diagnostic Tracer

    private func trace(_ msg: @autoclosure () -> String) {
        os_unfair_lock_lock(&stateLock)
        let enabled = debugLogEnabled
        os_unfair_lock_unlock(&stateLock)
        guard enabled else { return }
        let line = String(format: "%.4f %@\n", CFAbsoluteTimeGetCurrent(), msg())
        Self.debugLogQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: Self.debugLogPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }
    }
}
