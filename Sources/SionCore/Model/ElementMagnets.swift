import Foundation

extension SceneElement {
  /// Expands editing presets against the element's visible outline.
  public var expandedMagnets: [Magnet] {
    MagnetResolver.magnets(
      for: magnetConfiguration,
      normalizedOutline: normalizedMagnetOutline
    )
  }

  /// Resolves magnets in canvas coordinates, including element rotation.
  public var resolvedMagnets: [ResolvedMagnet] {
    let frame = geometry.frame.standardized

    return expandedMagnets.map { magnet in
      let endpoint = MagnetResolver.resolve(magnet, in: frame)

      return ResolvedMagnet(
        magnet: magnet,
        endpoint: geometry.rotating(endpoint, around: frame.center)
      )
    }
  }

  private var normalizedMagnetOutline: [SionPoint] {
    switch content {
    case .shape(let shape):
      return shape.kind.normalizedMagnetOutline(for: geometry.frame.size)
    case .path(let path):
      return path.path.normalizedMagnetOutline(for: geometry.frame.size)
    case .text, .image, .group, .connector:
      return MagnetResolver.rectangleOutline
    }
  }
}

extension ElementGeometry {
  fileprivate func rotating(
    _ endpoint: ResolvedConnectorEndpoint,
    around center: SionPoint
  ) -> ResolvedConnectorEndpoint {
    guard rotationRadians != 0 else {
      return endpoint
    }

    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let offset = endpoint.point - center
    let direction = endpoint.outwardDirection

    return ResolvedConnectorEndpoint(
      point: SionPoint(
        x: center.x + (offset.dx * cosine) - (offset.dy * sine),
        y: center.y + (offset.dx * sine) + (offset.dy * cosine)
      ),
      outwardDirection: SionVector(
        dx: (direction.dx * cosine) - (direction.dy * sine),
        dy: (direction.dx * sine) + (direction.dy * cosine)
      )
    )
  }
}

public enum ShapeGeometryDefaults {
  public static let hexagonInsetFraction = 0.2
  public static let cylinderArcFraction = 0.125
}

extension ShapeKind {
  fileprivate func normalizedMagnetOutline(for size: SionSize) -> [SionPoint] {
    switch self {
    case .triangle:
      return ElementMagnetOutlines.triangle
    case .diamond:
      return ElementMagnetOutlines.diamond
    case .hexagon:
      return ElementMagnetOutlines.hexagon
    case .custom(let path):
      return path.normalizedMagnetOutline(for: size)
    case .rectangle, .roundedRectangle, .ellipse, .capsule, .cylinder:
      return MagnetResolver.rectangleOutline
    }
  }
}

extension VectorPath {
  fileprivate func normalizedMagnetOutline(for size: SionSize) -> [SionPoint] {
    guard let outline = primaryOutline else {
      return MagnetResolver.rectangleOutline
    }

    let normalized: [SionPoint]
    switch coordinateSpace {
    case .normalized:
      normalized = outline
    case .localPoints:
      guard size.width > 0, size.height > 0 else {
        return MagnetResolver.rectangleOutline
      }

      normalized = outline.map { point in
        SionPoint(x: point.x / size.width, y: point.y / size.height)
      }
    }

    let cleaned = normalized.removingConsecutiveDuplicates()
    guard cleaned.count > 1 else {
      return MagnetResolver.rectangleOutline
    }

    return cleaned
  }

  fileprivate var primaryOutline: [SionPoint]? {
    var outlines: [[SionPoint]] = []
    var current: [SionPoint] = []

    for command in commands {
      switch command {
      case .move(let to):
        append(current, to: &outlines)
        current = [to]
      case .line(let to), .quadratic(_, let to), .cubic(_, _, let to):
        current.append(to)
      case .close:
        append(current, to: &outlines)
        current = []
      }
    }

    append(current, to: &outlines)

    var best: [SionPoint]?
    var bestArea = -Double.infinity

    for outline in outlines {
      let area = abs(outline.signedArea)
      let replacesBest =
        area > bestArea
        || (area == bestArea && outline.count > (best?.count ?? 0))
      guard replacesBest else {
        continue
      }

      best = outline
      bestArea = area
    }

    return best
  }

  fileprivate func append(_ outline: [SionPoint], to outlines: inout [[SionPoint]]) {
    let cleaned = outline.removingConsecutiveDuplicates()
    guard cleaned.count > 1 else {
      return
    }

    outlines.append(cleaned)
  }
}

extension Array where Element == SionPoint {
  fileprivate func removingConsecutiveDuplicates() -> [SionPoint] {
    var result: [SionPoint] = []

    for point in self {
      guard point != result.last else {
        continue
      }

      result.append(point)
    }

    if result.count > 1, result.first == result.last {
      result.removeLast()
    }

    return result
  }

  fileprivate var signedArea: Double {
    guard count > 2 else {
      return 0
    }

    var doubledArea = 0.0

    for index in indices {
      let first = self[index]
      let second = self[(index + 1) % count]
      doubledArea += (first.x * second.y) - (second.x * first.y)
    }

    return doubledArea / 2
  }
}

private enum ElementMagnetOutlines {
  static let triangle = [
    SionPoint(x: 0.5, y: 0),
    SionPoint(x: 1, y: 1),
    SionPoint(x: 0, y: 1),
  ]

  static let diamond = [
    SionPoint(x: 0.5, y: 0),
    SionPoint(x: 1, y: 0.5),
    SionPoint(x: 0.5, y: 1),
    SionPoint(x: 0, y: 0.5),
  ]

  static let hexagon = [
    SionPoint(x: ShapeGeometryDefaults.hexagonInsetFraction, y: 0),
    SionPoint(x: 1 - ShapeGeometryDefaults.hexagonInsetFraction, y: 0),
    SionPoint(x: 1, y: 0.5),
    SionPoint(x: 1 - ShapeGeometryDefaults.hexagonInsetFraction, y: 1),
    SionPoint(x: ShapeGeometryDefaults.hexagonInsetFraction, y: 1),
    SionPoint(x: 0, y: 0.5),
  ]
}
