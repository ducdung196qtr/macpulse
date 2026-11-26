import Foundation

public enum VietnameseInputMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case telex
    case vni
    case telexAndVni

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .telexAndVni: return "Telex + VNI"
        }
    }
}

public enum VietnameseHotkey: String, Codable, Sendable, CaseIterable, Identifiable {
    case ctrlShift
    case cmdShift
    case optionZ
    case ctrlSpace
    case capsLock

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ctrlShift: return "Ctrl + Shift"
        case .cmdShift: return "Cmd + Shift"
        case .optionZ: return "Option + Z"
        case .ctrlSpace: return "Ctrl + Space"
        case .capsLock: return "Caps Lock"
        }
    }
}

public struct VietnameseSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var inputMethod: VietnameseInputMethod
    public var hotkey: VietnameseHotkey
    public var modernOrthography: Bool
    public var freeMark: Bool
    public var spellCheckEnabled: Bool
    public var restoreOnEscape: Bool
    public var standaloneWAsU: Bool
    public var fixChromiumAutocomplete: Bool
    public var smartSwitchPerApp: Bool
    public var soundOnSwitch: Bool
    public var bracketShortcuts: Bool
    public var macroEnabled: Bool
    public var macroTable: [String: String]
    public var useCapsLockToSwitch: Bool
    public var quickTelex: Bool
    public var smartEnglishRestore: Bool
    public var autoCapitalize: Bool
    public var autoBypassVPSAndRemote: Bool
    public var autoBypassTerminal: Bool
    public var excludedBundleIDs: [String]

    public static let defaultMacroTable: [String: String] = [
        "vn": "Việt Nam",
        "hn": "Hà Nội",
        "sg": "Sài Gòn",
        "dc": "được",
        "ko": "không",
        "k": "không",
        "vs": "với",
        "bt": "biết",
        "ng": "người",
        "tk": "tài khoản",
        "mk": "mật khẩu",
        "sdt": "số điện thoại",
        "sđt": "số điện thoại",
        "mail": "email",
        "ms": "mình",
        "mik": "mình",
        "cx": "cũng",
        "j": "gì",
        "r": "rồi",
        "nt": "nhắn tin",
        "tl": "trả lời",
        "ok": "OK",
        "ad": "admin",
        "sp": "sản phẩm",
        "nv": "nhân viên",
        "kh": "khách hàng",
        "cty": "công ty"
    ]

    public init(
        isEnabled: Bool = true,
        inputMethod: VietnameseInputMethod = .telexAndVni,
        hotkey: VietnameseHotkey = .ctrlShift,
        modernOrthography: Bool = true,
        freeMark: Bool = true,
        spellCheckEnabled: Bool = true,
        restoreOnEscape: Bool = true,
        standaloneWAsU: Bool = true,
        fixChromiumAutocomplete: Bool = true,
        smartSwitchPerApp: Bool = true,
        soundOnSwitch: Bool = true,
        bracketShortcuts: Bool = true,
        macroEnabled: Bool = true,
        macroTable: [String: String] = VietnameseSettings.defaultMacroTable,
        useCapsLockToSwitch: Bool = false,
        quickTelex: Bool = false,
        smartEnglishRestore: Bool = true,
        autoCapitalize: Bool = false,
        autoBypassVPSAndRemote: Bool = true,
        autoBypassTerminal: Bool = true,
        excludedBundleIDs: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.inputMethod = inputMethod
        self.hotkey = hotkey
        self.modernOrthography = modernOrthography
        self.freeMark = freeMark
        self.spellCheckEnabled = spellCheckEnabled
        self.restoreOnEscape = restoreOnEscape
        self.standaloneWAsU = standaloneWAsU
        self.fixChromiumAutocomplete = fixChromiumAutocomplete
        self.smartSwitchPerApp = smartSwitchPerApp
        self.soundOnSwitch = soundOnSwitch
        self.bracketShortcuts = bracketShortcuts
        self.macroEnabled = macroEnabled
        self.macroTable = macroTable
        self.useCapsLockToSwitch = useCapsLockToSwitch
        self.quickTelex = quickTelex
        self.smartEnglishRestore = smartEnglishRestore
        self.autoCapitalize = autoCapitalize
        self.autoBypassVPSAndRemote = autoBypassVPSAndRemote
        self.autoBypassTerminal = autoBypassTerminal
        self.excludedBundleIDs = excludedBundleIDs
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case inputMethod
        case hotkey
        case modernOrthography
        case freeMark
        case spellCheckEnabled
        case restoreOnEscape
        case standaloneWAsU
        case fixChromiumAutocomplete
        case smartSwitchPerApp
        case soundOnSwitch
        case bracketShortcuts
        case macroEnabled
        case macroTable
        case useCapsLockToSwitch
        case quickTelex
        case smartEnglishRestore
        case autoCapitalize
        case autoBypassVPSAndRemote
        case autoBypassTerminal
        case excludedBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.inputMethod = try container.decodeIfPresent(VietnameseInputMethod.self, forKey: .inputMethod) ?? .telexAndVni
        self.hotkey = try container.decodeIfPresent(VietnameseHotkey.self, forKey: .hotkey) ?? .ctrlShift
        self.modernOrthography = try container.decodeIfPresent(Bool.self, forKey: .modernOrthography) ?? true
        self.freeMark = try container.decodeIfPresent(Bool.self, forKey: .freeMark) ?? true
        self.spellCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .spellCheckEnabled) ?? true
        self.restoreOnEscape = try container.decodeIfPresent(Bool.self, forKey: .restoreOnEscape) ?? true
        self.standaloneWAsU = try container.decodeIfPresent(Bool.self, forKey: .standaloneWAsU) ?? true
        self.fixChromiumAutocomplete = try container.decodeIfPresent(Bool.self, forKey: .fixChromiumAutocomplete) ?? true
        self.smartSwitchPerApp = try container.decodeIfPresent(Bool.self, forKey: .smartSwitchPerApp) ?? true
        self.soundOnSwitch = try container.decodeIfPresent(Bool.self, forKey: .soundOnSwitch) ?? true
        self.bracketShortcuts = try container.decodeIfPresent(Bool.self, forKey: .bracketShortcuts) ?? true
        self.macroEnabled = try container.decodeIfPresent(Bool.self, forKey: .macroEnabled) ?? true
        self.macroTable = try container.decodeIfPresent([String: String].self, forKey: .macroTable) ?? Self.defaultMacroTable
        self.useCapsLockToSwitch = try container.decodeIfPresent(Bool.self, forKey: .useCapsLockToSwitch) ?? false
        self.quickTelex = try container.decodeIfPresent(Bool.self, forKey: .quickTelex) ?? false
        self.smartEnglishRestore = try container.decodeIfPresent(Bool.self, forKey: .smartEnglishRestore) ?? true
        self.autoCapitalize = try container.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? false
        self.autoBypassVPSAndRemote = try container.decodeIfPresent(Bool.self, forKey: .autoBypassVPSAndRemote) ?? true
        self.autoBypassTerminal = try container.decodeIfPresent(Bool.self, forKey: .autoBypassTerminal) ?? true
        self.excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
    }
}

public enum VietnameseAppDetector {
    public static let vpsAndRemoteDesktopBundles: Set<String> = [
        // Microsoft Remote Desktop / Windows App
        "com.microsoft.rdc.macos",
        "com.microsoft.rdc.osx",
        "com.microsoft.rdc.mac",
        "com.microsoft.rdc.osx.beta",
        "com.microsoft.WindowsApp",
        // AnyDesk, RustDesk, TeamViewer
        "com.philandro.anydesk",
        "com.carriez.rustdesk",
        "com.teamviewer.TeamViewer",
        // VNC clients
        "com.realvnc.vncviewer",
        "com.tigervnc.vncviewer",
        "de.tightvnc.viewer",
        // Enterprise Remote Desktop & VPS
        "com.parallels.ras.client",
        "com.citrix.receiver.nomas",
        "com.vmware.horizon",
        "com.lemonmojo.RoyalTSX.App",
        "com.termius-desktop",
        "com.termius.mac",
        "com.google.chromeremotedesktop",
        "com.splashtop.Splashtop-Streamer",
        "com.splashtop.Splashtop-Remote",
        "com.moonlight-stream.Moonlight",
        "tv.parsec.parsec",
        "com.remotedesktopmanager",
        "com.fluidapp.FluidApp2",
        "com.apple.ScreenSharing",
        "com.jumpdesktop.mac",
        // Virtual Machines
        "com.utmapp.UTM",
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "org.virtualbox.app.VirtualBox"
    ]

