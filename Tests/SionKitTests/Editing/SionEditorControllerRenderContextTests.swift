#if canImport(AppKit)
  import XCTest

  @testable import SionCore
  @testable import SionKit

  @MainActor
  final class SionEditorControllerRenderContextTests: XCTestCase {
    func testLiveMoveUpdatesContextWithoutRebuildingIt() throws {
      let shape = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 80, height: 60),
        kind: .rectangle
      )
      var buildCount = 0
      let controller = try SionEditorController(
        package: SionPackage(
          document: SionDocument(scene: SionScene(elements: [shape]))
        ),
        undoManagerProvider: { nil },
        didChange: { _ in },
        renderContextBuilder: { scene in
          buildCount += 1
          return SceneRenderContext(scene: scene)
        }
      )
      controller.select(shape.id)
      try controller.beginMove()

      for expectedX in [40.0, 80.0, 120.0] {
        try controller.moveSelection(by: SionVector(dx: 40, dy: 0))
        let query = controller.elementsForRendering(
          intersecting: SionRect(x: expectedX, y: 0, width: 80, height: 60)
        )

        XCTAssertEqual(query.map(\.id), [shape.id])
      }

      try controller.endMove()

      XCTAssertEqual(buildCount, 1)
    }

    func testMovedDuplicateUpdatesItsSelectedIndexEntry() throws {
      let original = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 80, height: 60),
        kind: .rectangle
      )
      var buildCount = 0
      let controller = try SionEditorController(
        package: SionPackage(
          document: SionDocument(scene: SionScene(elements: [original]))
        ),
        undoManagerProvider: { nil },
        didChange: { _ in },
        renderContextBuilder: { scene in
          buildCount += 1
          return SceneRenderContext(scene: scene)
        }
      )
      controller.select(original.id)
      let duplicateID = try XCTUnwrap(controller.duplicateSelection().first)
      let buildCountAfterDuplication = buildCount
      try controller.beginMove()

      try controller.moveSelection(by: SionVector(dx: 200, dy: 0))
      let duplicate = try XCTUnwrap(
        controller.document.scene.element(withID: duplicateID)
      )
      try controller.endMove()

      XCTAssertEqual(controller.selection, [duplicateID])
      controller.select(original.id)
      let query = controller.elementsForRendering(
        intersecting: duplicate.geometry.frame
      )

      XCTAssertTrue(query.contains { $0.id == duplicateID })
      XCTAssertEqual(buildCount, buildCountAfterDuplication)
    }
  }

#endif
