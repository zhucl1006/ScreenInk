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
    /// 用户自定义快捷键配置（全局热键 + 批注内快捷键）
    public var shortcuts: ShortcutConfiguration

    public init(
        highlightColor: RGBAColor,
        lineWidth: CGFloat,
        cornerRadius: CGFloat,
        fillRectangleHighlight: Bool,
        retentionMode: RetentionMode,
        autoFadeHoldSeconds: Double,
        autoFadeDurationSeconds: Double,
        showToolbarOnActivate: Bool,
        cursorHighlightDiameter: CGFloat,
        cursorHighlightOpacity: Double,
        cursorFollowAnnotationColor: Bool,
        cursorCustomColor: RGBAColor,
        cursorClickRipple: Bool,
        shortcuts: ShortcutConfiguration = .default
    ) {
        self.highlightColor = highlightColor
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.fillRectangleHighlight = fillRectangleHighlight
        self.retentionMode = retentionMode
        self.autoFadeHoldSeconds = autoFadeHoldSeconds
        self.autoFadeDurationSeconds = autoFadeDurationSeconds
        self.showToolbarOnActivate = showToolbarOnActivate
        self.cursorHighlightDiameter = cursorHighlightDiameter
        self.cursorHighlightOpacity = cursorHighlightOpacity
        self.cursorFollowAnnotationColor = cursorFollowAnnotationColor
        self.cursorCustomColor = cursorCustomColor
        self.cursorClickRipple = cursorClickRipple
        self.shortcuts = shortcuts
    }

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
        cursorClickRipple: true,
        shortcuts: .default
    )

    public var effectiveCursorColor: RGBAColor {
        cursorFollowAnnotationColor ? highlightColor : cursorCustomColor
    }

    private enum CodingKeys: String, CodingKey {
        case highlightColor
        case lineWidth
        case cornerRadius
        case fillRectangleHighlight
        case retentionMode
        case autoFadeHoldSeconds
        case autoFadeDurationSeconds
        case showToolbarOnActivate
        case cursorHighlightDiameter
        case cursorHighlightOpacity
        case cursorFollowAnnotationColor
        case cursorCustomColor
        case cursorClickRipple
        case shortcuts
    }

    /// 兼容旧版偏好 JSON（新增字段缺省回退默认值，不丢失用户历史设置）
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        self.highlightColor = try c.decodeIfPresent(RGBAColor.self, forKey: .highlightColor) ?? d.highlightColor
        self.lineWidth = try c.decodeIfPresent(CGFloat.self, forKey: .lineWidth) ?? d.lineWidth
        self.cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? d.cornerRadius
        self.fillRectangleHighlight = try c.decodeIfPresent(Bool.self, forKey: .fillRectangleHighlight) ?? d.fillRectangleHighlight
        self.retentionMode = try c.decodeIfPresent(RetentionMode.self, forKey: .retentionMode) ?? d.retentionMode
        self.autoFadeHoldSeconds = try c.decodeIfPresent(Double.self, forKey: .autoFadeHoldSeconds) ?? d.autoFadeHoldSeconds
        self.autoFadeDurationSeconds = try c.decodeIfPresent(Double.self, forKey: .autoFadeDurationSeconds) ?? d.autoFadeDurationSeconds
        self.showToolbarOnActivate = try c.decodeIfPresent(Bool.self, forKey: .showToolbarOnActivate) ?? d.showToolbarOnActivate
        self.cursorHighlightDiameter = try c.decodeIfPresent(CGFloat.self, forKey: .cursorHighlightDiameter) ?? d.cursorHighlightDiameter
        self.cursorHighlightOpacity = try c.decodeIfPresent(Double.self, forKey: .cursorHighlightOpacity) ?? d.cursorHighlightOpacity
        self.cursorFollowAnnotationColor = try c.decodeIfPresent(Bool.self, forKey: .cursorFollowAnnotationColor) ?? d.cursorFollowAnnotationColor
        self.cursorCustomColor = try c.decodeIfPresent(RGBAColor.self, forKey: .cursorCustomColor) ?? d.cursorCustomColor
        self.cursorClickRipple = try c.decodeIfPresent(Bool.self, forKey: .cursorClickRipple) ?? d.cursorClickRipple
        self.shortcuts = try c.decodeIfPresent(ShortcutConfiguration.self, forKey: .shortcuts) ?? d.shortcuts
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
