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
      var notifications = 0
      _ = controller.observeChanges { notifications += 1 }

      controller.select(element.id)
      let baseline = notifications
      controller.select([element.id])

      XCTAssertEqual(controller.selection, [element.id])
      XCTAssertEqual(notifications, baseline)
    }

    func testSetSelectionDropsUnknownIDs() throws {
      let element = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let controller = try makeController(elements: [element])
      let unknownID = ElementID()

      controller.select([element.id, unknownID])

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

    func testMarqueeIntersectionMatchesNegativeDirectionDrags() throws {
      // Dragging up-left standardizes the rect: origin below-right of the hit.
      let element = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let controller = try makeController(elements: [element])

      let rect = SionRect(
        origin: SionPoint(x: 120, y: 80),
        size: SionSize(width: -200, height: -100)
      )

      XCTAssertEqual(controller.elementIDsIntersecting(rect), [element.id])
    }

    func testMarqueeIntersectionExcludesLockedAndHiddenElements() throws {
      var locked = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      locked.lockState = .locked
      var hidden = SceneElement.shape(
        frame: SionRect(x: 200, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      hidden.visibility = .hidden
      let editable = SceneElement.shape(
        frame: SionRect(x: 400, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let controller = try makeController(elements: [locked, hidden, editable])

      let wideRect = SionRect(x: -10, y: -10, width: 1_000, height: 100)
      XCTAssertEqual(controller.elementIDsIntersecting(wideRect), [editable.id])

      // Drag thresholds belong to the view; the controller only resolves hits.
      let tinyRect = SionRect(x: 400, y: 0, width: 1, height: 1)
      XCTAssertEqual(controller.elementIDsIntersecting(tinyRect), [editable.id])
    }

    func testMarqueeIntersectionIncludesConnectorsCrossingTheBand() throws {
      let source = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let target = SceneElement.shape(
        frame: SionRect(x: 300, y: 0, width: 100, height: 60),
        kind: .rectangle
      )
      let connector = SceneElement.connector(
        source: .element(
          source.id,
          attachment: .automatic,
          fallbackPoint: SionPoint(x: 100, y: 30)
        ),
        target: .element(
          target.id,
          attachment: .automatic,
          fallbackPoint: SionPoint(x: 300, y: 30)
        )
      )
      let controller = try makeController(elements: [source, target, connector])

      // A band across the route's middle without touching either shape.
      let band = SionRect(x: 180, y: 10, width: 40, height: 40)

      XCTAssertEqual(controller.elementIDsIntersecting(band), [connector.id])

      let reversedBand = SionRect(
        origin: SionPoint(x: 220, y: 50),
        size: SionSize(width: -40, height: -40)
      )
      XCTAssertEqual(controller.elementIDsIntersecting(reversedBand), [connector.id])
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
