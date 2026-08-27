import Foundation

public enum SceneRenderGeometry {
  public static let exportPadding = 32.0
  public static let minimumCanvasDimension = 256.0

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

  public static func contentBounds(of scene: SionScene) -> SionRect {
    if case .fixed(let size) = scene.canvas.extent {
      return SionRect(origin: .zero, size: size)
    }

    let content =
      visibleElementBounds(of: scene)
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
    minimumInfiniteSize: SionSize
  ) -> SionRect {
    if case .fixed(let size) = scene.canvas.extent {
      let page = SionRect(origin: .zero, size: size)
      guard let content = visibleElementBounds(of: scene) else { return page }

      return page.union(content.expanded(by: exportPadding))
    }

    let minimumBounds = SionRect(origin: .zero, size: minimumInfiniteSize)
    guard scene.elements.contains(where: { $0.visibility == .visible }) else {
      return minimumBounds
    }

    return minimumBounds.union(contentBounds(of: scene))
  }

  private static func visibleElementBounds(of scene: SionScene) -> SionRect? {
    var bounds: SionRect?

    for element in scene.elements where element.visibility == .visible {
      if let route = connectorRoute(for: element, in: scene) {
        for point in route.exportBoundsPoints {
          let pointRect = SionRect(x: point.x, y: point.y, width: 0, height: 0)
          bounds = bounds.map { $0.union(pointRect) } ?? pointRect
        }
        continue
      }

      guard element.content.connector == nil else {
        continue
      }
      let elementBounds = rotatedBounds(of: element.geometry)
      bounds = bounds.map { $0.union(elementBounds) } ?? elementBounds
    }

    return bounds
  }

  private static func rotatedBounds(of geometry: ElementGeometry) -> SionRect {
    let frame = geometry.frame.standardized
    guard geometry.rotationRadians != 0 else {
      return frame
    }

    let center = frame.center
    let corners = [
      SionPoint(x: frame.minX, y: frame.minY),
      SionPoint(x: frame.maxX, y: frame.minY),
      SionPoint(x: frame.maxX, y: frame.maxY),
      SionPoint(x: frame.minX, y: frame.maxY),
    ].map { point in
      InteractionGeometry.rotated(
        point,
        around: center,
        by: geometry.rotationRadians
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
