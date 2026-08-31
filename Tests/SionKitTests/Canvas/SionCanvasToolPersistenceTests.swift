import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasToolPersistenceTests: XCTestCase {
  func testOneShotShapeToolRevertsAfterOneCreation() throws {
    let controller = try makeController()
    let canvas = makeCanvas(controller: controller)
    defer { canvas.commitPendingEdits() }
    controller.setTool(.rectangle, persistence: .oneShot)

    try click(canvas: canvas, at: SionPoint(x: 80, y: 70))

    XCTAssertEqual(controller.document.scene.elements.count, 1)
    XCTAssertEqual(controller.tool, .select)
    XCTAssertEqual(controller.toolPersistence, .sticky)
  }

  func testStickyShapeToolStaysActiveAcrossCreations() throws {
    let controller = try makeController()
    let canvas = makeCanvas(controller: controller)
    defer { canvas.commitPendingEdits() }
    controller.setTool(.rectangle, persistence: .sticky)

    try click(canvas: canvas, at: SionPoint(x: 60, y: 60))
    try click(canvas: canvas, at: SionPoint(x: 380, y: 300))

    XCTAssertEqual(controller.document.scene.elements.count, 2)
    XCTAssertEqual(controller.tool, .rectangle)
    XCTAssertEqual(controller.toolPersistence, .sticky)
  }

  func testOneShotTextToolRevertsAfterOneCreation() throws {
    let controller = try makeController()
    let canvas = makeCanvas(controller: controller)
    defer { canvas.discardPendingEdits() }
    controller.setTool(.text, persistence: .oneShot)

    try click(canvas: canvas, at: SionPoint(x: 300, y: 200))

    XCTAssertEqual(controller.document.scene.elements.count, 1)
    XCTAssertEqual(controller.tool, .select)
  }

  func testFailedCreationKeepsTheToolArmed() throws {
    let controller = try makeController()
    var feedbackCount = 0
    let canvas = makeCanvas(controller: controller, creationFailureFeedback: { feedbackCount += 1 })
    controller.setTool(.rectangle, persistence: .oneShot)

    try click(
      canvas: canvas,
      at: SionPoint(x: SceneLimits.maximumCoordinateMagnitude + 100, y: 40)
    )

    XCTAssertEqual(feedbackCount, 1)
    XCTAssertTrue(controller.document.scene.elements.isEmpty)
    XCTAssertEqual(controller.tool, .rectangle)
    XCTAssertEqual(controller.toolPersistence, .oneShot)
  }

  func testOneShotConnectorToolRevertsAfterConnecting() throws {
    let sourceFrame = SionRect(x: 100, y: 100, width: 160, height: 96)
    let targetFrame = SionRect(x: 400, y: 100, width: 160, height: 96)
    let controller = try makeController(elements: [
      SceneElement.shape(frame: sourceFrame, kind: .rectangle),
      SceneElement.shape(frame: targetFrame, kind: .rectangle),
    ])
    let canvas = makeCanvas(controller: controller)
    controller.setTool(.connector, persistence: .oneShot)

    try drag(
      canvas: canvas,
      from: SionPoint(x: sourceFrame.maxX - 1, y: sourceFrame.center.y),
      to: SionPoint(x: targetFrame.minX + 1, y: targetFrame.center.y)
    )

    XCTAssertEqual(controller.document.scene.elements.count, 3)
    XCTAssertEqual(controller.tool, .select)
  }

  func testRejectedConnectorKeepsTheConnectorToolArmed() throws {
    let frame = SionRect(x: 100, y: 100, width: 160, height: 96)
    let shape = SceneElement.shape(frame: frame, kind: .rectangle)
    let controller = try makeController(elements: [shape])
    var feedbackCount = 0
    let canvas = makeCanvas(controller: controller, creationFailureFeedback: { feedbackCount += 1 })
    controller.setTool(.connector, persistence: .oneShot)

    try drag(
      canvas: canvas,
      from: SionPoint(x: frame.maxX - 1, y: frame.center.y),
      to: SionPoint(x: frame.minX + 1, y: frame.center.y)
    )

    XCTAssertEqual(feedbackCount, 1)
    XCTAssertEqual(controller.document.scene.elements, [shape])
    XCTAssertEqual(controller.tool, .connector)
    XCTAssertEqual(controller.toolPersistence, .oneShot)
  }

  private func makeController(elements: [SceneElement] = []) throws -> SionEditorController {
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(SionSize(width: 640, height: 480))),
      elements: elements
    )
    return try SionEditorController(
      package: SionPackage(document: SionDocument(scene: scene)),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func makeCanvas(
    controller: SionEditorController,
    creationFailureFeedback: @escaping @MainActor () -> Void = {}
  ) -> SionCanvasView {
    SionCanvasView(
      editorController: controller,
      creationFailureFeedback: creationFailureFeedback
    )
  }

  private func click(canvas: SionCanvasView, at point: SionPoint) throws {
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, canvas: canvas, at: point))
    canvas.mouseUp(with: try mouseEvent(.leftMouseUp, canvas: canvas, at: point))
  }

  private func drag(
    canvas: SionCanvasView,
    from start: SionPoint,
    to end: SionPoint
  ) throws {
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, canvas: canvas, at: start))
    canvas.mouseDragged(with: try mouseEvent(.leftMouseDragged, canvas: canvas, at: end))
    canvas.mouseUp(with: try mouseEvent(.leftMouseUp, canvas: canvas, at: end))
  }

  private func mouseEvent(
    _ type: NSEvent.EventType,
    canvas: SionCanvasView,
    at point: SionPoint
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type,
        location: canvas.convert(canvas.viewPoint(for: point), to: nil),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )
    )
  }
}
