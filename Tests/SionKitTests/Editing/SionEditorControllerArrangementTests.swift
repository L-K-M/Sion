#if canImport(AppKit)
  import XCTest

  @testable import SionCore
  @testable import SionKit

  @MainActor
  final class SionEditorControllerArrangementTests: XCTestCase {
    func testDuplicateOffsetsCopyAndSelectsIt() throws {
      let original = SceneElement.shape(
        frame: SionRect(x: 100, y: 100, width: 120, height: 80),
        kind: .rectangle
      )
      let controller = try makeController(elements: [original])
      controller.select(original.id)

      let duplicated = try controller.duplicateSelection()

      XCTAssertEqual(controller.document.scene.elements.count, 2)
      XCTAssertEqual(duplicated.count, 1)
      XCTAssertEqual(controller.selection, Set(duplicated))
      XCTAssertNotEqual(duplicated.first, original.id)

      let copyFrame = controller.document.scene.element(withID: duplicated[0])?
        .geometry.frame
      XCTAssertEqual(
        copyFrame?.origin,
        SionPoint(x: 116, y: 116)
      )
    }

    func testDuplicateIsOneUndoStep() throws {
      let original = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 120, height: 80),
        kind: .rectangle
      )
      let controller = try makeController(elements: [original])
      controller.select(original.id)

      _ = try controller.duplicateSelection()
      XCTAssertEqual(controller.document.scene.elements.count, 2)

      controller.undoSceneEdit()
      XCTAssertEqual(controller.document.scene.elements.count, 1)
      XCTAssertEqual(controller.document.scene.elements[0].id, original.id)
    }

    func testZOrderMovesSelectionAsABlock() throws {
      let scene = SionScene(
        elements: (0..<4).map { index in
          SceneElement.shape(
            frame: SionRect(x: Double(index) * 100, y: 0, width: 80, height: 60),
            kind: .rectangle
          )
        }
      )
      let controller = try makeController(elements: scene.elements)
      let middleTwo = Array(scene.elements[1...2].map(\.id))
      controller.select(middleTwo[0])
      controller.select(middleTwo[1], mode: .extend)

      try controller.changeSelectionZOrder(.forward)
      XCTAssertEqual(
        orderedIDs(controller), [scene.elements[0].id, scene.elements[3].id] + middleTwo)

      try controller.changeSelectionZOrder(.backward)
      XCTAssertEqual(
        orderedIDs(controller), middleTwo + [scene.elements[0].id, scene.elements[3].id])

      try controller.changeSelectionZOrder(.front)
      XCTAssertEqual(
        orderedIDs(controller),
        [scene.elements[0].id, scene.elements[3].id] + middleTwo
      )

      try controller.changeSelectionZOrder(.back)
      XCTAssertEqual(
        orderedIDs(controller),
        middleTwo + [scene.elements[0].id, scene.elements[3].id]
      )
    }

    func testZOrderAtTheEdgeIsANoOp() throws {
      let bottom = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 80, height: 60),
        kind: .rectangle
      )
      let top = SceneElement.shape(
        frame: SionRect(x: 100, y: 0, width: 80, height: 60),
        kind: .rectangle
      )
      let controller = try makeController(elements: [bottom, top])

      controller.select(bottom.id)
      try controller.changeSelectionZOrder(.backward)
      XCTAssertEqual(orderedIDs(controller), [bottom.id, top.id])

      controller.select(top.id)
      try controller.changeSelectionZOrder(.forward)
      XCTAssertEqual(orderedIDs(controller), [bottom.id, top.id])
    }

    private func orderedIDs(_ controller: SionEditorController) -> [ElementID] {
      controller.document.scene.elements.map(\.id)
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
#endif