    public static let terminalAndShellBundles: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "io.alacritty",
        "org.tabby",
        "com.vandyke.SecureCRT",
        "com.panic.Nova"
    ]

    public static let browserAndSearchBundles: Set<String> = [
        "com.google.chrome",
        "com.google.chrome.canary",
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        "com.apple.spotlight",
        "com.raycast.macos",
        "com.microsoft.edgemac",
        "com.microsoft.edge",
        "com.microsoft.edge.dev",
        "com.brave.browser",
        "com.operasoftware.opera",
        "com.operasoftware.operagx",
        "org.mozilla.firefox",
        "ru.yandex.desktop.yandex-browser",
        "com.vivaldi.vivaldi",
        "company.thebrowser.browser"
    ]

    public static func isBrowserOrSearchApp(bundleID: String, appName: String = "") -> Bool {
        let bLower = bundleID.lowercased()
        if browserAndSearchBundles.contains(bLower) { return true }
        let nLower = appName.lowercased()
        if bLower.contains("chrome") || bLower.contains("safari") || bLower.contains("edge")
            || bLower.contains("brave") || bLower.contains("opera") || bLower.contains("firefox")
            || bLower.contains("vivaldi") || bLower.contains("spotlight") || bLower.contains("raycast") {
            return true
        }
        if nLower.contains("chrome") || nLower.contains("safari") || nLower.contains("edge")
            || nLower.contains("brave") || nLower.contains("opera") || nLower.contains("firefox")
            || nLower == "arc" || nLower == "spotlight" || nLower == "raycast" {
            return true
        }
        return false
    }

    public static func isVPSOrRemoteApp(bundleID: String, appName: String = "") -> Bool {
        if vpsAndRemoteDesktopBundles.contains(bundleID) { return true }
        let bLower = bundleID.lowercased()
        let nLower = appName.lowercased()
        if bLower.contains("remotedesktop") || bLower.contains("rdc") || bLower.contains("anydesk")
            || bLower.contains("rustdesk") || bLower.contains("teamviewer") || bLower.contains("vnc")
            || bLower.contains("termius") || bLower.contains("putty") || bLower.contains("royaltsx")
            || bLower.contains("windowsapp") {
            return true
        }
        if nLower == "windows app" || nLower.hasPrefix("windows app") || nLower.contains("remote desktop") || nLower.contains("anydesk")
            || nLower.contains("rustdesk") || nLower.contains("teamviewer") || nLower.contains("vnc viewer")
            || nLower.contains("termius") || nLower.contains("screen sharing") || nLower.contains("jump desktop") {
            return true
        }
        return false
    }

    public static func isTerminalApp(bundleID: String, appName: String = "") -> Bool {
        if terminalAndShellBundles.contains(bundleID) { return true }
        let bLower = bundleID.lowercased()
        let nLower = appName.lowercased()
        if bLower.contains("terminal") || bLower.contains("iterm") || bLower.contains("warp") {
            return true
        }
        if nLower == "terminal" || nLower.contains("iterm") || nLower == "warp" {
            return true
        }
        return false
    }

    public static func computeIsAppExcluded(
        bundleID: String,
        appName: String,
        settings: VietnameseSettings,
        perAppEnabled: [String: Bool] = [:]
    ) -> Bool {
        guard !bundleID.isEmpty else { return false }
        if let saved = perAppEnabled[bundleID] {
            return !saved
        }
        if settings.autoBypassVPSAndRemote && isVPSOrRemoteApp(bundleID: bundleID, appName: appName) {
            return true
        }
        if settings.autoBypassTerminal && isTerminalApp(bundleID: bundleID, appName: appName) {
            return true
        }
        if settings.excludedBundleIDs.contains(bundleID) {
            return true
        }
        return false
    }
}

public enum KeyAction: Sendable, Equatable {
    case passthrough
    case replace(backspaceCount: Int, text: String)
}

public final class VietnameseEngine {
    public enum ToneMark: Equatable {
        case none
        case acute   // sắc (1, s)
        case grave   // huyền (2, f)
        case hook    // hỏi (3, r)
        case tilde   // ngã (4, x)
        case dot     // nặng (5, j)
    }

    public enum LetterShape: Equatable {
        case plain
        case circumflex // â, ê, ô
        case breve      // ă
        case horn       // ơ, ư
        case stroke     // đ
    }

    private struct CharSlot: Equatable {
        var base: Character // lowercase ASCII 'a'...'z'
        var shape: LetterShape
        var isUpper: Bool
        var shapeKey: Character? = nil
        var isStandaloneW: Bool = false
        var isBracketTransform: Bool = false
        var bracketKey: Character? = nil
        var isQuickTelex: Bool = false
        var quickTelexKey: Character? = nil
    }

    private enum ToneAction: Equatable {
        case set(ToneMark)
        case clear
    }

    public var settings: VietnameseSettings

    private var slots: [CharSlot] = []
    private var tone: ToneMark = .none
    private var toneKey: Character? = nil
    private var rawKeys: [Character] = []
    private var isRestoredToRaw: Bool = false
    private var hasPendingUndoMismatch: Bool = false
    private var strokeUndone: Bool = false
    private var circumflexUndone: Set<Character> = []
    private var hornUndone: Bool = false
    private var undoneTone: ToneMark? = nil
    private var bracketUndone: Bool = false
    private var shouldAutoCapitalize: Bool = false

    public init(settings: VietnameseSettings = VietnameseSettings()) {
        self.settings = settings
    }

    public var currentWord: String {
        isRestoredToRaw ? String(rawKeys) : render(slots: slots, tone: tone)
    }

    public var hasBufferedWord: Bool {
        !rawKeys.isEmpty
    }

    public func reset() {
        slots.removeAll(keepingCapacity: true)
        tone = .none
        toneKey = nil
        rawKeys.removeAll(keepingCapacity: true)
        isRestoredToRaw = false
        hasPendingUndoMismatch = false
        strokeUndone = false
        circumflexUndone.removeAll(keepingCapacity: true)
        hornUndone = false
        undoneTone = nil
        bracketUndone = false
    }

    public func processEscape() -> KeyAction {
        guard settings.restoreOnEscape, !rawKeys.isEmpty, !isRestoredToRaw else {
            reset()
            return .passthrough
        }
        let rendered = render(slots: slots, tone: tone)
        let raw = String(rawKeys)
        guard rendered != raw else {
            reset()
            return .passthrough
        }
        let action = diffAction(from: rendered, to: raw)
        isRestoredToRaw = true
        slots = rawKeys.map { CharSlot(base: Character($0.lowercased()), shape: .plain, isUpper: $0.isUppercase) }
        tone = .none
        return action
    }

