import Foundation

public enum SceneRenderGeometry {
  public static let exportPadding = 32.0
  public static let minimumCanvasDimension = 256.0

  /// Supplies the visual route of a connector without re-deriving it.
  public typealias ConnectorRouteProvider = (SceneElement) -> ConnectorRoute?

  public static func connectorRoute(
    for element: SceneElement,
    in scene: SionScene
  ) -> ConnectorRoute? {
    guard case .connector(let connector) = element.content else {
      return nil
    }

    if let resolvedRoute = connector.resolvedRoute {
      return resolvedRoute
    }

    let sourceReference = referencePoint(for: connector.target, in: scene)
    let targetReference = referencePoint(for: connector.source, in: scene)
    guard
      let source = resolve(
        connector.source,
        use: .outgoing,
        toward: sourceReference,
        in: scene
      ),
      let target = resolve(
        connector.target,
        use: .incoming,
        toward: targetReference,
        in: scene
      )
    else {
      return nil
    }

    if let manualRoute = connector.manualRoute {
      return route(manualRoute, from: source, to: target)
    }

    let connectedIDs = Set(
      [connector.source.elementID, connector.target.elementID].compactMap { $0 })
    let obstacles = scene.elements.compactMap { candidate -> SionRect? in
      guard candidate.content.connector == nil,
        candidate.visibility == .visible,
        !connectedIDs.contains(candidate.id)
      else {
        return nil
      }

      // Routing uses a conservative box so rotated content never becomes traversable.
      return rotatedBounds(of: candidate.geometry)
    }
    return ConnectorRouter.route(
      from: source,
      to: target,
      style: connector.routingStyle,
      obstacles: obstacles
    )
  }

  public static func contentBounds(
    of scene: SionScene,
    connectorRoutes: ConnectorRouteProvider? = nil
  ) -> SionRect {
    if case .fixed(let size) = scene.canvas.extent {
      return SionRect(origin: .zero, size: size)
    }

    let content =
      visibleElementBounds(of: scene, connectorRoutes: connectorRoutes)
      ?? SionRect(
        x: 0,
        y: 0,
        width: minimumCanvasDimension,
        height: minimumCanvasDimension
      )
    return content.expanded(by: exportPadding)
  }

  /// Keeps off-page fixed content reachable without changing fixed export bounds.
  public static func editingCanvasBounds(
    of scene: SionScene,
    minimumInfiniteSize: SionSize,
    connectorRoutes: ConnectorRouteProvider? = nil
  ) -> SionRect {
    if case .fixed(let size) = scene.canvas.extent {
      let page = SionRect(origin: .zero, size: size)
      guard let content = visibleElementBounds(of: scene, connectorRoutes: connectorRoutes)
      else { return page }

      return page.union(content.expanded(by: exportPadding))
    }

    let minimumBounds = SionRect(origin: .zero, size: minimumInfiniteSize)
    guard scene.elements.contains(where: { $0.visibility == .visible }) else {
      return minimumBounds
    }

    return minimumBounds.union(contentBounds(of: scene, connectorRoutes: connectorRoutes))
  }

  private static func visibleElementBounds(
    of scene: SionScene,
    connectorRoutes: ConnectorRouteProvider? = nil
  ) -> SionRect? {
    var bounds: SionRect?

    for element in scene.elements where element.visibility == .visible {
      let route = connectorRoute(
        for: element,
        in: scene,
        provider: connectorRoutes
      )
      guard element.content.connector == nil || route != nil else { continue }

      let elementBounds = paintedBounds(of: element, route: route)
      bounds = bounds.map { $0.union(elementBounds) } ?? elementBounds
    }

    return bounds
  }

  /// Axis-aligned bounds of every visible style effect on one element.
  package static func paintedBounds(
    of element: SceneElement,
    route: ConnectorRoute? = nil
  ) -> SionRect {
    let localBounds = unrotatedPaintedBounds(of: element, route: route)
    guard element.content.connector == nil else { return localBounds }

    return rotatedBounds(
      localBounds,
      around: element.geometry.frame.standardized.center,
      by: element.geometry.rotationRadians
    )
  }

