import CoreGraphics
import Foundation
import XCTest
@testable import ScreenInkCore

final class ScreenInkCoreTests: XCTestCase {
    func testAutoFadeLifecycle() {
        let state = CanvasState()
        let rect = RectangleAnnotation(
            start: CGPoint(x: 20, y: 20),
            end: CGPoint(x: 180, y: 120),
            color: .red,
            lineWidth: 4.5
        )
        state.commit(
            payload: .rectangle(rect),
            retentionMode: .autoFade,
            now: 100.0,
            holdDuration: 2.0,
            fadeDuration: 0.8
        )

        XCTAssertTrue(state.persistentItems.isEmpty)
        XCTAssertEqual(state.fadingItems.count, 1)

        // 停留期内保持满透明度
        XCTAssertEqual(state.fadingItems[0].opacity(at: 101.5), 1.0, accuracy: 0.001)

        // 淡出中段透明度衰减
        let midOpacity = state.fadingItems[0].opacity(at: 102.4)
        XCTAssertGreaterThan(midOpacity, 0.05)
        XCTAssertLessThan(midOpacity, 0.5)

        // 超时后被自动回收
        XCTAssertFalse(state.pruneExpired(at: 102.85))
        XCTAssertTrue(state.fadingItems.isEmpty)
        XCTAssertFalse(state.hasVisibleContent)
    }

    func testPersistentModeUndoRedoAndClear() {
        let state = CanvasState()
        let rect = RectangleAnnotation(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 80), color: .blue, lineWidth: 4)
        let text = TextAnnotation(text: "这里需要注意", origin: CGPoint(x: 110, y: 20), color: .yellow, fontSize: 24)

        state.commit(payload: .rectangle(rect), retentionMode: .persistent, now: 10.0, holdDuration: 2.0)
        state.commit(payload: .text(text), retentionMode: .persistent, now: 11.0, holdDuration: 2.0)

        XCTAssertEqual(state.persistentItems.count, 2)
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)

        XCTAssertTrue(state.undo())
        XCTAssertEqual(state.persistentItems.count, 1)
        XCTAssertTrue(state.canRedo)

        XCTAssertTrue(state.redo())
        XCTAssertEqual(state.persistentItems.count, 2)

        state.clearAll()
        XCTAssertTrue(state.persistentItems.isEmpty)
        XCTAssertTrue(state.undo())
        XCTAssertEqual(state.persistentItems.count, 2)
    }

    func testShiftSquareConstraint() {
        let end = GeometryHelpers.constrainSquareEndPoint(
            start: CGPoint(x: 50, y: 40),
            end: CGPoint(x: 130, y: 70)
        )
        XCTAssertEqual(end.x, 130, accuracy: 0.001)
        XCTAssertEqual(end.y, 120, accuracy: 0.001)

        let negativeEnd = GeometryHelpers.constrainSquareEndPoint(
            start: CGPoint(x: 100, y: 100),
            end: CGPoint(x: 70, y: 20)
        )
        XCTAssertEqual(abs(negativeEnd.x - 100), abs(negativeEnd.y - 100), accuracy: 0.001)
        XCTAssertEqual(negativeEnd.x, 20, accuracy: 0.001)
        XCTAssertEqual(negativeEnd.y, 20, accuracy: 0.001)
    }

    func testPreferencesPersistence() {
        let suiteName = "com.screenink.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 默认配置应为自动淡出 + 无工具栏激活
        let initial = PreferencesStore.load(from: defaults)
        XCTAssertEqual(initial.retentionMode, .autoFade)
        XCTAssertFalse(initial.showToolbarOnActivate)

        var updated = initial
        updated.retentionMode = .persistent
        updated.highlightColor = .green
        updated.autoFadeHoldSeconds = 4.5
        updated.cursorHighlightDiameter = 72.0
        updated.showToolbarOnActivate = true

        PreferencesStore.save(updated, to: defaults)
        let reloaded = PreferencesStore.load(from: defaults)
        XCTAssertEqual(reloaded, updated)
    }

    func testOffscreenRenderingSmoke() {
        let state = CanvasState()
        state.commit(
            payload: .rectangle(RectangleAnnotation(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 200, y: 120), color: .orange, lineWidth: 5)),
            retentionMode: .autoFade,
            now: 10.0,
            holdDuration: 2.0
        )
        state.commit(
            payload: .text(TextAnnotation(text: "关键指标", origin: CGPoint(x: 30, y: 140), color: .white, fontSize: 22)),
            retentionMode: .persistent,
            now: 10.0,
            holdDuration: 2.0
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 300,
            height: 220,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create CGContext")
            return
        }

        CanvasRenderer.render(
            state: state,
            in: ctx,
            bounds: CGRect(x: 0, y: 0, width: 300, height: 220),
            now: 10.5
        )

        let image = ctx.makeImage()
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, 300)
        XCTAssertEqual(image?.height, 220)
    }
}
