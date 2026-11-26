import AppKit
import Foundation

// 生成 1024x1024 原创 ScreenInk macOS 图标（高亮聚焦框 + 光标光环）
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = CGSize(width: 1024, height: 1024)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create bitmap")
}

NSGraphicsContext.saveGraphicsState()
let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext

let cardRect = CGRect(x: 92, y: 92, width: 840, height: 840)
let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 190, cornerHeight: 190, transform: nil)
ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgColors = [
    CGColor(srgbRed: 0.09, green: 0.11, blue: 0.19, alpha: 1.0),
    CGColor(srgbRed: 0.14, green: 0.18, blue: 0.30, alpha: 1.0)
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 120, y: 900),
        end: CGPoint(x: 900, y: 120),
        options: []
    )
}

// 发光高亮矩形框
let focusRect = CGRect(x: 230, y: 290, width: 510, height: 420)
let focusPath = CGPath(roundedRect: focusRect, cornerWidth: 52, cornerHeight: 52, transform: nil)

ctx.saveGState()
ctx.addPath(focusPath)
ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.28, blue: 0.30, alpha: 0.16))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 42, color: CGColor(srgbRed: 1.0, green: 0.30, blue: 0.32, alpha: 0.85))
ctx.addPath(focusPath)
ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 0.32, blue: 0.34, alpha: 1.0))
ctx.setLineWidth(44)
ctx.strokePath()
ctx.restoreGState()

// 右下角 Highlight Cursor 发光圆环
let haloCenter = CGPoint(x: 720, y: 310)
let haloRadius: CGFloat = 112
let haloRect = CGRect(
    x: haloCenter.x - haloRadius,
    y: haloCenter.y - haloRadius,
    width: haloRadius * 2,
    height: haloRadius * 2
)
ctx.saveGState()
ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.82, blue: 0.18, alpha: 0.32))
ctx.fillEllipse(in: haloRect)
ctx.setShadow(offset: .zero, blur: 28, color: CGColor(srgbRed: 1.0, green: 0.82, blue: 0.18, alpha: 0.85))
ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 0.86, blue: 0.30, alpha: 0.96))
ctx.setLineWidth(20)
ctx.strokeEllipse(in: haloRect)
ctx.restoreGState()

// 中心亮白点
ctx.setFillColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.96))
ctx.fillEllipse(in: CGRect(x: haloCenter.x - 24, y: haloCenter.y - 24, width: 48, height: 48))

ctx.restoreGState()

ctx.addPath(cardPath)
ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.16))
ctx.setLineWidth(6)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Generated icon at \(outputPath)")
