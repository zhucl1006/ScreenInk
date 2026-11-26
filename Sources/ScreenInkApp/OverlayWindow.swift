import AppKit
import ScreenInkCore

@MainActor
protocol CanvasViewDelegate: AnyObject {
    func canvasDidRequestExitAnnotating(_ canvasView: CanvasView)
    func canvasDidChangeContentState(_ canvasView: CanvasView)
    func canvasDidFinishAllFading(_ canvasView: CanvasView)
    func canvasDidSelectTool(_ tool: AnnotationTool)
    func canvasDidToggleRetentionMode()
    func canvasDidRequestClearAll()
}

/// 置顶全屏透明标注窗口（覆盖全屏应用与多 Space）
@MainActor
final class OverlayPanel: NSPanel {
    let canvasView: CanvasView

    init(screen: NSScreen, session: AppSession, state: CanvasState, delegate: CanvasViewDelegate) {
        self.canvasView = CanvasView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            session: session,
            state: state
        )
        self.canvasView.delegate = delegate

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = canvasView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func updateFrame(for screen: NSScreen) {
        setFrame(screen.frame, display: true)
        canvasView.frame = CGRect(origin: .zero, size: screen.frame.size)
        canvasView.needsDisplay = true
    }
}

/// 极简会议批注画布：仅支持矩形高亮框与内联文字标注，默认自动淡出
@MainActor
final class CanvasView: NSView {
    let session: AppSession
    let state: CanvasState
    weak var delegate: CanvasViewDelegate?

