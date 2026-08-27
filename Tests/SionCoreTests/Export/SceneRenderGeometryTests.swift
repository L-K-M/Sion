import XCTest

@testable import SionCore

final class SceneRenderGeometryTests: XCTestCase {
  private let canvasArrowLength = 12.0
  private let contentPadding = SceneRenderGeometry.exportPadding
  private let svgMarkerViewportScale = 7.0 / 10.0
  private let svgFilledArrowFarCorners = [
    SionVector(dx: -9, dy: -5),
    SionVector(dx: -9, dy: 5),
  ]
  private let svgOpenArrowFarCorners = [
    SionVector(dx: -8, dy: -4),
    SionVector(dx: -8, dy: 4),
  ]

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
    let strokeRadius = (shape.style.stroke?.width ?? 0) / 2

    XCTAssertLessThanOrEqual(
      bounds.minX,
      shape.geometry.frame.minX - strokeRadius - contentPadding
    )
    XCTAssertLessThanOrEqual(
      bounds.minY,
      shape.geometry.frame.minY - strokeRadius - contentPadding
    )
    XCTAssertGreaterThanOrEqual(
      bounds.maxX,
      shape.geometry.frame.maxX + strokeRadius + contentPadding
    )
    XCTAssertGreaterThanOrEqual(
      bounds.maxY,
      shape.geometry.frame.maxY + strokeRadius + contentPadding
    )
  }

  func testContentBoundsIncludeDistantShadow() {
    var shape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      kind: .rectangle
    )
    let shadow = ShadowStyle(
      color: .primaryInk,
      offset: SionVector(dx: 300, dy: 200),
      blurRadius: 40
    )
    shape.style.shadows = [shadow]

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [shape])
    )
    XCTAssertGreaterThanOrEqual(
      bounds.maxX,
      shape.geometry.frame.maxX + shadow.offset.dx + shadow.blurRadius + contentPadding
    )
    XCTAssertGreaterThanOrEqual(
      bounds.maxY,
      shape.geometry.frame.maxY + shadow.offset.dy + shadow.blurRadius + contentPadding
    )
  }

  func testContentBoundsIncludeEveryShadow() {
    var shape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      kind: .rectangle
    )
    let positiveShadow = ShadowStyle(
      color: .primaryInk,
      offset: SionVector(dx: 300, dy: 200),
      blurRadius: 40
    )
    let negativeShadow = ShadowStyle(
      color: .primaryInk,
      offset: SionVector(dx: -300, dy: -200),
      blurRadius: 40
    )
    shape.style.shadows = [positiveShadow, negativeShadow]

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [shape])
    )

    XCTAssertGreaterThanOrEqual(
      bounds.maxX,
      shape.geometry.frame.maxX
        + positiveShadow.offset.dx
        + positiveShadow.blurRadius
        + contentPadding
    )
    XCTAssertGreaterThanOrEqual(
      bounds.maxY,
      shape.geometry.frame.maxY
        + positiveShadow.offset.dy
        + positiveShadow.blurRadius
        + contentPadding
    )
    XCTAssertLessThanOrEqual(
      bounds.minX,
      shape.geometry.frame.minX
        + negativeShadow.offset.dx
        - negativeShadow.blurRadius
        - contentPadding
    )
    XCTAssertLessThanOrEqual(
      bounds.minY,
      shape.geometry.frame.minY
        + negativeShadow.offset.dy
        - negativeShadow.blurRadius
        - contentPadding
    )
  }

  func testRotatedShadowBoundsCoverCanvasAndSVGOffsets() {
    var shape = SceneElement.shape(
      frame: SionRect(x: 100, y: 80, width: 40, height: 80),
      kind: .rectangle
    )
    shape.geometry.rotationRadians = .pi / 2
    shape.style = ElementStyle(
      fill: .solid(.black),
      shadows: [
        ShadowStyle(
          color: .black,
          offset: SionVector(dx: 80, dy: 0),
          blurRadius: 0
        )
      ]
    )

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [shape])
    )
    let canvasShadowMaximumX = 240.0
    let svgShadowMaximumY = 220.0

    // Canvas keeps the offset in base space; SVG rotates it with the group.
    XCTAssertGreaterThanOrEqual(bounds.maxX, canvasShadowMaximumX + contentPadding)
    XCTAssertGreaterThanOrEqual(bounds.maxY, svgShadowMaximumY + contentPadding)
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
    let pathHull = SionRect(x: -100, y: -100, width: 600, height: 500)
    let strokeRadius = (element.style.stroke?.width ?? 0) / 2
    let paintedPadding = strokeRadius + contentPadding

    XCTAssertLessThanOrEqual(bounds.minX, pathHull.minX - paintedPadding)
    XCTAssertLessThanOrEqual(bounds.minY, pathHull.minY - paintedPadding)
    XCTAssertGreaterThanOrEqual(bounds.maxX, pathHull.maxX + paintedPadding)
    XCTAssertGreaterThanOrEqual(bounds.maxY, pathHull.maxY + paintedPadding)
  }

  func testContentBoundsIncludeConnectorEndMarker() {
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
        targetDecoration: .filledArrow
      )
    )
    connector.style.stroke = StrokeStyle(color: .primaryInk, width: 20)

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [connector])
    )

    XCTAssertGreaterThanOrEqual(bounds.maxX, 180 + contentPadding)
    XCTAssertLessThanOrEqual(bounds.minY, -80 - contentPadding)
    XCTAssertGreaterThanOrEqual(bounds.maxY, 80 + contentPadding)
  }

  func testContentBoundsIncludeDefaultArrowOnShortConnector() {
    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 0, y: 0)),
      target: .free(SionPoint(x: 1, y: 0)),
      routingStyle: .straight
    )
    connector.content = .connector(
      ConnectorContent(
        source: .free(SionPoint(x: 0, y: 0)),
        target: .free(SionPoint(x: 1, y: 0)),
        routingStyle: .straight,
        targetDecoration: .filledArrow
      )
    )

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [connector])
    )
    let strokeRadius = (connector.style.stroke?.width ?? 0) / 2

    XCTAssertLessThanOrEqual(
      bounds.minX,
      1 - canvasArrowLength - strokeRadius - contentPadding
    )
  }

  func testContentBoundsIncludeStrokeScaledArrowsOnShortDiagonalConnector() {
    let start = SionPoint(x: 0, y: 0)
    let end = SionPoint(x: 1, y: 1)
    let strokeWidth = 20.0
    let markerScale = strokeWidth * svgMarkerViewportScale
    let angle = atan2(end.y - start.y, end.x - start.x)
    let fixtures: [(ConnectorDecoration, [SionVector])] = [
      (.openArrow, svgOpenArrowFarCorners),
      (.filledArrow, svgFilledArrowFarCorners),
    ]

    for (decoration, corners) in fixtures {
      var connector = SceneElement.connector(
        source: .free(start),
        target: .free(end),
        routingStyle: .straight
      )
      connector.content = .connector(
        ConnectorContent(
          source: .free(start),
          target: .free(end),
          routingStyle: .straight,
          targetDecoration: decoration
        )
      )
      connector.style.stroke = StrokeStyle(color: .primaryInk, width: strokeWidth)

      let bounds = SceneRenderGeometry.contentBounds(
        of: SionScene(elements: [connector])
      )
      let paintedCorners = corners.map { corner in
        let scaled = corner * markerScale
        let rotated = InteractionGeometry.rotated(scaled, by: angle)
        return end + rotated
      }

      XCTAssertLessThanOrEqual(
        bounds.minX,
        (paintedCorners.map(\.x).min() ?? end.x) - contentPadding,
        "\(decoration)"
      )
      XCTAssertLessThanOrEqual(
        bounds.minY,
        (paintedCorners.map(\.y).min() ?? end.y) - contentPadding,
        "\(decoration)"
      )
    }
  }

  func testContentBoundsIncludeConnectorLabel() {
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
        label: TextContent(string: "Endpoint"),
        labelPosition: 1
      )
    )

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [connector])
    )

    XCTAssertGreaterThanOrEqual(bounds.maxX, 180 + contentPadding)
    XCTAssertLessThanOrEqual(bounds.minY, -18 - contentPadding)
    XCTAssertGreaterThanOrEqual(bounds.maxY, 18 + contentPadding)
  }

  func testContentBoundsUsesProvidedRouteWithExportPadding() {
    let connector = SceneElement.connector(
      source: .free(SionPoint(x: 0, y: 0)),
      target: .free(SionPoint(x: 100, y: 0)),
      routingStyle: .straight
    )
    let route = ConnectorRoute(
      start: SionPoint(x: -100, y: -50),
      segments: [.line(to: SionPoint(x: 500, y: 150))]
    )
    var providerCalls = 0

    let bounds = SceneRenderGeometry.contentBounds(
      of: SionScene(elements: [connector]),
      connectorRoutes: { element in
        providerCalls += 1
        return element.id == connector.id ? route : nil
      }
    )
    let expected = SceneRenderGeometry.paintedBounds(of: connector, route: route)
      .expanded(by: contentPadding)

    XCTAssertEqual(bounds, expected)
    XCTAssertEqual(providerCalls, 1)
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
