import Foundation

/// A language-neutral JSON value reserved for namespaced model extensions.
public indirect enum PortableValue: Equatable, Sendable {
  case null
  case boolean(Bool)
  case integer(Int64)
  case unsignedInteger(UInt64)
  case number(Double)
  case string(String)
  case array([PortableValue])
  case object([String: PortableValue])

  public static func == (left: PortableValue, right: PortableValue) -> Bool {
    switch (left, right) {
    case (.null, .null):
      return true
    case (.boolean(let left), .boolean(let right)):
      return left == right
    case (.integer(let left), .integer(let right)):
      return left == right
    case (.unsignedInteger(let left), .unsignedInteger(let right)):
      return left == right
    case (.number(let left), .number(let right)):
      return left == right
    case (.string(let left), .string(let right)):
      return left == right
    case (.array(let left), .array(let right)):
      return left == right
    case (.object(let left), .object(let right)):
      return left == right
    case (.integer(let left), .unsignedInteger(let right)),
      (.unsignedInteger(let right), .integer(let left)):
      return left >= 0 && UInt64(left) == right
    case (.integer(let integer), .number(let number)),
      (.number(let number), .integer(let integer)):
      return Double(exactly: integer) == number
    case (.unsignedInteger(let integer), .number(let number)),
      (.number(let number), .unsignedInteger(let integer)):
      return Double(exactly: integer) == number
    default:
      return false
    }
  }
}

extension PortableValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
      return
    }

    if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
      return
    }

    if let value = try? container.decode(Int64.self) {
      self = .integer(value)
      return
    }

    if let value = try? container.decode(UInt64.self) {
      self = .unsignedInteger(value)
      return
    }

    if let value = try? container.decode(Double.self), value.isFinite {
      self = .number(value)
      return
    }

    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }

    if let value = try? container.decode([PortableValue].self) {
      self = .array(value)
      return
    }

    if let value = try? container.decode([String: PortableValue].self) {
      self = .object(value)
      return
    }

    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Extension value is not valid JSON."
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .null:
      try container.encodeNil()
    case .boolean(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .unsignedInteger(let value):
      try container.encode(value)
    case .number(let value):
      guard value.isFinite else {
        throw EncodingError.invalidValue(
          value,
          EncodingError.Context(
            codingPath: encoder.codingPath,
            debugDescription: "Extension numbers must be finite."
          )
        )
      }

      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

public enum CanvasExtent: Equatable, Sendable {
  case infinite
  case fixed(SionSize)
}

extension CanvasExtent: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case size
  }

  private enum Kind: String, Codable {
    case infinite
    case fixed
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(Kind.self, forKey: .type) {
    case .infinite:
      self = .infinite
    case .fixed:
      self = .fixed(try container.decode(SionSize.self, forKey: .size))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .infinite:
      try container.encode(Kind.infinite, forKey: .type)
    case .fixed(let size):
      try container.encode(Kind.fixed, forKey: .type)
      try container.encode(size, forKey: .size)
    }
  }
}

public enum GridVisibility: String, Codable, CaseIterable, Sendable {
  case hidden
  case visible
}

public struct CanvasGrid: Codable, Equatable, Sendable {
  public var visibility: GridVisibility
  public var spacing: Double
  public var subdivisions: Int

  public init(
    visibility: GridVisibility = .hidden,
    spacing: Double = CanvasDefaults.gridSpacing,
    subdivisions: Int = CanvasDefaults.gridSubdivisions
  ) {
    self.visibility = visibility
    self.spacing = spacing
    self.subdivisions = subdivisions
  }
}

public struct SionCanvas: Codable, Equatable, Sendable {
  public var extent: CanvasExtent
  public var background: SionColor
  public var grid: CanvasGrid

  public init(
    extent: CanvasExtent = .infinite,
    background: SionColor = .canvas,
    grid: CanvasGrid = CanvasGrid()
  ) {
    self.extent = extent
    self.background = background
    self.grid = grid
  }
}

public struct ElementGeometry: Codable, Equatable, Sendable {
  public var frame: SionRect
  public var rotationRadians: Double

  public init(frame: SionRect, rotationRadians: Double = 0) {
    self.frame = frame
    self.rotationRadians = rotationRadians
  }

