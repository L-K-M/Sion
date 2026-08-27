import Foundation

public struct MagnetID: RawRepresentable, Codable, Equatable, Hashable, Sendable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: StringLiteralType) {
    rawValue = value
  }

  public var description: String {
    rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A persisted connection point expressed in element-local normalized coordinates.
public struct Magnet: Equatable, Hashable, Sendable {
  public var id: MagnetID
  public var normalizedPosition: SionPoint
  public var outwardDirection: SionVector
  public var connectionDirection: MagnetConnectionDirection

  public init(
    id: MagnetID,
    normalizedPosition: SionPoint,
    outwardDirection: SionVector,
    connectionDirection: MagnetConnectionDirection = .both
  ) {
    self.id = id
    self.normalizedPosition = normalizedPosition
    self.outwardDirection = outwardDirection.normalized
    self.connectionDirection = connectionDirection
  }
}

public enum MagnetConnectionDirection: String, Codable, CaseIterable, Equatable, Hashable, Sendable
{
  case incoming
  case outgoing
  case both

  public func allows(_ use: MagnetUse) -> Bool {
    switch (self, use) {
    case (.both, _), (.incoming, .incoming), (.outgoing, .outgoing):
      return true
    case (.incoming, .outgoing), (.outgoing, .incoming):
      return false
    }
  }
}

public enum MagnetUse: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case incoming
  case outgoing
}

extension Magnet: Codable {
  private enum CodingKeys: String, CodingKey {
    case id
    case position
    case normal
    case direction
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      id: try container.decode(MagnetID.self, forKey: .id),
      normalizedPosition: try container.decode(SionPoint.self, forKey: .position),
      outwardDirection: try container.decode(SionVector.self, forKey: .normal),
      connectionDirection: try container.decode(
        MagnetConnectionDirection.self,
        forKey: .direction
      )
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(normalizedPosition, forKey: .position)
    try container.encode(outwardDirection, forKey: .normal)
    try container.encode(connectionDirection, forKey: .direction)
  }
}

public enum MagnetPreset: Equatable, Hashable, Sendable {
  /// Generates no magnets. Automatic attachment may still use boundary fallback.
  case none
  case cardinalFour
  case northSouth
  case eastWest
  case diagonalFour
  case eight
  case vertices
  case perSegment(Int)
}

public enum MagnetConfiguration: Equatable, Hashable, Sendable {
  case preset(MagnetPreset)
  case custom([Magnet])

  public static let `default` = MagnetConfiguration.preset(.cardinalFour)
}

extension MagnetPreset: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case count
  }

  private enum PresetType: String, Codable {
    case none
    case cardinalFour
    case northSouth
    case eastWest
    case diagonalFour
    case eight
    case vertices
    case perSegment
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(PresetType.self, forKey: .type) {
    case .none:
      self = .none
    case .cardinalFour:
      self = .cardinalFour
    case .northSouth:
      self = .northSouth
    case .eastWest:
      self = .eastWest
    case .diagonalFour:
      self = .diagonalFour
    case .eight:
      self = .eight
    case .vertices:
      self = .vertices
    case .perSegment:
      self = .perSegment(try container.decode(Int.self, forKey: .count))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .none:
      try container.encode(PresetType.none, forKey: .type)
    case .cardinalFour:
      try container.encode(PresetType.cardinalFour, forKey: .type)
    case .northSouth:
      try container.encode(PresetType.northSouth, forKey: .type)
    case .eastWest:
      try container.encode(PresetType.eastWest, forKey: .type)
    case .diagonalFour:
      try container.encode(PresetType.diagonalFour, forKey: .type)
    case .eight:
      try container.encode(PresetType.eight, forKey: .type)
    case .vertices:
      try container.encode(PresetType.vertices, forKey: .type)
    case .perSegment(let count):
      try container.encode(PresetType.perSegment, forKey: .type)
      try container.encode(count, forKey: .count)
    }
  }
}

extension MagnetConfiguration: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case preset
    case magnets
  }

  private enum ConfigurationType: String, Codable {
    case preset
    case custom
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(ConfigurationType.self, forKey: .type) {
    case .preset:
      self = .preset(try container.decode(MagnetPreset.self, forKey: .preset))
    case .custom:
      self = .custom(try container.decode([Magnet].self, forKey: .magnets))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .preset(let preset):
      try container.encode(ConfigurationType.preset, forKey: .type)
      try container.encode(preset, forKey: .preset)
    case .custom(let magnets):
      try container.encode(ConfigurationType.custom, forKey: .type)
      try container.encode(magnets, forKey: .magnets)
    }
  }
}