    public func processBackspace() -> KeyAction {
        guard !rawKeys.isEmpty else {
            return .passthrough
        }
        if isRestoredToRaw {
            rawKeys.removeLast()
            if !slots.isEmpty { slots.removeLast() }
            if rawKeys.isEmpty { reset() }
            return .passthrough
        }

        let prevRendered = render(slots: slots, tone: tone)
        guard !slots.isEmpty else {
            reset()
            return .passthrough
        }

        let deletedIndex = slots.count - 1
        let prevStruct = analyzeSyllable(slots)
        let prevToneIdx = toneTargetIndex(in: slots, structure: prevStruct)

        slots.removeLast()
        if slots.isEmpty {
            reset()
            return .passthrough
        }

        let structInfo = analyzeSyllable(slots)
        if structInfo.vowelRange.isEmpty || prevToneIdx == deletedIndex {
            tone = .none
            toneKey = nil
        }

        var rebuilt: [Character] = []
        for s in slots {
            rebuilt.append(renderChar(base: s.base, shape: .plain, tone: .none, upper: s.isUpper))
            if let sk = s.shapeKey {
                rebuilt.append(sk)
            }
        }
        if let tk = toneKey {
            rebuilt.append(tk)
        }
        rawKeys = rebuilt

        let newRendered = render(slots: slots, tone: tone)
        if !prevRendered.isEmpty && String(prevRendered.dropLast()) == newRendered {
            return .passthrough
        }
        return diffAction(from: prevRendered, to: newRendered)
    }

    public func processDelimiter(_ char: Character, allowAutoRestore: Bool = true) -> KeyAction {
        defer { reset() }
        let prevRendered = render(slots: slots, tone: tone)
        let raw = String(rawKeys)

        // Update smart auto capitalization state
        if char == "." || char == "!" || char == "?" || char == "\n" {
            shouldAutoCapitalize = true
        } else if char != " " && char != "\t" {
            shouldAutoCapitalize = false
        }

        // Smart English Words Auto-Restore
        if settings.smartEnglishRestore && !slots.isEmpty && !raw.isEmpty {
            let lowerRaw = raw.lowercased()
            let endsInToneOrHorn = lowerRaw.hasSuffix("s") || lowerRaw.hasSuffix("f") || lowerRaw.hasSuffix("r") || lowerRaw.hasSuffix("x") || lowerRaw.hasSuffix("j") || lowerRaw.hasSuffix("w")
            if !(lowerRaw.count <= 3 && endsInToneOrHorn) {
                if Self.commonEnglishWords.contains(lowerRaw) {
                    return .replace(backspaceCount: prevRendered.count, text: raw + String(char))
                }
            }
            // Check if raw contains a duplicate tone undo consonant that maps to a common English word
            // e.g. 'tesst' -> 'test', 'posst' -> 'post', 'lisst' -> 'list', 'besst' -> 'best', 'pausse' -> 'pause', 'resset' -> 'reset'
            if let dupIdx = findDoubleUndoConsonantIndex(in: Array(raw)) {
                var deduped = Array(raw)
                deduped.remove(at: dupIdx)
                let dedupedStr = String(deduped)
                let lowerDeduped = dedupedStr.lowercased()
                if Self.commonEnglishWords.contains(lowerDeduped) {
                    return .replace(backspaceCount: prevRendered.count, text: dedupedStr + String(char))
                }
            }
        }

        // Macros only trigger on whitespace delimiters (Space, Tab, Enter) to avoid corrupting URLs, domains (.vn) and code
        if settings.macroEnabled && (char == " " || char == "\t" || char == "\n") && !slots.isEmpty && !raw.isEmpty {
            let lowerRaw = raw.lowercased()
            if let replacement = settings.macroTable[lowerRaw] {
                let finalReplacement: String
                if raw == raw.uppercased() && raw.count > 1 {
                    finalReplacement = replacement.uppercased()
                } else if raw.first?.isUppercase == true {
                    finalReplacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
                } else {
                    finalReplacement = replacement
                }
                return .replace(backspaceCount: prevRendered.count, text: finalReplacement + String(char))
            }
        }

        guard allowAutoRestore, settings.spellCheckEnabled, !isRestoredToRaw, !slots.isEmpty else {
            return .passthrough
        }
        guard prevRendered != raw else {
            return .passthrough
        }
        if !isCompleteSyllableValidOnDelimiter(slots: slots, tone: tone) {
            return .replace(backspaceCount: prevRendered.count, text: raw + String(char))
        }
        return .passthrough
    }