  static func unrotatedPaintedBounds(
    of element: SceneElement,
    route: ConnectorRoute? = nil
  ) -> SionRect {
    var bounds = baseBounds(of: element, route: route)
    bounds = bounds.expanded(by: strokeExpansion(for: element.style.stroke))

    if case .connector(let connector) = element.content, let route {
      let adornmentBounds = connectorAdornmentBounds(
        connector,
        route: route,
        style: element.style
      )
      bounds = bounds.union(adornmentBounds)
    }

    let sourceBounds = bounds

    // Bound every styled shadow so renderers cannot clip collection entries.
    for shadow in element.style.shadows {
      let blurExtent = shadow.blurRadius * PaintedBounds.shadowBlurExtentMultiplier
      let shadowBounds =
        sourceBounds
        .translated(by: shadow.offset)
        .expanded(by: blurExtent)
      bounds = bounds.union(shadowBounds)
    }

    return bounds
  }

  private static func connectorRoute(
    for element: SceneElement,
    in scene: SionScene,
    provider: ConnectorRouteProvider?
  ) -> ConnectorRoute? {
    guard element.content.connector != nil else { return nil }
    if let provider {
      return provider(element)
    }

    return connectorRoute(for: element, in: scene)
  }

  private static func baseBounds(
    of element: SceneElement,
    route: ConnectorRoute?
  ) -> SionRect {
    if let route {
      return bounds(containing: route.exportBoundsPoints)
    }

    let frame = element.geometry.frame.standardized
    guard case .path(let content) = element.content else { return frame }

    let points = pathPoints(content.path, in: frame)
    guard !points.isEmpty else { return frame }

    let commandBounds = bounds(containing: points)
    return frame.union(commandBounds)
  }

  private static func pathPoints(
    _ path: VectorPath,
    in frame: SionRect
  ) -> [SionPoint] {
    func resolved(_ point: SionPoint) -> SionPoint {
      switch path.coordinateSpace {
      case .normalized:
        return frame.point(atNormalized: point)
      case .localPoints:
        return SionPoint(x: frame.minX + point.x, y: frame.minY + point.y)
      }
    }

    return path.commands.flatMap { command in
      switch command {
      case .move(let point), .line(let point):
        return [resolved(point)]
      case .quadratic(let control, let point):
        return [resolved(control), resolved(point)]
      case .cubic(let control1, let control2, let point):
        return [resolved(control1), resolved(control2), resolved(point)]
      case .close:
        return []
      }
    }
  }

  private static func connectorAdornmentBounds(
    _ connector: ConnectorContent,
    route: ConnectorRoute,
    style: ElementStyle
  ) -> SionRect {
    var bounds = bounds(containing: route.exportBoundsPoints)
    let strokeWidth =
      style.stroke?.width ?? PaintedBounds.nativeDefaultConnectorWidth

    if connector.sourceDecoration != .none {
      let radius = connectorDecorationRadius(
        connector.sourceDecoration,
        strokeWidth: strokeWidth
      )
      bounds = bounds.union(pointBounds(route.start, radius: radius))
    }
    if connector.targetDecoration != .none {
      let radius = connectorDecorationRadius(
        connector.targetDecoration,
        strokeWidth: strokeWidth
      )
      bounds = bounds.union(pointBounds(route.end, radius: radius))
    }

    if connector.label != nil {
      let point = route.point(atFraction: connector.labelPosition)
      let labelBounds = SionRect(
        x: point.x - (PaintedBounds.connectorLabelWidth / 2),
        y: point.y - (PaintedBounds.connectorLabelHeight / 2),
        width: PaintedBounds.connectorLabelWidth,
        height: PaintedBounds.connectorLabelHeight
      )
      bounds = bounds.union(labelBounds)
    }

    return bounds
  }

  private static func connectorDecorationRadius(
    _ decoration: ConnectorDecoration,
    strokeWidth: Double
  ) -> Double {
    let nativeRadius: Double
    let svgRadiusFactor: Double
    switch decoration {
    case .none:
      return 0
    case .openArrow, .filledArrow:
      nativeRadius = PaintedBounds.nativeArrowRadius
      svgRadiusFactor = PaintedBounds.svgArrowMarkerRadiusFactor
    case .circle:
      nativeRadius = PaintedBounds.nativeCircleRadius
      svgRadiusFactor = PaintedBounds.svgCompactMarkerRadiusFactor
    case .diamond:
      nativeRadius = PaintedBounds.nativeDiamondRadius
      svgRadiusFactor = PaintedBounds.svgCompactMarkerRadiusFactor
    }

    let nativePaintedRadius = nativeRadius + (strokeWidth / 2)
    let svgRadius = strokeWidth * svgRadiusFactor
    return max(nativePaintedRadius, svgRadius)
  }