public struct ResolvedConnectorEndpoint: Codable, Equatable, Hashable, Sendable {
  public var point: SionPoint
  public var outwardDirection: SionVector

  public init(point: SionPoint, outwardDirection: SionVector) {
    self.point = point
    self.outwardDirection = outwardDirection.normalized
  }
}

public struct ResolvedMagnet: Codable, Equatable, Hashable, Sendable {
  public var magnet: Magnet
  public var endpoint: ResolvedConnectorEndpoint

  public init(magnet: Magnet, endpoint: ResolvedConnectorEndpoint) {
    self.magnet = magnet
    self.endpoint = endpoint
  }
}

public enum MagnetResolver {
  public static let maximumMagnetsPerSegment = 32

  public static let rectangleOutline = [
    SionPoint(x: 0, y: 0),
    SionPoint(x: 1, y: 0),
    SionPoint(x: 1, y: 1),
    SionPoint(x: 0, y: 1),
  ]

  public static func magnets(
    for configuration: MagnetConfiguration,
    normalizedOutline: [SionPoint] = rectangleOutline
  ) -> [Magnet] {
    switch configuration {
    case .custom(let magnets):
      return magnets
    case .preset(let preset):
      return magnets(for: preset, normalizedOutline: normalizedOutline)
    }
  }

  public static func magnets(
    for preset: MagnetPreset,
    normalizedOutline: [SionPoint] = rectangleOutline
  ) -> [Magnet] {
    switch preset {
    case .none:
      return []
    case .cardinalFour:
      return directionalMagnets(cardinalFour, outline: normalizedOutline)
    case .northSouth:
      return directionalMagnets([north, south], outline: normalizedOutline)
    case .eastWest:
      return directionalMagnets([east, west], outline: normalizedOutline)
    case .diagonalFour:
      return directionalMagnets(
        [northWest, northEast, southEast, southWest],
        outline: normalizedOutline
      )
    case .eight:
      return directionalMagnets(
        [northWest, north, northEast, east, southEast, south, southWest, west],
        outline: normalizedOutline
      )
    case .vertices:
      return vertexMagnets(outline: normalizedOutline)
    case .perSegment(let count):
      return segmentMagnets(count: count, outline: normalizedOutline)
    }
  }

  public static func resolve(_ magnet: Magnet, in bounds: SionRect) -> ResolvedConnectorEndpoint {
    ResolvedConnectorEndpoint(
      point: bounds.point(atNormalized: magnet.normalizedPosition),
      outwardDirection: magnet.outwardDirection
    )
  }

  public static func resolve(
    _ id: MagnetID,
    in configuration: MagnetConfiguration,
    bounds: SionRect,
    use: MagnetUse? = nil,
    normalizedOutline: [SionPoint] = rectangleOutline
  ) -> ResolvedConnectorEndpoint? {
    resolve(
      id,
      among: magnets(
        for: configuration,
        normalizedOutline: normalizedOutline
      ),
      bounds: bounds,
      use: use
    )
  }

  public static func resolve(
    _ id: MagnetID,
    among magnets: [Magnet],
    bounds: SionRect,
    use: MagnetUse? = nil
  ) -> ResolvedConnectorEndpoint? {
    let magnet = magnets.first { magnet in
      magnet.id == id && (use.map { magnet.connectionDirection.allows($0) } ?? true)
    }

    guard let magnet else {
      return nil
    }

    return resolve(magnet, in: bounds)
  }

  public static func resolveNearest(
    in configuration: MagnetConfiguration,
    bounds: SionRect,
    to point: SionPoint,
    use: MagnetUse? = nil,
    normalizedOutline: [SionPoint] = rectangleOutline
  ) -> ResolvedMagnet? {
    resolveNearest(
      among: magnets(
        for: configuration,
        normalizedOutline: normalizedOutline
      ),
      bounds: bounds,
      to: point,
      use: use
    )
  }

  public static func resolveNearest(
    among magnets: [Magnet],
    bounds: SionRect,
    to point: SionPoint,
    use: MagnetUse? = nil
  ) -> ResolvedMagnet? {
    let candidates = magnets.filter { magnet in
      use.map { magnet.connectionDirection.allows($0) } ?? true
    }

    var best: ResolvedMagnet?
    var bestDistance = Double.infinity

    // Declaration order intentionally breaks equal-distance ties.
    for magnet in candidates {
      let endpoint = resolve(magnet, in: bounds)
      let offset = endpoint.point - point
      let distance = offset.lengthSquared
      guard distance < bestDistance else {
        continue
      }

      best = ResolvedMagnet(magnet: magnet, endpoint: endpoint)
      bestDistance = distance
    }

    return best
  }

