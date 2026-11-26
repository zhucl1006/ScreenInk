import Foundation

/// 快捷键生效范围
public enum ShortcutScope: String, Codable, Equatable, Hashable, Sendable {
    /// 全局生效（任意应用 / 全屏演示中随时触发）
    case global
    /// 仅在批注画布激活时生效
    case canvas
}

/// 快捷键修饰键（与 macOS 硬件/系统修饰键一一对应，独立于 AppKit/Carbon 便于核心层单测）
public struct KeyModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option  = KeyModifiers(rawValue: 1 << 1)
    public static let shift   = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// 是否包含至少一个可用于全局热键的主修饰键（⌘ / ⌥ / ⌃）
    public var hasPrimaryGlobalModifier: Bool {
        !intersection([.command, .option, .control]).isEmpty
    }

    /// 按 Apple HIG 标准顺序输出修饰键符号：⌃⌥⇧⌘
    public var displaySymbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option)  { result += "⌥" }
        if contains(.shift)   { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

/// 单个快捷键绑定（基于 macOS 虚拟键码 + 修饰键）
public struct KeyShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 是否为仅修饰键的虚拟键码（不可单独作为按键）
    public static func isModifierOnlyKeyCode(_ keyCode: UInt32) -> Bool {
        KeyCodeTable.modifierKeyCodes.contains(keyCode)
    }

    /// 是否为受支持的可绑定虚拟键码
    public var isSupportedKey: Bool {
        KeyCodeTable.displayName(for: keyCode) != nil
    }

    /// 是否为 F1–F20 功能键
    public var isFunctionKey: Bool {
        KeyCodeTable.functionKeyCodes.contains(keyCode)
    }

    /// 按键主字符显示名（例如 "1"、"C"、"F8"、"Space"）
    public var keyDisplayName: String {
        KeyCodeTable.displayName(for: keyCode) ?? "Key(\(keyCode))"
    }

    /// 紧凑展示格式（用于菜单提示与浮窗 Tooltip，例如 "⌘1"、"⌃⇧A"、"R"）
    public var displayString: String {
        modifiers.displaySymbols + keyDisplayName
    }

    /// 带空格分隔的键帽展示格式（用于偏好设置界面，例如 "⌘ 1"、"⌃ ⇧ A"、"R"）
    public var badgeDisplayString: String {
        let symbols = modifiers.displaySymbols
        guard !symbols.isEmpty else { return keyDisplayName }
        let spacedModifiers = symbols.map(String.init).joined(separator: " ")
        return "\(spacedModifiers) \(keyDisplayName)"
    }

    /// 转换为 NSMenuItem 使用的 keyEquivalent 字符串（若无对应字符返回空字符串）
    public var menuKeyEquivalent: String {
        KeyCodeTable.menuKeyEquivalent(for: keyCode) ?? ""
    }

    /// 校验在指定生效范围内是否合法
    public func validate(for scope: ShortcutScope) -> ShortcutValidationError? {
        guard !Self.isModifierOnlyKeyCode(keyCode), isSupportedKey else {
            return .unsupportedKey
        }

        switch scope {
        case .global:
            if !modifiers.hasPrimaryGlobalModifier && !isFunctionKey {
                return .missingGlobalModifier
            }
            // 禁止覆盖 ⌘Q（退出应用）与 ⌘Tab（系统应用切换）
            if modifiers == .command && (keyCode == KeyCodeTable.q || keyCode == KeyCodeTable.tab) {
                return .reservedSystemShortcut
            }
            return nil

        case .canvas:
            // Esc、Return/Enter 固定用于取消/提交；⌘Z / ⇧⌘Z 固定用于撤销/重做
            if keyCode == KeyCodeTable.escape || keyCode == KeyCodeTable.returnKey || keyCode == KeyCodeTable.keypadEnter {
                return .reservedCanvasShortcut
            }
            if keyCode == KeyCodeTable.z && (modifiers == .command || modifiers == [.command, .shift]) {
                return .reservedCanvasShortcut
            }
            return nil
        }
    }
}