  /// The axis-aligned bounds of the frame after rotation about its center.
  public var rotatedBounds: SionRect {
    let standardized = frame.standardized
    guard rotationRadians != 0 else {
      return standardized
    }

    let center = standardized.center
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let corners = [
      SionPoint(x: standardized.minX, y: standardized.minY),
      SionPoint(x: standardized.maxX, y: standardized.minY),
      SionPoint(x: standardized.maxX, y: standardized.maxY),
      SionPoint(x: standardized.minX, y: standardized.maxY),
    ].map { point in
      let dx = point.x - center.x
      let dy = point.y - center.y
      return SionPoint(
        x: center.x + (dx * cosine) - (dy * sine),
        y: center.y + (dx * sine) + (dy * cosine)
      )
    }

    let minimumX = corners.map(\.x).min() ?? standardized.minX
    let maximumX = corners.map(\.x).max() ?? standardized.maxX
    let minimumY = corners.map(\.y).min() ?? standardized.minY
    let maximumY = corners.map(\.y).max() ?? standardized.maxY
    return SionRect(
      x: minimumX,
      y: minimumY,
      width: maximumX - minimumX,
      height: maximumY - minimumY
    )
  }
}

public enum ElementVisibility: String, Codable, CaseIterable, Sendable {
  case visible
  case hidden
}

public enum ElementLockState: String, Codable, CaseIterable, Sendable {
  case editable
  case locked
}

public struct SceneElement: Codable, Equatable, Sendable {
  public var id: ElementID
  /// Grouping is logical; every frame remains in absolute canvas coordinates.
  public var parentID: ElementID?
  public var name: String?
  public var geometry: ElementGeometry
  public var visibility: ElementVisibility
  public var lockState: ElementLockState
  public var magnetConfiguration: MagnetConfiguration
  public var style: ElementStyle
  public var content: ElementContent
  public var extensions: [String: PortableValue]

  public init(
    id: ElementID = ElementID(),
    parentID: ElementID? = nil,
    name: String? = nil,
    geometry: ElementGeometry,
    visibility: ElementVisibility = .visible,
    lockState: ElementLockState = .editable,
    magnetConfiguration: MagnetConfiguration,
    style: ElementStyle,
    content: ElementContent,
    extensions: [String: PortableValue] = [:]
  ) {
    self.id = id
    self.parentID = parentID
    self.name = name
    self.geometry = geometry
    self.visibility = visibility
    self.lockState = lockState
    self.magnetConfiguration = magnetConfiguration
    self.style = style
    self.content = content
    self.extensions = extensions
  }
}

extension SceneElement {
  public static func shape(
    id: ElementID = ElementID(),
    frame: SionRect,
    kind: ShapeKind = .roundedRectangle(radius: SceneElementDefaults.cornerRadius),
    text: String = "",
    parentID: ElementID? = nil
  ) -> SceneElement {
    let label: TextContent? =
      text.isEmpty
      ? nil
      : TextContent(string: text, style: .shapeLabelDefault)

    return SceneElement(
      id: id,
      parentID: parentID,
      geometry: ElementGeometry(frame: frame),
      magnetConfiguration: .preset(.cardinalFour),
      style: .shapeDefault,
      content: .shape(ShapeContent(kind: kind, label: label))
    )
  }

  public static func text(
    id: ElementID = ElementID(),
    frame: SionRect,
    text: String,
    parentID: ElementID? = nil
  ) -> SceneElement {
    SceneElement(
      id: id,
      parentID: parentID,
      geometry: ElementGeometry(frame: frame),
      magnetConfiguration: .preset(.cardinalFour),
      style: .textDefault,
      content: .text(TextContent(string: text))
    )
  }

  public static func path(
    id: ElementID = ElementID(),
    frame: SionRect,
    path: VectorPath,
    parentID: ElementID? = nil
  ) -> SceneElement {
    SceneElement(
      id: id,
      parentID: parentID,
      geometry: ElementGeometry(frame: frame),
      magnetConfiguration: .preset(.vertices),
      style: .shapeDefault,
      content: .path(PathContent(path: path))
    )
  }

  public static func image(
    id: ElementID = ElementID(),
    frame: SionRect,
    assetID: AssetID,
    displayAssetID: AssetID,
    parentID: ElementID? = nil
  ) -> SceneElement {
    SceneElement(
      id: id,
      parentID: parentID,
      geometry: ElementGeometry(frame: frame),
      magnetConfiguration: .preset(.eight),
      style: .imageDefault,
      content: .image(
        ImageContent(assetID: assetID, displayAssetID: displayAssetID)
      )
    )
  }

  public static func group(
    id: ElementID = ElementID(),
    frame: SionRect,
    parentID: ElementID? = nil
  ) -> SceneElement {
    SceneElement(
      id: id,
      parentID: parentID,
      geometry: ElementGeometry(frame: frame),
      magnetConfiguration: .preset(.none),
      style: .groupDefault,
      content: .group(GroupContent())
    )
  }

