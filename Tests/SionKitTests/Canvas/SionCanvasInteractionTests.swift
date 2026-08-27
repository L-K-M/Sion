import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasInteractionTests: XCTestCase {
  func testCanvasCreationSelectsEachNewElement() throws {
    let controller = try makeController()
    let canvas = makeCanvas(controller: controller)
    defer { canvas.commitPendingEdits() }

    controller.setTool(.rectangle)
    try click(canvas: canvas, at: SionPoint(x: 80, y: 70))
    let shape = try XCTUnwrap(controller.document.scene.elements.last)
    XCTAssertEqual(controller.selection, [shape.id])

    controller.setTool(.text)
    try click(canvas: canvas, at: SionPoint(x: 300, y: 200))
    let text = try XCTUnwrap(controller.document.scene.elements.last)
    XCTAssertEqual(controller.selection, [text.id])
  }

  func testCanvasCreationBeepsWhenInsertionFails() throws {
    let controller = try makeController()
    var feedbackCount = 0
    let canvas = makeCanvas(
      controller: controller,
      creationFailureFeedback: { feedbackCount += 1 }
    )
    controller.setTool(.rectangle)

    try click(
      canvas: canvas,
      at: SionPoint(x: SceneLimits.maximumCoordinateMagnitude + 100, y: 40)
    )

    XCTAssertEqual(feedbackCount, 1)
    XCTAssertTrue(controller.document.scene.elements.isEmpty)
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

  private func mouseEvent(
    _ type: NSEvent.EventType,
    canvas: SionCanvasView,
    at point: SionPoint
  ) throws -> NSEvent {
    return try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type,
        location: canvas.viewPoint(for: point),
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