    public func processCharacter(_ char: Character) -> KeyAction {
        guard settings.isEnabled else {
            reset()
            return .passthrough
        }

        var effectiveChar = char
        if settings.autoCapitalize && shouldAutoCapitalize && slots.isEmpty && char.isLetter && char.isLowercase {
            effectiveChar = Character(char.uppercased())
            shouldAutoCapitalize = false
        }

        let isBracketChar = (effectiveChar == "[" || effectiveChar == "]" || effectiveChar == "{" || effectiveChar == "}")
        let telexEnabled = settings.inputMethod == .telex || settings.inputMethod == .telexAndVni

        if isBracketChar && settings.bracketShortcuts && telexEnabled && !isRestoredToRaw {
            let isClosing = (effectiveChar == "]" || effectiveChar == "}")
            let isUpper = (effectiveChar == "{" || effectiveChar == "}")
            let prevRendered = render(slots: slots, tone: tone)

            if isClosing {
                // ']' -> ư, '}' -> Ư
                // Check double-tap undo
                if !slots.isEmpty && slots.last?.bracketKey == "]" {
                    slots.removeLast()
                    slots.append(CharSlot(base: "]", shape: .plain, isUpper: isUpper))
                    rawKeys.append(effectiveChar)
                    isRestoredToRaw = true
                    bracketUndone = true
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }

                slots.append(CharSlot(base: "u", shape: .horn, isUpper: isUpper, isBracketTransform: true, bracketKey: "]"))
                rawKeys.append(effectiveChar)
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            } else {
                // '[' -> ơ, '{' -> Ơ
                // Check double-tap undo
                if !slots.isEmpty && slots.last?.bracketKey == "[" {
                    slots.removeLast()
                    slots.append(CharSlot(base: "[", shape: .plain, isUpper: isUpper))
                    rawKeys.append(effectiveChar)
                    isRestoredToRaw = true
                    bracketUndone = true
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }

                // If preceding slot was plain 'u', convert 'u' -> 'ư' and add 'ơ' -> 'ươ'
                if !slots.isEmpty && slots.last?.base == "u" && slots.last?.shape == .plain {
                    slots[slots.count - 1].shape = .horn
                    slots.append(CharSlot(base: "o", shape: .horn, isUpper: isUpper, isBracketTransform: true, bracketKey: "["))
                    rawKeys.append(effectiveChar)
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }

                slots.append(CharSlot(base: "o", shape: .horn, isUpper: isUpper, isBracketTransform: true, bracketKey: "["))
                rawKeys.append(effectiveChar)
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            }
        }

        let lowerStr = effectiveChar.lowercased()
        guard lowerStr.count == 1, let lower = lowerStr.first else {
            return processDelimiter(effectiveChar, allowAutoRestore: false)
        }

        let isAsciiLetter = lower >= "a" && lower <= "z"
        let isDigit = lower >= "0" && lower <= "9"

        if !isAsciiLetter && !isDigit {
            return processDelimiter(effectiveChar, allowAutoRestore: isPrintableWordDelimiter(effectiveChar))
        }

        if isDigit {
            let allowsVNI = (settings.inputMethod == .vni || settings.inputMethod == .telexAndVni)
            if !allowsVNI || rawKeys.isEmpty || isRestoredToRaw {
                if rawKeys.isEmpty {
                    reset()
                    return .passthrough
                }
                if !allowsVNI {
                    reset()
                    return .passthrough
                }
                rawKeys.append(effectiveChar)
                return .passthrough
            }
        }

        if isRestoredToRaw {
            let prevDisplayed = render(slots: slots, tone: tone)
            rawKeys.append(effectiveChar)
            slots.append(CharSlot(base: lower, shape: .plain, isUpper: effectiveChar.isUppercase))
            if hasPendingUndoMismatch {
                hasPendingUndoMismatch = false
                let rawLower = String(rawKeys).lowercased()

                var shouldDeduplicate = true

                // Stems with intentional double consonants in English must never be deduplicated
                let doubleStems = [
                    "diff", "coff", "pass", "mess", "poss", "sess", "err", "arr", "traff", "off",
                    "miss", "less", "boss", "kiss", "cross", "press", "stress", "status",
                    "staff", "stuff", "class", "glass", "grass"
                ]
                for stem in doubleStems {
                    if rawLower.hasPrefix(stem) {
                        // In English phonotactics, double consonants are never followed by 't', 'd', 'k' (e.g. 'post', 'past', 'test')
                        if rawLower.hasPrefix(stem + "t") || rawLower.hasPrefix(stem + "d") || rawLower.hasPrefix(stem + "k") {
                            continue
                        }
                        shouldDeduplicate = false
                        break
                    }
                }

                if shouldDeduplicate {
                    if let dupIdx = findDoubleUndoConsonantIndex(in: rawKeys) {
                        rawKeys.remove(at: dupIdx)
                    }
                }

                slots = rawKeys.map { CharSlot(base: Character($0.lowercased()), shape: .plain, isUpper: $0.isUppercase) }
                let raw = String(rawKeys)
                return diffAction(from: prevDisplayed, to: raw)
            }
            return .passthrough
        }

        let prevRendered = render(slots: slots, tone: tone)

        if slots.isEmpty && lower == "w" && settings.standaloneWAsU && (settings.inputMethod == .telex || settings.inputMethod == .telexAndVni) {
            rawKeys.append(effectiveChar)
            slots.append(CharSlot(base: "u", shape: .horn, isUpper: effectiveChar.isUppercase, isStandaloneW: true))
            let nextRendered = render(slots: slots, tone: tone)
            return .replace(backspaceCount: 0, text: nextRendered)
        }

        if isDigit && slots.isEmpty {
            reset()
            return .passthrough
        }

        if !slots.isEmpty {
            let telexEnabled = settings.inputMethod == .telex || settings.inputMethod == .telexAndVni
            let vniEnabled = settings.inputMethod == .vni || settings.inputMethod == .telexAndVni

            // Quick Telex onset expansion: cc->ch, kk->kh, gg->gi, nn->ng, qq->qu, pp->ph, tt->th
            if settings.quickTelex && telexEnabled && tone == .none {
                if slots.count == 1 && slots[0].shape == .plain {
                    let first = slots[0].base
                    let quickMap: [Character: Character] = [
                        "c": "h", "k": "h", "g": "i", "n": "g", "q": "u", "p": "h", "t": "h"
                    ]
                    if let second = quickMap[first], lower == first {
                        slots = [
                            CharSlot(base: first, shape: .plain, isUpper: slots[0].isUpper),
                            CharSlot(base: second, shape: .plain, isUpper: effectiveChar.isUppercase, isQuickTelex: true, quickTelexKey: first)
                        ]
                        rawKeys.append(effectiveChar)
                        let nextRendered = render(slots: slots, tone: tone)
                        return diffAction(from: prevRendered, to: nextRendered)
                    } else if first == "q" {
                        // Quick Telex q + vowel -> qu + vowel (e.g. qa->qua, qas->quá, qan->quan, qen->quen, qy->quy)
                        let quickVowels: Set<Character> = ["a", "e", "i", "o", "y"]
                        if quickVowels.contains(lower) {
                            slots = [
                                CharSlot(base: "q", shape: .plain, isUpper: slots[0].isUpper),
                                CharSlot(base: "u", shape: .plain, isUpper: false, isQuickTelex: true, quickTelexKey: "q"),
                                CharSlot(base: lower, shape: .plain, isUpper: effectiveChar.isUppercase)
                            ]
                            rawKeys.append(effectiveChar)
                            let nextRendered = render(slots: slots, tone: tone)
                            return diffAction(from: prevRendered, to: nextRendered)
                        }
                    }
                } else if slots.count == 2 && slots[1].isQuickTelex && slots[1].quickTelexKey == lower {
                    // Undo quick telex on 3rd identical tap (e.g. ccc -> cc, kkk -> kk)
                    let origBase = slots[0].base
                    slots = [
                        CharSlot(base: origBase, shape: .plain, isUpper: slots[0].isUpper),
                        CharSlot(base: origBase, shape: .plain, isUpper: slots[1].isUpper),
                        CharSlot(base: origBase, shape: .plain, isUpper: effectiveChar.isUppercase)
                    ]
                    rawKeys.append(effectiveChar)
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }
            }

            let prefixCanTransform = !settings.spellCheckEnabled || canAcceptVietnameseTransforms(slots: slots)

            if prefixCanTransform {
                if (telexEnabled && lower == "d") || (vniEnabled && lower == "9") {
                    if let action = tryApplyStroke(char: effectiveChar, prevRendered: prevRendered, isVNI: lower == "9") {
                        return action
                    }
                }

                if (telexEnabled && (lower == "a" || lower == "e" || lower == "o")) || (vniEnabled && lower == "6") {
                    if let action = tryApplyCircumflex(char: effectiveChar, lower: lower, prevRendered: prevRendered, isVNI: lower == "6") {
                        return action
                    }
                }

                if (telexEnabled && lower == "w") || (vniEnabled && (lower == "7" || lower == "8")) {
                    if let action = tryApplyHornOrBreve(char: effectiveChar, lower: lower, prevRendered: prevRendered) {
                        return action
                    }
                }

                if let toneCmd = parseToneAction(lower: lower, telexEnabled: telexEnabled, vniEnabled: vniEnabled) {
                    if let action = tryApplyTone(toneCmd, char: effectiveChar, prevRendered: prevRendered) {
                        return action
                    }
                }
            }
        }

        // In-flight English word recognition & tone unroll:
        // In Vietnamese phonotactics, a vowel can NEVER follow a tone mark unless it forms a valid diphthong/triphthong.
        // Also, Vietnamese codas can NEVER be invalid consonants (e.g. 'l', 'v', 'k') or clusters (e.g. 'st', 'rt', 'rd', 'rk', 'ft').
        // If a tone was applied and typing the next character forms an English word/stem or invalid Vietnamese syllable,
        // unroll using exact rawKeys so characters are never scrambled (e.g. 'té'+'t' -> 'test', 'réu'+'l' -> 'resul', 'ú'+'e' -> 'use').
        if settings.spellCheckEnabled && tone != .none, let tk = toneKey {
            let isVowel = (lower == "a" || lower == "e" || lower == "i" || lower == "o" || lower == "u" || lower == "y")
            let sInfo = analyzeSyllable(slots)
            var shouldUnroll = false

            if isVowel && sInfo.codaRange.isEmpty {
                var candidate = slots
                candidate.append(CharSlot(base: lower, shape: .plain, isUpper: effectiveChar.isUppercase))
                if !isSyllablePrefixValid(slots: candidate, tone: tone) {
                    shouldUnroll = true
                } else if sInfo.onsetRange.isEmpty && slots.count == 1 && slots[0].base == "u" && lower == "e" {
                    // Protect English 'use' / 'user' / 'used' (Vietnamese 'uế' is typed 'uees' or 'uese', never 'use')
                    shouldUnroll = true
                }
            } else if !isVowel && sInfo.codaRange.isEmpty {
                var candidate = slots
                candidate.append(CharSlot(base: lower, shape: .plain, isUpper: effectiveChar.isUppercase))
                if !isSyllablePrefixValid(slots: candidate, tone: tone) {
                    shouldUnroll = true
                } else {
                    var unrolled = slots
                    if tk.isLetter {
                        unrolled.append(CharSlot(base: Character(tk.lowercased()), shape: .plain, isUpper: tk.isUppercase))
                    }
                    unrolled.append(CharSlot(base: lower, shape: .plain, isUpper: effectiveChar.isUppercase))
                    let unrolledStr = unrolled.map { String($0.base) }.joined().lowercased()
                    if Self.commonEnglishWords.contains(unrolledStr) || Self.commonEnglishStems.contains(unrolledStr) {
                        shouldUnroll = true
                    }
                }
            }

            if shouldUnroll {
                tone = .none
                toneKey = nil
                rawKeys.append(effectiveChar)
                slots = rawKeys.map { CharSlot(base: Character($0.lowercased()), shape: .plain, isUpper: $0.isUppercase) }
                hasPendingUndoMismatch = false
                isRestoredToRaw = true
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            }
        }

        if isDigit {
            rawKeys.append(effectiveChar)
            isRestoredToRaw = true
            let raw = String(rawKeys)
            if prevRendered != String(rawKeys.dropLast()) {
                return diffAction(from: prevRendered, to: raw)
            }
            return .passthrough
        }

        rawKeys.append(effectiveChar)
        slots.append(CharSlot(base: lower, shape: .plain, isUpper: effectiveChar.isUppercase))

        // In-flight restore for unambiguous English words that temporarily form a circumflex syllable (e.g. 'r-e-s-e-t' -> 'reset')
        if settings.smartEnglishRestore && !isRestoredToRaw && tone != .none {
            let rawLower = String(rawKeys).lowercased()
            if Self.inFlightEnglishRestoreWords.contains(rawLower) {
                tone = .none
                toneKey = nil
                isRestoredToRaw = true
                slots = rawKeys.map { CharSlot(base: Character($0.lowercased()), shape: .plain, isUpper: $0.isUppercase) }
                return diffAction(from: prevRendered, to: String(rawKeys))
            }
        }

        upgradeUOHornWithCodaIfNeeded()

        let newRendered = render(slots: slots, tone: tone)
        if newRendered == prevRendered + String(char) {
            return .passthrough
        }
        return diffAction(from: prevRendered, to: newRendered)
    }

