import AppKit
import Combine
import ScreenInkCore

/// 应用主控制器：菜单栏常驻、两种启动方式、多屏画布、Highlight Cursor 与全局快捷键
@MainActor
final class AppController: NSObject, NSApplicationDelegate, CanvasViewDelegate {
    private let session = AppSession()
    private var statusItem: NSStatusItem!
    private var hotKeyManager: GlobalHotKeyManager!
    private var toolbarPanel: FloatingToolbarPanel!
    private var cursorHighlightController: CursorHighlightController!
    private var settingsWindowController: SettingsWindowController?

    private var overlays: [CGDirectDisplayID: OverlayPanel] = [:]
    private var canvasStates: [CGDirectDisplayID: CanvasState] = [:]
    private var cancellables: Set<AnyCancellable> = []

    // 动态刷新的菜单项
    private var annotateCleanMenuItem: NSMenuItem?
    private var annotateToolbarMenuItem: NSMenuItem?
    private var highlightCursorMenuItem: NSMenuItem?
    private var showToolbarMenuItem: NSMenuItem?
    private var autoFadeMenuItem: NSMenuItem?
    private var persistentMenuItem: NSMenuItem?
    private var clearMenuItem: NSMenuItem?
    private var colorMenuItems: [(color: RGBAColor, item: NSMenuItem)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        cursorHighlightController = CursorHighlightController(session: session)
        setupToolbar()
        setupStatusItem()
        rebuildOverlayWindows()
        setupHotKeys()
        observeSessionChanges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregisterAll()
        cursorHighlightController?.stop()
        for panel in overlays.values {
            panel.canvasView.stopTimers()
        }
    }

    // MARK: - 菜单栏构建（简洁会议模式风格）

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()

