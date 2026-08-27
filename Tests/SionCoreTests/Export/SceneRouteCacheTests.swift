import Foundation
import XCTest

@testable import SionCore

final class SceneRouteCacheTests: XCTestCase {
  private let sourceElement = SceneElement.shape(
    id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!),
    frame: SionRect(x: 0, y: 0, width: 100, height: 60)
  )
  private let targetElement = SceneElement.shape(
    id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!),
    frame: SionRect(x: 300, y: 0, width: 100, height: 60)
  )

  func testNonConnectorRoutesToNil() {
    var cache = SceneRouteCache()
    let scene = SionScene(elements: [sourceElement, targetElement])

    XCTAssertNil(cache.route(for: sourceElement, in: scene))
  }

  func testRouteMatchesDirectRouting() {
    var cache = SceneRouteCache()
    let connector = makeConnector()
    let scene = SionScene(elements: [sourceElement, targetElement, connector])

    let direct = SceneRenderGeometry.connectorRoute(for: connector, in: scene)
    XCTAssertEqual(cache.route(for: connector, in: scene), direct)
    XCTAssertEqual(cache.route(for: connector, in: scene), direct)
  }

  /// The cache deliberately replays stale routes until told about an edit;
  /// callers own invalidation, so both halves of the contract are pinned here.
  func testInvalidateRefreshesMovedEndpoint() {
    var cache = SceneRouteCache()
    let connector = makeConnector()
    let scene = SionScene(elements: [sourceElement, targetElement, connector])

    let before = cache.route(for: connector, in: scene)

    var moved = sourceElement
    moved.geometry.frame.origin = SionPoint(x: 0, y: 200)
    let movedScene = SionScene(elements: [moved, targetElement, connector])

    XCTAssertEqual(cache.route(for: connector, in: movedScene), before)

    cache.invalidate()

    let after = cache.route(for: connector, in: movedScene)
    XCTAssertNotEqual(after, before)
    XCTAssertEqual(
      after,
      SceneRenderGeometry.connectorRoute(for: connector, in: movedScene)
    )
  }

  private func makeConnector() -> SceneElement {
    SceneElement.connector(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!),
      source: .element(
        sourceElement.id,
        attachment: .automatic,
        fallbackPoint: sourceElement.geometry.frame.center
      ),
      target: .element(
        targetElement.id,
        attachment: .automatic,
        fallbackPoint: targetElement.geometry.frame.center
      ),
      routingStyle: .straight
    )
  }
}
