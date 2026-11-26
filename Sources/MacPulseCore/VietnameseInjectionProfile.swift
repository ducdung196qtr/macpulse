import Foundation

/// Delivery compatibility preset for macOS synthetic text injection.
/// - `.auto`: Proven Dokey/OpenKey/PHTV matrix — Select-then-type (`Shift+←`) on Electron & Browsers
///   (with `U+00B7` autocomplete guard on Browsers/Spotlight), plain `Backspace` on Native/Terminals,
///   0ms callback blocking, and `freeTextKey()` (never `kVK_ANSI_A`) so fast 200+ WPM rollover never drops chars.
/// - `.fast`: Classic 0ms Backspace + `freeTextKey()` everywhere (for users who never want `Shift+←`).
/// - `.safe`: Same as `.auto` with gentle 1.5ms/4ms breathing pauses for heavily loaded Electron/Web editors.
public enum IMEInjectionSpeedMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto
    case fast
    case safe

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Tự động (Chọn đè)"
        case .fast: return "Backspace 0ms"
        case .safe: return "An toàn (+trễ nhẹ)"
        }
    }

    public var subtitle: String {
        switch self {
        case .auto: return "Bôi đen Shift+← ghi đè cho Electron/Chrome (0ms lag) + Backspace cho app Native."
        case .fast: return "Dùng Backspace thuần 0ms toàn hệ thống (kiểu EVKey/OpenKey cổ điển)."
        case .safe: return "Chọn đè kèm nghỉ 1.5ms/4ms khi máy tải nặng hoặc soạn thảo web lớn."
        }
    }
}

/// High-level app category resolved ONCE on app switch (main thread) — zero AX IPC on keystroke hot path!
public enum IMEAppKind: String, Sendable, Equatable {
    case browser       // Chromium / Gecko / WebKit browsers & Spotlight/Raycast/Alfred
    case electron      // Electron / CEF / rich-text desktop apps (Antigravity, VSCode, Cursor, Slack, Zalo, Notion...)
    case terminal      // Standalone terminals (Shift+← emits escape sequence, must use Backspace)
    case singleChar    // Adobe Creative Cloud, TeXstudio, Foxit PDF (1 UTF-16 unit per event)
    case normal        // Native macOS apps (Notes, Messages, Mail, TextEdit, Finder, MacPulse...)
    case passthrough   // Remote Desktop, VPS, iPhone Mirroring (0ms raw hardware passthrough)
}

/// Concrete delivery method badge shown in UI and tested in unit tests.
public enum IMEInjectionMethod: String, Sendable, Equatable {
    case selectAndReplace       // Shift+← + freeTextKey() atomic typeover (Electron / Rich-text / Web)
    case browserGuardSelect     // U+00B7 selection guard + (bs+1) Shift+← + freeTextKey() (Chrome / Brave / Edge / Safari / Spotlight)
    case backspaceFast          // Clean Backspace + freeTextKey() at 0ms (Native apps & Terminals)
    case charByChar             // 1 UTF-16 unit per event (Google Docs/Sheets/Slides, Adobe, TeXstudio)
    case passthrough            // 0ms hardware passthrough (Windows App, 9Remote, AnyDesk, RustDesk, iPhone Mirroring)

    public var displayBadge: String {
        switch self {
        case .selectAndReplace: return "Select-Replace 0ms"
        case .browserGuardSelect: return "Browser Guard 0ms"
        case .backspaceFast: return "Native Backspace 0ms"
        case .charByChar: return "Char-by-Char"
        case .passthrough: return "0ms Passthrough"
        }
    }
}

/// Single step in a deletion sequence executed before posting replacement Unicode text.
public enum IMEDeletionStep: Sendable, Equatable {
    case guardCharacter  // U+00B7 MIDDLE DOT — replaces any inline autocomplete selection
    case selectLeft      // Shift+← (with .maskShift | .maskSecondaryFn | .maskNumericPad)
    case backspace       // Physical Backspace (0x33, clean empty flags)
}

/// Microsecond pacing parameters (all zero in `.auto`/`.fast` for 0ms lag & zero tap timeout risk).
public struct IMEInjectionDelays: Sendable, Equatable {
    public let stepUs: UInt32
    public let settleUs: UInt32
    public let tailUs: UInt32

    public init(stepUs: UInt32 = 0, settleUs: UInt32 = 0, tailUs: UInt32 = 0) {
        self.stepUs = stepUs
        self.settleUs = settleUs
        self.tailUs = tailUs
    }

