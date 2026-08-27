import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerAnchorEditingTests: XCTestCase {
  func testRectangleAnchorProjectsToNearestEdgeAndCanBeRemoved() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96),
      kind: .rectangle
    )
    shape.magnetConfiguration = .preset(.none)
    let controller = try makeController(elements: [shape])
    controller.select(shape.id)
    controller.beginAnchorEditing(on: shape.id)

    XCTAssertEqual(
      try controller.editAnchor(
        at: SionPoint(x: 170, y: 70),
        on: shape.id,
        hitTolerance: 1
      ),
      .changed
    )

    let changed = try XCTUnwrap(controller.document.scene.element(withID: shape.id))
    guard case .custom(let anchors) = changed.magnetConfiguration else {
      return XCTFail("Expected custom anchors")
    }
    let anchor = try XCTUnwrap(anchors.first)
    XCTAssertEqual(anchors.count, 1)
    XCTAssertEqual(anchor.normalizedPosition.x, 1)
    XCTAssertEqual(anchor.normalizedPosition.y, 40.0 / 96.0, accuracy: 0.000_001)
    XCTAssertEqual(anchor.outwardDirection, .east)

    XCTAssertEqual(
      try controller.editAnchor(
        at: SionPoint(x: 180, y: 70),
        on: shape.id,
        hitTolerance: 1
      ),
      .changed
    )
    XCTAssertEqual(
      controller.document.scene.element(withID: shape.id)?.magnetConfiguration,
      .custom([])
    )
  }

  func testAnchorEditingRejectsClicksOutsideTheObject() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96)
    )
    let controller = try makeController(elements: [shape])
    controller.select(shape.id)
    controller.beginAnchorEditing(on: shape.id)

    XCTAssertEqual(
      try controller.editAnchor(
        at: SionPoint(x: 500, y: 500),
        on: shape.id,
        hitTolerance: 8
      ),
      .outsideElement
    )
    XCTAssertEqual(controller.anchorEditingState, .editing(shape.id))
  }

  func testToolAndSelectionChangesExitAnchorEditing() throws {
    let first = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96)
    )
    let second = SceneElement.shape(
      frame: SionRect(x: 240, y: 30, width: 160, height: 96)
    )
    let controller = try makeController(elements: [first, second])
    controller.select(first.id)

    controller.beginAnchorEditing(on: first.id)
    controller.setTool(.rectangle)
    XCTAssertEqual(controller.anchorEditingState, .inactive)

    controller.beginAnchorEditing(on: first.id)
    controller.select(second.id)
    XCTAssertEqual(controller.anchorEditingState, .inactive)

    controller.select(first.id)
    controller.beginAnchorEditing(on: first.id)
    controller.endAnchorEditing()
    XCTAssertEqual(controller.anchorEditingState, .inactive)
  }

  private func makeController(elements: [SceneElement]) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: elements))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }
}
