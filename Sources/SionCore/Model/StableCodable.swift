import Foundation

extension FillStyle {
  private enum CodingKeys: String, CodingKey {
    case type
    case color
    case gradient
  }

  private enum Kind: String, Codable {
    case none
    case solid
    case linearGradient
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .none:
      self = .none
    case .solid:
      self = .solid(try container.decode(SionColor.self, forKey: .color))
    case .linearGradient:
      self = .linearGradient(
        try container.decode(LinearGradientFill.self, forKey: .gradient)
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .none:
      try container.encode(Kind.none, forKey: .type)
    case .solid(let color):
      try container.encode(Kind.solid, forKey: .type)
      try container.encode(color, forKey: .color)
    case .linearGradient(let gradient):
      try container.encode(Kind.linearGradient, forKey: .type)
      try container.encode(gradient, forKey: .gradient)
    }
  }
}

extension FontFamily {
  private enum CodingKeys: String, CodingKey {
    case type
    case name
  }

  private enum Kind: String, Codable {
    case system
    case named
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .system:
      self = .system
    case .named:
      self = .named(try container.decode(String.self, forKey: .name))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .system:
      try container.encode(Kind.system, forKey: .type)
    case .named(let name):
      try container.encode(Kind.named, forKey: .type)
      try container.encode(name, forKey: .name)
    }
  }
}

extension PathCommand {
  private enum CodingKeys: String, CodingKey {
    case type
    case to
    case control
    case control1
    case control2
  }

  private enum Kind: String, Codable {
    case move
    case line
    case quadratic
    case cubic
    case close
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .move:
      self = .move(to: try container.decode(SionPoint.self, forKey: .to))
    case .line:
      self = .line(to: try container.decode(SionPoint.self, forKey: .to))
    case .quadratic:
      self = .quadratic(
        control: try container.decode(SionPoint.self, forKey: .control),
        to: try container.decode(SionPoint.self, forKey: .to)
      )
    case .cubic:
      self = .cubic(
        control1: try container.decode(SionPoint.self, forKey: .control1),
        control2: try container.decode(SionPoint.self, forKey: .control2),
        to: try container.decode(SionPoint.self, forKey: .to)
      )
    case .close:
      self = .close
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .move(let point):
      try container.encode(Kind.move, forKey: .type)
      try container.encode(point, forKey: .to)
    case .line(let point):
      try container.encode(Kind.line, forKey: .type)
      try container.encode(point, forKey: .to)
    case .quadratic(let control, let point):
      try container.encode(Kind.quadratic, forKey: .type)
      try container.encode(control, forKey: .control)
      try container.encode(point, forKey: .to)
    case .cubic(let control1, let control2, let point):
      try container.encode(Kind.cubic, forKey: .type)
      try container.encode(control1, forKey: .control1)
      try container.encode(control2, forKey: .control2)
      try container.encode(point, forKey: .to)
    case .close:
      try container.encode(Kind.close, forKey: .type)
    }
  }
}

extension ShapeKind {
  private enum CodingKeys: String, CodingKey {
    case type
    case radius
    case path
  }

  private enum Kind: String, Codable {
    case rectangle
    case roundedRectangle
    case ellipse
    case diamond
    case triangle
    case hexagon
    case capsule
    case cylinder
    case custom
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .rectangle:
      self = .rectangle
    case .roundedRectangle:
      self = .roundedRectangle(radius: try container.decode(Double.self, forKey: .radius))
    case .ellipse:
      self = .ellipse
    case .diamond:
      self = .diamond
    case .triangle:
      self = .triangle
    case .hexagon:
      self = .hexagon
    case .capsule:
      self = .capsule
    case .cylinder:
      self = .cylinder
    case .custom:
      self = .custom(try container.decode(VectorPath.self, forKey: .path))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .rectangle:
      try container.encode(Kind.rectangle, forKey: .type)
    case .roundedRectangle(let radius):
      try container.encode(Kind.roundedRectangle, forKey: .type)
      try container.encode(radius, forKey: .radius)
    case .ellipse:
      try container.encode(Kind.ellipse, forKey: .type)
    case .diamond:
      try container.encode(Kind.diamond, forKey: .type)
    case .triangle:
      try container.encode(Kind.triangle, forKey: .type)
    case .hexagon:
      try container.encode(Kind.hexagon, forKey: .type)
    case .capsule:
      try container.encode(Kind.capsule, forKey: .type)
    case .cylinder:
      try container.encode(Kind.cylinder, forKey: .type)
    case .custom(let path):
      try container.encode(Kind.custom, forKey: .type)
      try container.encode(path, forKey: .path)
    }
  }
}

