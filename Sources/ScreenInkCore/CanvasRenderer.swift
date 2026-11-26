import AppKit
import CoreGraphics
import Foundation

/// 高性能 CoreGraphics 渲染器：专为会议演示优化的高亮矩形框与清晰文字标注（isFlipped = true 坐标系）
public enum CanvasRenderer {
    public static func render(
        state: CanvasState,
        in context: CGContext,
        bounds: CGRect,
        now: TimeInterval
    ) {
        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // 1. 停留模式标注
        for item in state.persistentItems {
            renderItem(item, opacity: 1.0, in: context)
        }

        // 2. 自动淡出标注
        for item in state.fadingItems {
            let alpha = item.opacity(at: now)
            if alpha > 0.005 {
                renderItem(item, opacity: alpha, in: context)
            }
        }

        // 3. 正在拖拽中的矩形草稿
        if let draft = state.activeDraft {
            renderRectangle(draft, opacity: 1.0, in: context)
        }

        context.restoreGState()
    }

    private static func renderItem(_ item: AnnotationItem, opacity: CGFloat, in context: CGContext) {
        switch item.payload {
        case .rectangle(let rectAnnotation):
            renderRectangle(rectAnnotation, opacity: opacity, in: context)
        case .text(let textAnnotation):
            renderText(textAnnotation, opacity: opacity, in: context)
        }
    }

    private static func renderRectangle(
        _ annotation: RectangleAnnotation,
        opacity: CGFloat,
        in context: CGContext
    ) {
        let rect = annotation.normalizedRect
        guard rect.width >= 1.0 || rect.height >= 1.0 else { return }

        let maxRadius = min(rect.width, rect.height) * 0.5
        let radius = min(annotation.cornerRadius, maxRadius)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()

        // 极淡的内部高亮底色，开会时一眼突出被圈选的区域
        if annotation.fillHighlight {
            context.addPath(path)
            context.setFillColor(annotation.color.withAlpha(0.10 * opacity).cgColor)
            context.fillPath()
        }

        // 外发光 + 高亮主边框
        context.setShadow(
            offset: .zero,
            blur: 10,
            color: annotation.color.withAlpha(0.50 * opacity).cgColor
        )
        context.addPath(path)
        context.setStrokeColor(annotation.color.withAlpha(0.96 * opacity).cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineJoin(.round)
        context.strokePath()

        context.restoreGState()
    }

    private static func renderText(
        _ annotation: TextAnnotation,
        opacity: CGFloat,
        in context: CGContext
    ) {
        let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let nsColor = NSColor(
            srgbRed: annotation.color.r,
            green: annotation.color.g,
            blue: annotation.color.b,
            alpha: annotation.color.a * opacity
        )
        let font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55 * opacity)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor,
            .shadow: shadow
        ]

        let nsText = annotation.text as NSString
        let textSize = nsText.size(withAttributes: attributes)
        let padX: CGFloat = 10
        let padY: CGFloat = 6
        let badgeRect = CGRect(
            x: annotation.origin.x - padX,
            y: annotation.origin.y - padY,
            width: textSize.width + padX * 2,
            height: textSize.height + padY * 2
        )

        context.saveGState()
        // 半透明深色圆角标签底板，确保在白底文档或深色代码上都极其清晰
        let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(badgePath)
        context.setFillColor(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.72 * opacity))
        context.fillPath()

        context.addPath(badgePath)
        context.setStrokeColor(annotation.color.withAlpha(0.55 * opacity).cgColor)
        context.setLineWidth(1.2)
        context.strokePath()

        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = graphicsContext
        nsText.draw(at: annotation.origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
}