/// 快捷键校验失败原因
public enum ShortcutValidationError: Equatable, Sendable {
    case unsupportedKey
    case missingGlobalModifier
    case reservedSystemShortcut
    case reservedCanvasShortcut
    case conflict(ShortcutAction)

    public var message: String {
        switch self {
        case .unsupportedKey:
            return "不支持该按键，请选择字母、数字、符号或功能键"
        case .missingGlobalModifier:
            return "全局快捷键需包含 ⌘ / ⌥ / ⌃ 修饰键，或使用 F1–F20 功能键"
        case .reservedSystemShortcut:
            return "该组合为系统保留快捷键，请更换其他组合"
        case .reservedCanvasShortcut:
            return "Esc、Return 与 ⌘Z / ⇧⌘Z 为批注内固定按键，请更换其他按键"
        case .conflict(let action):
            return "与「\(action.displayName)」快捷键冲突，请更换其他组合"
        }
    }
}

/// ScreenInk 支持自定义的全部快捷键动作
public enum ShortcutAction: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    // 全局快捷键
    case toggleAnnotateClean
    case toggleAnnotateWithToolbar
    case toggleClickHighlight
    case clearAnnotations

    // 批注模式内快捷键
    case selectRectangle
    case selectText
    case toggleRetentionMode

    public var id: String { rawValue }

    /// 供 Carbon RegisterEventHotKey 使用的稳定 ID（仅全局动作有效）
    public var hotKeyID: UInt32? {
        switch self {
        case .toggleAnnotateClean: return 1
        case .toggleAnnotateWithToolbar: return 2
        case .toggleClickHighlight: return 3
        case .clearAnnotations: return 4
        case .selectRectangle, .selectText, .toggleRetentionMode: return nil
        }
    }

    public static func fromHotKeyID(_ id: UInt32) -> ShortcutAction? {
        globalActions.first { $0.hotKeyID == id }
    }

    public var scope: ShortcutScope {
        switch self {
        case .toggleAnnotateClean, .toggleAnnotateWithToolbar, .toggleClickHighlight, .clearAnnotations:
            return .global
        case .selectRectangle, .selectText, .toggleRetentionMode:
            return .canvas
        }
    }

    public var isGlobal: Bool { scope == .global }

    public var displayName: String {
        switch self {
        case .toggleAnnotateClean: return "无工具栏矩形批注"
        case .toggleAnnotateWithToolbar: return "有工具栏矩形批注"
        case .toggleClickHighlight: return "点击高亮（脉动光环）"
        case .clearAnnotations: return "清空屏幕标注"
        case .selectRectangle: return "切换矩形高亮框"
        case .selectText: return "切换文字标注"
        case .toggleRetentionMode: return "切换自动淡出 / 停留模式"
        }
    }

    public var defaultShortcut: KeyShortcut {
        switch self {
        case .toggleAnnotateClean:
            return KeyShortcut(keyCode: KeyCodeTable.num1, modifiers: .command)
        case .toggleAnnotateWithToolbar:
            return KeyShortcut(keyCode: KeyCodeTable.num2, modifiers: .command)
        case .toggleClickHighlight:
            return KeyShortcut(keyCode: KeyCodeTable.num3, modifiers: .command)
        case .clearAnnotations:
            return KeyShortcut(keyCode: KeyCodeTable.c, modifiers: .option)
        case .selectRectangle:
            return KeyShortcut(keyCode: KeyCodeTable.r, modifiers: [])
        case .selectText:
            return KeyShortcut(keyCode: KeyCodeTable.t, modifiers: [])
        case .toggleRetentionMode:
            return KeyShortcut(keyCode: KeyCodeTable.f, modifiers: [])
        }
    }

    public static let globalActions: [ShortcutAction] = [
        .toggleAnnotateClean,
        .toggleAnnotateWithToolbar,
        .toggleClickHighlight,
        .clearAnnotations
    ]

    public static let canvasActions: [ShortcutAction] = [
        .selectRectangle,
        .selectText,
        .toggleRetentionMode
    ]
}