  public static func connector(
    id: ElementID = ElementID(),
    source: ConnectionEndpoint,
    target: ConnectionEndpoint,
    routingStyle: ConnectorRoutingStyle = .orthogonal,
    parentID: ElementID? = nil
  ) -> SceneElement {
    SceneElement(
      id: id,
      parentID: parentID,
      geometry: ElementGeometry(frame: .zero),
      magnetConfiguration: .preset(.none),
      style: .connectorDefault,
      content: .connector(
        ConnectorContent(
          source: source,
          target: target,
          routingStyle: routingStyle
        )
      )
    )
  }
}

public struct SionScene: Codable, Equatable, Sendable {
  public var canvas: SionCanvas
  public internal(set) var elements: [SceneElement]
  public var extensions: [String: PortableValue]

  public init(
    canvas: SionCanvas = SionCanvas(),
    elements: [SceneElement] = [],
    extensions: [String: PortableValue] = [:]
  ) {
    self.canvas = canvas
    self.elements = elements
    self.extensions = extensions
  }

  public func element(withID id: ElementID) -> SceneElement? {
    elements.first { $0.id == id }
  }

  public func index(of id: ElementID) -> Int? {
    elements.firstIndex { $0.id == id }
  }

  public func children(of parentID: ElementID?) -> [SceneElement] {
    elements.filter { $0.parentID == parentID }
  }

  public func descendantIDs(of parentID: ElementID) -> Set<ElementID> {
    var descendants = Set<ElementID>()
    var pending = [parentID]

    while let candidate = pending.popLast() {
      for child in elements where child.parentID == candidate {
        guard descendants.insert(child.id).inserted else {
          continue
        }

        pending.append(child.id)
      }
    }

    return descendants
  }

  public func validate() throws {
    guard elements.count <= SceneLimits.maximumElementCount else {
      throw SceneValidationError.tooManyElements(elements.count)
    }

    guard extensions.values.allSatisfy(\.isValid) else {
      throw SceneValidationError.invalidExtension
    }

    try validateCanvas()

    var byID = [ElementID: SceneElement]()

    for element in elements {
      guard byID.updateValue(element, forKey: element.id) == nil else {
        throw SceneValidationError.duplicateElementID(element.id)
      }

      try validateGeometry(of: element)
      try validateLocalContent(of: element)
    }

    for element in elements {
      try validateParent(of: element, in: byID)
      try validateConnector(of: element, in: byID)
    }

    try validateParentCycles(in: byID)
  }

  private func validateGeometry(of element: SceneElement) throws {
    let frame = element.geometry.frame
    let values = [
      frame.origin.x,
      frame.origin.y,
      frame.size.width,
      frame.size.height,
      element.geometry.rotationRadians,
    ]

    let standardized = frame.standardized
    let isInsideCanvasLimits = [
      standardized.minX,
      standardized.minY,
      standardized.maxX,
      standardized.maxY,
    ].allSatisfy { abs($0) <= SceneLimits.maximumCoordinateMagnitude }

    guard values.allSatisfy(\.isFinite),
      frame.size.width >= 0,
      frame.size.height >= 0,
      isInsideCanvasLimits
    else {
      throw SceneValidationError.invalidGeometry(element.id)
    }
  }

  private func validateLocalContent(of element: SceneElement) throws {
    guard element.extensions.values.allSatisfy(\.isValid) else {
      throw SceneValidationError.invalidExtension
    }

    guard element.content.shapeIsValid else {
      throw SceneValidationError.invalidShape(element.id)
    }

    guard element.content.vectorPaths.allSatisfy(\.isValid) else {
      throw SceneValidationError.invalidVectorPath(element.id)
    }

    if case .preset(.perSegment(let count)) = element.magnetConfiguration,
      !(1...MagnetResolver.maximumMagnetsPerSegment).contains(count)
    {
      throw SceneValidationError.invalidMagnet(element.id)
    }

    let magnets = element.expandedMagnets
    guard magnets.count <= SceneLimits.maximumMagnetsPerElement else {
      throw SceneValidationError.tooManyMagnets(element.id)
    }

    var magnetIDs = Set<MagnetID>()
    for magnet in magnets {
      let position = magnet.normalizedPosition
      let positionIsNormalized = (0...1).contains(position.x) && (0...1).contains(position.y)

      guard magnetIDs.insert(magnet.id).inserted,
        !magnet.id.rawValue.isEmpty,
        position.isFinite,
        positionIsNormalized,
        magnet.outwardDirection.isFinite,
        magnet.outwardDirection != .zero
      else {
        throw SceneValidationError.invalidMagnet(element.id)
      }
    }

    if case .image(let image) = element.content {
      guard !image.assetID.rawValue.isEmpty, !image.displayAssetID.rawValue.isEmpty else {
        throw SceneValidationError.emptyAssetID(element.id)
      }
    }

    guard element.style.isValid else {
      throw SceneValidationError.invalidStyle(element.id)
    }

    guard element.content.textValues.allSatisfy(\.style.isValid) else {
      throw SceneValidationError.invalidText(element.id)
    }

    guard let connector = element.content.connector else {
      return
    }

    guard (0...1).contains(connector.labelPosition), connector.labelPosition.isFinite else {
      throw SceneValidationError.invalidConnectorLabelPosition(element.id)
    }

    try validateEndpoint(connector.source, connectorID: element.id)
    try validateEndpoint(connector.target, connectorID: element.id)

    guard connector.manualRoute.isValid(for: connector.routingStyle) else {
      throw SceneValidationError.invalidManualRoute(element.id)
    }

    if let route = connector.resolvedRoute {
      guard route.segments.count <= SceneLimits.maximumRouteSegmentCount,
        route.start.isValidCanvasPoint,
        route.segments.allSatisfy(routeSegmentIsValid)
      else {
        throw SceneValidationError.invalidResolvedRoute(element.id)
      }
    }
  }