    public static let zero = IMEInjectionDelays(stepUs: 0, settleUs: 0, tailUs: 0)
}

public struct IMEInjectionProfile: Sendable, Equatable {
    public let appKind: IMEAppKind
    public let method: IMEInjectionMethod
    public let useSelection: Bool
    public let clearInlineSelection: Bool
    public let unitsPerEvent: Int
    public let delays: IMEInjectionDelays
    public let reason: String

    /// Middle dot (U+00B7) — breaks Chrome, Edge, Safari, and Spotlight inline autocomplete
    /// where zero-width spaces (U+200B / U+202F) can be skipped by Omnibox suggestion engines.
    public static let selectionGuardScalar: UInt16 = 0x00B7

    public init(
        appKind: IMEAppKind,
        method: IMEInjectionMethod,
        useSelection: Bool,
        clearInlineSelection: Bool,
        unitsPerEvent: Int = 16,
        delays: IMEInjectionDelays = .zero,
        reason: String
    ) {
        self.appKind = appKind
        self.method = method
        self.useSelection = useSelection
        self.clearInlineSelection = clearInlineSelection
        self.unitsPerEvent = unitsPerEvent
        self.delays = delays
        self.reason = reason
    }

    /// Computes the exact deletion step sequence for a replacement edit.
    /// Never uses `Shift+←` when `replacementIsEmpty` (pure deletion must always use Backspace).
    public func deletionSteps(backspaces: Int, replacementIsEmpty: Bool) -> [IMEDeletionStep] {
        guard backspaces > 0 else { return [] }
        let useSel = useSelection && !replacementIsEmpty
        let count = clearInlineSelection ? (backspaces + 1) : backspaces
        let steps = [IMEDeletionStep](repeating: useSel ? .selectLeft : .backspace, count: count)
        return clearInlineSelection ? ([.guardCharacter] + steps) : steps
    }
}

/// App-aware delivery profile resolver modeled after Dokey + OpenKey + PHTV.
/// Pure Swift (no AppKit/AX dependency) so every rule is 100% unit-testable.
public enum IMEAppProfileResolver {
    public static let passthroughBundles: Set<String> = [
        "com.apple.screencontinuity", // iPhone Mirroring
        "cc.9remote.desktop",         // 9Remote
        "com.carriez.rustdesk",       // RustDesk
        "com.philandro.anydesk",      // AnyDesk
        "com.teamviewer.teamviewer",  // TeamViewer
        "com.microsoft.rdc.macos",
        "com.microsoft.rdc.osx",
        "com.microsoft.rdc.mac",
        "com.microsoft.rdc.osx.beta",
        "com.microsoft.windowsapp"
    ]

    public static let spotlightLikeBundles: Set<String> = [
        "com.apple.spotlight",
        "com.apple.systemuiserver",
        "com.apple.apps.launcher",
        "com.raycast.macos",
        "com.runningwithcrayons.alfred",
        "com.alfredapp.alfred"
    ]

    public static let browserBundles: Set<String> = [
        // Chromium-based
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.google.chrome.beta",
        "com.google.chrome.dev",
        "org.chromium.chromium",
        "com.brave.browser",
        "com.brave.browser.beta",
        "com.brave.browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.beta",
        "com.microsoft.edgemac.dev",
        "com.microsoft.edgemac.canary",
        "com.microsoft.edge",
        "com.microsoft.edge.dev",
        "com.vivaldi.vivaldi",
        "com.vivaldi.vivaldi.snapshot",
        "com.coccoc.browser",
        "com.coccoc.coccoc",
        "com.naver.whale",
        "ru.yandex.desktop.yandex-browser",
        "net.imput.helium",
        // Opera
        "com.opera.opera",
        "com.operasoftware.opera",
        "com.operasoftware.operagx",
        "com.operasoftware.operaair",
        "com.operasoftware.operanext",
        // Arc / Dia / AI Browsers / Safari
        "company.thebrowser.browser",
        "company.thebrowser.arc",
        "company.thebrowser.dia",
        "com.thebrowser.browser",
        "ai.perplexity.comet",
        "com.openai.atlas",
        "com.openai.atlas.beta",
        "com.duckduckgo.macos.browser",
        "com.kagi.kagimacos",
        "com.sigmaos.sigmaos.macos",
        "com.pushplaylabs.sidekick",
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        // Firefox / Gecko
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "org.waterfoxproject.waterfox",
        "net.waterfox.waterfox",
        "io.gitlab.librewolf-community.librewolf",
        "one.ablaze.floorp",
        "app.zen-browser.zen"
    ]

