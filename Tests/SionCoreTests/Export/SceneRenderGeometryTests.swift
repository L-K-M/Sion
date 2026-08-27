import XCTest

@testable import SionCore

final class SceneRenderGeometryTests: XCTestCase {
  func testAutomaticBoundaryEndpointFollowsElementRotation() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 100, y: 200, width: 200, height: 100)
    )
    shape.geometry.rotationRadians = .pi / 2
    shape.magnetConfiguration = .preset(.none)
    let connector = SceneElement.connector(
      source: .element(
        shape.id,
        attachment: .automatic,
        fallbackPoint: .zero
      ),
      target: .free(SionPoint(x: 400, y: 250)),
      routingStyle: .orthogonal
    )
    let scene = SionScene(elements: [shape, connector])

    let route = try XCTUnwrap(
      SceneRenderGeometry.connectorRoute(for: connector, in: scene)
    )

    XCTAssertEqual(route.start.x, 250, accuracy: pointAccuracy)
    XCTAssertEqual(route.start.y, 250, accuracy: pointAccuracy)
    XCTAssertGreaterThan(route.polylinePoints[1].x, route.start.x)
    XCTAssertEqual(route.polylinePoints[1].y, route.start.y, accuracy: pointAccuracy)
  }

  func testOrthogonalRouteAvoidsRotatedObstacleBounds() throws {
    var obstacle = SceneElement.shape(
      frame: SionRect(x: 140, y: 75, width: 100, height: 20)
    )
    obstacle.geometry.rotationRadians = .pi / 2
    let connector = SceneElement.connector(
      source: .free(SionPoint(x: 50, y: 85)),
      target: .free(SionPoint(x: 330, y: 85)),
      routingStyle: .orthogonal
    )
    let scene = SionScene(elements: [obstacle, connector])
    let rotatedObstacleBounds = SionRect(x: 180, y: 35, width: 20, height: 100)

    let route = try XCTUnwrap(
      SceneRenderGeometry.connectorRoute(for: connector, in: scene)
    )

    XCTAssertFalse(
      route.polylineSegments.contains { segment in
        segment.intersectsInterior(of: rotatedObstacleBounds)
      }
    )
  }

  private let pointAccuracy = 1e-9
}