  private func validateCanvas() throws {
    guard canvas.background.isValid,
      canvas.grid.spacing.isFinite,
      canvas.grid.spacing > 0,
      canvas.grid.spacing <= SceneLimits.maximumCoordinateMagnitude,
      canvas.grid.subdivisions > 0,
      canvas.grid.subdivisions <= SceneLimits.maximumGridSubdivisions
    else {
      throw SceneValidationError.invalidCanvas
    }

    guard case .fixed(let size) = canvas.extent else {
      return
    }

    guard size.isFinite,
      size.width > 0,
      size.height > 0,
      size.width <= SceneLimits.maximumCoordinateMagnitude,
      size.height <= SceneLimits.maximumCoordinateMagnitude
    else {
      throw SceneValidationError.invalidCanvas
    }
  }

  private func validateEndpoint(
    _ endpoint: ConnectionEndpoint,
    connectorID: ElementID
  ) throws {
    let point: SionPoint

    switch endpoint {
    case .element(_, let attachment, let fallbackPoint):
      if case .magnet(let id) = attachment, id.rawValue.isEmpty {
        throw SceneValidationError.invalidConnectorEndpoint(connectorID)
      }

      point = fallbackPoint
    case .free(let freePoint):
      point = freePoint
    }

    guard point.isFinite,
      abs(point.x) <= SceneLimits.maximumCoordinateMagnitude,
      abs(point.y) <= SceneLimits.maximumCoordinateMagnitude
    else {
      throw SceneValidationError.invalidConnectorEndpoint(connectorID)
    }
  }

  private func routeSegmentIsValid(_ segment: ConnectorRouteSegment) -> Bool {
    switch segment {
    case .line(let to):
      return to.isValidCanvasPoint
    case .quadratic(let control, let to):
      return control.isValidCanvasPoint && to.isValidCanvasPoint
    case .cubic(let control1, let control2, let to):
      return control1.isValidCanvasPoint
        && control2.isValidCanvasPoint
        && to.isValidCanvasPoint
    }
  }

  private func validateParent(
    of element: SceneElement,
    in elementsByID: [ElementID: SceneElement]
  ) throws {
    guard let parentID = element.parentID else {
      return
    }

    guard let parent = elementsByID[parentID] else {
      throw SceneValidationError.missingParent(element: element.id, parent: parentID)
    }

    guard parent.content.isGroup else {
      throw SceneValidationError.parentIsNotGroup(element: element.id, parent: parentID)
    }
  }

  private func validateConnector(
    of element: SceneElement,
    in elementsByID: [ElementID: SceneElement]
  ) throws {
    guard let connector = element.content.connector else {
      return
    }

    for endpoint in [connector.source, connector.target] {
      guard let targetID = endpoint.elementID else {
        continue
      }

      guard let target = elementsByID[targetID] else {
        throw SceneValidationError.missingConnectedElement(
          connector: element.id,
          target: targetID
        )
      }

      guard target.content.connector == nil else {
        throw SceneValidationError.connectorTargetsConnector(
          connector: element.id,
          target: targetID
        )
      }
    }
  }

  private func validateParentCycles(in elementsByID: [ElementID: SceneElement]) throws {
    for element in elements {
      var path = [element.id]
      var visited = Set(path)
      var parentID = element.parentID
      var depth = 0

      while let candidate = parentID {
        guard visited.insert(candidate).inserted else {
          path.append(candidate)
          throw SceneValidationError.parentCycle(path)
        }

        path.append(candidate)
        depth += 1
        guard depth <= SceneLimits.maximumGroupDepth else {
          throw SceneValidationError.groupDepthExceeded(element.id)
        }

        parentID = elementsByID[candidate]?.parentID
      }
    }
  }
}

