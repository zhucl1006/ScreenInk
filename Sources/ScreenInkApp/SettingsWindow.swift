import AppKit
import ScreenInkCore
import SwiftUI

/// 原生 macOS 偏好设置窗口
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let recorder: ShortcutRecorderCoordinator

    init(session: AppSession) {
        let recorder = ShortcutRecorderCoordinator(session: session)
        self.recorder = recorder

        let view = SettingsView(session: session, recorder: recorder)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ScreenInk 偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 530))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndActivate() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stopRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        recorder.stopRecording()
    }
}

/// 快捷键录制协调器：通过 AppKit 本地事件监视器捕获任意组合键（兼容 macOS 13+）
@MainActor
final class ShortcutRecorderCoordinator: ObservableObject {
    @Published private(set) var recordingAction: ShortcutAction?
    @Published private(set) var liveModifiers: KeyModifiers = []
    @Published private(set) var feedbackMessage: String?

    private weak var session: AppSession?
    private var localMonitor: Any?

    init(session: AppSession) {
        self.session = session
    }

    func toggleRecording(for action: ShortcutAction) {
        if recordingAction == action {
            stopRecording()
        } else {
            startRecording(action)
        }
    }

    func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        liveModifiers = []
        feedbackMessage = nil
        session?.isRecordingShortcut = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let eventType = event.type
            let keyCode = UInt32(event.keyCode)
            let modifiers = KeyModifiers(appKitFlags: event.modifierFlags)
            let shouldConsume = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleMonitorEvent(type: eventType, keyCode: keyCode, modifiers: modifiers)
            }
            return shouldConsume ? nil : event
        }
    }

    func stopRecording(keepFeedback: Bool = false) {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        recordingAction = nil
        liveModifiers = []
        if !keepFeedback {
            feedbackMessage = nil
        }
        if session?.isRecordingShortcut == true {
            session?.isRecordingShortcut = false
        }
    }

    func clearShortcut(for action: ShortcutAction) {
        stopRecording()
        session?.preferences.shortcuts[action] = nil
    }

    func resetShortcut(for action: ShortcutAction) {
        stopRecording()
        guard let session else { return }
        let defaultShortcut = action.defaultShortcut
        if let conflict = session.preferences.shortcuts.conflictingAction(for: defaultShortcut, excluding: action) {
            feedbackMessage = "无法恢复默认：\(defaultShortcut.displayString) 已被「\(conflict.displayName)」占用"
            NSSound.beep()
            return
        }
        session.preferences.shortcuts.reset(action)
    }

    func resetAllShortcuts() {
        stopRecording()
        session?.preferences.shortcuts.resetAll()
    }

    /// 返回 true 表示已消费该按键事件（不再向窗口或菜单传递）
    private func handleMonitorEvent(type: NSEvent.EventType, keyCode: UInt32, modifiers: KeyModifiers) -> Bool {
        guard let action = recordingAction, let session else {
            return false
        }

        if type == .flagsChanged {
            liveModifiers = modifiers
            return false
        }

        guard type == .keyDown else {
            return false
        }

        let candidate = KeyShortcut(keyCode: keyCode, modifiers: modifiers)

        // 忽略纯修饰键事件
        if KeyShortcut.isModifierOnlyKeyCode(candidate.keyCode) {
            return true
        }

        // 单独按 Esc：取消当前录制
        if candidate.keyCode == KeyCodeTable.escape && candidate.modifiers.isEmpty {
            stopRecording()
            return true
        }

        // 单独按 Delete / Forward Delete：清除（禁用）当前动作的快捷键
        if (candidate.keyCode == KeyCodeTable.delete || candidate.keyCode == KeyCodeTable.forwardDelete),
           candidate.modifiers.isEmpty {
            session.preferences.shortcuts[action] = nil
            stopRecording()
            return true
        }

        // 校验合法性与跨动作冲突
        if let error = session.preferences.shortcuts.validate(candidate: candidate, for: action) {
            feedbackMessage = error.message
            NSSound.beep()
            return true
        }

        // 保存并立即生效
        session.preferences.shortcuts[action] = candidate
        stopRecording()
        return true
    }
}

private enum SettingsTab: Hashable {
    case general
    case shortcuts
}

struct SettingsView: View {
    @ObservedObject var session: AppSession
    @ObservedObject var recorder: ShortcutRecorderCoordinator
    @State private var selectedTab: SettingsTab = .general