    public func simulate(_ input: String) -> String {
        reset()
        var buffer = ""
        for ch in input {
            let action: KeyAction
            if ch == "\u{08}" {
                action = processBackspace()
                switch action {
                case .passthrough:
                    if !buffer.isEmpty { buffer.removeLast() }
                case .replace(let bs, let text):
                    if bs > 0 { buffer = String(buffer.dropLast(min(bs, buffer.count))) }
                    buffer.append(text)
                }
                continue
            } else if ch == "\u{1B}" {
                action = processEscape()
                switch action {
                case .passthrough:
                    break
                case .replace(let bs, let text):
                    if bs > 0 { buffer = String(buffer.dropLast(min(bs, buffer.count))) }
                    buffer.append(text)
                }
                continue
            } else {
                action = processCharacter(ch)
            }

            switch action {
            case .passthrough:
                buffer.append(ch)
            case .replace(let bs, let text):
                if bs > 0 {
                    buffer = String(buffer.dropLast(min(bs, buffer.count)))
                }
                buffer.append(text)
            }
        }
        return buffer
    }

    private func tryApplyStroke(char: Character, prevRendered: String, isVNI: Bool) -> KeyAction? {
        guard !slots.isEmpty, slots[0].base == "d" else { return nil }
        if !isVNI && !settings.freeMark && slots.count > 1 {
            return nil
        }

        if slots[0].shape == .stroke {
            guard !strokeUndone else { return nil }
            slots[0].shape = .plain
            slots[0].shapeKey = nil
            strokeUndone = true
            if !isVNI {
                slots.append(CharSlot(base: "d", shape: .plain, isUpper: char.isUppercase))
            }
            rawKeys = slots.map { renderChar(base: $0.base, shape: .plain, tone: .none, upper: $0.isUpper) }
            isRestoredToRaw = true
            let nextRendered = render(slots: slots, tone: tone)
            return diffAction(from: prevRendered, to: nextRendered)
        }

        guard !strokeUndone else { return nil }
        if settings.spellCheckEnabled && !isSyllablePrefixValid(slots: slots, tone: tone) {
            return nil
        }

        var candidate = slots
        candidate[0].shape = .stroke
        if settings.spellCheckEnabled && !isSyllablePrefixValid(slots: candidate, tone: tone) {
            return nil
        }

        slots = candidate
        rawKeys.append(char)
        let nextRendered = render(slots: slots, tone: tone)
        return diffAction(from: prevRendered, to: nextRendered)
    }

    private func tryApplyCircumflex(char: Character, lower: Character, prevRendered: String, isVNI: Bool) -> KeyAction? {
        let targets: [Character] = isVNI ? ["a", "e", "o"] : [lower]
        let sInfo = analyzeSyllable(slots)

        var targetIndex: Int?
        for idx in sInfo.vowelRange.reversed() {
            if targets.contains(slots[idx].base) {
                targetIndex = idx
                break
            }
        }
        guard let idx = targetIndex else { return nil }
        if !settings.freeMark && idx != slots.count - 1 { return nil }

        let targetBase = slots[idx].base

        if slots[idx].shape == .circumflex {
            guard !circumflexUndone.contains(targetBase) else { return nil }
            slots[idx].shape = .plain
            slots[idx].shapeKey = nil
            circumflexUndone.insert(targetBase)
            if !isVNI {
                slots.append(CharSlot(base: lower, shape: .plain, isUpper: char.isUppercase))
            }
            rawKeys = slots.map { renderChar(base: $0.base, shape: .plain, tone: .none, upper: $0.isUpper) }
            let nextRendered = render(slots: slots, tone: tone)
            return diffAction(from: prevRendered, to: nextRendered)
        }

        guard slots[idx].shape == .plain, !circumflexUndone.contains(targetBase) else {
            return nil
        }

        var candidate = slots
        candidate[idx].shape = .circumflex
        candidate[idx].shapeKey = char
        if settings.spellCheckEnabled && !isSyllablePrefixValid(slots: candidate, tone: tone) {
            return nil
        }

        slots = candidate
        rawKeys.append(char)
        let nextRendered = render(slots: slots, tone: tone)
        return diffAction(from: prevRendered, to: nextRendered)
    }

