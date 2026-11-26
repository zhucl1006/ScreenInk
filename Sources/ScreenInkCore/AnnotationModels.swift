import CoreGraphics
import Foundation

/// 精简版会议标注工具：仅保留矩形高亮框与文字标注
public enum AnnotationTool: String, CaseIterable, Sendable, Identifiable {
    case rectangle
    case text

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rectangle: return "矩形高亮框"
        case .text: return "文字标注"
        }
    }

    public var shortName: String {
        switch self {
        case .rectangle: return "矩形"
        case .text: return "文字"
        }
    }

    public var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .text: return "textformat"
        }
    }

    public var shortcutHint: String {
        switch self {
        case .rectangle: return "R"
        case .text: return "T"
        }
    }
}

/// 标注停留策略：默认自动淡出，可配置为停留不消失
public enum RetentionMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case autoFade
    case persistent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .autoFade: return "自动淡出模式"
        case .persistent: return "停留模式"
        }
    }

    public var shortName: String {
        switch self {
        case .autoFade: return "自动淡出"
        case .persistent: return "停留"
        }
    }

    public var symbolName: String {
        switch self {
        case .autoFade: return "sparkles"
        case .persistent: return "pin.fill"
        }
    }

    public var toggled: RetentionMode {
        self == .autoFade ? .persistent : .autoFade
    }
}

/// 标注覆盖层所处交互状态
public enum AnnotationPhase: String, Sendable, Equatable {
    /// 完全隐藏（不拦截鼠标，无可见标注）
    case idle
    /// 正在批注（拦截鼠标与快捷键，可画矩形或输入文字）
    case annotating
    /// 穿透展示（鼠标穿透底层应用，保留停留标注或等待自动淡出结束）
    case passthrough
}

/// RGBA 颜色模型（Codable + Sendable，方便持久化）
public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public let r: CGFloat
    public let g: CGFloat
    public let b: CGFloat
    public let a: CGFloat

    public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public func withAlpha(_ alpha: CGFloat) -> RGBAColor {
        RGBAColor(r: r, g: g, b: b, a: max(0, min(1, alpha)))
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    public static let red = RGBAColor(r: 1.00, g: 0.24, b: 0.26)
    public static let orange = RGBAColor(r: 1.00, g: 0.56, b: 0.04)
    public static let yellow = RGBAColor(r: 1.00, g: 0.82, b: 0.05)
    public static let green = RGBAColor(r: 0.16, g: 0.84, b: 0.42)
    public static let blue = RGBAColor(r: 0.08, g: 0.56, b: 1.00)
    public static let purple = RGBAColor(r: 0.69, g: 0.36, b: 1.00)
    public static let white = RGBAColor(r: 1.00, g: 1.00, b: 1.00)

    public static let presets: [(id: String, name: String, color: RGBAColor)] = [
        ("red", "醒目红", .red),
        ("orange", "活力橙", .orange),
        ("yellow", "荧光黄", .yellow),
        ("green", "高亮绿", .green),
        ("blue", "演示蓝", .blue),
        ("purple", "霓虹紫", .purple),
        ("white", "纯白", .white)
    ]
}

/// 矩形高亮框标注
public struct RectangleAnnotation: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var color: RGBAColor
    public var lineWidth: CGFloat
    public var cornerRadius: CGFloat
    public var fillHighlight: Bool

    public init(
        start: CGPoint,
        end: CGPoint,
        color: RGBAColor,
        lineWidth: CGFloat,
        cornerRadius: CGFloat = 8.0,
        fillHighlight: Bool = true
    ) {
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.fillHighlight = fillHighlight
    }

    public var normalizedRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

/// 文字标注
public struct TextAnnotation: Equatable, Sendable {
    public var text: String
    public var origin: CGPoint
    public var color: RGBAColor
    public var fontSize: CGFloat

    public init(
        text: String,
        origin: CGPoint,
        color: RGBAColor,
        fontSize: CGFloat
    ) {
        self.text = text
        self.origin = origin
        self.color = color
        self.fontSize = fontSize
    }
}

/// 画布标注项（同时支持停留模式与自动淡出生命周期）
public struct AnnotationItem: Identifiable, Equatable, Sendable {
    public enum Payload: Equatable, Sendable {
        case rectangle(RectangleAnnotation)
        case text(TextAnnotation)
    }

    public let id: UUID
    public var payload: Payload
    /// 若非 nil，表示该项属于自动淡出标注，记录创建/完成时间戳
    public var createdAt: TimeInterval?
    public var holdDuration: TimeInterval
    public var fadeDuration: TimeInterval

    public init(
        id: UUID = UUID(),
        payload: Payload,
        createdAt: TimeInterval? = nil,
        holdDuration: TimeInterval = 2.0,
        fadeDuration: TimeInterval = 0.75
    ) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
        self.holdDuration = holdDuration
        self.fadeDuration = fadeDuration
    }

    public var isAutoFading: Bool { createdAt != nil }

    /// 计算当前时刻的透明度 [0, 1]
    public func opacity(at now: TimeInterval) -> CGFloat {
        guard let createdAt else { return 1.0 }
        let elapsed = now - createdAt
        if elapsed <= holdDuration {
            return 1.0
        }
        guard fadeDuration > 0.001 else { return 0.0 }
        let progress = (elapsed - holdDuration) / fadeDuration
        // 平滑 ease-out 淡出
        let linear = max(0.0, min(1.0, 1.0 - progress))
        return CGFloat(linear * linear)
    }

    public func isExpired(at now: TimeInterval) -> Bool {
        guard isAutoFading else { return false }
        return opacity(at: now) <= 0.005
    }
}

/// 几何辅助函数
public enum GeometryHelpers {
    /// 按住 Shift 时将矩形约束为正方形
    public static func constrainSquareEndPoint(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        let sx: CGFloat = dx >= 0 ? 1 : -1
        let sy: CGFloat = dy >= 0 ? 1 : -1
        return CGPoint(x: start.x + sx * side, y: start.y + sy * side)
    }
}
