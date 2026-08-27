import Foundation

public enum PathCoordinateSpace: String, Codable, CaseIterable, Sendable {
  case normalized
  case localPoints
}

public enum PathFillRule: String, Codable, CaseIterable, Sendable {
  case evenOdd
  case nonZero
}

public enum PathCommand: Codable, Equatable, Sendable {
  case move(to: SionPoint)
  case line(to: SionPoint)
  case quadratic(control: SionPoint, to: SionPoint)
  case cubic(control1: SionPoint, control2: SionPoint, to: SionPoint)
  case close
}

public struct VectorPath: Codable, Equatable, Sendable {
  public var coordinateSpace: PathCoordinateSpace
  public var fillRule: PathFillRule
  public var commands: [PathCommand]

  public init(
    coordinateSpace: PathCoordinateSpace = .normalized,
    fillRule: PathFillRule = .nonZero,
    commands: [PathCommand]
  ) {
    self.coordinateSpace = coordinateSpace
    self.fillRule = fillRule
    self.commands = commands
  }
}

public enum ShapeKind: Codable, Equatable, Sendable {
  case rectangle
  case roundedRectangle(radius: Double)
  case ellipse
  case diamond
  case triangle
  case hexagon
  case capsule
  case cylinder
  case custom(VectorPath)
}

public struct TextContent: Codable, Equatable, Sendable {
  public var string: String
  public var style: TextStyle

  public init(string: String, style: TextStyle = .standaloneDefault) {
    self.string = string
    self.style = style
  }
}

public struct ShapeContent: Codable, Equatable, Sendable {
  public var kind: ShapeKind
  public var label: TextContent?

  public init(kind: ShapeKind, label: TextContent? = nil) {
    self.kind = kind
    self.label = label
  }
}

public struct PathContent: Codable, Equatable, Sendable {
  public var path: VectorPath

  public init(path: VectorPath) {
    self.path = path
  }
}

public enum ImageScalingMode: String, Codable, CaseIterable, Sendable {
  case fit
  case fill
  case stretch
  case tile
}

public enum ImageInterpolation: String, Codable, CaseIterable, Sendable {
  case automatic
  case nearestNeighbor
  case highQuality
}

public struct ImageContent: Codable, Equatable, Sendable {
  /// The exact imported bytes retained for future reuse.
  public var assetID: AssetID
  /// A validated PNG used for rendering and recovery exports.
  public var displayAssetID: AssetID
  public var scalingMode: ImageScalingMode
  public var interpolation: ImageInterpolation
  public var accessibilityDescription: String?

  public init(
    assetID: AssetID,
    displayAssetID: AssetID,
    scalingMode: ImageScalingMode = .fit,
    interpolation: ImageInterpolation = .automatic,
    accessibilityDescription: String? = nil
  ) {
    self.assetID = assetID
    self.displayAssetID = displayAssetID
    self.scalingMode = scalingMode
    self.interpolation = interpolation
    self.accessibilityDescription = accessibilityDescription
  }
}

public enum GroupClipping: String, Codable, CaseIterable, Sendable {
  case none
  case clipToBounds
}

public struct GroupContent: Codable, Equatable, Sendable {
  public var clipping: GroupClipping

  public init(clipping: GroupClipping = .none) {
    self.clipping = clipping
  }
}

public enum MagnetAttachment: Codable, Equatable, Sendable {
  case automatic
  case magnet(MagnetID)
}

public enum ConnectionEndpoint: Codable, Equatable, Sendable {
  case element(
    ElementID,
    attachment: MagnetAttachment,
    fallbackPoint: SionPoint
  )
  case free(SionPoint)

  public var elementID: ElementID? {
    switch self {
    case .element(let elementID, _, _):
      elementID
    case .free:
      nil
    }
  }
}

public enum ConnectorDecoration: String, Codable, CaseIterable, Sendable {
  case none
  case openArrow
  case filledArrow
  case circle
  case diamond
}

public enum ManualConnectorRoute: Codable, Equatable, Sendable {
  case orthogonal(waypoints: [SionPoint])
  case curved(controlPoint: SionPoint)
  case bezier(sourceControl: SionPoint, targetControl: SionPoint)
}

public struct ConnectorContent: Codable, Equatable, Sendable {
  public static let defaultLabelPosition = 0.5

  public var source: ConnectionEndpoint
  public var target: ConnectionEndpoint
  public var routingStyle: ConnectorRoutingStyle
  public var manualRoute: ManualConnectorRoute?
  /// The saved rendering is preserved until an editing command invalidates it.
  public var resolvedRoute: ConnectorRoute?
  public var sourceDecoration: ConnectorDecoration
  public var targetDecoration: ConnectorDecoration
  public var label: TextContent?
  public var labelPosition: Double

  public init(
    source: ConnectionEndpoint,
    target: ConnectionEndpoint,
    routingStyle: ConnectorRoutingStyle = .orthogonal,
    manualRoute: ManualConnectorRoute? = nil,
    resolvedRoute: ConnectorRoute? = nil,
    sourceDecoration: ConnectorDecoration = .none,
    targetDecoration: ConnectorDecoration = .filledArrow,
    label: TextContent? = nil,
    labelPosition: Double = ConnectorContent.defaultLabelPosition
  ) {
    self.source = source
    self.target = target
    self.routingStyle = routingStyle
    self.manualRoute = manualRoute
    self.resolvedRoute = resolvedRoute
    self.sourceDecoration = sourceDecoration
    self.targetDecoration = targetDecoration
    self.label = label
    self.labelPosition = labelPosition
  }
}

public enum ElementContent: Codable, Equatable, Sendable {
  case shape(ShapeContent)
  case path(PathContent)
  case text(TextContent)
  case image(ImageContent)
  case group(GroupContent)
  case connector(ConnectorContent)

  public var isGroup: Bool {
    if case .group = self {
      return true
    }

    return false
  }

  public var connector: ConnectorContent? {
    if case .connector(let content) = self {
      return content
    }

    return nil
  }
}
