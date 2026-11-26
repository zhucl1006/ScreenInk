import Combine
import Foundation
import ScreenInkCore

/// 全局运行时状态与持久化偏好
@MainActor
final class AppSession: ObservableObject {
    @Published var phase: AnnotationPhase = .idle
    @Published var selectedTool: AnnotationTool = .rectangle
    @Published var isToolbarVisible: Bool = false
    @Published var isCursorHighlightEnabled: Bool = false

    @Published var preferences: AppPreferences {
        didSet {
            PreferencesStore.save(preferences)
        }
    }

    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var hasPersistentContent: Bool = false
    /// 当前是否正在偏好设置中录制快捷键（录制期间暂停全局热键拦截）
    @Published var isRecordingShortcut: Bool = false
    /// 全局热键注册失败（被系统或其他应用占用）的动作集合
    @Published var hotKeyRegistrationFailures: Set<ShortcutAction> = []

    init(preferences: AppPreferences = PreferencesStore.load()) {
        self.preferences = preferences
    }
}
