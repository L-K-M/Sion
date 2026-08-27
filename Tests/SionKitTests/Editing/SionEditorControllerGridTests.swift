import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerGridTests: XCTestCase {
  private func makeController(elements: [SceneElement]) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument(scene: SionScene(elements: elements))),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  func testGridVisibilityRoundTripsThroughSetCanvas() throws {
    let controller = try makeController(elements: [])
    XCTAssertEqual(controller.gridVisibility(), .hidden)

    try controller.setGridVisibility(.visible)
    XCTAssertEqual(controller.gridVisibility(), .visible)

    controller.undoSceneEdit()
    XCTAssertEqual(controller.gridVisibility(), .hidden)
  }

  func testSnapRoundsToGridSpacing() throws {
    let controller = try makeController(elements: [])

    XCTAssertEqual(
      controller.snappedToGrid(SionPoint(x: 19, y: 41)),
      SionPoint(x: 16, y: 48)
    )

    controller.isSnapToGridEnabled = false
    XCTAssertEqual(
      controller.snappedToGrid(SionPoint(x: 19, y: 41)),
      SionPoint(x: 19, y: 41)
    )
  }

  func testMoveWithSnapLandsOnGridPoints() throws {
    let element = SceneElement.shape(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
      frame: SionRect(x: 5, y: 5, width: 50, height: 40)
    )
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    try controller.beginMove()
    try controller.moveSelection(by: SionVector(dx: 1, dy: 0))
    try controller.endMove()

    // Nearest grid point to 5 + 1 = 6 is 0.
    XCTAssertEqual(controller.frame(of: element.id)?.minX, 0)

    try controller.beginMove()
    try controller.moveSelection(by: SionVector(dx: 20, dy: 0))
    try controller.endMove()

    // Nearest grid point to 0 + 20 = 20 is 16.
    XCTAssertEqual(controller.frame(of: element.id)?.minX, 16)
  }

  func testMoveWithoutSnapAppliesDeltaExactly() throws {
    let element = SceneElement.shape(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
      frame: SionRect(x: 5, y: 5, width: 50, height: 40)
    )
    let controller = try makeController(elements: [element])
    controller.isSnapToGridEnabled = false
    controller.select(element.id)

    try controller.beginMove()
    try controller.moveSelection(by: SionVector(dx: 3, dy: 0))
    try controller.endMove()

    XCTAssertEqual(controller.frame(of: element.id)?.minX, 8)
  }
}

extension SionEditorController {
  fileprivate func gridVisibility() -> GridVisibility {
    document.scene.canvas.grid.visibility
  }

  fileprivate func frame(of id: ElementID) -> SionRect? {
    document.scene.element(withID: id)?.geometry.frame.standardized
  }
}
