import AppKit
import ScreenInkCore
import SwiftUI

/// 原生 macOS 偏好设置窗口
@MainActor
final class SettingsWindowController: NSWindowController {
    init(session: AppSession) {
        let view = SettingsView(session: session)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ScreenInk 偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 470, height: 520))
        window.center()
        super.init(window: window)
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
}

struct SettingsView: View {
    @ObservedObject var session: AppSession

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
                Toggle("默认快捷键 (⌥A) 启动时显示工具栏", isOn: $session.preferences.showToolbarOnActivate)
            }

            Section("光标高亮（Highlight Cursor）") {
                HStack {
                    Text("光环直径")
                    Slider(value: $session.preferences.cursorHighlightDiameter, in: 28...110, step: 2)
                    Text("\(Int(session.preferences.cursorHighlightDiameter)) px")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                HStack {
                    Text("光环透明度")
                    Slider(value: $session.preferences.cursorHighlightOpacity, in: 0.12...0.75, step: 0.05)
                    Text("\(Int(session.preferences.cursorHighlightOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }

                Toggle("光标颜色跟随高亮标注颜色", isOn: $session.preferences.cursorFollowAnnotationColor)

                if !session.preferences.cursorFollowAnnotationColor {
                    ColorPicker("光标独立高亮颜色", selection: cursorCustomColorBinding, supportsOpacity: false)
                }

                Toggle("鼠标点击时显示涟漪脉冲动画", isOn: $session.preferences.cursorClickRipple)
            }

            Section("快捷键速查") {
                shortcutRow("矩形批注（无工具栏）", "⌥ A")
                shortcutRow("带工具栏批注", "⌥ ⇧ A")
                shortcutRow("光标高亮 Highlight Cursor", "⌥ S")
                shortcutRow("清除停留标注", "⌥ C")
                shortcutRow("批注内切换：矩形 / 文字 / 自动淡出", "R / T / F")
                shortcutRow("退出批注模式", "Esc")
            }
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 520)
    }

    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
        }
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
