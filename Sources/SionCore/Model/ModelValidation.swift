import Foundation

extension PortableValue {
  var isValid: Bool {
    switch self {
    case .null, .boolean, .integer, .unsignedInteger, .string:
      return true
    case .number(let value):
      return value.isFinite
    case .array(let values):
      return values.allSatisfy(\.isValid)
    case .object(let values):
      return values.values.allSatisfy(\.isValid)
    }
  }
}

extension SionPoint {
  var isValidCanvasPoint: Bool {
    isFinite
      && abs(x) <= SceneLimits.maximumCoordinateMagnitude
      && abs(y) <= SceneLimits.maximumCoordinateMagnitude
  }

  var isNormalized: Bool {
    isFinite && (0...1).contains(x) && (0...1).contains(y)
  }
}

extension SionColor {
  var isValid: Bool {
    [red, green, blue, alpha].allSatisfy { component in
      component.isFinite && (0...1).contains(component)
    }
  }
}

extension ElementStyle {
  var isValid: Bool {
    guard opacity.isFinite, (0...1).contains(opacity), fill.isValid else {
      return false
    }

    guard stroke?.isValid ?? true else {
      return false
    }

    return shadows.allSatisfy(\.isValid)
  }
}

extension FillStyle {
  fileprivate var isValid: Bool {
    switch self {
    case .none:
      return true
    case .solid(let color):
      return color.isValid
    case .linearGradient(let gradient):
      return gradient.isValid
    }
  }
}

extension LinearGradientFill {
  fileprivate var isValid: Bool {
    guard stops.count >= ModelValidationLimits.minimumGradientStopCount,
      start.isNormalized,
      end.isNormalized
    else {
      return false
    }

    var previousLocation = 0.0

    for (index, stop) in stops.enumerated() {
      guard stop.color.isValid,
        stop.location.isFinite,
        (0...1).contains(stop.location)
      else {
        return false
      }

      guard index == 0 || stop.location >= previousLocation else {
        return false
      }

      previousLocation = stop.location
    }

    return true
  }
}

extension StrokeStyle {
  fileprivate var isValid: Bool {
    guard color.isValid,
      width.isValidNonnegativeCanvasMetric,
      dashPattern.allSatisfy(\.isValidNonnegativeCanvasMetric)
    else {
      return false
    }

    return dashPattern.isEmpty || dashPattern.contains { $0 > 0 }
  }
}

extension ShadowStyle {
  fileprivate var isValid: Bool {
    color.isValid
      && offset.isFinite
      && abs(offset.dx) <= SceneLimits.maximumCoordinateMagnitude
      && abs(offset.dy) <= SceneLimits.maximumCoordinateMagnitude
      && blurRadius.isValidNonnegativeCanvasMetric
      && spread.isValidCanvasMetric
  }
}

extension TextStyle {
  var isValid: Bool {
    guard font.isValid,
      color.isValid,
      lineSpacing.isValidCanvasMetric,
      paragraphSpacing.isValidCanvasMetric
    else {
      return false
    }

    return insets.values.allSatisfy(\.isValidCanvasMetric)
  }
}

extension FontDescriptor {
  fileprivate var isValid: Bool {
    guard size.isFinite,
      size > 0,
      size <= SceneLimits.maximumCoordinateMagnitude
    else {
      return false
    }

    guard case .named(let name) = family else {
      return true
    }

    return !name.isEmpty
  }
}

extension TextInsets {
  fileprivate var values: [Double] {
    [top, leading, bottom, trailing]
  }
}

extension VectorPath {
  var isValid: Bool {
    guard !commands.isEmpty,
      commands.count <= SceneLimits.maximumPathCommandCount
    else {
      return false
    }

    var hasOpenSubpath = false

    for command in commands {
      switch command {
      case .move(let to):
        guard pointIsValid(to) else {
          return false
        }

        hasOpenSubpath = true
      case .line(let to):
        guard hasOpenSubpath, pointIsValid(to) else {
          return false
        }
      case .quadratic(let control, let to):
        guard hasOpenSubpath,
          pointIsValid(control),
          pointIsValid(to)
        else {
          return false
        }
      case .cubic(let control1, let control2, let to):
        guard hasOpenSubpath,
          pointIsValid(control1),
          pointIsValid(control2),
          pointIsValid(to)
        else {
          return false
        }
      case .close:
        guard hasOpenSubpath else {
          return false
        }
      }
    }

    return true
  }

  private func pointIsValid(_ point: SionPoint) -> Bool {
    switch coordinateSpace {
    case .normalized:
      return point.isNormalized
    case .localPoints:
      return point.isValidCanvasPoint
    }
  }
}

extension ElementContent {
  var shapeIsValid: Bool {
    guard case .shape(let shape) = self,
      case .roundedRectangle(let radius) = shape.kind
    else {
      return true
    }

    return radius.isValidNonnegativeCanvasMetric
  }

  var vectorPaths: [VectorPath] {
    switch self {
    case .shape(let shape):
      guard case .custom(let path) = shape.kind else {
        return []
      }

      return [path]
    case .path(let path):
      return [path.path]
    case .text, .image, .group, .connector:
      return []
    }
  }

  var textValues: [TextContent] {
    switch self {
    case .shape(let shape):
      return shape.label.map { [$0] } ?? []
    case .text(let text):
      return [text]
    case .connector(let connector):
      return connector.label.map { [$0] } ?? []
    case .path, .image, .group:
      return []
    }
  }
}

extension Optional where Wrapped == ManualConnectorRoute {
  func isValid(for routingStyle: ConnectorRoutingStyle) -> Bool {
    guard let route = self else {
      return true
    }

    return route.isValid(for: routingStyle)
  }
}

extension ManualConnectorRoute {
  fileprivate func isValid(for routingStyle: ConnectorRoutingStyle) -> Bool {
    switch (self, routingStyle) {
    case (.orthogonal(let waypoints), .orthogonal):
      return waypoints.count <= SceneLimits.maximumRouteSegmentCount
        && waypoints.allSatisfy(\.isValidCanvasPoint)
    case (.curved(let controlPoint), .curved):
      return controlPoint.isValidCanvasPoint
    case (.bezier(let sourceControl, let targetControl), .bezier):
      return sourceControl.isValidCanvasPoint && targetControl.isValidCanvasPoint
    case (.orthogonal, _), (.curved, _), (.bezier, _):
      return false
    }
  }
}

extension Double {
  fileprivate var isValidCanvasMetric: Bool {
    isFinite && abs(self) <= SceneLimits.maximumCoordinateMagnitude
  }

  fileprivate var isValidNonnegativeCanvasMetric: Bool {
    isFinite && self >= 0 && self <= SceneLimits.maximumCoordinateMagnitude
  }
}

private enum ModelValidationLimits {
  static let minimumGradientStopCount = 2
}