extension MagnetAttachment {
  private enum CodingKeys: String, CodingKey {
    case type
    case magnetID
  }

  private enum Kind: String, Codable {
    case automatic
    case magnet
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .automatic:
      self = .automatic
    case .magnet:
      self = .magnet(try container.decode(MagnetID.self, forKey: .magnetID))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .automatic:
      try container.encode(Kind.automatic, forKey: .type)
    case .magnet(let id):
      try container.encode(Kind.magnet, forKey: .type)
      try container.encode(id, forKey: .magnetID)
    }
  }
}

extension ConnectionEndpoint {
  private enum CodingKeys: String, CodingKey {
    case type
    case elementID
    case attachment
    case fallbackPoint
    case point
  }

  private enum Kind: String, Codable {
    case element
    case free
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .element:
      self = .element(
        try container.decode(ElementID.self, forKey: .elementID),
        attachment: try container.decode(MagnetAttachment.self, forKey: .attachment),
        fallbackPoint: try container.decode(SionPoint.self, forKey: .fallbackPoint)
      )
    case .free:
      self = .free(try container.decode(SionPoint.self, forKey: .point))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .element(let elementID, let attachment, let fallbackPoint):
      try container.encode(Kind.element, forKey: .type)
      try container.encode(elementID, forKey: .elementID)
      try container.encode(attachment, forKey: .attachment)
      try container.encode(fallbackPoint, forKey: .fallbackPoint)
    case .free(let point):
      try container.encode(Kind.free, forKey: .type)
      try container.encode(point, forKey: .point)
    }
  }
}

extension ManualConnectorRoute {
  private enum CodingKeys: String, CodingKey {
    case type
    case waypoints
    case controlPoint
    case sourceControl
    case targetControl
  }

  private enum Kind: String, Codable {
    case orthogonal
    case curved
    case bezier
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .orthogonal:
      self = .orthogonal(
        waypoints: try container.decode([SionPoint].self, forKey: .waypoints)
      )
    case .curved:
      self = .curved(
        controlPoint: try container.decode(SionPoint.self, forKey: .controlPoint)
      )
    case .bezier:
      self = .bezier(
        sourceControl: try container.decode(SionPoint.self, forKey: .sourceControl),
        targetControl: try container.decode(SionPoint.self, forKey: .targetControl)
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .orthogonal(let waypoints):
      try container.encode(Kind.orthogonal, forKey: .type)
      try container.encode(waypoints, forKey: .waypoints)
    case .curved(let controlPoint):
      try container.encode(Kind.curved, forKey: .type)
      try container.encode(controlPoint, forKey: .controlPoint)
    case .bezier(let sourceControl, let targetControl):
      try container.encode(Kind.bezier, forKey: .type)
      try container.encode(sourceControl, forKey: .sourceControl)
      try container.encode(targetControl, forKey: .targetControl)
    }
  }
}

extension ElementContent {
  private enum CodingKeys: String, CodingKey {
    case type
    case shape
    case path
    case text
    case image
    case group
    case connector
  }

  private enum Kind: String, Codable {
    case shape
    case path
    case text
    case image
    case group
    case connector
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .shape:
      self = .shape(try container.decode(ShapeContent.self, forKey: .shape))
    case .path:
      self = .path(try container.decode(PathContent.self, forKey: .path))
    case .text:
      self = .text(try container.decode(TextContent.self, forKey: .text))
    case .image:
      self = .image(try container.decode(ImageContent.self, forKey: .image))
    case .group:
      self = .group(try container.decode(GroupContent.self, forKey: .group))
    case .connector:
      self = .connector(
        try container.decode(ConnectorContent.self, forKey: .connector)
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .shape(let content):
      try container.encode(Kind.shape, forKey: .type)
      try container.encode(content, forKey: .shape)
    case .path(let content):
      try container.encode(Kind.path, forKey: .type)
      try container.encode(content, forKey: .path)
    case .text(let content):
      try container.encode(Kind.text, forKey: .type)
      try container.encode(content, forKey: .text)
    case .image(let content):
      try container.encode(Kind.image, forKey: .type)
      try container.encode(content, forKey: .image)
    case .group(let content):
      try container.encode(Kind.group, forKey: .type)
      try container.encode(content, forKey: .group)
    case .connector(let content):
      try container.encode(Kind.connector, forKey: .type)
      try container.encode(content, forKey: .connector)
    }
  }
}
