import Foundation
import XCTest

@testable import SionCore

final class ConnectorRouterTests: XCTestCase {
  private static let excessiveObstacleCount = 128

  private let source = ResolvedConnectorEndpoint(
    point: SionPoint(x: 100, y: 100),
    outwardDirection: .east
  )
  private let target = ResolvedConnectorEndpoint(
    point: SionPoint(x: 400, y: 250),
    outwardDirection: .west
  )

  func testStraightRouteContainsOneLine() {
    let route = ConnectorRouter.route(from: source, to: target, style: .straight)

    XCTAssertEqual(route.start, source.point)
    XCTAssertEqual(route.segments, [.line(to: target.point)])
  }

  func testCurvedRouteUsesAQuadraticSegment() {
    let route = ConnectorRouter.route(from: source, to: target, style: .curved)

    guard case .quadratic(let control, let end) = route.segments.first else {
      return XCTFail("Expected one quadratic segment")
    }

    XCTAssertEqual(route.segments.count, 1)
    XCTAssertEqual(end, target.point)
    XCTAssertTrue(control.isFinite)
  }

  func testBezierRouteUsesManualControlPoints() {
    let controls = BezierControlPoints(
      first: SionPoint(x: 180, y: 40),
      second: SionPoint(x: 320, y: 310)
    )

    let route = ConnectorRouter.route(
      from: source,
      to: target,
      style: .bezier,
      bezierControlPoints: controls
    )

    XCTAssertEqual(
      route.segments,
      [
        .cubic(control1: controls.first, control2: controls.second, to: target.point)
      ])
  }

  func testOrthogonalRouteIsAxisAligned() {
    let route = ConnectorRouter.route(from: source, to: target, style: .orthogonal)

    assertAxisAligned(route.polylinePoints)
    XCTAssertEqual(route.start, source.point)
    XCTAssertEqual(route.end, target.point)
    XCTAssertGreaterThan(route.polylinePoints[1].x, route.start.x)
    XCTAssertGreaterThan(route.end.x, route.polylinePoints[route.polylinePoints.count - 2].x)
  }

  func testSameSideOrthogonalRouteLoopsOutsideBothEndpoints() {
    let first = ResolvedConnectorEndpoint(
      point: SionPoint(x: 100, y: 100),
      outwardDirection: .east
    )
    let second = ResolvedConnectorEndpoint(
      point: SionPoint(x: 400, y: 100),
      outwardDirection: .east
    )

    let route = ConnectorRouter.route(from: first, to: second, style: .orthogonal)
    let points = route.polylinePoints

    assertAxisAligned(points)
    XCTAssertGreaterThan(points.map(\.x).max() ?? 0, second.point.x)
    XCTAssertTrue(points.contains { $0.y != first.point.y })
  }

  func testOrthogonalRouteDetoursAroundObstacle() {
    let obstacle = SionRect(x: 220, y: 60, width: 80, height: 230)

    let route = ConnectorRouter.route(
      from: source,
      to: target,
      style: .orthogonal,
      obstacles: [obstacle]
    )

    assertAxisAligned(route.polylinePoints)
    XCTAssertFalse(
      route.polylineSegments.contains { segment in
        segment.intersectsInterior(of: obstacle)
      })
  }

  func testOrthogonalRoutingIsIndependentOfObstacleOrder() {
    let obstacles = [
      SionRect(x: 180, y: 80, width: 50, height: 120),
      SionRect(x: 280, y: 160, width: 60, height: 130),
    ]

    let first = ConnectorRouter.route(
      from: source,
      to: target,
      style: .orthogonal,
      obstacles: obstacles
    )
    let second = ConnectorRouter.route(
      from: source,
      to: target,
      style: .orthogonal,
      obstacles: Array(obstacles.reversed())
    )

    XCTAssertEqual(first, second)
  }