    public static let electronAndRichEditorBundles: Set<String> = [
        // Antigravity & VSCode-based IDEs
        "com.google.antigravity",
        "com.google.antigravity-ide",
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.visualstudio.code.oss",
        "com.vscodium",
        "com.vscodium.codium",
        "com.todesktop.cursor",
        "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf",
        "com.anthropic.claudefordesktop",
        "com.qoder.ide",
        // AI & Developer Electron/WebView apps
        "com.openai.codex",
        "com.openai.chat",
        "com.openmausbot.app",
        "ai.opencode.desktop",
        "com.getflywheel.lightning.local",
        "com.github.githubclient",
        "com.postmanlabs.mac",
        // Chat, Collaboration & Knowledge Electron apps
        "com.tinyspeck.slackmacgap",
        "com.vng.zalo",
        "com.hnc.discord",
        "com.electron.discord",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.facebook.archon",
        "net.whatsapp.whatsapp",
        "notion.id",
        "md.obsidian",
        "com.linear",
        "com.figma.desktop",
        "com.logseq.logseq",
        "com.upwork.upwork",
        "com.loom.desktop",
        "com.skype.skype",
        // JetBrains / Android Studio
        "com.google.android.studio"
    ]

    public static let terminalBundles: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "dev.warp.warp-stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "org.tabby",
        "com.raphaelamorim.rio",
        "com.cmuxterm.app",
        "com.termius-dmg.mac"
    ]

    private static let googleDocsTitleKeywords = [
        "Google Docs", "Google Tài liệu",
        "Google Sheets", "Google Trang tính",
        "Google Slides", "Google Trang trình bày"
    ]

    public static func isSpotlightLike(bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        return spotlightLikeBundles.contains(lower) || lower.hasPrefix("com.raycast.")
    }

    public static func isGoogleDocsWindowTitle(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }
        return googleDocsTitleKeywords.contains { title.contains($0) }
    }

    public static func classifyAppKind(
        bundleID: String,
        appName: String = "",
        isElectronBundle: Bool = false,
        isBrowserBundle: Bool = false
    ) -> IMEAppKind {
        let lower = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if passthroughBundles.contains(lower) {
            return .passthrough
        }
        if isSpotlightLike(bundleID: lower) {
            return .browser
        }
        let isBrowserWebApp = lower.contains(".chrome.app.")
            || lower.contains(".brave.browser.app.")
            || lower.contains(".edgemac.app.")
            || lower.hasPrefix("com.apple.safari.webapp.")
        if browserBundles.contains(lower) || isBrowserWebApp || isBrowserBundle {
            return .browser
        }
        if terminalBundles.contains(lower) || VietnameseAppDetector.isTerminalApp(bundleID: bundleID, appName: appName) {
            return .terminal
        }
        if lower.hasPrefix("com.adobe.") || lower == "texstudio" || lower == "com.foxit-software.foxit.pdf.reader" {
            return .singleChar
        }
        if electronAndRichEditorBundles.contains(lower)
            || lower.hasPrefix("com.google.antigravity")
            || lower.hasPrefix("com.todesktop.")
            || lower.hasPrefix("com.jetbrains.")
            || isElectronBundle {
            return .electron
        }
        return .normal
    }

    public static func resolve(
        bundleID: String,
        appName: String = "",
        windowTitle: String = "",
        isElectronBundle: Bool = false,
        isBrowserBundle: Bool = false,
        fixChromiumAutocomplete: Bool = true,
        speedMode: IMEInjectionSpeedMode = .auto
    ) -> IMEInjectionProfile {
        let kind = classifyAppKind(
            bundleID: bundleID,
            appName: appName,
            isElectronBundle: isElectronBundle,
            isBrowserBundle: isBrowserBundle
        )

        if kind == .passthrough {
            return IMEInjectionProfile(
                appKind: .passthrough,
                method: .passthrough,
                useSelection: false,
                clearInlineSelection: false,
                unitsPerEvent: 16,
                delays: .zero,
                reason: "passthrough:remote"
            )
        }

        // Google Docs / Sheets / Slides in a browser need 1 char per event + short pauses
        if kind == .browser && isGoogleDocsWindowTitle(windowTitle) {
            let safe = (speedMode == .safe)
            return IMEInjectionProfile(
                appKind: .browser,
                method: .charByChar,
                useSelection: speedMode != .fast,
                clearInlineSelection: false,
                unitsPerEvent: 1,
                delays: IMEInjectionDelays(stepUs: safe ? 4_000 : 2_000, settleUs: safe ? 10_000 : 6_000, tailUs: 0),
                reason: "site:google-docs"
            )
        }

        // Classic 0ms Backspace mode when user explicitly chooses `.fast`
        if speedMode == .fast {
            let clearSel = (kind == .browser) && fixChromiumAutocomplete
            return IMEInjectionProfile(
                appKind: kind,
                method: clearSel ? .browserGuardSelect : .backspaceFast,
                useSelection: false,
                clearInlineSelection: clearSel,
                unitsPerEvent: kind == .singleChar ? 1 : 16,
                delays: .zero,
                reason: "mode:backspace-0ms"
            )
        }

        let safeDelays = (speedMode == .safe)
            ? IMEInjectionDelays(stepUs: 1_500, settleUs: 4_000, tailUs: 0)
            : .zero

        switch kind {
        case .browser:
            let clearSel = fixChromiumAutocomplete
            return IMEInjectionProfile(
                appKind: .browser,
                method: clearSel ? .browserGuardSelect : .selectAndReplace,
                useSelection: true,
                clearInlineSelection: clearSel,
                unitsPerEvent: 16,
                delays: safeDelays,
                reason: clearSel ? "browser:guard-select" : "browser:select"
            )

        case .electron:
            return IMEInjectionProfile(
                appKind: .electron,
                method: .selectAndReplace,
                useSelection: true,
                clearInlineSelection: false,
                unitsPerEvent: 16,
                delays: safeDelays,
                reason: "electron:select"
            )

        case .terminal:
            return IMEInjectionProfile(
                appKind: .terminal,
                method: .backspaceFast,
                useSelection: false,
                clearInlineSelection: false,
                unitsPerEvent: 16,
                delays: (speedMode == .safe) ? IMEInjectionDelays(stepUs: 1_000, settleUs: 3_000, tailUs: 0) : .zero,
                reason: "terminal:backspace"
            )

        case .singleChar:
            return IMEInjectionProfile(
                appKind: .singleChar,
                method: .charByChar,
                useSelection: false,
                clearInlineSelection: false,
                unitsPerEvent: 1,
                delays: IMEInjectionDelays(stepUs: 1_500, settleUs: 4_000, tailUs: 0),
                reason: "editor:single-char"
            )

        case .normal:
            return IMEInjectionProfile(
                appKind: .normal,
                method: .backspaceFast,
                useSelection: false,
                clearInlineSelection: false,
                unitsPerEvent: 16,
                delays: .zero,
                reason: "native:backspace"
            )

        case .passthrough:
            return IMEInjectionProfile(
                appKind: .passthrough,
                method: .passthrough,
                useSelection: false,
                clearInlineSelection: false,
                unitsPerEvent: 16,
                delays: .zero,
                reason: "passthrough:remote"
            )
        }
    }
}