    private func tryApplyHornOrBreve(char: Character, lower: Character, prevRendered: String) -> KeyAction? {
        let isVNI7 = (lower == "7")
        let isVNI8 = (lower == "8")
        let sInfo = analyzeSyllable(slots)

        // When vowel is empty and user types 'w' in Telex after a valid onset (e.g. 'ch' + 'w' -> 'chư', 't' + 'w' -> 'tư')
        if sInfo.vowelRange.isEmpty {
            let telexEnabled = settings.inputMethod == .telex || settings.inputMethod == .telexAndVni
            guard telexEnabled && lower == "w" && !slots.isEmpty && sInfo.codaRange.isEmpty else {
                return nil
            }
            let onsetStr = renderSlice(slots[sInfo.onsetRange])
            guard Self.validOnsets.contains(onsetStr) && onsetStr != "q" else {
                return nil
            }
            slots.append(CharSlot(base: "u", shape: .horn, isUpper: char.isUppercase, isStandaloneW: true))
            rawKeys.append(char)
            let nextRendered = render(slots: slots, tone: tone)
            return .replace(backspaceCount: prevRendered.count, text: nextRendered)
        }

        if !settings.freeMark {
            let lastVowel = sInfo.vowelRange.upperBound - 1
            if lastVowel < slots.count - 1 && sInfo.codaRange.isEmpty {
                return nil
            }
        }

        // 1. Compound 'uo' / 'ưo' -> 'ươ' / 'uơ' (for Telex 'w' and VNI '7')
        if !isVNI8 {
            if let uIdx = findUOPairIndex(in: sInfo) {
                let oIdx = uIdx + 1
                let uShape = slots[uIdx].shape
                let oShape = slots[oIdx].shape

                if oShape == .horn {
                    guard !hornUndone else { return nil }
                    slots[uIdx].shape = .plain
                    slots[uIdx].shapeKey = nil
                    slots[oIdx].shape = .plain
                    slots[oIdx].shapeKey = nil
                    hornUndone = true
                    if lower == "w" {
                        slots.append(CharSlot(base: "w", shape: .plain, isUpper: char.isUppercase))
                    }
                    rawKeys = slots.map { renderChar(base: $0.base, shape: .plain, tone: .none, upper: $0.isUpper) }
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }

                guard !hornUndone else { return nil }
                var candidate = slots
                let hasTrailingChars = (oIdx + 1) < slots.count
                if uShape == .horn || hasTrailingChars {
                    // 'ưo' + w -> 'ươ', or 'uoc' + w -> 'ươc'
                    candidate[uIdx].shape = .horn
                    candidate[oIdx].shape = .horn
                    candidate[oIdx].shapeKey = char
                } else {
                    candidate[oIdx].shape = .horn
                    candidate[oIdx].shapeKey = char
                }
                if settings.spellCheckEnabled && !isSyllablePrefixValid(slots: candidate, tone: tone) {
                    return nil
                }
                slots = candidate
                rawKeys.append(char)
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            }
        }

        // 2. Single target vowel selection
        let vStart = sInfo.vowelRange.lowerBound
        let vCount = sInfo.vowelRange.count

        for idx in sInfo.vowelRange.reversed() {
            let s = slots[idx]
            if (isVNI8 && s.base == "a" && s.shape == .breve)
                || (isVNI7 && (s.base == "o" || s.base == "u") && s.shape == .horn)
                || (lower == "w" && ((s.base == "a" && s.shape == .breve) || ((s.base == "o" || s.base == "u") && s.shape == .horn))) {
                guard !hornUndone else { return nil }
                if slots[idx].isStandaloneW && lower == "w" {
                    slots[idx] = CharSlot(base: "w", shape: .plain, isUpper: slots[idx].isUpper)
                } else {
                    slots[idx].shape = .plain
                    slots[idx].shapeKey = nil
                    if lower == "w" {
                        slots.append(CharSlot(base: "w", shape: .plain, isUpper: char.isUppercase))
                    }
                }
                hornUndone = true
                rawKeys = slots.map { renderChar(base: $0.base, shape: .plain, tone: .none, upper: $0.isUpper) }
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            }
        }

        guard !hornUndone else { return nil }

        var chosenIndex: Int?
        var chosenShape: LetterShape = .plain

        if isVNI8 {
            for idx in sInfo.vowelRange.reversed() where slots[idx].base == "a" && slots[idx].shape == .plain {
                chosenIndex = idx
                chosenShape = .breve
                break
            }
        } else {
            if vCount == 2 {
                let first = slots[vStart].base
                let second = slots[vStart + 1].base
                if first == "o" && second == "a" && lower == "w" {
                    chosenIndex = vStart + 1
                    chosenShape = .breve
                } else if first == "u" && (second == "a" || second == "u" || second == "i") {
                    chosenIndex = vStart
                    chosenShape = .horn
                }
            }
            if chosenIndex == nil {
                for idx in sInfo.vowelRange.reversed() where slots[idx].shape == .plain {
                    let b = slots[idx].base
                    if b == "o" || b == "u" {
                        chosenIndex = idx
                        chosenShape = .horn
                        break
                    } else if b == "a" && lower == "w" {
                        chosenIndex = idx
                        chosenShape = .breve
                        break
                    }
                }
            }
        }

        guard let idx = chosenIndex else { return nil }
        var candidate = slots
        candidate[idx].shape = chosenShape
        if settings.spellCheckEnabled && !isSyllablePrefixValid(slots: candidate, tone: tone) {
            return nil
        }

        slots = candidate
        rawKeys.append(char)
        let nextRendered = render(slots: slots, tone: tone)
        return diffAction(from: prevRendered, to: nextRendered)
    }

    private func tryApplyTone(_ cmd: ToneAction, char: Character, prevRendered: String) -> KeyAction? {
        let sInfo = analyzeSyllable(slots)
        let isQUOnset = (slots.count == 2 && slots[0].base == "q" && slots[1].base == "u")
        guard !sInfo.vowelRange.isEmpty || (settings.freeMark && isQUOnset) else { return nil }

        if !settings.freeMark && !sInfo.codaRange.isEmpty {
            return nil
        }

        switch cmd {
        case .clear:
            if tone != .none {
                tone = .none
                rawKeys.append(char)
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            }
            return nil

        case .set(let targetTone):
            if tone == targetTone {
                guard undoneTone != targetTone else { return nil }
                tone = .none
                toneKey = nil
                undoneTone = targetTone
                let lower = Character(char.lowercased())
                if lower >= "a" && lower <= "z" {
                    slots.append(CharSlot(base: lower, shape: .plain, isUpper: char.isUppercase))
                } else {
                    isRestoredToRaw = true
                }
                rawKeys.append(char)
                hasPendingUndoMismatch = true
                if settings.spellCheckEnabled && !isSyllablePrefixValid(slots: slots, tone: tone) {
                    isRestoredToRaw = true
                }
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            }

            if undoneTone == targetTone && tone == .none {
                return nil
            }

            if settings.spellCheckEnabled && !isToneCompatibleWithCoda(slots: slots, tone: targetTone) {
                return nil
            }

            tone = targetTone
            toneKey = char
            undoneTone = nil
            rawKeys.append(char)
            let nextRendered = render(slots: slots, tone: tone)
            return diffAction(from: prevRendered, to: nextRendered)
        }
    }

    private func parseToneAction(lower: Character, telexEnabled: Bool, vniEnabled: Bool) -> ToneAction? {
        if telexEnabled {
            switch lower {
            case "s": return .set(.acute)
            case "f": return .set(.grave)
            case "r": return .set(.hook)
            case "x": return .set(.tilde)
            case "j": return .set(.dot)
            case "z": return .clear
            default: break
            }
        }
        if vniEnabled {
            switch lower {
            case "1": return .set(.acute)
            case "2": return .set(.grave)
            case "3": return .set(.hook)
            case "4": return .set(.tilde)
            case "5": return .set(.dot)
            case "0": return .clear
            default: break
            }
        }
        return nil
    }

    private func findUOPairIndex(in sInfo: SyllableStructure) -> Int? {
        guard sInfo.vowelRange.count >= 2 else { return nil }
        for i in sInfo.vowelRange.lowerBound..<(sInfo.vowelRange.upperBound - 1) {
            if slots[i].base == "u" && slots[i + 1].base == "o" {
                return i
            }
        }
        return nil
    }

    private func upgradeUOHornWithCodaIfNeeded() {
        let sInfo = analyzeSyllable(slots)
        guard let uIdx = findUOPairIndex(in: sInfo) else { return }
        let oIdx = uIdx + 1
        if (slots[oIdx].shape == .horn || slots[uIdx].shape == .horn) && (oIdx + 1) < slots.count {
            slots[uIdx].shape = .horn
            slots[oIdx].shape = .horn
        }
    }

    private struct SyllableStructure {
        var onsetRange: Range<Int>
        var vowelRange: Range<Int>
        var codaRange: Range<Int>
    }

    private static let vowelBases: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    private func analyzeSyllable(_ list: [CharSlot]) -> SyllableStructure {
        let count = list.count
        guard count > 0 else {
            return SyllableStructure(onsetRange: 0..<0, vowelRange: 0..<0, codaRange: 0..<0)
        }

        var idx = 0
        if count >= 2 && list[0].base == "q" && list[1].base == "u" && (count == 2 || Self.vowelBases.contains(list[2].base)) {
            idx = 2
        } else if count >= 3 && list[0].base == "g" && list[1].base == "i" && Self.vowelBases.contains(list[2].base) {
            idx = 2
        } else {
            while idx < count && !Self.vowelBases.contains(list[idx].base) {
                idx += 1
            }
        }
        let onsetEnd = idx

        while idx < count && Self.vowelBases.contains(list[idx].base) {
            idx += 1
        }
        let vowelEnd = idx

        return SyllableStructure(
            onsetRange: 0..<onsetEnd,
            vowelRange: onsetEnd..<vowelEnd,
            codaRange: vowelEnd..<count
        )
    }

