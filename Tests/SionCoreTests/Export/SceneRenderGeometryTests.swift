import XCTest

@testable import SionCore

final class SceneRenderGeometryTests: XCTestCase {
  func testContentBoundsIncludeWideStroke() {
    var shape = SceneElement.shape(
      frame: SionRect(x: 100, y: 100, width: 100, height: 100),
      kind: .rectangle
    )
    shape.style.stroke = StrokeStyle(
      color: .primaryInk,
      width: 200,
      lineJoin: .miter
    )

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [shape])
    )

    XCTAssertLessThanOrEqual(bounds.minX, -32)
    XCTAssertLessThanOrEqual(bounds.minY, -32)
    XCTAssertGreaterThanOrEqual(bounds.maxX, 332)
    XCTAssertGreaterThanOrEqual(bounds.maxY, 332)
  }

  func testContentBoundsIncludeDistantShadow() {
    var shape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      kind: .rectangle
    )
    shape.style.shadows = [
      ShadowStyle(
        color: .primaryInk,
        offset: SionVector(dx: 300, dy: 200),
        blurRadius: 40
      )
    ]

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [shape])
    )

    XCTAssertGreaterThan(bounds.maxX, 432)
    XCTAssertGreaterThan(bounds.maxY, 332)
  }

  func testContentBoundsIncludeLocalPathCommandsOutsideFrame() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: SionPoint(x: -200, y: -100)),
        .cubic(
          control1: SionPoint(x: -150, y: 300),
          control2: SionPoint(x: 350, y: -200),
          to: SionPoint(x: 400, y: 300)
        ),
      ]
    )
    let element = SceneElement.path(
      frame: SionRect(x: 100, y: 100, width: 100, height: 100),
      path: path
    )

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [element])
    )

    XCTAssertLessThanOrEqual(bounds.minX, -132)
    XCTAssertLessThanOrEqual(bounds.minY, -132)
    XCTAssertGreaterThanOrEqual(bounds.maxX, 532)
    XCTAssertGreaterThanOrEqual(bounds.maxY, 432)
  }

  func testContentBoundsIncludeConnectorLabelAndMarker() {
    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 0, y: 0)),
      target: .free(SionPoint(x: 100, y: 0)),
      routingStyle: .straight
    )
    connector.content = .connector(
      ConnectorContent(
        source: .free(SionPoint(x: 0, y: 0)),
        target: .free(SionPoint(x: 100, y: 0)),
        routingStyle: .straight,
        targetDecoration: .filledArrow,
        label: TextContent(string: "Endpoint"),
        labelPosition: 1
      )
    )
    connector.style.stroke = StrokeStyle(color: .primaryInk, width: 20)

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [connector])
    )

    XCTAssertGreaterThanOrEqual(bounds.maxX, 212)
    XCTAssertLessThanOrEqual(bounds.minY, -102)
    XCTAssertGreaterThanOrEqual(bounds.maxY, 102)
  }

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
    let firstLegEnd = try XCTUnwrap(route.polylinePoints.dropFirst().first)
    XCTAssertGreaterThan(firstLegEnd.x, route.start.x)
    XCTAssertEqual(firstLegEnd.y, route.start.y, accuracy: pointAccuracy)
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