  private static func strokeExpansion(for stroke: StrokeStyle?) -> Double {
    guard let stroke else { return 0 }

    let radius = stroke.width / 2
    guard stroke.lineJoin == .miter else { return radius }

    return radius * PaintedBounds.nativeMiterLimit
  }

  private static func pointBounds(_ point: SionPoint, radius: Double) -> SionRect {
    SionRect(x: point.x, y: point.y, width: 0, height: 0).expanded(by: radius)
  }

  private static func bounds(containing points: [SionPoint]) -> SionRect {
    guard let first = points.first else { return .zero }

    return points.dropFirst().reduce(
      SionRect(x: first.x, y: first.y, width: 0, height: 0)
    ) { bounds, point in
      bounds.union(SionRect(x: point.x, y: point.y, width: 0, height: 0))
    }
  }

  private static func rotatedBounds(of geometry: ElementGeometry) -> SionRect {
    let frame = geometry.frame.standardized
    return rotatedBounds(
      frame,
      around: frame.center,
      by: geometry.rotationRadians
    )
  }

  private static func rotatedBounds(
    _ bounds: SionRect,
    around center: SionPoint,
    by radians: Double
  ) -> SionRect {
    let frame = bounds.standardized
    guard radians != 0 else { return frame }

    let corners = [
      SionPoint(x: frame.minX, y: frame.minY),
      SionPoint(x: frame.maxX, y: frame.minY),
      SionPoint(x: frame.maxX, y: frame.maxY),
      SionPoint(x: frame.minX, y: frame.maxY),
    ].map { point in
      InteractionGeometry.rotated(
        point,
        around: center,
        by: radians
      )
    }

    let minimumX = corners.map(\.x).min() ?? frame.minX
    let maximumX = corners.map(\.x).max() ?? frame.maxX
    let minimumY = corners.map(\.y).min() ?? frame.minY
    let maximumY = corners.map(\.y).max() ?? frame.maxY
    return SionRect(
      x: minimumX,
      y: minimumY,
      width: maximumX - minimumX,
      height: maximumY - minimumY
    )
  }

  private static func referencePoint(
    for endpoint: ConnectionEndpoint,
    in scene: SionScene
  ) -> SionPoint {
    switch endpoint {
    case .free(let point):
      return point
    case .element(let id, _, let fallbackPoint):
      return scene.element(withID: id)?.geometry.frame.center ?? fallbackPoint
    }
  }

  private static func resolve(
    _ endpoint: ConnectionEndpoint,
    use: MagnetUse,
    toward reference: SionPoint,
    in scene: SionScene
  ) -> ResolvedConnectorEndpoint? {
    switch endpoint {
    case .free(let point):
      return ResolvedConnectorEndpoint(point: point, outwardDirection: .zero)
    case .element(let id, let attachment, let fallbackPoint):
      guard let element = scene.element(withID: id) else {
        return ResolvedConnectorEndpoint(
          point: fallbackPoint,
          outwardDirection: (reference - fallbackPoint).normalized
        )
      }

      let magnets = element.resolvedMagnets
      switch attachment {
      case .magnet(let magnetID):
        if let resolved = magnets.first(where: { resolved in
          resolved.magnet.id == magnetID
            && resolved.magnet.connectionDirection.allows(use)
        }) {
          return resolved.endpoint
        }
      case .automatic:
        if let resolved = nearestMagnet(
          among: magnets,
          to: reference,
          use: use
        ) {
          return resolved.endpoint
        }
      }

      return boundaryEndpoint(of: element.geometry, toward: reference)
    }
  }

  private static func nearestMagnet(
    among magnets: [ResolvedMagnet],
    to reference: SionPoint,
    use: MagnetUse
  ) -> ResolvedMagnet? {
    var nearest: ResolvedMagnet?
    var nearestDistance = Double.infinity

    // Declaration order keeps equal-distance automatic attachment stable.
    for magnet in magnets where magnet.magnet.connectionDirection.allows(use) {
      let distance = (magnet.endpoint.point - reference).lengthSquared
      guard distance < nearestDistance else {
        continue
      }

      nearest = magnet
      nearestDistance = distance
    }

    return nearest
  }

