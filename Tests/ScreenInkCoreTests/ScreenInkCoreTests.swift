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

    func testLegacyPreferencesBackwardCompatibility() throws {
        // 模拟旧版本已保存、缺少 shortcuts 字段的偏好 JSON
        let legacyJSON = """
        {
          "highlightColor": { "r": 0.08, "g": 0.56, "b": 1.0, "a": 1.0 },
          "lineWidth": 6.0,
          "cornerRadius": 10.0,
          "fillRectangleHighlight": false,
          "retentionMode": "persistent",
          "autoFadeHoldSeconds": 3.5,
          "autoFadeDurationSeconds": 0.75,
          "showToolbarOnActivate": true,
          "cursorHighlightDiameter": 80.0,
          "cursorHighlightOpacity": 0.5,
          "cursorFollowAnnotationColor": false,
          "cursorCustomColor": { "r": 1.0, "g": 0.82, "b": 0.05, "a": 1.0 },
          "cursorClickRipple": true
        }
        """
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.highlightColor, .blue)
        XCTAssertEqual(decoded.lineWidth, 6.0)
        XCTAssertEqual(decoded.retentionMode, .persistent)
        XCTAssertTrue(decoded.showToolbarOnActivate)
        // 旧版配置升级后应自动填充默认快捷键，而不丢失已有设置
        XCTAssertEqual(decoded.shortcuts, .default)
    }

    func testShortcutFormattingValidationAndConflicts() {
        let defaults = ShortcutConfiguration.default
        XCTAssertTrue(defaults.isDefault)
        XCTAssertEqual(defaults.displayString(for: .toggleAnnotateClean), "⌘1")
        XCTAssertEqual(defaults.badgeDisplayString(for: .toggleAnnotateClean), "⌘ 1")
        XCTAssertEqual(defaults.displayString(for: .clearAnnotations), "⌥C")
        XCTAssertEqual(defaults.displayString(for: .selectRectangle), "R")

        // 修饰键展示顺序应遵循 Apple HIG：⌃⌥⇧⌘
        let combo = KeyShortcut(keyCode: KeyCodeTable.a, modifiers: [.command, .control, .shift, .option])
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘A")
        XCTAssertEqual(combo.badgeDisplayString, "⌃ ⌥ ⇧ ⌘ A")
        XCTAssertEqual(combo.menuKeyEquivalent, "a")

        // 全局快捷键校验：裸键与仅 Shift+字母不合法；带 ⌘/⌥/⌃ 或功能键 F8 合法
        let bareKey = KeyShortcut(keyCode: KeyCodeTable.k, modifiers: [])
        XCTAssertEqual(defaults.validate(candidate: bareKey, for: .toggleAnnotateClean), .missingGlobalModifier)

        let shiftOnly = KeyShortcut(keyCode: KeyCodeTable.k, modifiers: .shift)
        XCTAssertEqual(defaults.validate(candidate: shiftOnly, for: .toggleAnnotateClean), .missingGlobalModifier)

        let f8Key = KeyShortcut(keyCode: 0x64, modifiers: [])
        XCTAssertNil(defaults.validate(candidate: f8Key, for: .toggleAnnotateClean))
        XCTAssertEqual(f8Key.displayString, "F8")

        // 系统保留键校验
        let cmdQ = KeyShortcut(keyCode: KeyCodeTable.q, modifiers: .command)
        XCTAssertEqual(defaults.validate(candidate: cmdQ, for: .toggleAnnotateClean), .reservedSystemShortcut)

        // 批注内快捷键校验：裸字母合法，但 Esc / Return / ⌘Z 禁止占用
        XCTAssertNil(defaults.validate(candidate: bareKey, for: .selectRectangle))
        XCTAssertEqual(
            defaults.validate(candidate: KeyShortcut(keyCode: KeyCodeTable.escape), for: .selectRectangle),
            .reservedCanvasShortcut
        )
        XCTAssertEqual(
            defaults.validate(candidate: KeyShortcut(keyCode: KeyCodeTable.z, modifiers: .command), for: .selectText),
            .reservedCanvasShortcut
        )

        // 跨动作冲突检测
        let conflictWithToolbar = KeyShortcut(keyCode: KeyCodeTable.num2, modifiers: .command)
        XCTAssertEqual(
            defaults.validate(candidate: conflictWithToolbar, for: .toggleAnnotateClean),
            .conflict(.toggleAnnotateWithToolbar)
        )
        // 自身当前快捷键不视为与自己冲突
        let sameAsSelf = KeyShortcut(keyCode: KeyCodeTable.num1, modifiers: .command)
        XCTAssertNil(defaults.validate(candidate: sameAsSelf, for: .toggleAnnotateClean))
    }

    func testCustomShortcutsAndDisabledPersistence() {
        let suiteName = "com.screenink.tests.shortcuts.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var prefs = AppPreferences.default
        let customClean = KeyShortcut(keyCode: KeyCodeTable.d, modifiers: [.option, .shift])
        let customRect = KeyShortcut(keyCode: KeyCodeTable.b, modifiers: [])
        prefs.shortcuts[.toggleAnnotateClean] = customClean
        prefs.shortcuts[.toggleAnnotateWithToolbar] = nil // 显式禁用
        prefs.shortcuts[.selectRectangle] = customRect

        XCTAssertFalse(prefs.shortcuts.isDefault)
        XCTAssertEqual(prefs.shortcuts.matchingCanvasAction(for: customRect), .selectRectangle)
        XCTAssertNil(prefs.shortcuts.matchingCanvasAction(for: KeyShortcut(keyCode: KeyCodeTable.r)))

        PreferencesStore.save(prefs, to: defaults)
        let reloaded = PreferencesStore.load(from: defaults)

        XCTAssertEqual(reloaded.shortcuts[.toggleAnnotateClean], customClean)
        // 显式禁用的 nil 必须持久化保留，不得在解码时回退为默认值
        XCTAssertNil(reloaded.shortcuts[.toggleAnnotateWithToolbar])
        XCTAssertEqual(reloaded.shortcuts.displayString(for: .toggleAnnotateWithToolbar), "未设置")
        XCTAssertEqual(reloaded.shortcuts[.selectRectangle], customRect)
        XCTAssertEqual(reloaded.shortcuts[.toggleClickHighlight], ShortcutAction.toggleClickHighlight.defaultShortcut)
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