public struct SionDocument: Codable, Equatable, Sendable {
  public static let untitledName = "Untitled"

  public var id: DocumentID
  public var title: String
  public internal(set) var scene: SionScene
  public var extensions: [String: PortableValue]

  public init(
    id: DocumentID = DocumentID(),
    title: String = SionDocument.untitledName,
    scene: SionScene = SionScene(),
    extensions: [String: PortableValue] = [:]
  ) {
    self.id = id
    self.title = title
    self.scene = scene
    self.extensions = extensions
  }

  public func validate() throws {
    guard extensions.values.allSatisfy(\.isValid) else {
      throw SceneValidationError.invalidExtension
    }

    try scene.validate()
  }
}

public enum SceneValidationError: Error, Equatable, Sendable {
  case tooManyElements(Int)
  case invalidCanvas
  case invalidExtension
  case duplicateElementID(ElementID)
  case invalidGeometry(ElementID)
  case emptyAssetID(ElementID)
  case missingParent(element: ElementID, parent: ElementID)
  case parentIsNotGroup(element: ElementID, parent: ElementID)
  case parentCycle([ElementID])
  case missingConnectedElement(connector: ElementID, target: ElementID)
  case connectorTargetsConnector(connector: ElementID, target: ElementID)
  case invalidConnectorLabelPosition(ElementID)
  case invalidConnectorEndpoint(ElementID)
  case invalidManualRoute(ElementID)
  case invalidResolvedRoute(ElementID)
  case invalidStyle(ElementID)
  case invalidShape(ElementID)
  case invalidText(ElementID)
  case invalidVectorPath(ElementID)
  case invalidMagnet(ElementID)
  case tooManyMagnets(ElementID)
  case groupDepthExceeded(ElementID)
}

extension SceneValidationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .tooManyElements(let count):
      "Scene contains too many elements: \(count)"
    case .invalidCanvas:
      "Canvas settings are invalid"
    case .invalidExtension:
      "Extension data contains an invalid JSON value"
    case .duplicateElementID(let id):
      "Duplicate element ID: \(id)"
    case .invalidGeometry(let id):
      "Element has invalid geometry: \(id)"
    case .emptyAssetID(let id):
      "Image has an empty asset ID: \(id)"
    case .missingParent(let element, let parent):
      "Element \(element) references missing parent \(parent)"
    case .parentIsNotGroup(let element, let parent):
      "Element \(element) references non-group parent \(parent)"
    case .parentCycle(let path):
      "Parent cycle: \(path.map(\.description).joined(separator: " -> "))"
    case .missingConnectedElement(let connector, let target):
      "Connector \(connector) references missing element \(target)"
    case .connectorTargetsConnector(let connector, let target):
      "Connector \(connector) targets connector \(target)"
    case .invalidConnectorLabelPosition(let id):
      "Connector label position is outside 0...1: \(id)"
    case .invalidConnectorEndpoint(let id):
      "Connector endpoint is invalid: \(id)"
    case .invalidManualRoute(let id):
      "Connector manual route is invalid: \(id)"
    case .invalidResolvedRoute(let id):
      "Connector resolved route is invalid: \(id)"
    case .invalidStyle(let id):
      "Element style is invalid: \(id)"
    case .invalidShape(let id):
      "Element shape is invalid: \(id)"
    case .invalidText(let id):
      "Element text style is invalid: \(id)"
    case .invalidVectorPath(let id):
      "Element vector path is invalid: \(id)"
    case .invalidMagnet(let id):
      "Element contains an invalid magnet: \(id)"
    case .tooManyMagnets(let id):
      "Element contains too many magnets: \(id)"
    case .groupDepthExceeded(let id):
      "Element exceeds the maximum group depth: \(id)"
    }
  }
}

public enum CanvasDefaults {
  public static let gridSpacing = 16.0
  public static let gridSubdivisions = 1
}

public enum SceneElementDefaults {
  public static let cornerRadius = 14.0
}

public enum SceneLimits {
  public static let maximumCoordinateMagnitude = 1_000_000.0
  public static let maximumElementCount = 100_000
  public static let maximumMagnetsPerElement = 256
  public static let maximumPathCommandCount = 4_096
  public static let maximumRouteSegmentCount = 4_096
  public static let maximumGroupDepth = 64
  public static let maximumGridSubdivisions = 1_024
}