  private static func boundaryEndpoint(
    of geometry: ElementGeometry,
    toward reference: SionPoint
  ) -> ResolvedConnectorEndpoint {
    let frame = geometry.frame.standardized
    let rotation = geometry.rotationRadians
    guard rotation != 0 else {
      return boundaryEndpoint(of: frame, toward: reference)
    }

    // Intersect in local space, then restore the element's canvas rotation.
    let localReference = InteractionGeometry.rotated(
      reference,
      around: frame.center,
      by: -rotation
    )
    let localEndpoint = boundaryEndpoint(of: frame, toward: localReference)

    return ResolvedConnectorEndpoint(
      point: InteractionGeometry.rotated(
        localEndpoint.point,
        around: frame.center,
        by: rotation
      ),
      outwardDirection: InteractionGeometry.rotated(
        localEndpoint.outwardDirection,
        by: rotation
      )
    )
  }

  private static func boundaryEndpoint(
    of frame: SionRect,
    toward reference: SionPoint
  ) -> ResolvedConnectorEndpoint {
    let center = frame.center
    let delta = reference - center
    guard delta.lengthSquared > 0 else {
      return ResolvedConnectorEndpoint(
        point: SionPoint(x: frame.maxX, y: center.y),
        outwardDirection: .east
      )
    }

    let horizontalScale = delta.dx == 0 ? Double.infinity : (frame.width / 2) / abs(delta.dx)
    let verticalScale = delta.dy == 0 ? Double.infinity : (frame.height / 2) / abs(delta.dy)
    let scale = min(horizontalScale, verticalScale)
    let direction: SionVector
    if horizontalScale < verticalScale {
      direction = delta.dx > 0 ? .east : .west
    } else {
      direction = delta.dy > 0 ? .south : .north
    }

    return ResolvedConnectorEndpoint(
      point: center + (delta * scale),
      outwardDirection: direction
    )
  }

  private static func route(
    _ manual: ManualConnectorRoute,
    from source: ResolvedConnectorEndpoint,
    to target: ResolvedConnectorEndpoint
  ) -> ConnectorRoute {
    switch manual {
    case .orthogonal(let waypoints):
      let points = ConnectorRouter.collapseCollinear([source.point] + waypoints + [target.point])
      return ConnectorRoute(
        start: source.point,
        segments: points.dropFirst().map { .line(to: $0) }
      )
    case .curved(let controlPoint):
      return ConnectorRoute(
        start: source.point,
        segments: [.quadratic(control: controlPoint, to: target.point)]
      )
    case .bezier(let sourceControl, let targetControl):
      return ConnectorRoute(
        start: source.point,
        segments: [
          .cubic(
            control1: sourceControl,
            control2: targetControl,
            to: target.point
          )
        ]
      )
    }
  }
}

private enum PaintedBounds {
  // Use the larger Canvas/SVG footprints so neither renderer clips.
  static let connectorLabelWidth = 160.0
  static let connectorLabelHeight = 36.0
  static let nativeArrowRadius = hypot(12.0, 6.0)
  static let nativeCircleRadius = 5.0
  static let nativeDiamondRadius = 10.0
  static let nativeDefaultConnectorWidth = 1.5
  static let nativeMiterLimit = 10.0
  static let shadowBlurExtentMultiplier = 3.0
  static let svgCompactMarkerRadiusFactor = 4.0

  // SVG markers scale a 10-unit viewBox into seven stroke-width units.
  static let svgMarkerViewportScale = 7.0 / 10.0
  static let svgFilledArrowReferenceOffset = SionVector(dx: 9, dy: 5)
  static let svgArrowMarkerRadiusFactor =
    hypot(
      svgFilledArrowReferenceOffset.dx,
      svgFilledArrowReferenceOffset.dy
    ) * svgMarkerViewportScale
}

extension ConnectorRoute {
  fileprivate var exportBoundsPoints: [SionPoint] {
    var points = [start]
    for segment in segments {
      switch segment {
      case .line(let to):
        points.append(to)
      case .quadratic(let control, let to):
        points.append(contentsOf: [control, to])
      case .cubic(let control1, let control2, let to):
        points.append(contentsOf: [control1, control2, to])
      }
    }
    return points
  }
}