  private static let north = Magnet(
    id: "north",
    normalizedPosition: SionPoint(x: 0.5, y: 0),
    outwardDirection: .north
  )

  private static let east = Magnet(
    id: "east",
    normalizedPosition: SionPoint(x: 1, y: 0.5),
    outwardDirection: .east
  )

  private static let south = Magnet(
    id: "south",
    normalizedPosition: SionPoint(x: 0.5, y: 1),
    outwardDirection: .south
  )

  private static let west = Magnet(
    id: "west",
    normalizedPosition: SionPoint(x: 0, y: 0.5),
    outwardDirection: .west
  )

  private static let cardinalFour = [north, east, south, west]

  private static let northWest = Magnet(
    id: "north-west",
    normalizedPosition: SionPoint(x: 0, y: 0),
    outwardDirection: SionVector(dx: -1, dy: -1)
  )

  private static let northEast = Magnet(
    id: "north-east",
    normalizedPosition: SionPoint(x: 1, y: 0),
    outwardDirection: SionVector(dx: 1, dy: -1)
  )

  private static let southEast = Magnet(
    id: "south-east",
    normalizedPosition: SionPoint(x: 1, y: 1),
    outwardDirection: SionVector(dx: 1, dy: 1)
  )

  private static let southWest = Magnet(
    id: "south-west",
    normalizedPosition: SionPoint(x: 0, y: 1),
    outwardDirection: SionVector(dx: -1, dy: 1)
  )

  private static func directionalMagnets(
    _ templates: [Magnet],
    outline: [SionPoint]
  ) -> [Magnet] {
    let vertices = normalizedVertices(outline)
    guard vertices.count > 1, vertices != rectangleOutline else {
      return templates
    }

    let origin = outlineBoundsCenter(vertices)

    // Compass rays retain preset meaning while moving points onto the outline.
    return templates.map { template in
      let position =
        rayIntersection(
          from: origin,
          direction: template.outwardDirection,
          with: vertices
        ) ?? nearestOutlinePoint(to: template.normalizedPosition, vertices: vertices)

      return Magnet(
        id: template.id,
        normalizedPosition: position,
        outwardDirection: template.outwardDirection,
        connectionDirection: template.connectionDirection
      )
    }
  }

  private static func rayIntersection(
    from origin: SionPoint,
    direction: SionVector,
    with vertices: [SionPoint]
  ) -> SionPoint? {
    guard direction != .zero else {
      return nil
    }

    var nearestPositiveDistance = Double.infinity
    var intersectsAtOrigin = false

    for index in vertices.indices {
      let start = vertices[index]
      let end = vertices[(index + 1) % vertices.count]
      let segment = end - start
      let offset = start - origin
      let denominator = cross(direction, segment)

      if abs(denominator) <= directionalIntersectionTolerance {
        guard abs(cross(offset, direction)) <= directionalIntersectionTolerance else {
          continue
        }

        for endpoint in [start, end] {
          let distance = (endpoint - origin).dot(direction)
          guard distance >= -directionalIntersectionTolerance else {
            continue
          }

          if distance <= directionalIntersectionTolerance {
            intersectsAtOrigin = true
            continue
          }

          nearestPositiveDistance = min(nearestPositiveDistance, distance)
        }

        continue
      }

      let distance = cross(offset, segment) / denominator
      let segmentFraction = cross(offset, direction) / denominator
      guard distance >= -directionalIntersectionTolerance,
        segmentFraction >= -directionalIntersectionTolerance,
        segmentFraction <= 1 + directionalIntersectionTolerance
      else {
        continue
      }

      if distance <= directionalIntersectionTolerance {
        intersectsAtOrigin = true
        continue
      }

      nearestPositiveDistance = min(nearestPositiveDistance, distance)
    }

    if nearestPositiveDistance.isFinite {
      return origin + (direction * nearestPositiveDistance)
    }

    return intersectsAtOrigin ? origin : nil
  }

