#if canImport(AppKit)
  import XCTest

  @testable import SionCore
  @testable import SionKit

  @MainActor
  final class SionEditorControllerRouteCacheTests: XCTestCase {
    func testRouteCacheInvalidatesWhenConnectedElementMoves() throws {
      let (controller, connector) = try makeConnectedScene()

      let routeBefore = try XCTUnwrap(controller.connectorRoute(for: connector))

      let sourceID = controller.document.scene.elements[0].id
      controller.select(sourceID)
      try controller.beginMove()
      try controller.moveSelection(by: SionVector(dx: 0, dy: 200))
      try controller.endMove()

      let routeAfter = try XCTUnwrap(controller.connectorRoute(for: connector))

      XCTAssertNotEqual(routeBefore, routeAfter)
    }

    func testRouteCacheInvalidatesOnUndo() throws {
      let (controller, connector) = try makeConnectedScene()
      let originalRoute = try XCTUnwrap(controller.connectorRoute(for: connector))

      let sourceID = controller.document.scene.elements[0].id
      controller.select(sourceID)
      try controller.beginMove()
      try controller.moveSelection(by: SionVector(dx: 0, dy: 200))
      try controller.endMove()
      controller.undoSceneEdit()

      let cachedRoute = try XCTUnwrap(controller.connectorRoute(for: connector))
      let derivedRoute = try XCTUnwrap(
        SceneRenderGeometry.connectorRoute(
          for: connector,
          in: controller.document.scene
        )
      )

      XCTAssertEqual(cachedRoute, originalRoute)
      XCTAssertEqual(cachedRoute, derivedRoute)
    }

    func testConnectorIsSelectableByRouteOnly() throws {
      let (controller, connector) = try makeConnectedScene()

      // On the routed path: selectable.
      XCTAssertEqual(controller.element(at: SionPoint(x: 200, y: 30))?.id, connector.id)
      // Far off the path: never the connector's stale frame.
      XCTAssertNotEqual(controller.element(at: SionPoint(x: 200, y: 500))?.id, connector.id)
    }

    private func makeConnectedScene() throws -> (SionEditorController, SceneElement) {
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
      let controller = try SionEditorController(
        package: SionPackage(
          document: SionDocument(scene: SionScene(elements: [source, target, connector]))
        ),
        undoManagerProvider: { nil },
        didChange: { _ in }
      )

      return (controller, connector)
    }
  }

#endif
