import CoreGraphics
import Foundation

/// 用户偏好持久化配置（默认：无工具栏启动、自动淡出模式、醒目红高亮）
public struct AppPreferences: Codable, Equatable, Sendable {
    public var highlightColor: RGBAColor
    public var lineWidth: CGFloat
    public var cornerRadius: CGFloat
    public var fillRectangleHighlight: Bool
    public var retentionMode: RetentionMode
    public var autoFadeHoldSeconds: Double
    public var autoFadeDurationSeconds: Double
    /// 通过默认快捷键激活时是否显示工具栏（默认 false：无工具栏纯净启动）
    public var showToolbarOnActivate: Bool
    /// 光标高亮光环参数
    public var cursorHighlightDiameter: CGFloat
    public var cursorHighlightOpacity: Double
    public var cursorFollowAnnotationColor: Bool
    public var cursorCustomColor: RGBAColor
    public var cursorClickRipple: Bool

    public static let `default` = AppPreferences(
        highlightColor: .red,
        lineWidth: 4.5,
        cornerRadius: 8.0,
        fillRectangleHighlight: true,
        retentionMode: .autoFade,
        autoFadeHoldSeconds: 2.0,
        autoFadeDurationSeconds: 0.75,
        showToolbarOnActivate: false,
        cursorHighlightDiameter: 68.0,
        cursorHighlightOpacity: 0.45,
        cursorFollowAnnotationColor: true,
        cursorCustomColor: .yellow,
        cursorClickRipple: true
    )

    public var effectiveCursorColor: RGBAColor {
        cursorFollowAnnotationColor ? highlightColor : cursorCustomColor
    }
}

public enum PreferencesStore {
    private static let storageKey = "com.screenink.preferences.v1"

    public static func load(from defaults: UserDefaults = .standard) -> AppPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    public static func save(_ preferences: AppPreferences, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
