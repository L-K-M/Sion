import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasResizeAspectTests: XCTestCase {
  private let frame = SionRect(x: 100, y: 100, width: 200, height: 100)

  func testResizingAnImageKeepsItsProportions() throws {
    let (controller, canvas, id) = try makeSelection(.image)
    defer { canvas.invalidate() }

    try dragSouthEastCorner(canvas, to: SionPoint(x: 500, y: 220))

    // Width leads, so the height follows it back to the 2:1 the frame had.
    assertFrame(
      try frame(of: id, in: controller),
      equals: SionRect(x: 100, y: 100, width: 400, height: 200)
    )
  }

  func testShiftFreesAnImageFromItsProportions() throws {
    let (controller, canvas, id) = try makeSelection(.image)
    defer { canvas.invalidate() }

    try dragSouthEastCorner(canvas, to: SionPoint(x: 500, y: 220), modifierFlags: .shift)

    assertFrame(
      try frame(of: id, in: controller),
      equals: SionRect(x: 100, y: 100, width: 400, height: 120)
    )
  }

  func testResizingAShapeStaysFree() throws {
    let (controller, canvas, id) = try makeSelection(.shape)
    defer { canvas.invalidate() }

    try dragSouthEastCorner(canvas, to: SionPoint(x: 500, y: 220))

    assertFrame(
      try frame(of: id, in: controller),
      equals: SionRect(x: 100, y: 100, width: 400, height: 120)
    )
  }

  func testShiftConstrainsAShape() throws {
    let (controller, canvas, id) = try makeSelection(.shape)
    defer { canvas.invalidate() }

    try dragSouthEastCorner(canvas, to: SionPoint(x: 500, y: 220), modifierFlags: .shift)

    assertFrame(
      try frame(of: id, in: controller),
      equals: SionRect(x: 100, y: 100, width: 400, height: 200)
    )
  }

  private enum Subject {
    case image
    case shape
  }

  private func makeSelection(
    _ subject: Subject
  ) throws -> (SionEditorController, SionCanvasView, ElementID) {
    let element: SceneElement
    switch subject {
    case .image:
      element = SceneElement.image(
        frame: frame,
        assetID: AssetID(rawValue: "asset"),
        displayAssetID: AssetID(rawValue: "display")
      )
    case .shape:
      element = SceneElement.shape(frame: frame, kind: .rectangle)
    }

    let controller = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [element]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let canvas = SionCanvasView(editorController: controller)
    controller.select(element.id)

    return (controller, canvas, element.id)
  }

  private func dragSouthEastCorner(
    _ canvas: SionCanvasView,
    to end: SionPoint,
    modifierFlags: NSEvent.ModifierFlags = []
  ) throws {
    let corner = SionPoint(x: frame.maxX, y: frame.maxY)
    canvas.mouseDown(
      with: try mouseEvent(.leftMouseDown, canvas: canvas, at: corner, modifierFlags: modifierFlags)
    )
    canvas.mouseDragged(
      with: try mouseEvent(.leftMouseDragged, canvas: canvas, at: end, modifierFlags: modifierFlags)
    )
    canvas.mouseUp(
      with: try mouseEvent(.leftMouseUp, canvas: canvas, at: end, modifierFlags: modifierFlags)
    )
  }

  private func frame(
    of id: ElementID,
    in controller: SionEditorController
  ) throws -> SionRect {
    try XCTUnwrap(controller.document.scene.element(withID: id)).geometry.frame.standardized
  }

  private func assertFrame(
    _ actual: SionRect,
    equals expected: SionRect,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
  }

  private func mouseEvent(
    _ type: NSEvent.EventType,
    canvas: SionCanvasView,
    at point: SionPoint,
    modifierFlags: NSEvent.ModifierFlags
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type,
        location: canvas.convert(canvas.viewPoint(for: point), to: nil),
        modifierFlags: modifierFlags,
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
