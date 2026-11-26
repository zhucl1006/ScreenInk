import AppKit
import ScreenInkCore

/// 全局光标高亮控制器（Highlight Cursor）：
/// 使用全透明点击穿透 NSPanel + NSEvent.mouseLocation 实时追踪，无需辅助功能权限，全屏演示 100% 稳定跟随
@MainActor
final class CursorHighlightController {
    private let session: AppSession
    private let panel: NSPanel
    private let haloView: CursorHaloView

    private var trackingTimer: Timer?
    private var previousMouseButtons: Int = 0
    private var lastMouseLocation: NSPoint = .zero
    private let panelExtent: CGFloat = 180.0

    init(session: AppSession) {
        self.session = session
        self.haloView = CursorHaloView(frame: NSRect(x: 0, y: 0, width: panelExtent, height: panelExtent))
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelExtent, height: panelExtent),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = haloView
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func refreshAppearance() {
        haloView.updateStyle(
            color: session.preferences.effectiveCursorColor,
            diameter: session.preferences.cursorHighlightDiameter,
            opacity: session.preferences.cursorHighlightOpacity
        )
    }

    private func start() {
        refreshAppearance()
        previousMouseButtons = NSEvent.pressedMouseButtons
        repositionToCurrentMouse(force: true)
        panel.orderFrontRegardless()

        guard trackingTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        haloView.clearRipples()
        panel.orderOut(nil)
    }

    private func tick() {
        repositionToCurrentMouse(force: false)

        let buttons = NSEvent.pressedMouseButtons
        let isPressed = buttons != 0
        let wasPressed = previousMouseButtons != 0
        previousMouseButtons = buttons

        if isPressed && !wasPressed && session.preferences.cursorClickRipple {
            haloView.triggerClickRipple(at: ProcessInfo.processInfo.systemUptime)
        }
        haloView.setMousePressed(isPressed)
        haloView.tickAnimation(now: ProcessInfo.processInfo.systemUptime)
    }

    private func repositionToCurrentMouse(force: Bool) {
        let loc = NSEvent.mouseLocation
        if force || abs(loc.x - lastMouseLocation.x) > 0.25 || abs(loc.y - lastMouseLocation.y) > 0.25 {
            lastMouseLocation = loc
            let origin = NSPoint(x: loc.x - panelExtent * 0.5, y: loc.y - panelExtent * 0.5)
            panel.setFrameOrigin(origin)
        }
    }
}

/// 绘制柔和光标高亮光环及点击脉冲涟漪
@MainActor
private final class CursorHaloView: NSView {
    private var haloColor: RGBAColor = .red
    private var diameter: CGFloat = 54.0
    private var baseOpacity: Double = 0.35
    private var isMousePressed: Bool = false
    private var rippleStartTimes: [TimeInterval] = []
    private var currentTime: TimeInterval = 0

    private let rippleDuration: TimeInterval = 0.42

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateStyle(color: RGBAColor, diameter: CGFloat, opacity: Double) {
        self.haloColor = color
        self.diameter = diameter
        self.baseOpacity = opacity
        needsDisplay = true
    }

    func setMousePressed(_ pressed: Bool) {
        if isMousePressed != pressed {
            isMousePressed = pressed
            needsDisplay = true
        }
    }

    func triggerClickRipple(at now: TimeInterval) {
        currentTime = now
        rippleStartTimes.append(now)
        needsDisplay = true
    }

    func clearRipples() {
        rippleStartTimes.removeAll()
        isMousePressed = false
    }

    func tickAnimation(now: TimeInterval) {
        guard !rippleStartTimes.isEmpty else { return }
        currentTime = now
        rippleStartTimes.removeAll { now - $0 >= rippleDuration }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let activeScale: CGFloat = isMousePressed ? 0.86 : 1.0
        let r = diameter * 0.5 * activeScale
        let haloRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)

        // 主光环柔和填充
        ctx.setFillColor(haloColor.withAlpha(CGFloat(baseOpacity)).cgColor)
        ctx.fillEllipse(in: haloRect)

        // 主光环高亮清晰外圈
        ctx.setStrokeColor(haloColor.withAlpha(min(0.95, CGFloat(baseOpacity + 0.48))).cgColor)
        ctx.setLineWidth(isMousePressed ? 3.2 : 2.4)
        ctx.strokeEllipse(in: haloRect)

        // 点击涟漪扩散波纹
        for start in rippleStartTimes {
            let progress = max(0.0, min(1.0, (currentTime - start) / rippleDuration))
            let easeOut = 1.0 - pow(1.0 - progress, 3.0)
            let rippleR = (diameter * 0.5) + CGFloat(easeOut) * (diameter * 0.65)
            let alpha = CGFloat(1.0 - progress) * 0.78
            let rippleRect = CGRect(
                x: center.x - rippleR,
                y: center.y - rippleR,
                width: rippleR * 2,
                height: rippleR * 2
            )
            ctx.setStrokeColor(haloColor.withAlpha(alpha).cgColor)
            ctx.setLineWidth(2.6 * CGFloat(1.0 - progress * 0.5))
            ctx.strokeEllipse(in: rippleRect)
        }

        ctx.restoreGState()
    }
}
