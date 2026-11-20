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

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ctrlShift: return "Ctrl + Shift"
        case .cmdShift: return "Cmd + Shift"
        case .optionZ: return "Option + Z"
        case .ctrlSpace: return "Ctrl + Space"
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
        "mail": "email"
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
        macroTable: [String: String] = VietnameseSettings.defaultMacroTable
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

        let isBracketChar = (char == "[" || char == "]" || char == "{" || char == "}")
        let telexEnabled = settings.inputMethod == .telex || settings.inputMethod == .telexAndVni

        if isBracketChar && settings.bracketShortcuts && telexEnabled && !isRestoredToRaw {
            let isClosing = (char == "]" || char == "}")
            let isUpper = (char == "{" || char == "}")
            let prevRendered = render(slots: slots, tone: tone)

            if isClosing {
                // ']' -> ư, '}' -> Ư
                // Check double-tap undo
                if !slots.isEmpty && slots.last?.bracketKey == "]" {
                    slots.removeLast()
                    slots.append(CharSlot(base: "]", shape: .plain, isUpper: isUpper))
                    rawKeys.append(char)
                    isRestoredToRaw = true
                    bracketUndone = true
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }

                slots.append(CharSlot(base: "u", shape: .horn, isUpper: isUpper, isBracketTransform: true, bracketKey: "]"))
                rawKeys.append(char)
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            } else {
                // '[' -> ơ, '{' -> Ơ
                // Check double-tap undo
                if !slots.isEmpty && slots.last?.bracketKey == "[" {
                    slots.removeLast()
                    slots.append(CharSlot(base: "[", shape: .plain, isUpper: isUpper))
                    rawKeys.append(char)
                    isRestoredToRaw = true
                    bracketUndone = true
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }

                // If preceding slot was plain 'u', convert 'u' -> 'ư' and add 'ơ' -> 'ươ'
                if !slots.isEmpty && slots.last?.base == "u" && slots.last?.shape == .plain {
                    slots[slots.count - 1].shape = .horn
                    slots.append(CharSlot(base: "o", shape: .horn, isUpper: isUpper, isBracketTransform: true, bracketKey: "["))
                    rawKeys.append(char)
                    let nextRendered = render(slots: slots, tone: tone)
                    return diffAction(from: prevRendered, to: nextRendered)
                }

                slots.append(CharSlot(base: "o", shape: .horn, isUpper: isUpper, isBracketTransform: true, bracketKey: "["))
                rawKeys.append(char)
                let nextRendered = render(slots: slots, tone: tone)
                return diffAction(from: prevRendered, to: nextRendered)
            }
        }

        let lowerStr = char.lowercased()
        guard lowerStr.count == 1, let lower = lowerStr.first else {
            return processDelimiter(char, allowAutoRestore: false)
        }

        let isAsciiLetter = lower >= "a" && lower <= "z"
        let isDigit = lower >= "0" && lower <= "9"

        if !isAsciiLetter && !isDigit {
            return processDelimiter(char, allowAutoRestore: isPrintableWordDelimiter(char))
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
                rawKeys.append(char)
                return .passthrough
            }
        }

        if isRestoredToRaw {
            let prevDisplayed = render(slots: slots, tone: tone)
            rawKeys.append(char)
            slots.append(CharSlot(base: lower, shape: .plain, isUpper: char.isUppercase))
            if hasPendingUndoMismatch {
                hasPendingUndoMismatch = false
                slots = rawKeys.map { CharSlot(base: Character($0.lowercased()), shape: .plain, isUpper: $0.isUppercase) }
                let raw = String(rawKeys)
                return diffAction(from: prevDisplayed, to: raw)
            }
            return .passthrough
        }

        let prevRendered = render(slots: slots, tone: tone)

        if slots.isEmpty && lower == "w" && settings.standaloneWAsU && (settings.inputMethod == .telex || settings.inputMethod == .telexAndVni) {
            rawKeys.append(char)
            slots.append(CharSlot(base: "u", shape: .horn, isUpper: char.isUppercase, isStandaloneW: true))
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

            let prefixCanTransform = !settings.spellCheckEnabled || canAcceptVietnameseTransforms(slots: slots)

            if prefixCanTransform {
                if (telexEnabled && lower == "d") || (vniEnabled && lower == "9") {
                    if let action = tryApplyStroke(char: char, prevRendered: prevRendered, isVNI: lower == "9") {
                        return action
                    }
                }

                if (telexEnabled && (lower == "a" || lower == "e" || lower == "o")) || (vniEnabled && lower == "6") {
                    if let action = tryApplyCircumflex(char: char, lower: lower, prevRendered: prevRendered, isVNI: lower == "6") {
                        return action
                    }
                }

                if (telexEnabled && lower == "w") || (vniEnabled && (lower == "7" || lower == "8")) {
                    if let action = tryApplyHornOrBreve(char: char, lower: lower, prevRendered: prevRendered) {
                        return action
                    }
                }

                if let toneCmd = parseToneAction(lower: lower, telexEnabled: telexEnabled, vniEnabled: vniEnabled) {
                    if let action = tryApplyTone(toneCmd, char: char, prevRendered: prevRendered) {
                        return action
                    }
                }
            }
        }

        if isDigit {
            rawKeys.append(char)
            isRestoredToRaw = true
            let raw = String(rawKeys)
            if prevRendered != String(rawKeys.dropLast()) {
                return diffAction(from: prevRendered, to: raw)
            }
            return .passthrough
        }

        rawKeys.append(char)
        slots.append(CharSlot(base: lower, shape: .plain, isUpper: char.isUppercase))

        upgradeUOHornWithCodaIfNeeded()

        if settings.spellCheckEnabled && !isSyllablePrefixValid(slots: slots, tone: tone) {
            let raw = String(rawKeys)
            let wasModified = (prevRendered + String(char)) != raw
            isRestoredToRaw = true
            hasPendingUndoMismatch = false
            tone = .none
            slots = rawKeys.map { CharSlot(base: Character($0.lowercased()), shape: .plain, isUpper: $0.isUppercase) }
            if wasModified {
                return diffAction(from: prevRendered, to: raw)
            }
            return .passthrough
        }

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
        guard !sInfo.vowelRange.isEmpty else { return nil }

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
                rawKeys.append(char)
                hasPendingUndoMismatch = true
                if lower >= "a" && lower <= "z" {
                    slots.append(CharSlot(base: lower, shape: .plain, isUpper: char.isUppercase))
                } else {
                    isRestoredToRaw = true
                }
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
        guard vCount > 0 else { return nil }
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
        "ie", "iec", "iem", "ien", "ieng", "iep", "iet", "ieu",
        "uo", "uoc", "uom", "uon", "uong", "uop", "uot", "uoi", "uou",
        "uye", "uyen", "uyet",
        "ye", "yem", "yen", "yeng", "yet", "yeu",
        "uu", "ưo", "ưoc", "ưoi", "ưom", "ưon", "ưong", "ưop", "ưot", "ưou"
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

    private func isPrintableWordDelimiter(_ char: Character) -> Bool {
        char == " " || ".,;:!?/\\()[]{}-_'\"".contains(char)
    }
}
