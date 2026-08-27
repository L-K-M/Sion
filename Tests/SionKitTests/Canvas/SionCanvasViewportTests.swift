import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasViewportTests: XCTestCase {
  func testFixedCanvasViewUsesDeclaredExtent() throws {
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(SionSize(width: 640, height: 480)))
    )
    let canvas = SionCanvasView(editorController: try makeController(scene: scene))

    XCTAssertEqual(canvas.frame.size, NSSize(width: 640, height: 480))
    XCTAssertEqual(canvas.visibleCenter, SionPoint(x: 320, y: 240))
  }

  func testInfiniteCanvasMapsNegativeAndDistantContentIntoView() throws {
    let negative = SceneElement.shape(
      frame: SionRect(x: -500, y: -300, width: 100, height: 80),
      kind: .rectangle
    )
    let distant = SceneElement.shape(
      frame: SionRect(x: 4_500, y: 3_400, width: 200, height: 100),
      kind: .rectangle
    )
    let scene = SionScene(elements: [negative, distant])
    let expected = SceneRenderGeometry.editingCanvasBounds(
      of: scene,
      minimumInfiniteSize: SionSize(width: 4_000, height: 3_000)
    )
    let canvas = SionCanvasView(editorController: try makeController(scene: scene))

    XCTAssertEqual(canvas.frame.size, NSSize(width: expected.width, height: expected.height))
    XCTAssertEqual(canvas.viewPoint(for: expected.origin), .zero)
    XCTAssertEqual(canvas.visibleCenter, expected.center)
  }

  func testInfiniteCanvasDoesNotShrinkAfterContentMovesInward() throws {
    let controller = try makeController(scene: SionScene())
    let canvas = SionCanvasView(editorController: controller)
    let id = try controller.insertShape(at: SionPoint(x: -200, y: -200))
    let zeroAfterGrowth = canvas.viewPoint(for: .zero)

    XCTAssertGreaterThan(zeroAfterGrowth.x, 0)
    XCTAssertGreaterThan(zeroAfterGrowth.y, 0)

    controller.select(id)
    try controller.nudgeSelection(by: SionVector(dx: 1_000, dy: 1_000))

    XCTAssertEqual(canvas.viewPoint(for: .zero), zeroAfterGrowth)
  }

  func testGrowingNegativeOriginPreservesVisibleModelCenter() throws {
    let controller = try makeController(scene: SionScene())
    let canvas = SionCanvasView(editorController: controller)
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    scrollView.documentView = canvas
    scrollView.contentView.scroll(to: NSPoint(x: 1_000, y: 800))
    let centerBeforeGrowth = canvas.visibleCenter

    _ = try controller.insertShape(at: SionPoint(x: -200, y: -200))

    XCTAssertEqual(canvas.visibleCenter.x, centerBeforeGrowth.x, accuracy: 0.001)
    XCTAssertEqual(canvas.visibleCenter.y, centerBeforeGrowth.y, accuracy: 0.001)
  }

  private func makeController(scene: SionScene) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument(scene: scene)),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }
}