  private static func nearestOutlinePoint(
    to point: SionPoint,
    vertices: [SionPoint]
  ) -> SionPoint {
    var nearest = vertices[0]
    var nearestDistance = (nearest - point).lengthSquared

    for index in vertices.indices {
      let start = vertices[index]
      let end = vertices[(index + 1) % vertices.count]
      let segment = end - start
      let segmentLength = segment.lengthSquared
      let fraction =
        segmentLength <= directionalIntersectionTolerance
        ? 0
        : min(1, max(0, (point - start).dot(segment) / segmentLength))
      let candidate = start + (segment * fraction)
      let distance = (candidate - point).lengthSquared

      guard distance < nearestDistance else {
        continue
      }

      nearest = candidate
      nearestDistance = distance
    }

    return nearest
  }

  private static func outlineBoundsCenter(_ vertices: [SionPoint]) -> SionPoint {
    var minimumX = vertices[0].x
    var maximumX = vertices[0].x
    var minimumY = vertices[0].y
    var maximumY = vertices[0].y

    for vertex in vertices.dropFirst() {
      minimumX = min(minimumX, vertex.x)
      maximumX = max(maximumX, vertex.x)
      minimumY = min(minimumY, vertex.y)
      maximumY = max(maximumY, vertex.y)
    }

    return SionPoint(
      x: (minimumX + maximumX) / 2,
      y: (minimumY + maximumY) / 2
    )
  }

  private static func cross(_ first: SionVector, _ second: SionVector) -> Double {
    (first.dx * second.dy) - (first.dy * second.dx)
  }

  private static let directionalIntersectionTolerance = 1e-12

  private static func vertexMagnets(outline: [SionPoint]) -> [Magnet] {
    let vertices = normalizedVertices(outline)
    guard vertices.count > 1 else {
      return []
    }

    let normals = edgeNormals(vertices)

    return vertices.indices.map { index in
      let previousIndex = (index + vertices.count - 1) % vertices.count
      var direction = (normals[previousIndex] + normals[index]).normalized

      if direction == .zero {
        direction = (vertices[index] - polygonCenter(vertices)).normalized
      }

      return Magnet(
        id: MagnetID("vertex-\(index)"),
        normalizedPosition: vertices[index],
        outwardDirection: direction
      )
    }
  }

  private static func segmentMagnets(count: Int, outline: [SionPoint]) -> [Magnet] {
    let vertices = normalizedVertices(outline)
    guard vertices.count > 1 else {
      return []
    }

    let placementCount = min(max(count, 0), maximumMagnetsPerSegment)
    guard placementCount > 0 else {
      return []
    }

    let normals = edgeNormals(vertices)
    var magnets: [Magnet] = []
    magnets.reserveCapacity(vertices.count * placementCount)

    for edgeIndex in vertices.indices {
      let start = vertices[edgeIndex]
      let end = vertices[(edgeIndex + 1) % vertices.count]

      for placementIndex in 1...placementCount {
        let fraction = Double(placementIndex) / Double(placementCount + 1)
        magnets.append(
          Magnet(
            id: MagnetID("segment-\(edgeIndex)-\(placementIndex)"),
            normalizedPosition: start.interpolated(to: end, fraction: fraction),
            outwardDirection: normals[edgeIndex]
          ))
      }
    }

    return magnets
  }

  private static func normalizedVertices(_ outline: [SionPoint]) -> [SionPoint] {
    var vertices: [SionPoint] = []

    for point in outline where point.isFinite {
      guard point != vertices.last else {
        continue
      }

      vertices.append(point)
    }

    if vertices.count > 1, vertices.first == vertices.last {
      vertices.removeLast()
    }

    return vertices
  }

  private static func edgeNormals(_ vertices: [SionPoint]) -> [SionVector] {
    let useRightHandNormal = signedArea(vertices) >= 0

    return vertices.indices.map { index in
      let edge = vertices[(index + 1) % vertices.count] - vertices[index]

      if useRightHandNormal {
        return SionVector(dx: edge.dy, dy: -edge.dx).normalized
      }

      return SionVector(dx: -edge.dy, dy: edge.dx).normalized
    }
  }

  private static func signedArea(_ vertices: [SionPoint]) -> Double {
    var doubledArea = 0.0

    for index in vertices.indices {
      let first = vertices[index]
      let second = vertices[(index + 1) % vertices.count]
      doubledArea += (first.x * second.y) - (second.x * first.y)
    }

    return doubledArea / 2
  }

  private static func polygonCenter(_ vertices: [SionPoint]) -> SionPoint {
    let sum = vertices.reduce(SionVector.zero) { partial, point in
      partial + SionVector(dx: point.x, dy: point.y)
    }
    let count = Double(vertices.count)

    return SionPoint(x: sum.dx / count, y: sum.dy / count)
  }
}
