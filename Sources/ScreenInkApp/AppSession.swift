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

    init(preferences: AppPreferences = PreferencesStore.load()) {
        self.preferences = preferences
    }
}
