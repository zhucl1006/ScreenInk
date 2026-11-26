import AppKit
import ScreenInkCore
import SwiftUI

/// 可选的极简浮动工具栏（仅在通过菜单/快捷键显式开启工具栏时显示）
@MainActor
final class FloatingToolbarPanel: NSPanel {
    private let hostingView: NSHostingView<FloatingToolbarView>

    init(
        session: AppSession,
        onClear: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onExitAnnotating: @escaping () -> Void
    ) {
        let rootView = FloatingToolbarView(
            session: session,
            onClear: onClear,
            onOpenSettings: onOpenSettings,
            onExitAnnotating: onExitAnnotating
        )
        self.hostingView = NSHostingView(rootView: rootView)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = hostingView
        fitToContent(recenterOn: NSScreen.main)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fitToContent(recenterOn screen: NSScreen? = nil) {
        hostingView.layoutSubtreeIfNeeded()
        let idealSize = hostingView.fittingSize

        if let targetScreen = screen {
            let visible = targetScreen.visibleFrame
            let x = visible.midX - idealSize.width * 0.5
            let y = visible.minY + 34
            setFrame(NSRect(origin: NSPoint(x: x, y: y), size: idealSize), display: true)
        } else {
            let deltaW = idealSize.width - frame.width
            let newOrigin = NSPoint(x: frame.origin.x - deltaW * 0.5, y: frame.origin.y)
            setFrame(NSRect(origin: newOrigin, size: idealSize), display: true)
        }
    }
}

struct FloatingToolbarView: View {
    @ObservedObject var session: AppSession
    let onClear: () -> Void
    let onOpenSettings: () -> Void
    let onExitAnnotating: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 仅保留：矩形 / 文字
            HStack(spacing: 3) {
                ForEach(AnnotationTool.allCases) { tool in
                    toolButton(tool)
                }
            }

            divider

            // 颜色快速切换
            HStack(spacing: 5) {
                ForEach(RGBAColor.presets, id: \.id) { preset in
                    colorDot(preset.color, name: preset.name)
                }
            }

            divider

            // 自动淡出 / 停留模式一键切换
            Button {
                session.preferences.retentionMode = session.preferences.retentionMode.toggled
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: session.preferences.retentionMode.symbolName)
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(session.preferences.retentionMode.shortName)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        session.preferences.retentionMode == .autoFade
                            ? Color.accentColor.opacity(0.18)
                            : Color.orange.opacity(0.22)
                    )
                )
                .foregroundStyle(
                    session.preferences.retentionMode == .autoFade ? Color.accentColor : Color.orange
                )
            }
            .buttonStyle(.plain)
            .help("切换自动淡出 / 停留模式 (F)")

            if session.hasPersistentContent || session.preferences.retentionMode == .persistent {
                iconButton(
                    systemName: "trash",
                    isEnabled: session.hasPersistentContent,
                    help: "清除停留标注 (⌥C)",
                    action: onClear
                )
            }

            divider

            iconButton(systemName: "gearshape", help: "偏好设置 (⌘,)", action: onOpenSettings)
            iconButton(systemName: "xmark.circle.fill", help: "退出批注 (Esc / ⌥A)", action: onExitAnnotating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 12, y: 5)
        .fixedSize()
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = session.selectedTool == tool
        return Button {
            session.selectedTool = tool
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(tool.shortName)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help("\(tool.displayName) (\(tool.shortcutHint))")
    }

    private func colorDot(_ color: RGBAColor, name: String) -> some View {
        let isSelected = session.preferences.highlightColor == color
        return Button {
            session.preferences.highlightColor = color
        } label: {
            Circle()
                .fill(Color(red: color.r, green: color.g, blue: color.b))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.7))
                .padding(2)
                .overlay(
                    Circle().strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.8)
                )
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func iconButton(
        systemName: String,
        isEnabled: Bool = true,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 18)
    }
}
