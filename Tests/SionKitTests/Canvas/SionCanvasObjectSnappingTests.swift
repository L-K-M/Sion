import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasObjectSnappingTests: XCTestCase {
  private let anchorFrame = SionRect(x: 100, y: 100, width: 200, height: 100)
  private let movingFrame = SionRect(x: 400, y: 400, width: 60, height: 60)

  func testDraggingLinesAnObjectUpWithANeighboursEdge() throws {
    let (controller, canvas, moving) = try makeDrag()

    // The drag alone would leave the leading edge four points past the anchor's.
    try drag(canvas: canvas, from: SionPoint(x: 430, y: 430), to: SionPoint(x: 134, y: 430))

    XCTAssertEqual(try frame(of: moving, in: controller).minX, anchorFrame.minX, accuracy: 0.001)
  }

  func testSnappingOffLeavesTheDragExactlyWhereItLanded() throws {
    let (controller, canvas, moving) = try makeDrag()
    canvas.toggleObjectSnapping(nil)

    try drag(canvas: canvas, from: SionPoint(x: 430, y: 430), to: SionPoint(x: 134, y: 430))

    XCTAssertFalse(canvas.snapsToObjects)
    XCTAssertEqual(try frame(of: moving, in: controller).minX, 104, accuracy: 0.001)
  }

  func testADragBeyondToleranceIsNotPulledIn() throws {
    let (controller, canvas, moving) = try makeDrag()

    // Twenty points out is well past the snapping tolerance.
    try drag(canvas: canvas, from: SionPoint(x: 430, y: 430), to: SionPoint(x: 150, y: 430))

    XCTAssertEqual(try frame(of: moving, in: controller).minX, 120, accuracy: 0.001)
  }

  func testTheMenuItemMirrorsTheSnappingState() throws {
    let (_, canvas, _) = try makeDrag()
    let item = NSMenuItem(
      title: "Snap to Objects",
      action: #selector(SionCanvasView.toggleObjectSnapping(_:)),
      keyEquivalent: ""
    )

    XCTAssertTrue(canvas.validateMenuItem(item))
    XCTAssertEqual(item.state, .on)

    canvas.toggleObjectSnapping(nil)

    XCTAssertTrue(canvas.validateMenuItem(item))
    XCTAssertEqual(item.state, .off)
  }

  private func makeDrag() throws -> (SionEditorController, SionCanvasView, ElementID) {
    let anchor = SceneElement.shape(frame: anchorFrame, kind: .rectangle)
    let moving = SceneElement.shape(frame: movingFrame, kind: .rectangle)
    let controller = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [anchor, moving]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let canvas = SionCanvasView(editorController: controller)
    controller.select(moving.id)

    return (controller, canvas, moving.id)
  }

  private func frame(
    of id: ElementID,
    in controller: SionEditorController
  ) throws -> SionRect {
    try XCTUnwrap(controller.document.scene.element(withID: id)).geometry.frame.standardized
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