    private func toneTargetIndex(in list: [CharSlot], structure s: SyllableStructure) -> Int? {
        let vStart = s.vowelRange.lowerBound
        let vCount = s.vowelRange.count
        guard vCount > 0 else {
            if list.count == 2 && list[0].base == "q" && list[1].base == "u" {
                return 1
            }
            return nil
        }
        if vCount == 1 { return vStart }

        for i in vStart..<(s.vowelRange.upperBound - 1) {
            if list[i].base == "u" && list[i].shape == .horn && list[i + 1].base == "o" && list[i + 1].shape == .horn {
                return i + 1
            }
        }

        let shapedIndices = s.vowelRange.filter { list[$0].shape != .plain }
        if shapedIndices.count == 1, let onlyShaped = shapedIndices.first {
            return onlyShaped
        }
        if let lastShaped = shapedIndices.last {
            return lastShaped
        }

        if vCount == 2 {
            if !s.codaRange.isEmpty {
                return vStart + 1
            }
            let pair = String([list[vStart].base, list[vStart + 1].base])
            if pair == "oa" || pair == "oe" || pair == "uy" {
                return settings.modernOrthography ? (vStart + 1) : vStart
            }
            return vStart
        }

        return vStart + 1
    }

    private static let validOnsets: Set<String> = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m",
        "n", "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"
    ]

    /// 'q' is valid before 'u' arrives while composing 'qu...'
    private static let composingOnlyOnsets: Set<String> = ["q"]

    private static let validCodas: Set<String> = [
        "", "c", "ch", "m", "n", "ng", "nh", "p", "t"
    ]

    private static let stopCodas: Set<String> = ["c", "ch", "p", "t"]



    /// Composing prefixes allowed mid-word before user presses the circumflex/horn key (e.g. 't-i-e-n-g-s' -> 't-i-ê-n-g-s')
    private static let composingOnlyRhymes: Set<String> = [
        "ic", "uyc", "yc", "oon",
        "enh", "eu",
        "ie", "iec", "iem", "ien", "ieng", "iep", "iet", "ieu",
        "uan", "uang", "uat", "uay",
        "ue", "uec", "uech", "uen", "uenh",
        "uo", "uoc", "uom", "uon", "uong", "uop", "uot", "uoi", "uou",
        "uye", "uyen", "uyet",
        "ye", "yem", "yen", "yeng", "yet", "yeu",
        "uu",
        "ưo", "ưoc", "ưoi", "ưom", "ưon", "ưong", "ưop", "ưot", "ưou",
        "uơc", "uơi", "uơm", "uơn", "uơng", "uơp", "uơt", "uơu"
    ]

    private static let inFlightEnglishRestoreWords: Set<String> = [
        "reset", "resets"
    ]

    private static let validRhymes: Set<String> = [
        "a", "ac", "ach", "ai", "am", "an", "ang", "anh", "ao", "ap", "at", "au", "ay",
        "ă", "ăc", "ăm", "ăn", "ăng", "ăp", "ăt",
        "â", "âc", "âm", "ân", "âng", "âp", "ât", "âu", "ây",
        "e", "ec", "ech", "em", "en", "eng", "eo", "ep", "et",
        "ê", "êc", "êch", "êm", "ên", "êng", "ênh", "êp", "êt", "êu",
        "i", "ia", "ich", "iê", "iêc", "iêm", "iên", "iêng", "iêp", "iêt", "iêu", "im", "in", "inh", "ip", "it", "iu",
        "o", "oa", "oac", "oach", "oai", "oam", "oan", "oang", "oanh", "oao", "oap", "oat", "oay",
        "oă", "oăc", "oăm", "oăn", "oăng", "oăp", "oăt",
        "oc", "oe", "oen", "oeo", "oet", "oi", "om", "on", "ong", "oo", "ooc", "oong", "op", "ot",
        "ô", "ôc", "ôi", "ôm", "ôn", "ông", "ôp", "ôt",
        "ơ", "ơc", "ơi", "ơm", "ơn", "ơp", "ơt",
        "u", "ua", "uâ", "uân", "uâng", "uât", "uây", "uc", "uê", "uêc", "uêch", "uên", "uênh",
        "ui", "um", "un", "ung", "uô", "uôc", "uôi", "uôm", "uôn", "uông", "uôt",
        "uơ", "up", "ut", "uy", "uya", "uych", "uyê", "uyên", "uyêt", "uyn", "uynh", "uyp", "uyt", "uyu",
        "ư", "ưa", "ưc", "ưi", "ưm", "ưn", "ưng", "ưo", "ưt", "ưu",
        "ươ", "ươc", "ươi", "ươm", "ươn", "ương", "ươp", "ươt", "ươu",
        "y", "ych", "yê", "yêm", "yên", "yêng", "yêt", "yêu", "ym", "yn", "ynh", "yt"
    ]

    public static let commonEnglishWords: Set<String> = [
        // Tech, programming & developer terms
        "post", "get", "set", "test", "user", "admin", "login", "reset", "format",
        "password", "email", "server", "client", "docker", "react", "swift", "git",
        "pause", "cause", "close", "house", "different", "coffee",
        "status", "commit", "push", "pull", "branch", "merge", "checkout", "true",
        "false", "null", "class", "import", "export", "function", "return", "const",
        "table", "column", "row", "view", "page", "site", "chat", "link", "text",
        "type", "date", "time", "file", "path", "home", "app", "help", "info",
        "case", "break", "switch", "while", "loop", "error", "warn", "debug",
        "trace", "log", "start", "stop", "next", "prev", "index", "count", "size",
        "data", "base", "token", "auth", "host", "port", "root", "main", "node",
        "item", "list", "form", "input", "output", "query", "state", "props",
        "hook", "card", "icon", "modal", "title", "body", "head", "footer", "meta",
        "style", "font", "color", "image", "media", "audio", "video", "event",
        "click", "drag", "drop", "press", "touch", "scroll", "load", "save",
        "open", "close", "read", "write", "send", "call", "wait", "done", "fail",
        "pass", "badge", "label", "button", "menu", "tab", "alert", "toast",
        "group", "stack", "grid", "box", "flex", "wrap", "auto", "fixed",
        "span", "code", "block", "inline", "chart", "graph", "metric", "stat",
        "report", "track", "filter", "sort", "search", "find", "match", "replace",
        "regex", "string", "number", "boolean", "array", "object", "map",
        "hash", "cache", "store", "memory", "cpu", "disk", "ram", "task", "job",
        "worker", "queue", "pipe", "stream", "socket", "http", "https", "url",
        "api", "rest", "json", "xml", "yaml", "html", "css", "sql",
        "key", "value", "field", "record", "entry", "schema", "model",
        "mock", "stub", "patch", "diff", "tag", "release", "build", "deploy",
        "ci", "cd", "spec", "suite", "runner", "lint",

        // Common conversational & internet English words
        "the", "and", "for", "with", "from", "have", "that", "your",
        "more", "make", "like", "just", "know", "take", "people", "into",
        "year", "good", "some", "could", "them", "other", "than", "then",
        "now", "look", "only", "come", "its", "over", "think", "also",
        "back", "after", "use", "two", "how", "our", "work", "first",
        "well", "way", "even", "new", "want", "because", "any",
        "give", "day", "most", "us", "facebook", "google", "apple", "microsoft",
        "youtube", "tiktok", "zalo", "telegram", "slack", "discord", "zoom",
        "chrome", "safari", "iphone", "ipad", "macbook", "laptop", "online",
        "offline", "game", "shop", "sale", "order", "ship", "bill", "bank",
        "check", "deal", "super", "smart", "pro", "mini", "plus",
        "cool", "nice", "fast", "slow", "easy", "hard", "high", "low",
        "free", "vip", "hot", "top", "best", "fan", "club", "team",
        "house", "car", "bus", "bike", "play", "music",
        "song", "film", "movie", "star", "show", "live", "feed",
        "share", "follow", "story", "reel", "note", "poll", "vote",
        "quiz", "meme", "trend", "viral", "blog", "vlog", "podcast", "cast",
        "broadcast", "channel", "sub", "hit", "rule", "safe", "name", "zone",
        "rate", "gate", "blue", "mode", "role",

        // Frequently mistyped English words & developer inflections
        "tests", "testing", "tested", "tester", "testers",
        "posts", "posting", "posted", "lists", "listing", "listed",
        "costs", "costing", "costly", "faster", "fastest",
        "lasting", "lasted", "trusted", "trusting", "exists", "existing", "existed",
        "systems", "systematic", "install", "installed", "installing",
        "instance", "instances", "constant", "constants", "request", "requests", "requested",
        "suggest", "suggests", "suggested", "resets", "results",
        "cards", "parts", "starts", "started", "starting",
        "forms", "formed", "forming", "works", "worked", "working",
        "turns", "turned", "turning", "pauses", "paused", "pausing",
        "causes", "caused", "causing", "cases", "based", "closes", "closed",
        "draft", "craft", "lift", "gift", "soft", "left", "dust", "rust", "burst"
    ]

    public static let commonEnglishStems: Set<String> = [
        "test", "best", "rest", "list", "post", "cost", "fast", "last", "must", "just",
        "dust", "rust", "trust", "burst", "first", "exist", "artist", "custom", "system",
        "instal", "master", "poster", "card", "part", "start", "form", "work", "mark",
        "turn", "burn", "learn", "alert", "court", "short", "shirt", "draft", "craft", "lift", "gift", "soft"
    ]

    private func canAcceptVietnameseTransforms(slots: [CharSlot]) -> Bool {
        let s = analyzeSyllable(slots)
        let onsetStr = renderSlice(slots[s.onsetRange])
        let onsetAllowed = Self.validOnsets.contains(onsetStr) || (s.vowelRange.isEmpty && Self.composingOnlyOnsets.contains(onsetStr))
        if !onsetAllowed {
            return false
        }
        return isSyllablePrefixValid(slots: slots, tone: tone)
    }

    private func isToneCompatibleWithCoda(slots: [CharSlot], tone targetTone: ToneMark) -> Bool {
        let s = analyzeSyllable(slots)
        let codaStr = renderSlice(slots[s.codaRange])
        if Self.stopCodas.contains(codaStr) {
            return targetTone == .none || targetTone == .acute || targetTone == .dot
        }
        return true
    }

    private func isSyllablePrefixValid(slots: [CharSlot], tone: ToneMark) -> Bool {
        let s = analyzeSyllable(slots)
        let onsetStr = renderSlice(slots[s.onsetRange])

        if s.vowelRange.isEmpty {
            return Self.validOnsets.contains(onsetStr) || Self.composingOnlyOnsets.contains(onsetStr)
        }

        if !Self.validOnsets.contains(onsetStr) {
            return false
        }

        let rhymeStr = renderSlice(slots[s.vowelRange]) + renderSlice(slots[s.codaRange])
        guard Self.validRhymes.contains(rhymeStr) || Self.composingOnlyRhymes.contains(rhymeStr) else {
            return false
        }

        let codaStr = renderSlice(slots[s.codaRange])
        if !Self.validCodas.contains(codaStr) {
            return false
        }
        if Self.stopCodas.contains(codaStr) && tone != .none && tone != .acute && tone != .dot {
            return false
        }

        return true
    }

    private func isCompleteSyllableValidOnDelimiter(slots: [CharSlot], tone: ToneMark) -> Bool {
        if slots.count == 1 && slots[0].base == "d" && slots[0].shape == .stroke && tone == .none {
            return true
        }
        let s = analyzeSyllable(slots)
        guard !s.vowelRange.isEmpty else { return false }
        let onsetStr = renderSlice(slots[s.onsetRange])
        let codaStr = renderSlice(slots[s.codaRange])
        let vowelStr = renderSlice(slots[s.vowelRange])
        let rhymeStr = vowelStr + codaStr

        if !Self.validRhymes.contains(rhymeStr) {
            return false
        }
        if Self.stopCodas.contains(codaStr) && tone == .none {
            return false
        }
        if codaStr.isEmpty && vowelStr == "ưo" {
            return false
        }
        if codaStr.isEmpty && (vowelStr == "ă" || vowelStr == "â") && !onsetStr.isEmpty {
            return false
        }
        if codaStr.isEmpty && (vowelStr == "iê" || vowelStr == "uô" || vowelStr == "uyê" || vowelStr == "yê" || vowelStr == "uâ") {
            return false
        }
        return true
    }

    private func renderSlice(_ slice: ArraySlice<CharSlot>) -> String {
        var out = ""
        out.reserveCapacity(slice.count)
        for slot in slice {
            out.append(renderChar(base: slot.base, shape: slot.shape, tone: .none, upper: false))
        }
        return out
    }

    private func render(slots list: [CharSlot], tone: ToneMark) -> String {
        guard !list.isEmpty else { return "" }
        let s = analyzeSyllable(list)
        let targetIdx = toneTargetIndex(in: list, structure: s)
        var out = ""
        out.reserveCapacity(list.count)
        for (idx, slot) in list.enumerated() {
            let appliedTone: ToneMark = (idx == targetIdx) ? tone : .none
            out.append(renderChar(base: slot.base, shape: slot.shape, tone: appliedTone, upper: slot.isUpper))
        }
        return out
    }

    private func renderChar(base: Character, shape: LetterShape, tone: ToneMark, upper: Bool) -> Character {
        if base == "d" && shape == .stroke {
            return upper ? "Đ" : "đ"
        }

        let table: [Character]
        switch (base, shape) {
        case ("a", .plain):      table = ["a", "á", "à", "ả", "ã", "ạ"]
        case ("a", .breve):      table = ["ă", "ắ", "ằ", "ẳ", "ẵ", "ặ"]
        case ("a", .circumflex): table = ["â", "ấ", "ầ", "ẩ", "ẫ", "ậ"]
        case ("e", .plain):      table = ["e", "é", "è", "ẻ", "ẽ", "ẹ"]
        case ("e", .circumflex): table = ["ê", "ế", "ề", "ể", "ễ", "ệ"]
        case ("i", .plain):      table = ["i", "í", "ì", "ỉ", "ĩ", "ị"]
        case ("o", .plain):      table = ["o", "ó", "ò", "ỏ", "õ", "ọ"]
        case ("o", .circumflex): table = ["ô", "ố", "ồ", "ổ", "ỗ", "ộ"]
        case ("o", .horn):       table = ["ơ", "ớ", "ờ", "ở", "ỡ", "ợ"]
        case ("u", .plain):      table = ["u", "ú", "ù", "ủ", "ũ", "ụ"]
        case ("u", .horn):       table = ["ư", "ứ", "ừ", "ử", "ữ", "ự"]
        case ("y", .plain):      table = ["y", "ý", "ỳ", "ỷ", "ỹ", "ỵ"]
        default:
            return upper ? Character(base.uppercased()) : base
        }

        let toneIndex: Int
        switch tone {
        case .none:  toneIndex = 0
        case .acute: toneIndex = 1
        case .grave: toneIndex = 2
        case .hook:  toneIndex = 3
        case .tilde: toneIndex = 4
        case .dot:   toneIndex = 5
        }

        let ch = table[toneIndex]
        return upper ? Character(ch.uppercased()) : ch
    }

    private func diffAction(from prev: String, to next: String) -> KeyAction {
        let pChars = Array(prev)
        let nChars = Array(next)
        var common = 0
        while common < pChars.count && common < nChars.count && pChars[common] == nChars[common] {
            common += 1
        }
        let backspaces = pChars.count - common
        let replacement = String(nChars[common...])
        return .replace(backspaceCount: backspaces, text: replacement)
    }

    private func findDoubleUndoConsonantIndex(in keys: [Character]) -> Int? {
        let toneChars: Set<Character> = ["s", "f", "r", "x", "j"]
        guard keys.count >= 2 else { return nil }
        for i in 0..<(keys.count - 1) {
            let lower1 = Character(keys[i].lowercased())
            let lower2 = Character(keys[i + 1].lowercased())
            if toneChars.contains(lower1) && lower1 == lower2 {
                return i + 1
            }
        }
        return nil
    }

    private func isPrintableWordDelimiter(_ char: Character) -> Bool {
        char == " " || ".,;:!?/\\()[]{}-_'\"".contains(char)
    }
}