        let cleanItem = NSMenuItem(title: "无工具栏矩形批注", action: #selector(menuAnnotateWithoutControls), keyEquivalent: "1")
        cleanItem.keyEquivalentModifierMask = [.command]
        cleanItem.target = self
        menu.addItem(cleanItem)
        annotateCleanMenuItem = cleanItem

        let withToolbarItem = NSMenuItem(title: "有工具栏矩形批注", action: #selector(menuAnnotateWithControls), keyEquivalent: "2")
        withToolbarItem.keyEquivalentModifierMask = [.command]
        withToolbarItem.target = self
        menu.addItem(withToolbarItem)
        annotateToolbarMenuItem = withToolbarItem

        menu.addItem(.separator())

        let cursorItem = NSMenuItem(title: "点击高亮（脉动光环）", action: #selector(menuToggleHighlightCursor), keyEquivalent: "3")
        cursorItem.keyEquivalentModifierMask = [.command]
        cursorItem.target = self
        menu.addItem(cursorItem)
        highlightCursorMenuItem = cursorItem

        menu.addItem(.separator())

        // 标注停留策略
        let fadeItem = NSMenuItem(title: "自动淡出模式（默认）", action: #selector(menuSelectAutoFade), keyEquivalent: "")
        fadeItem.target = self
        menu.addItem(fadeItem)
        autoFadeMenuItem = fadeItem

        let stayItem = NSMenuItem(title: "停留模式（手动清除）", action: #selector(menuSelectPersistent), keyEquivalent: "")
        stayItem.target = self
        menu.addItem(stayItem)
        persistentMenuItem = stayItem

        // 颜色选择子菜单
        let colorParent = NSMenuItem(title: "高亮颜色", action: nil, keyEquivalent: "")
        let colorSubmenu = NSMenu()
        colorMenuItems.removeAll()
        for (idx, preset) in RGBAColor.presets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(menuSelectPresetColor(_:)), keyEquivalent: "")
            item.tag = idx
            item.target = self
            item.image = makeColorDotImage(preset.color)
            colorSubmenu.addItem(item)
            colorMenuItems.append((preset.color, item))
        }
        colorSubmenu.addItem(.separator())
        let customColorItem = NSMenuItem(title: "更多颜色设置…", action: #selector(menuOpenSettings), keyEquivalent: "")
        customColorItem.target = self
        colorSubmenu.addItem(customColorItem)
        colorParent.submenu = colorSubmenu
        menu.addItem(colorParent)

        // 工具栏显示开关
        let toolbarToggle = NSMenuItem(title: "显示浮动工具栏", action: #selector(menuToggleToolbarVisibility), keyEquivalent: "")
        toolbarToggle.target = self
        menu.addItem(toolbarToggle)
        showToolbarMenuItem = toolbarToggle

        // 清空屏幕标注
        let clearItem = NSMenuItem(title: "清空屏幕标注", action: #selector(menuClearAll), keyEquivalent: "c")
        clearItem.keyEquivalentModifierMask = [.option]
        clearItem.target = self
        menu.addItem(clearItem)
        clearMenuItem = clearItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "偏好设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出 ScreenInk", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuState()
    }

    private func makeColorDotImage(_ color: RGBAColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(x: 1, y: 1, width: 10, height: 10)
        NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.black.withAlphaComponent(0.22).setStroke()
        let border = NSBezierPath(ovalIn: rect)
        border.lineWidth = 0.8
        border.stroke()
        image.unlockFocus()
        return image
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        if session.phase == .annotating {
            symbolName = "rectangle.dashed.badge.record"
        } else if session.isCursorHighlightEnabled {
            symbolName = "cursorarrow.rays"
        } else {
            symbolName = "rectangle.dashed"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ScreenInk")
            ?? NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "ScreenInk")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "ScreenInk — ⌘1 无工具栏矩形 | ⌘2 有工具栏矩形 | ⌘3 点击高亮"
    }

    private func updateMenuState() {
        let isAnnotating = session.phase == .annotating
        annotateCleanMenuItem?.state = (isAnnotating && !session.isToolbarVisible) ? .on : .off
        annotateToolbarMenuItem?.state = (isAnnotating && session.isToolbarVisible) ? .on : .off
        highlightCursorMenuItem?.state = session.isCursorHighlightEnabled ? .on : .off

        showToolbarMenuItem?.state = session.isToolbarVisible ? .on : .off
        autoFadeMenuItem?.state = session.preferences.retentionMode == .autoFade ? .on : .off
        persistentMenuItem?.state = session.preferences.retentionMode == .persistent ? .on : .off

        for entry in colorMenuItems {
            entry.item.state = (entry.color == session.preferences.highlightColor) ? .on : .off
        }

        let hasContent = canvasStates.values.contains { $0.hasVisibleContent }
        clearMenuItem?.isEnabled = hasContent
    }

    // MARK: - 组件初始化

    private func setupToolbar() {
        toolbarPanel = FloatingToolbarPanel(
            session: session,
            onClear: { [weak self] in self?.clearAllCanvases() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onExitAnnotating: { [weak self] in self?.exitAnnotating() }
        )
    }

    private func rebuildOverlayWindows() {
        let screens = NSScreen.screens
        var aliveIDs = Set<CGDirectDisplayID>()

        for screen in screens {
            guard let displayID = screen.displayID else { continue }
            aliveIDs.insert(displayID)

            let state = canvasStates[displayID] ?? CanvasState()
            canvasStates[displayID] = state

            if let existing = overlays[displayID] {
                existing.updateFrame(for: screen)
            } else {
                let panel = OverlayPanel(screen: screen, session: session, state: state, delegate: self)
                overlays[displayID] = panel
            }
        }

        for (id, panel) in overlays where !aliveIDs.contains(id) {
            panel.canvasView.stopTimers()
            panel.orderOut(nil)
            overlays.removeValue(forKey: id)
            canvasStates.removeValue(forKey: id)
        }

        applyWindowStates()
    }

    private func setupHotKeys() {
        hotKeyManager = GlobalHotKeyManager { [weak self] action in
            self?.handleGlobalHotKey(action)
        }
        hotKeyManager.registerAll()
    }

    private func observeSessionChanges() {
        session.$preferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.cursorHighlightController.refreshAppearance()
                self.updateMenuState()
                self.refreshAllCanvases()
            }
            .store(in: &cancellables)

        session.$selectedTool
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAllCanvases()
            }
            .store(in: &cancellables)

        session.$isCursorHighlightEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.cursorHighlightController.setEnabled(enabled)
                self.updateStatusIcon()
                self.updateMenuState()
            }
            .store(in: &cancellables)
    }

    // MARK: - 两种启动方式与模式状态机

    private func startAnnotating(showToolbar: Bool, tool: AnnotationTool = .rectangle) {
        session.selectedTool = tool
        session.isToolbarVisible = showToolbar
        session.phase = .annotating
        applyWindowStates()
        updateStatusIcon()
        updateMenuState()
    }

    private func exitAnnotating() {
        for panel in overlays.values {
            panel.canvasView.commitInlineTextIfNeeded()
        }
        session.isToolbarVisible = false

        let hasAnyVisible = canvasStates.values.contains { $0.hasVisibleContent }
        session.phase = hasAnyVisible ? .passthrough : .idle
        applyWindowStates()
        updateStatusIcon()
        updateMenuState()
    }

    private func applyWindowStates() {
        switch session.phase {
        case .idle:
            for panel in overlays.values {
                panel.ignoresMouseEvents = true
                panel.orderOut(nil)
            }
            toolbarPanel.orderOut(nil)

        case .annotating:
            let activeScreen = screenContainingMouse() ?? NSScreen.main
            for panel in overlays.values {
                panel.ignoresMouseEvents = false
                panel.orderFrontRegardless()
                panel.invalidateCursorRects(for: panel.canvasView)
                panel.canvasView.needsDisplay = true
            }
            if let screenID = activeScreen?.displayID, let activePanel = overlays[screenID] {
                activePanel.makeKey()
                activePanel.makeFirstResponder(activePanel.canvasView)
            }
            if session.isToolbarVisible {
                toolbarPanel.fitToContent(recenterOn: toolbarPanel.isVisible ? nil : activeScreen)
                toolbarPanel.orderFrontRegardless()
            } else {
                toolbarPanel.orderOut(nil)
            }

        case .passthrough:
            for panel in overlays.values {
                panel.ignoresMouseEvents = true
                panel.orderFrontRegardless()
                panel.canvasView.needsDisplay = true
            }
            toolbarPanel.orderOut(nil)
        }
    }

    private func handleGlobalHotKey(_ action: GlobalHotKeyAction) {
        switch action {
        case .toggleAnnotateClean:
            if session.phase == .annotating {
                if session.selectedTool != .rectangle {
                    session.selectedTool = .rectangle
                } else {
                    exitAnnotating()
                }
            } else {
                startAnnotating(showToolbar: session.preferences.showToolbarOnActivate, tool: .rectangle)
            }

        case .toggleAnnotateWithToolbar:
            if session.phase == .annotating && session.isToolbarVisible {
                if session.selectedTool != .rectangle {
                    session.selectedTool = .rectangle
                } else {
                    exitAnnotating()
                }
            } else {
                startAnnotating(showToolbar: true, tool: .rectangle)
            }

        case .toggleClickHighlight:
            session.isCursorHighlightEnabled.toggle()

        case .clearAnnotations:
            clearAllCanvases()
        }
    }

    private func clearAllCanvases() {
        for panel in overlays.values {
            panel.canvasView.commitInlineTextIfNeeded()
        }
        for state in canvasStates.values {
            state.clearAll()
        }
        if session.phase == .passthrough {
            session.phase = .idle
            applyWindowStates()
        } else {
            refreshAllCanvases()
        }
        syncContentState()
    }

    private func openSettings() {
        if session.phase == .annotating {
            exitAnnotating()
        }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(session: session)
        }
        settingsWindowController?.showAndActivate()
    }

    private func refreshAllCanvases() {
        for panel in overlays.values {
            panel.invalidateCursorRects(for: panel.canvasView)
            panel.canvasView.needsDisplay = true
        }
    }

    private func syncContentState() {
        session.canUndo = canvasStates.values.contains { $0.canUndo }
        session.canRedo = canvasStates.values.contains { $0.canRedo }
        session.hasPersistentContent = canvasStates.values.contains { $0.hasPersistentItems }
        updateMenuState()
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    // MARK: - CanvasViewDelegate

    func canvasDidRequestExitAnnotating(_ canvasView: CanvasView) {
        exitAnnotating()
    }

    func canvasDidChangeContentState(_ canvasView: CanvasView) {
        syncContentState()
    }

    func canvasDidFinishAllFading(_ canvasView: CanvasView) {
        syncContentState()
        // 如果已处于穿透等待态，且所有屏幕上的自动淡出标注都已消失、也没有停留标注，则自动完全收起窗口
        if session.phase == .passthrough {
            let stillHasVisible = canvasStates.values.contains { $0.hasVisibleContent }
            if !stillHasVisible {
                session.phase = .idle
                applyWindowStates()
                updateStatusIcon()
            }
        }
    }

    func canvasDidSelectTool(_ tool: AnnotationTool) {
        session.selectedTool = tool
    }

    func canvasDidToggleRetentionMode() {
        session.preferences.retentionMode = session.preferences.retentionMode.toggled
    }

    func canvasDidRequestClearAll() {
        clearAllCanvases()
    }

    // MARK: - 菜单响应

    @objc private func menuAnnotateWithoutControls() {
        if session.phase == .annotating && !session.isToolbarVisible {
            exitAnnotating()
        } else {
            startAnnotating(showToolbar: false, tool: .rectangle)
        }
    }

    @objc private func menuAnnotateWithControls() {
        if session.phase == .annotating && session.isToolbarVisible {
            exitAnnotating()
        } else {
            startAnnotating(showToolbar: true, tool: .rectangle)
        }
    }

    @objc private func menuToggleHighlightCursor() {
        session.isCursorHighlightEnabled.toggle()
    }

    @objc private func menuSelectAutoFade() {
        session.preferences.retentionMode = .autoFade
    }

    @objc private func menuSelectPersistent() {
        session.preferences.retentionMode = .persistent
    }

    @objc private func menuSelectPresetColor(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0 && idx < RGBAColor.presets.count else { return }
        session.preferences.highlightColor = RGBAColor.presets[idx].color
    }

    @objc private func menuToggleToolbarVisibility() {
        if session.phase == .annotating {
            session.isToolbarVisible.toggle()
            applyWindowStates()
            updateMenuState()
        } else {
            startAnnotating(showToolbar: true, tool: session.selectedTool)
        }
    }

    @objc private func menuClearAll() {
        clearAllCanvases()
    }

    @objc private func menuOpenSettings() {
        openSettings()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    @objc private func handleScreenParametersChanged() {
        rebuildOverlayWindows()
        cursorHighlightController.rebuildPanels()
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
