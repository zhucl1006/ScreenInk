import CoreGraphics
import Foundation

/// 单屏画布状态容器：分别管理停留标注（支持撤销/重做/清除）与自动淡出标注
public final class CanvasState {
    /// 停留模式的持久标注
    public private(set) var persistentItems: [AnnotationItem] = []
    /// 自动淡出模式的临时标注
    public private(set) var fadingItems: [AnnotationItem] = []
    /// 当前正在拖拽中的矩形草稿
    public var activeDraft: RectangleAnnotation?

    private var undoStack: [[AnnotationItem]] = []
    private var redoStack: [[AnnotationItem]] = []
    private let maxUndoDepth: Int

    public init(maxUndoDepth: Int = 50) {
        self.maxUndoDepth = maxUndoDepth
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var hasPersistentItems: Bool { !persistentItems.isEmpty }
    public var hasFadingItems: Bool { !fadingItems.isEmpty }
    public var hasVisibleContent: Bool {
        !persistentItems.isEmpty || !fadingItems.isEmpty || activeDraft != nil
    }

    /// 提交一个标注（根据当前停留模式决定进入停留队列还是自动淡出队列）
    public func commit(
        payload: AnnotationItem.Payload,
        retentionMode: RetentionMode,
        now: TimeInterval,
        holdDuration: TimeInterval,
        fadeDuration: TimeInterval = 0.75
    ) {
        activeDraft = nil
        switch retentionMode {
        case .autoFade:
            let item = AnnotationItem(
                payload: payload,
                createdAt: now,
                holdDuration: holdDuration,
                fadeDuration: fadeDuration
            )
            fadingItems.append(item)

        case .persistent:
            pushUndoSnapshot()
            let item = AnnotationItem(payload: payload, createdAt: nil)
            persistentItems.append(item)
        }
    }

    /// 清理所有已完全淡出的临时标注，返回是否仍有存活的淡出标注
    @discardableResult
    public func pruneExpired(at now: TimeInterval) -> Bool {
        fadingItems.removeAll { $0.isExpired(at: now) }
        return !fadingItems.isEmpty
    }

    /// 清空全部标注（停留标注支持撤销恢复）
    public func clearAll() {
        if !persistentItems.isEmpty {
            pushUndoSnapshot()
            persistentItems.removeAll()
        }
        fadingItems.removeAll()
        activeDraft = nil
    }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(persistentItems)
        persistentItems = previous
        activeDraft = nil
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(persistentItems)
        persistentItems = next
        activeDraft = nil
        return true
    }

    private func pushUndoSnapshot() {
        undoStack.append(persistentItems)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
        redoStack.removeAll()
    }
}