/// 全部自定义快捷键配置（支持显式禁用某项为 nil，也兼容旧版 JSON 缺省升级）
public struct ShortcutConfiguration: Codable, Equatable, Sendable {
    public var toggleAnnotateClean: KeyShortcut?
    public var toggleAnnotateWithToolbar: KeyShortcut?
    public var toggleClickHighlight: KeyShortcut?
    public var clearAnnotations: KeyShortcut?
    public var selectRectangle: KeyShortcut?
    public var selectText: KeyShortcut?
    public var toggleRetentionMode: KeyShortcut?

    public init(
        toggleAnnotateClean: KeyShortcut? = ShortcutAction.toggleAnnotateClean.defaultShortcut,
        toggleAnnotateWithToolbar: KeyShortcut? = ShortcutAction.toggleAnnotateWithToolbar.defaultShortcut,
        toggleClickHighlight: KeyShortcut? = ShortcutAction.toggleClickHighlight.defaultShortcut,
        clearAnnotations: KeyShortcut? = ShortcutAction.clearAnnotations.defaultShortcut,
        selectRectangle: KeyShortcut? = ShortcutAction.selectRectangle.defaultShortcut,
        selectText: KeyShortcut? = ShortcutAction.selectText.defaultShortcut,
        toggleRetentionMode: KeyShortcut? = ShortcutAction.toggleRetentionMode.defaultShortcut
    ) {
        self.toggleAnnotateClean = toggleAnnotateClean
        self.toggleAnnotateWithToolbar = toggleAnnotateWithToolbar
        self.toggleClickHighlight = toggleClickHighlight
        self.clearAnnotations = clearAnnotations
        self.selectRectangle = selectRectangle
        self.selectText = selectText
        self.toggleRetentionMode = toggleRetentionMode
    }

    public static let `default` = ShortcutConfiguration()

    public var isDefault: Bool { self == .default }

    public subscript(_ action: ShortcutAction) -> KeyShortcut? {
        get {
            switch action {
            case .toggleAnnotateClean: return toggleAnnotateClean
            case .toggleAnnotateWithToolbar: return toggleAnnotateWithToolbar
            case .toggleClickHighlight: return toggleClickHighlight
            case .clearAnnotations: return clearAnnotations
            case .selectRectangle: return selectRectangle
            case .selectText: return selectText
            case .toggleRetentionMode: return toggleRetentionMode
            }
        }
        set {
            switch action {
            case .toggleAnnotateClean: toggleAnnotateClean = newValue
            case .toggleAnnotateWithToolbar: toggleAnnotateWithToolbar = newValue
            case .toggleClickHighlight: toggleClickHighlight = newValue
            case .clearAnnotations: clearAnnotations = newValue
            case .selectRectangle: selectRectangle = newValue
            case .selectText: selectText = newValue
            case .toggleRetentionMode: toggleRetentionMode = newValue
            }
        }
    }

    /// 校验候选快捷键是否可用于目标动作（同时检查合法性与跨动作冲突）
    public func validate(candidate: KeyShortcut, for action: ShortcutAction) -> ShortcutValidationError? {
        if let baseError = candidate.validate(for: action.scope) {
            return baseError
        }
        if let conflict = conflictingAction(for: candidate, excluding: action) {
            return .conflict(conflict)
        }
        return nil
    }

    /// 检查是否与当前配置中其他动作快捷键冲突
    public func conflictingAction(for candidate: KeyShortcut, excluding action: ShortcutAction) -> ShortcutAction? {
        for other in ShortcutAction.allCases where other != action {
            if self[other] == candidate {
                return other
            }
        }
        return nil
    }

    /// 在批注模式中按输入的按键组合反查匹配的批注内动作
    public func matchingCanvasAction(for input: KeyShortcut) -> ShortcutAction? {
        for action in ShortcutAction.canvasActions {
            if self[action] == input {
                return action
            }
        }
        return nil
    }

    public func displayString(for action: ShortcutAction, fallback: String = "未设置") -> String {
        self[action]?.displayString ?? fallback
    }

    public func badgeDisplayString(for action: ShortcutAction, fallback: String = "未设置") -> String {
        self[action]?.badgeDisplayString ?? fallback
    }

    public mutating func reset(_ action: ShortcutAction) {
        self[action] = action.defaultShortcut
    }

    public mutating func resetAll() {
        self = .default
    }