    private var dragStartPoint: CGPoint?
    private var fadeTimer: Timer?
    private var inlineTextView: InlineAnnotationTextView?
    private var inlineTextOrigin: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: CGRect, session: AppSession, state: CanvasState) {
        self.session = session
        self.state = state
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 渲染

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        CanvasRenderer.render(
            state: state,
            in: ctx,
            bounds: bounds,
            now: ProcessInfo.processInfo.systemUptime
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard session.phase == .annotating else { return }
        let cursor: NSCursor = session.selectedTool == .text ? .iBeam : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - 鼠标交互

    override func mouseDown(with event: NSEvent) {
        guard session.phase == .annotating else { return }
        window?.makeKey()
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)

        if inlineTextView != nil {
            commitInlineText()
            if session.selectedTool != .text {
                return
            }
        }

        switch session.selectedTool {
        case .rectangle:
            dragStartPoint = point
            state.activeDraft = RectangleAnnotation(
                start: point,
                end: point,
                color: session.preferences.highlightColor,
                lineWidth: session.preferences.lineWidth,
                cornerRadius: session.preferences.cornerRadius,
                fillHighlight: session.preferences.fillRectangleHighlight
            )
            needsDisplay = true

        case .text:
            beginInlineText(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard session.phase == .annotating, session.selectedTool == .rectangle else { return }
        guard let start = dragStartPoint else { return }
        let rawEnd = convert(event.locationInWindow, from: nil)
        let end = event.modifierFlags.contains(.shift)
            ? GeometryHelpers.constrainSquareEndPoint(start: start, end: rawEnd)
            : rawEnd

        state.activeDraft = RectangleAnnotation(
            start: start,
            end: end,
            color: session.preferences.highlightColor,
            lineWidth: session.preferences.lineWidth,
            cornerRadius: session.preferences.cornerRadius,
            fillHighlight: session.preferences.fillRectangleHighlight
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard session.phase == .annotating, session.selectedTool == .rectangle else { return }
        defer {
            dragStartPoint = nil
            needsDisplay = true
        }

        guard let draft = state.activeDraft else { return }
        let rect = draft.normalizedRect
        if rect.width >= 6.0 || rect.height >= 6.0 {
            let prefs = session.preferences
            state.commit(
                payload: .rectangle(draft),
                retentionMode: prefs.retentionMode,
                now: ProcessInfo.processInfo.systemUptime,
                holdDuration: prefs.autoFadeHoldSeconds,
                fadeDuration: prefs.autoFadeDurationSeconds
            )
            if prefs.retentionMode == .autoFade {
                ensureFadeTimerRunning()
            }
            delegate?.canvasDidChangeContentState(self)
        } else {
            state.activeDraft = nil
        }
    }

    // MARK: - 键盘快捷键（批注模式下）

    override func keyDown(with event: NSEvent) {
        let input = KeyShortcut(event: event)

        // Esc：固定用于取消文字输入或退出批注
        if input.keyCode == KeyCodeTable.escape && input.modifiers.isEmpty {
            if inlineTextView != nil {
                cancelInlineText()
            } else {
                delegate?.canvasDidRequestExitAnnotating(self)
            }
            return
        }

        // ⌘Z / ⇧⌘Z：固定用于撤销与重做
        if input.keyCode == KeyCodeTable.z && (input.modifiers == .command || input.modifiers == [.command, .shift]) {
            let changed = input.modifiers.contains(.shift) ? state.redo() : state.undo()
            if changed {
                delegate?.canvasDidChangeContentState(self)
                needsDisplay = true
            }
            return
        }

        // 优先匹配用户自定义的批注内快捷键
        let shortcuts = session.preferences.shortcuts
        if let matchedAction = shortcuts.matchingCanvasAction(for: input) {
            switch matchedAction {
            case .selectRectangle:
                delegate?.canvasDidSelectTool(.rectangle)
            case .selectText:
                delegate?.canvasDidSelectTool(.text)
            case .toggleRetentionMode:
                delegate?.canvasDidToggleRetentionMode()
            default:
                break
            }
            return
        }

        // 清空屏幕标注快捷键在画布内兜底触发（即使全局注册被系统占用也能在批注内使用）
        if shortcuts.clearAnnotations == input || (input.keyCode == KeyCodeTable.k && input.modifiers == .command) {
            delegate?.canvasDidRequestClearAll()
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - 内联文字标注

    func commitInlineTextIfNeeded() {
        if inlineTextView != nil {
            commitInlineText()
        }
    }

    private func beginInlineText(at point: CGPoint) {
        cancelInlineText()

        let fontSize = max(20.0, session.preferences.lineWidth * 3.6 + 10.0)
        let textView = InlineAnnotationTextView(
            frame: CGRect(x: point.x, y: point.y, width: 320, height: fontSize * 2.1)
        )
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let color = session.preferences.highlightColor
        textView.textColor = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1.0)
        textView.insertionPointColor = textView.textColor ?? .white
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.80)
        textView.wantsLayer = true
        textView.layer?.cornerRadius = 8
        textView.layer?.borderWidth = 1.2
        textView.layer?.borderColor = color.withAlpha(0.7).cgColor
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        textView.onCommit = { [weak self] in
            self?.commitInlineText()
        }
        textView.onCancel = { [weak self] in
            self?.cancelInlineText()
        }

        addSubview(textView)
        inlineTextView = textView
        inlineTextOrigin = point

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(textView)
    }

    private func commitInlineText() {
        guard let textView = inlineTextView, let origin = inlineTextOrigin else { return }
        let rawText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let fontSize = textView.font?.pointSize ?? 24.0

        textView.removeFromSuperview()
        inlineTextView = nil
        inlineTextOrigin = nil

        if !rawText.isEmpty {
            let prefs = session.preferences
            let textAnnotation = TextAnnotation(
                text: rawText,
                origin: CGPoint(x: origin.x + 8, y: origin.y + 6),
                color: prefs.highlightColor,
                fontSize: fontSize
            )
            state.commit(
                payload: .text(textAnnotation),
                retentionMode: prefs.retentionMode,
                now: ProcessInfo.processInfo.systemUptime,
                holdDuration: prefs.autoFadeHoldSeconds,
                fadeDuration: prefs.autoFadeDurationSeconds
            )
            if prefs.retentionMode == .autoFade {
                ensureFadeTimerRunning()
            }
            delegate?.canvasDidChangeContentState(self)
        }

        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelInlineText() {
        inlineTextView?.removeFromSuperview()
        inlineTextView = nil
        inlineTextOrigin = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - 自动淡出驱动定时器

    private func ensureFadeTimerRunning() {
        guard fadeTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickFade()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func tickFade() {
        let now = ProcessInfo.processInfo.systemUptime
        let hasMoreFading = state.pruneExpired(at: now)
        needsDisplay = true
        if !hasMoreFading {
            fadeTimer?.invalidate()
            fadeTimer = nil
            delegate?.canvasDidFinishAllFading(self)
        }
    }

    func stopTimers() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }
}

/// 支持 Enter 提交、Shift+Enter 换行、Esc 取消的内联输入框
@MainActor
private final class InlineAnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if (event.keyCode == 36 || event.keyCode == 76) && !hasMarkedText() {
            if !event.modifierFlags.contains(.shift) {
                onCommit?()
                return
            }
        }
        super.keyDown(with: event)
    }
}