/// Pure, allocation-free modifier-only chord detector (modeled after GoNhanh Issue #399).
/// Tracks the high-water mark (`peak`) of held modifiers and fires ONLY when all modifiers
/// are cleanly released AND no non-modifier key was pressed mid-chord.
public struct ModifierChordTracker: Sendable, Equatable {
    public private(set) var peakRawMask: UInt64 = 0
    public private(set) var invalidated: Bool = false

    public init() {}

    public mutating func modifiersChanged(to maskedRaw: UInt64) -> UInt64? {
        if maskedRaw == 0 {
            let result = invalidated ? nil : (peakRawMask == 0 ? nil : peakRawMask)
            peakRawMask = 0
            invalidated = false
            return result
        }
        if maskedRaw.nonzeroBitCount > peakRawMask.nonzeroBitCount {
            peakRawMask = maskedRaw
        } else if maskedRaw.nonzeroBitCount == peakRawMask.nonzeroBitCount && maskedRaw != peakRawMask {
            invalidated = true
        }
        return nil
    }

    public mutating func keyPressed(modifiersHeldRaw maskedRaw: UInt64) {
        if maskedRaw != 0 {
            invalidated = true
        }
    }

    public mutating func reset() {
        peakRawMask = 0
        invalidated = false
    }
}