    private var highlightColorBinding: Binding<Color> {
        Binding(
            get: {
                let c = session.preferences.highlightColor
                return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1.0)
            },
            set: { newColor in
                if let rgba = Self.extractRGBAColor(from: newColor) {
                    session.preferences.highlightColor = rgba
                }
            }
        )
    }

    private var cursorCustomColorBinding: Binding<Color> {
        Binding(
            get: {
                let c = session.preferences.cursorCustomColor
                return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1.0)
            },
            set: { newColor in
                if let rgba = Self.extractRGBAColor(from: newColor) {
                    session.preferences.cursorCustomColor = rgba
                }
            }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("通用设置", systemImage: "slider.horizontal.3")
                }
                .tag(SettingsTab.general)

            shortcutsTab
                .tabItem {
                    Label("快捷键", systemImage: "command")
                }
                .tag(SettingsTab.shortcuts)
        }
        .padding(.top, 8)
        .frame(width: 520, height: 530)
        .onChange(of: selectedTab) { _ in
            recorder.stopRecording()
        }
        .onDisappear {
            recorder.stopRecording()
        }
    }

    // MARK: - 通用设置标签页

    private var generalTab: some View {
        Form {
            Section("高亮标注（矩形 & 文字）") {
                HStack(spacing: 8) {
                    Text("预设颜色")
                    Spacer()
                    ForEach(RGBAColor.presets, id: \.id) { preset in
                        Button {
                            session.preferences.highlightColor = preset.color
                        } label: {
                            Circle()
                                .fill(Color(red: preset.color.r, green: preset.color.g, blue: preset.color.b))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().strokeBorder(
                                        session.preferences.highlightColor == preset.color
                                            ? Color.accentColor
                                            : Color.black.opacity(0.2),
                                        lineWidth: session.preferences.highlightColor == preset.color ? 2.2 : 0.8
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                    ColorPicker("", selection: highlightColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }

                Picker("标注保留方式", selection: $session.preferences.retentionMode) {
                    ForEach(RetentionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if session.preferences.retentionMode == .autoFade {
                    HStack {
                        Text("自动淡出停留时长")
                        Slider(value: $session.preferences.autoFadeHoldSeconds, in: 0.5...8.0, step: 0.5)
                        Text(String(format: "%.1f 秒", session.preferences.autoFadeHoldSeconds))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                HStack {
                    Text("矩形边框粗细")
                    Slider(value: $session.preferences.lineWidth, in: 2.0...12.0, step: 0.5)
                    Text(String(format: "%.1f pt", session.preferences.lineWidth))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                Toggle("矩形内部淡色高亮填充", isOn: $session.preferences.fillRectangleHighlight)
                Toggle(
                    "无工具栏批注快捷键 (\(session.preferences.shortcuts.displayString(for: .toggleAnnotateClean))) 启动时显示工具栏",
                    isOn: $session.preferences.showToolbarOnActivate
                )
            }

            Section("点击高亮（Click Highlight · 点击脉动后消失）") {
                HStack {
                    Text("光环基准大小")
                    Slider(value: $session.preferences.cursorHighlightDiameter, in: 36...120, step: 2)
                    Text("\(Int(session.preferences.cursorHighlightDiameter)) px")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                HStack {
                    Text("光环填充透明度")
                    Slider(value: $session.preferences.cursorHighlightOpacity, in: 0.12...0.75, step: 0.05)
                    Text("\(Int(session.preferences.cursorHighlightOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                Toggle("光环颜色跟随高亮标注颜色", isOn: $session.preferences.cursorFollowAnnotationColor)

                if !session.preferences.cursorFollowAnnotationColor {
                    ColorPicker("点击光环独立颜色", selection: cursorCustomColorBinding, supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 自定义快捷键标签页

    private var shortcutsTab: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(ShortcutAction.globalActions) { action in
                        shortcutRecorderRow(for: action)
                    }
                } header: {
                    Text("全局快捷键（任意应用 / 全屏演示中随时生效）")
                } footer: {
                    Text("点击右侧键帽开始录制；需包含 ⌘ / ⌥ / ⌃ 修饰键或使用 F1–F20。录制时按 Esc 取消，按 ⌫ 清除。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(ShortcutAction.canvasActions) { action in
                        shortcutRecorderRow(for: action)
                    }
                } header: {
                    Text("批注内快捷键（批注画布激活时生效）")
                } footer: {
                    Text("固定按键：Esc 退出批注 / 取消输入 · ⌘Z / ⇧⌘Z 撤销与重做 · 拖拽按住 Shift 画正方形")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let banner = activeStatusBanner {
                HStack(spacing: 6) {
                    Image(systemName: banner.isError ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(banner.isError ? .red : .orange)
                    Text(banner.text)
                        .font(.footnote)
                        .foregroundStyle(banner.isError ? .red : .orange)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background((banner.isError ? Color.red : Color.orange).opacity(0.08))
            }

            Divider()

            HStack {
                Text(recorder.recordingAction == nil ? "所有快捷键修改立即生效并自动保存" : "正在录制「\(recorder.recordingAction!.displayName)」…")
                    .font(.footnote)
                    .foregroundStyle(recorder.recordingAction == nil ? Color.secondary : Color.accentColor)
                Spacer()
                Button("恢复全部默认") {
                    recorder.resetAllShortcuts()
                }
                .disabled(session.preferences.shortcuts.isDefault)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    private var activeStatusBanner: (text: String, isError: Bool)? {
        if let message = recorder.feedbackMessage {
            return (message, true)
        }
        if !session.hotKeyRegistrationFailures.isEmpty {
            let names = ShortcutAction.globalActions
                .filter { session.hotKeyRegistrationFailures.contains($0) }
                .map { "「\($0.displayName)」" }
                .joined(separator: "、")
            return ("\(names) 的全局快捷键已被系统或其他应用占用，请更换组合。", false)
        }
        return nil
    }

    private func shortcutRecorderRow(for action: ShortcutAction) -> some View {
        let isRecording = recorder.recordingAction == action
        let currentShortcut = session.preferences.shortcuts[action]
        let isDefault = currentShortcut == action.defaultShortcut
        let hasRegistrationFailure = session.hotKeyRegistrationFailures.contains(action)

        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(action.displayName)
                if hasRegistrationFailure {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help("系统或其他应用已占用此全局快捷键，请点击右侧重新录制")
                }
            }

            Spacer()

            Button {
                recorder.toggleRecording(for: action)
            } label: {
                Text(recorderPillText(isRecording: isRecording, shortcut: currentShortcut))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(recorderPillForeground(isRecording: isRecording, hasShortcut: currentShortcut != nil))
                    .frame(minWidth: 108)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isRecording
                                    ? Color.accentColor
                                    : (hasRegistrationFailure ? Color.orange.opacity(0.75) : Color.secondary.opacity(0.25)),
                                lineWidth: isRecording ? 1.5 : 0.8
                            )
                    )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "按下新的快捷键组合，Esc 取消，⌫ 清除" : "点击录制新的快捷键")

            // 清除按钮
            Button {
                recorder.clearShortcut(for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(currentShortcut != nil && !isRecording ? 0.8 : 0.0)
            .disabled(currentShortcut == nil || isRecording)
            .help("清除此快捷键")

            // 单项恢复默认按钮
            Button {
                recorder.resetShortcut(for: action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(!isDefault && !isRecording ? 0.85 : 0.0)
            .disabled(isDefault || isRecording)
            .help("恢复默认 (\(action.defaultShortcut.displayString))")
        }
    }

    private func recorderPillText(isRecording: Bool, shortcut: KeyShortcut?) -> String {
        if isRecording {
            let mods = recorder.liveModifiers.displaySymbols
            if !mods.isEmpty {
                let spaced = mods.map(String.init).joined(separator: " ")
                return "\(spaced) …"
            }
            return "请按下快捷键…"
        }
        return shortcut?.badgeDisplayString ?? "未设置"
    }

    private func recorderPillForeground(isRecording: Bool, hasShortcut: Bool) -> Color {
        if isRecording { return .accentColor }
        return hasShortcut ? .primary : .secondary
    }

    private static func extractRGBAColor(from color: Color) -> RGBAColor? {
        let nsColor = NSColor(color)
        guard let converted = nsColor.usingColorSpace(.sRGB) else { return nil }
        return RGBAColor(
            r: converted.redComponent,
            g: converted.greenComponent,
            b: converted.blueComponent,
            a: 1.0
        )
    }
}
