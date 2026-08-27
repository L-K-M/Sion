#if canImport(AppKit)
  import XCTest

  @testable import SionCore
  @testable import SionKit

  @MainActor
  final class SionEditorControllerSelectionTests: XCTestCase {
    func testSetSelectionReplacesAndExtends() throws {
      let first = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let second = SceneElement.shape(
        frame: SionRect(x: 200, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let controller = try makeController(elements: [first, second])

      controller.select([first.id, second.id])
      XCTAssertEqual(controller.selection, [first.id, second.id])

      controller.select([first.id])
      XCTAssertEqual(controller.selection, [first.id])

      controller.select([second.id], mode: .extend)
      XCTAssertEqual(controller.selection, [first.id, second.id])
    }

    func testSetSelectionSkipsNotificationWhenUnchanged() throws {
      let element = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let controller = try makeController(elements: [element])

      controller.select(element.id)
      controller.select([element.id])
      XCTAssertEqual(controller.selection, [element.id])
    }

    func testCancelActiveGestureRestoresPreGestureScene() throws {
      let element = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let controller = try makeController(elements: [element])
      let originalFrame = element.geometry.frame

      controller.select(element.id)
      try controller.beginMove()
      try controller.moveSelection(by: SionVector(dx: 30, dy: 30))
      controller.cancelActiveGesture()

      XCTAssertEqual(
        controller.document.scene.element(withID: element.id)?.geometry.frame,
        originalFrame
      )
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