    // MARK: - 显式编码 nil 与兼容缺失字段的 Codable

    private enum CodingKeys: String, CodingKey {
        case toggleAnnotateClean
        case toggleAnnotateWithToolbar
        case toggleClickHighlight
        case clearAnnotations
        case selectRectangle
        case selectText
        case toggleRetentionMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.toggleAnnotateClean = c.contains(.toggleAnnotateClean)
            ? try c.decodeIfPresent(KeyShortcut.self, forKey: .toggleAnnotateClean)
            : ShortcutAction.toggleAnnotateClean.defaultShortcut
        self.toggleAnnotateWithToolbar = c.contains(.toggleAnnotateWithToolbar)
            ? try c.decodeIfPresent(KeyShortcut.self, forKey: .toggleAnnotateWithToolbar)
            : ShortcutAction.toggleAnnotateWithToolbar.defaultShortcut
        self.toggleClickHighlight = c.contains(.toggleClickHighlight)
            ? try c.decodeIfPresent(KeyShortcut.self, forKey: .toggleClickHighlight)
            : ShortcutAction.toggleClickHighlight.defaultShortcut
        self.clearAnnotations = c.contains(.clearAnnotations)
            ? try c.decodeIfPresent(KeyShortcut.self, forKey: .clearAnnotations)
            : ShortcutAction.clearAnnotations.defaultShortcut
        self.selectRectangle = c.contains(.selectRectangle)
            ? try c.decodeIfPresent(KeyShortcut.self, forKey: .selectRectangle)
            : ShortcutAction.selectRectangle.defaultShortcut
        self.selectText = c.contains(.selectText)
            ? try c.decodeIfPresent(KeyShortcut.self, forKey: .selectText)
            : ShortcutAction.selectText.defaultShortcut
        self.toggleRetentionMode = c.contains(.toggleRetentionMode)
            ? try c.decodeIfPresent(KeyShortcut.self, forKey: .toggleRetentionMode)
            : ShortcutAction.toggleRetentionMode.defaultShortcut
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // 使用 encode 而非 encodeIfPresent，以便区分“用户显式禁用(null)”与“旧版缺失字段”
        try c.encode(toggleAnnotateClean, forKey: .toggleAnnotateClean)
        try c.encode(toggleAnnotateWithToolbar, forKey: .toggleAnnotateWithToolbar)
        try c.encode(toggleClickHighlight, forKey: .toggleClickHighlight)
        try c.encode(clearAnnotations, forKey: .clearAnnotations)
        try c.encode(selectRectangle, forKey: .selectRectangle)
        try c.encode(selectText, forKey: .selectText)
        try c.encode(toggleRetentionMode, forKey: .toggleRetentionMode)
    }
}

/// macOS HIToolbox 虚拟键码映射表（与 <Carbon/HIToolbox/Events.h> 完全一致）
public enum KeyCodeTable {
    public static let a: UInt32 = 0x00
    public static let s: UInt32 = 0x01
    public static let d: UInt32 = 0x02
    public static let f: UInt32 = 0x03
    public static let h: UInt32 = 0x04
    public static let g: UInt32 = 0x05
    public static let z: UInt32 = 0x06
    public static let x: UInt32 = 0x07
    public static let c: UInt32 = 0x08
    public static let v: UInt32 = 0x09
    public static let b: UInt32 = 0x0B
    public static let q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D
    public static let e: UInt32 = 0x0E
    public static let r: UInt32 = 0x0F
    public static let y: UInt32 = 0x10
    public static let t: UInt32 = 0x11
    public static let num1: UInt32 = 0x12
    public static let num2: UInt32 = 0x13
    public static let num3: UInt32 = 0x14
    public static let num4: UInt32 = 0x15
    public static let num6: UInt32 = 0x16
    public static let num5: UInt32 = 0x17
    public static let equal: UInt32 = 0x18
    public static let num9: UInt32 = 0x19
    public static let num7: UInt32 = 0x1A
    public static let minus: UInt32 = 0x1B
    public static let num8: UInt32 = 0x1C
    public static let num0: UInt32 = 0x1D
    public static let rightBracket: UInt32 = 0x1E
    public static let o: UInt32 = 0x1F
    public static let u: UInt32 = 0x20
    public static let leftBracket: UInt32 = 0x21
    public static let i: UInt32 = 0x22
    public static let p: UInt32 = 0x23
    public static let returnKey: UInt32 = 0x24
    public static let l: UInt32 = 0x25
    public static let j: UInt32 = 0x26
    public static let quote: UInt32 = 0x27
    public static let k: UInt32 = 0x28
    public static let semicolon: UInt32 = 0x29
    public static let backslash: UInt32 = 0x2A
    public static let comma: UInt32 = 0x2B
    public static let slash: UInt32 = 0x2C
    public static let n: UInt32 = 0x2D
    public static let m: UInt32 = 0x2E
    public static let period: UInt32 = 0x2F
    public static let tab: UInt32 = 0x30
    public static let space: UInt32 = 0x31
    public static let grave: UInt32 = 0x32
    public static let delete: UInt32 = 0x33
    public static let escape: UInt32 = 0x35
    public static let keypadEnter: UInt32 = 0x4C
    public static let forwardDelete: UInt32 = 0x75

