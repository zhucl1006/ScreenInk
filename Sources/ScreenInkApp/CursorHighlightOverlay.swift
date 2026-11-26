import AppKit
import ScreenInkCore

/// 全局点击高亮控制器（Click Highlight）：
/// 平时不显示任何光标遮挡；仅在鼠标左/右键点击瞬间，在点击位置弹出高亮光环并脉动扩散后自动消失。
/// 基于 NSEvent.pressedMouseButtons + NSEvent.mouseLocation，无需辅助功能权限，全屏应用 100% 生效。
@MainActor
final class CursorHighlightController {
    private let session: AppSession
    private var ripplePanels: [CGDirectDisplayID: ClickRipplePanel] = [:]
    private var pollingTimer: Timer?
    private var previousMouseButtons: Int = 0
    private var isEnabled: Bool = false

    init(session: AppSession) {
        self.session = session
        rebuildPanels()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func rebuildPanels() {
        let screens = NSScreen.screens
        var aliveIDs = Set<CGDirectDisplayID>()

        for screen in screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            aliveIDs.insert(id)
            if let existing = ripplePanels[id] {
                existing.updateFrame(for: screen)
            } else {
                ripplePanels[id] = ClickRipplePanel(screen: screen)
            }
        }

        for (id, panel) in ripplePanels where !aliveIDs.contains(id) {
            panel.orderOut(nil)
            ripplePanels.removeValue(forKey: id)
        }
    }

    func refreshAppearance() {
        // 新点击会即时读取最新的颜色、直径和透明度配置
    }

    private func start() {
        rebuildPanels()
        previousMouseButtons = NSEvent.pressedMouseButtons

        guard pollingTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        previousMouseButtons = 0
        for panel in ripplePanels.values {
            panel.clearAndHide()
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let buttons = NSEvent.pressedMouseButtons
        let isPressed = buttons != 0
        let wasPressed = previousMouseButtons != 0
        previousMouseButtons = buttons

        // 检测按键按下的上升沿：在当前鼠标位置触发一次脉动光环
        if isPressed && !wasPressed {
            spawnClickPulse(atGlobalPoint: NSEvent.mouseLocation, now: now)
        }

        // 推进所有屏幕上的脉动动画；动画播完自动隐藏面板
        for panel in ripplePanels.values {
            panel.tick(now: now)
        }
    }

    private func spawnClickPulse(atGlobalPoint globalPoint: NSPoint, now: TimeInterval) {
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(globalPoint) }),
              let displayID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let panel = ripplePanels[displayID]
        else {
            return
        }

        let localPoint = CGPoint(
            x: globalPoint.x - targetScreen.frame.origin.x,
            y: globalPoint.y - targetScreen.frame.origin.y
        )
        let prefs = session.preferences
        panel.addPulse(
            ClickPulse(
                center: localPoint,
                startTime: now,
                color: prefs.effectiveCursorColor,
                diameter: prefs.cursorHighlightDiameter,
                opacity: prefs.cursorHighlightOpacity
            )
        )
    }
}

private struct ClickPulse {
    let center: CGPoint
    let startTime: TimeInterval
    let color: RGBAColor
    let diameter: CGFloat
    let opacity: Double

    static let duration: TimeInterval = 0.56
}

/// 单屏透明点击穿透面板：无动画时保持隐藏，有点击脉动时显示并绘制光环
@MainActor
private final class ClickRipplePanel: NSPanel {
    private let rippleView: ClickRippleView

    init(screen: NSScreen) {
        self.rippleView = ClickRippleView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = rippleView
    }

    func updateFrame(for screen: NSScreen) {
        setFrame(screen.frame, display: false)
        rippleView.frame = CGRect(origin: .zero, size: screen.frame.size)
    }

    func addPulse(_ pulse: ClickPulse) {
        rippleView.addPulse(pulse)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func tick(now: TimeInterval) {
        let hasActive = rippleView.tick(now: now)
        if !hasActive && isVisible {
            orderOut(nil)
        }
    }

    func clearAndHide() {
        rippleView.clear()
        orderOut(nil)
    }
}

/// 负责绘制点击瞬间的脉动光环（柔和光晕 + 清晰外环 + 扩散波纹，脉动后平滑消失）
@MainActor
private final class ClickRippleView: NSView {
    private var pulses: [ClickPulse] = []
    private var currentTime: TimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addPulse(_ pulse: ClickPulse) {
        currentTime = pulse.startTime
        pulses.append(pulse)
        needsDisplay = true
    }

    @discardableResult
    func tick(now: TimeInterval) -> Bool {
        guard !pulses.isEmpty else { return false }
        currentTime = now
        pulses.removeAll { now - $0.startTime >= ClickPulse.duration }
        needsDisplay = true
        return !pulses.isEmpty
    }

    func clear() {
        pulses.removeAll()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !pulses.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        for pulse in pulses {
            let progress = max(0.0, min(1.0, (currentTime - pulse.startTime) / ClickPulse.duration))
            let easeOutCubic = 1.0 - pow(1.0 - progress, 3.0)
            let fadeOut = pow(1.0 - progress, 1.55)

            let baseRadius = pulse.diameter * 0.5

            // 1. 中心柔和光晕（前段瞬间亮起，随后迅速收缩淡出）
            let innerRadius = baseRadius * CGFloat(0.45 + 0.55 * easeOutCubic)
            let innerAlpha = CGFloat(pulse.opacity) * CGFloat(fadeOut)
            let innerRect = CGRect(
                x: pulse.center.x - innerRadius,
                y: pulse.center.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            )
            ctx.setFillColor(pulse.color.withAlpha(innerAlpha).cgColor)
            ctx.fillEllipse(in: innerRect)

            // 2. 主脉动高亮圆环（向外弹性扩张并渐隐）
            let mainRadius = baseRadius * CGFloat(0.42 + 0.85 * easeOutCubic)
            let mainAlpha = min(0.98, CGFloat(pulse.opacity + 0.50)) * CGFloat(fadeOut)
            let mainRect = CGRect(
                x: pulse.center.x - mainRadius,
                y: pulse.center.y - mainRadius,
                width: mainRadius * 2,
                height: mainRadius * 2
            )
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10, color: pulse.color.withAlpha(mainAlpha * 0.65).cgColor)
            ctx.setStrokeColor(pulse.color.withAlpha(mainAlpha).cgColor)
            ctx.setLineWidth(max(1.4, 3.6 * CGFloat(1.0 - progress * 0.55)))
            ctx.strokeEllipse(in: mainRect)
            ctx.restoreGState()

            // 3. 外圈细腻扩散涟漪
            let outerRadius = baseRadius * CGFloat(0.65 + 1.15 * easeOutCubic)
            let outerAlpha = CGFloat(fadeOut * 0.55)
            let outerRect = CGRect(
                x: pulse.center.x - outerRadius,
                y: pulse.center.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )
            ctx.setStrokeColor(pulse.color.withAlpha(outerAlpha).cgColor)
            ctx.setLineWidth(max(1.0, 2.0 * CGFloat(1.0 - progress * 0.6)))
            ctx.strokeEllipse(in: outerRect)
        }

        ctx.restoreGState()
    }
}
