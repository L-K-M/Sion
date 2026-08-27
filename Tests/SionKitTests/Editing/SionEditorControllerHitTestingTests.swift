#if canImport(AppKit)
  import XCTest

  @testable import SionCore
  @testable import SionKit

  @MainActor
  final class SionEditorControllerHitTestingTests: XCTestCase {
    /// A square rotated 45° covers a diamond inside its axis-aligned bounds;
    /// selection must follow the diamond, not the bounding box.
    func testHitTestingRotatedElementUsesRotatedFrame() throws {
      let element = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 100),
        kind: .rectangle
      )
      var rotated = element
      rotated.geometry.rotationRadians = .pi / 4
      let controller = try makeController(elements: [rotated])

      // Inside the rotated diamond, above the unrotated frame.
      XCTAssertEqual(controller.element(at: SionPoint(x: 50, y: -10))?.id, rotated.id)

      // Inside the axis-aligned bounding box, outside the diamond.
      XCTAssertNil(controller.element(at: SionPoint(x: 0, y: -15)))
    }

    func testConnectableElementUsesRotatedFrame() throws {
      var element = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 100),
        kind: .rectangle
      )
      element.geometry.rotationRadians = .pi / 4
      let controller = try makeController(elements: [element])

      XCTAssertEqual(controller.connectableElement(at: SionPoint(x: 50, y: -10))?.id, element.id)
      XCTAssertNil(controller.connectableElement(at: SionPoint(x: 0, y: -15)))
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