    public static let modifierKeyCodes: Set<UInt32> = [
        0x36, // RightCommand
        0x37, // Command
        0x38, // Shift
        0x39, // CapsLock
        0x3A, // Option
        0x3B, // Control
        0x3C, // RightShift
        0x3D, // RightOption
        0x3E, // RightControl
        0x3F  // Function
    ]

    public static let functionKeyCodes: Set<UInt32> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A
    ]

    private static let keyDisplayNames: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
        0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x24: "↩", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
        0x30: "⇥", 0x31: "Space", 0x32: "`", 0x33: "⌫", 0x35: "Esc",
        0x41: "Num.", 0x43: "Num*", 0x45: "Num+", 0x4B: "Num/", 0x4C: "⌤",
        0x4E: "Num-", 0x51: "Num=",
        0x52: "Num0", 0x53: "Num1", 0x54: "Num2", 0x55: "Num3", 0x56: "Num4",
        0x57: "Num5", 0x58: "Num6", 0x59: "Num7", 0x5B: "Num8", 0x5C: "Num9",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑"
    ]

    private static let menuEquivalents: [UInt32: String] = [
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g",
        0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v", 0x0B: "b", 0x0C: "q",
        0x0D: "w", 0x0E: "e", 0x0F: "r", 0x10: "y", 0x11: "t",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
        0x1E: "]", 0x1F: "o", 0x20: "u", 0x21: "[", 0x22: "i", 0x23: "p",
        0x24: "\r", 0x25: "l", 0x26: "j", 0x27: "'", 0x28: "k", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "n", 0x2E: "m", 0x2F: ".",
        0x30: "\t", 0x31: " ", 0x32: "`", 0x33: "\u{0008}",
        0x4C: "\u{0003}",
        0x7A: "\u{F704}", 0x78: "\u{F705}", 0x63: "\u{F706}", 0x76: "\u{F707}",
        0x60: "\u{F708}", 0x61: "\u{F709}", 0x62: "\u{F70A}", 0x64: "\u{F70B}",
        0x65: "\u{F70C}", 0x6D: "\u{F70D}", 0x67: "\u{F70E}", 0x6F: "\u{F70F}",
        0x69: "\u{F710}", 0x6B: "\u{F711}", 0x71: "\u{F712}", 0x6A: "\u{F713}",
        0x40: "\u{F714}", 0x4F: "\u{F715}", 0x50: "\u{F716}", 0x5A: "\u{F717}",
        0x73: "\u{F729}", 0x77: "\u{F72B}", 0x74: "\u{F72C}", 0x79: "\u{F72D}",
        0x75: "\u{F728}",
        0x7B: "\u{F702}", 0x7C: "\u{F703}", 0x7D: "\u{F701}", 0x7E: "\u{F700}"
    ]

    public static func displayName(for keyCode: UInt32) -> String? {
        keyDisplayNames[keyCode]
    }

    public static func menuKeyEquivalent(for keyCode: UInt32) -> String? {
        menuEquivalents[keyCode]
    }
}
