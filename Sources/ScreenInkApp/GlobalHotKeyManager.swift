import AppKit
import Carbon
import Foundation
import ScreenInkCore

extension KeyModifiers {
    /// 转换为 Carbon RegisterEventHotKey 修饰键掩码
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option)  { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift)   { flags |= UInt32(shiftKey) }
        return flags
    }

    /// 转换为 AppKit NSEvent / NSMenuItem 修饰键掩码
    var appKitFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option)  { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift)   { flags.insert(.shift) }
        return flags
    }

    /// 从 AppKit NSEvent.ModifierFlags 提取标准快捷键修饰键
    init(appKitFlags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if appKitFlags.contains(.command) { result.insert(.command) }
        if appKitFlags.contains(.option)  { result.insert(.option) }
        if appKitFlags.contains(.control) { result.insert(.control) }
        if appKitFlags.contains(.shift)   { result.insert(.shift) }
        self = result
    }
}

extension KeyShortcut {
    /// 从 NSEvent 构造快捷键对象
    init(event: NSEvent) {
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: KeyModifiers(appKitFlags: event.modifierFlags)
        )
    }
}

extension NSMenuItem {
    /// 将自定义快捷键同步到菜单项的右侧快捷提示
    func apply(shortcut: KeyShortcut?) {
        guard let shortcut else {
            keyEquivalent = ""
            keyEquivalentModifierMask = []
            return
        }
        let equivalent = shortcut.menuKeyEquivalent
        keyEquivalent = equivalent
        keyEquivalentModifierMask = equivalent.isEmpty ? [] : shortcut.modifiers.appKitFlags
    }
}

/// Carbon RegisterEventHotKey 动态全局快捷键管理器（支持运行时热更新、录制期挂起与占用检测）
@MainActor
final class GlobalHotKeyManager {
    private static let signature: OSType = 0x5349_4E4B // 'SINK'
    private static weak var activeManager: GlobalHotKeyManager?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var currentConfiguration: ShortcutConfiguration = .default
    private var isSuspended: Bool = false
    private let onAction: (ShortcutAction) -> Void

    init(onAction: @escaping (ShortcutAction) -> Void) {
        self.onAction = onAction
    }

    /// 注册全部全局快捷键，返回因被系统或其他应用占用而注册失败的动作集合
    @discardableResult
    func register(configuration: ShortcutConfiguration) -> Set<ShortcutAction> {
        currentConfiguration = configuration
        guard !isSuspended else { return [] }

        unregisterAll()
        Self.activeManager = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            guard let eventRef else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == GlobalHotKeyManager.signature,
                  let action = ShortcutAction.fromHotKeyID(hotKeyID.id)
            else {
                return OSStatus(eventNotHandledErr)
            }

            Task { @MainActor in
                GlobalHotKeyManager.activeManager?.onAction(action)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        var failedActions: Set<ShortcutAction> = []
        for action in ShortcutAction.globalActions {
            guard let hotKeyIDValue = action.hotKeyID,
                  let shortcut = configuration[action]
            else {
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotKeyIDValue)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers.carbonFlags,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let ref = hotKeyRef {
                hotKeyRefs.append(ref)
            } else {
                failedActions.insert(action)
            }
        }
        return failedActions
    }

    /// 录制快捷键时临时挂起全局拦截，结束录制后自动恢复注册
    @discardableResult
    func setSuspended(_ suspended: Bool, configuration: ShortcutConfiguration? = nil) -> Set<ShortcutAction> {
        if let configuration {
            currentConfiguration = configuration
        }
        isSuspended = suspended
        if suspended {
            unregisterAll()
            return []
        } else {
            return register(configuration: currentConfiguration)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
