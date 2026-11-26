import Carbon
import Foundation

/// 全局快捷键动作定义（任意应用生效，无需系统辅助功能权限）
enum GlobalHotKeyAction: UInt32, CaseIterable {
    /// ⌘1：无工具栏矩形批注
    case toggleAnnotateClean = 1
    /// ⌘2：有工具栏矩形批注
    case toggleAnnotateWithToolbar = 2
    /// ⌘3：点击高亮模式（点击时出现脉动光环后消失）
    case toggleClickHighlight = 3
    /// ⌥C：清空屏幕停留标注
    case clearAnnotations = 4

    var keyCode: UInt32 {
        switch self {
        case .toggleAnnotateClean: return UInt32(kVK_ANSI_1)
        case .toggleAnnotateWithToolbar: return UInt32(kVK_ANSI_2)
        case .toggleClickHighlight: return UInt32(kVK_ANSI_3)
        case .clearAnnotations: return UInt32(kVK_ANSI_C)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .toggleAnnotateClean, .toggleAnnotateWithToolbar, .toggleClickHighlight:
            return UInt32(cmdKey)
        case .clearAnnotations:
            return UInt32(optionKey)
        }
    }
}

/// Carbon RegisterEventHotKey 全局快捷键管理器
@MainActor
final class GlobalHotKeyManager {
    private static let signature: OSType = 0x5349_4E4B // 'SINK'
    private static weak var activeManager: GlobalHotKeyManager?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private let onAction: (GlobalHotKeyAction) -> Void

    init(onAction: @escaping (GlobalHotKeyAction) -> Void) {
        self.onAction = onAction
    }

    func registerAll() {
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
                  let action = GlobalHotKeyAction(rawValue: hotKeyID.id)
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

        for action in GlobalHotKeyAction.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(
                action.keyCode,
                action.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let ref = hotKeyRef {
                hotKeyRefs.append(ref)
            }
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
