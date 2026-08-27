import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerInsertionTests: XCTestCase {
  func testPointInsertionUsesPointAsTopLeft() throws {
    let controller = try makeController()
    let origin = SionPoint(x: 120, y: 80)

    let shapeID = try controller.insertShape(at: origin)
    let textID = try controller.insertText("Text", at: origin)

    XCTAssertEqual(
      controller.document.scene.element(withID: shapeID)?.geometry.frame.origin,
      origin
    )
    XCTAssertEqual(controller.document.scene.element(withID: textID)?.geometry.frame.origin, origin)
  }

  func testFrameInsertionPreservesDraggedBoundsAndShapeKind() throws {
    let controller = try makeController()
    let rectangleFrame = SionRect(x: 20, y: 30, width: 240, height: 120)
    let circleFrame = SionRect(x: 300, y: 40, width: 96, height: 96)
    let textFrame = SionRect(x: 40, y: 220, width: 280, height: 72)

    let rectangleID = try controller.insertShape(
      in: rectangleFrame,
      kind: .roundedRectangle(radius: 12)
    )
    let circleID = try controller.insertShape(in: circleFrame, kind: .ellipse)
    let textID = try controller.insertText("Text", in: textFrame)

    XCTAssertEqual(
      controller.document.scene.element(withID: rectangleID)?.geometry.frame,
      rectangleFrame
    )
    XCTAssertEqual(
      controller.document.scene.element(withID: rectangleID)?.content.testShapeKind,
      .roundedRectangle(radius: 12)
    )
    XCTAssertEqual(controller.document.scene.element(withID: circleID)?.geometry.frame, circleFrame)
    XCTAssertEqual(
      controller.document.scene.element(withID: circleID)?.content.testShapeKind,
      .ellipse
    )
    XCTAssertEqual(controller.document.scene.element(withID: textID)?.geometry.frame, textFrame)
  }

  func testLibraryInsertionCanCenterDefaultsInTheViewport() throws {
    let controller = try makeController()
    let center = SionPoint(x: 500, y: 300)

    let shapeID = try controller.insertShape(centeredAt: center, kind: .diamond)
    let circleID = try controller.insertShape(centeredAt: center, kind: .ellipse)
    let textID = try controller.insertText("Text", centeredAt: center)

    XCTAssertEqual(
      controller.document.scene.element(withID: shapeID)?.geometry.frame.center,
      center
    )
    XCTAssertEqual(
      controller.document.scene.element(withID: circleID)?.geometry.frame,
      SionRect(x: 440, y: 240, width: 120, height: 120)
    )
    XCTAssertEqual(
      controller.document.scene.element(withID: textID)?.geometry.frame.center,
      center
    )
  }

  func testToolbarToolsSeparateBasicShapesAndOmitMagnetEditing() {
    XCTAssertEqual(
      SionEditorController.Tool.allCases.map(\.title),
      ["Select", "Rectangle", "Circle", "Text", "Connector"]
    )
  }

  func testInsertionKeepsTheSelectedToolActive() throws {
    let controller = try makeController()
    controller.setTool(.rectangle)

    _ = try controller.insertShape(at: .zero)

    XCTAssertEqual(controller.tool, .rectangle)
  }

  private func makeController() throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }
}

extension ElementContent {
  fileprivate var testShapeKind: ShapeKind? {
    guard case .shape(let shape) = self else { return nil }

    return shape.kind
  }
}