  func testOrthogonalRoutingFallsBackWhenVisibilityGridWouldBeTooLarge() {
    let blockingObstacle = SionRect(x: 200, y: 50, width: 100, height: 250)
    let distantObstacles = (0..<Self.excessiveObstacleCount).map { index in
      let offset = Double(index * 40)

      return SionRect(
        x: 10_000 + offset,
        y: 20_000 + offset,
        width: 1,
        height: 1
      )
    }
    let obstacles = [blockingObstacle] + distantObstacles
    let route = ConnectorRouter.route(
      from: source,
      to: target,
      style: .orthogonal,
      obstacles: obstacles
    )
    let reorderedRoute = ConnectorRouter.route(
      from: source,
      to: target,
      style: .orthogonal,
      obstacles: Array(obstacles.reversed())
    )
    let sourceStub = source.point + (.east * ConnectorRoutingDefaults.endpointStubLength)
    let targetStub = target.point + (.west * ConnectorRoutingDefaults.endpointStubLength)
    let expandedBlocker = blockingObstacle.expanded(
      by: ConnectorRoutingDefaults.obstacleClearance
    )
    let fallbackY = expandedBlocker.minY - ConnectorRoutingDefaults.endpointStubLength

    XCTAssertEqual(
      route.polylinePoints,
      [
        source.point,
        sourceStub,
        SionPoint(x: sourceStub.x, y: fallbackY),
        SionPoint(x: targetStub.x, y: fallbackY),
        targetStub,
        target.point,
      ])
    XCTAssertEqual(reorderedRoute, route)
  }

  func testCollinearPointsAreCollapsed() {
    let points = ConnectorRouter.collapseCollinear([
      SionPoint(x: 0, y: 0),
      SionPoint(x: 20, y: 0),
      SionPoint(x: 40, y: 0),
      SionPoint(x: 40, y: 20),
    ])

    XCTAssertEqual(
      points,
      [
        SionPoint(x: 0, y: 0),
        SionPoint(x: 40, y: 0),
        SionPoint(x: 40, y: 20),
      ])
  }

  func testRoutePointFollowsPathLength() {
    let route = ConnectorRoute(
      start: SionPoint(x: 0, y: 0),
      segments: [
        .line(to: SionPoint(x: 100, y: 0)),
        .line(to: SionPoint(x: 100, y: 300)),
      ]
    )

    XCTAssertEqual(route.point(atFraction: 0.5), SionPoint(x: 100, y: 100))
    XCTAssertEqual(route.point(atFraction: -1), route.start)
    XCTAssertEqual(route.point(atFraction: 2), route.end)
  }

  func testCurvedPolylineFollowsVisibleCurve() {
    let route = ConnectorRoute(
      start: SionPoint(x: 0, y: 0),
      segments: [
        .quadratic(
          control: SionPoint(x: 50, y: 100),
          to: SionPoint(x: 100, y: 0)
        )
      ]
    )

    XCTAssertGreaterThan(route.polylinePoints.count, 2)
    XCTAssertGreaterThan(route.polylinePoints.map(\.y).max() ?? 0, 40)
    XCTAssertEqual(route.polylinePoints.first, route.start)
    XCTAssertEqual(route.polylinePoints.last, route.end)
  }

  func testRouteSegmentsUseStableDiscriminatedJSON() throws {
    let segment = ConnectorRouteSegment.cubic(
      control1: SionPoint(x: 10, y: 20),
      control2: SionPoint(x: 30, y: 40),
      to: SionPoint(x: 50, y: 60)
    )
    let data = try JSONEncoder().encode(segment)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    XCTAssertEqual(object["type"] as? String, "cubic")
    XCTAssertNotNil(object["control1"])
    XCTAssertNotNil(object["control2"])
    XCTAssertNil(object["_0"])
    XCTAssertEqual(try JSONDecoder().decode(ConnectorRouteSegment.self, from: data), segment)
  }

  private func assertAxisAligned(
    _ points: [SionPoint],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for (first, second) in zip(points, points.dropFirst()) {
      XCTAssertTrue(
        first.x == second.x || first.y == second.y,
        "Non-orthogonal segment: \(first) -> \(second)",
        file: file,
        line: line
      )
    }
  }
}
