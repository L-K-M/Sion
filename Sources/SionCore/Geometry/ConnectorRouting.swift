import Foundation

public enum ConnectorRoutingStyle: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case straight
  case curved
  case orthogonal
  case bezier
}

public enum ConnectorRoutingDefaults {
  public static let endpointStubLength = 20.0
  public static let obstacleClearance = 8.0
  public static let bendPenalty = 32.0
  public static let curvedOffsetFraction = 0.16
  public static let maximumCurvedOffset = 80.0
  public static let bezierHandleFraction = 0.35
  public static let minimumBezierHandleLength = 24.0
  public static let maximumBezierHandleLength = 180.0
}

public struct ConnectorRoutingOptions: Codable, Equatable, Hashable, Sendable {
  public var endpointStubLength: Double
  public var obstacleClearance: Double
  public var bendPenalty: Double
  public var curvedOffsetFraction: Double
  public var maximumCurvedOffset: Double
  public var bezierHandleFraction: Double
  public var minimumBezierHandleLength: Double
  public var maximumBezierHandleLength: Double

  public init(
    endpointStubLength: Double = ConnectorRoutingDefaults.endpointStubLength,
    obstacleClearance: Double = ConnectorRoutingDefaults.obstacleClearance,
    bendPenalty: Double = ConnectorRoutingDefaults.bendPenalty,
    curvedOffsetFraction: Double = ConnectorRoutingDefaults.curvedOffsetFraction,
    maximumCurvedOffset: Double = ConnectorRoutingDefaults.maximumCurvedOffset,
    bezierHandleFraction: Double = ConnectorRoutingDefaults.bezierHandleFraction,
    minimumBezierHandleLength: Double = ConnectorRoutingDefaults.minimumBezierHandleLength,
    maximumBezierHandleLength: Double = ConnectorRoutingDefaults.maximumBezierHandleLength
  ) {
    self.endpointStubLength = endpointStubLength
    self.obstacleClearance = obstacleClearance
    self.bendPenalty = bendPenalty
    self.curvedOffsetFraction = curvedOffsetFraction
    self.maximumCurvedOffset = maximumCurvedOffset
    self.bezierHandleFraction = bezierHandleFraction
    self.minimumBezierHandleLength = minimumBezierHandleLength
    self.maximumBezierHandleLength = maximumBezierHandleLength
  }

  public static let standard = ConnectorRoutingOptions()
}

public struct BezierControlPoints: Codable, Equatable, Hashable, Sendable {
  public var first: SionPoint
  public var second: SionPoint

  public init(first: SionPoint, second: SionPoint) {
    self.first = first
    self.second = second
  }
}

public enum ConnectorRouteSegment: Equatable, Hashable, Sendable {
  case line(to: SionPoint)
  case quadratic(control: SionPoint, to: SionPoint)
  case cubic(control1: SionPoint, control2: SionPoint, to: SionPoint)

  public var end: SionPoint {
    switch self {
    case .line(let to):
      return to
    case .quadratic(_, let to):
      return to
    case .cubic(_, _, let to):
      return to
    }
  }
}

extension ConnectorRouteSegment: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case to
    case control
    case control1
    case control2
  }

  private enum SegmentType: String, Codable {
    case line
    case quadratic
    case cubic
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    switch try container.decode(SegmentType.self, forKey: .type) {
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
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .line(let to):
      try container.encode(SegmentType.line, forKey: .type)
      try container.encode(to, forKey: .to)
    case .quadratic(let control, let to):
      try container.encode(SegmentType.quadratic, forKey: .type)
      try container.encode(control, forKey: .control)
      try container.encode(to, forKey: .to)
    case .cubic(let control1, let control2, let to):
      try container.encode(SegmentType.cubic, forKey: .type)
      try container.encode(control1, forKey: .control1)
      try container.encode(control2, forKey: .control2)
      try container.encode(to, forKey: .to)
    }
  }
}

public struct ConnectorRoute: Codable, Equatable, Hashable, Sendable {
  public var start: SionPoint
  public var segments: [ConnectorRouteSegment]

  public init(start: SionPoint, segments: [ConnectorRouteSegment]) {
    self.start = start
    self.segments = segments
  }

  public var end: SionPoint {
    segments.last?.end ?? start
  }

  /// A flattened visual path used for hit testing and tangent direction.
  public var polylinePoints: [SionPoint] {
    sampledPoints
  }

  public var polylineSegments: [SionLineSegment] {
    let points = polylinePoints

    return zip(points, points.dropFirst()).map { first, second in
      SionLineSegment(start: first, end: second)
    }
  }

  /// Finds a visual point by distance along the routed path.
  public func point(atFraction requestedFraction: Double) -> SionPoint {
    guard requestedFraction.isFinite else { return start }

    let fraction = min(1, max(0, requestedFraction))
    let points = sampledPoints
    let measuredSegments = zip(points, points.dropFirst()).map { start, end in
      (start: start, end: end, length: start.distance(to: end))
    }
    let totalLength = measuredSegments.reduce(0) { $0 + $1.length }
    guard totalLength > 0 else { return start }

    let targetLength = totalLength * fraction
    var traversedLength = 0.0

    for segment in measuredSegments {
      let segmentEnd = traversedLength + segment.length
      guard targetLength <= segmentEnd else {
        traversedLength = segmentEnd
        continue
      }

      guard segment.length > 0 else { return segment.end }

      let localFraction = (targetLength - traversedLength) / segment.length
      return segment.start.interpolated(to: segment.end, fraction: localFraction)
    }

    return end
  }

  private var sampledPoints: [SionPoint] {
    var points = [start]
    var current = start

    for segment in segments {
      switch segment {
      case .line(let to):
        points.append(to)
      case .quadratic(let control, let to):
        for index in 1...ConnectorRouteSampling.curveSegmentCount {
          let fraction = Double(index) / Double(ConnectorRouteSampling.curveSegmentCount)
          points.append(
            quadraticPoint(
              from: current,
              control: control,
              to: to,
              fraction: fraction
            ))
        }
      case .cubic(let control1, let control2, let to):
        for index in 1...ConnectorRouteSampling.curveSegmentCount {
          let fraction = Double(index) / Double(ConnectorRouteSampling.curveSegmentCount)
          points.append(
            cubicPoint(
              from: current,
              control1: control1,
              control2: control2,
              to: to,
              fraction: fraction
            ))
        }
      }

      current = segment.end
    }

    return points
  }

  private func quadraticPoint(
    from start: SionPoint,
    control: SionPoint,
    to end: SionPoint,
    fraction: Double
  ) -> SionPoint {
    let remaining = 1 - fraction
    let startWeight = remaining * remaining
    let controlWeight = 2 * remaining * fraction
    let endWeight = fraction * fraction

    return SionPoint(
      x: (start.x * startWeight) + (control.x * controlWeight) + (end.x * endWeight),
      y: (start.y * startWeight) + (control.y * controlWeight) + (end.y * endWeight)
    )
  }

  private func cubicPoint(
    from start: SionPoint,
    control1: SionPoint,
    control2: SionPoint,
    to end: SionPoint,
    fraction: Double
  ) -> SionPoint {
    let remaining = 1 - fraction
    let startWeight = remaining * remaining * remaining
    let firstControlWeight = 3 * remaining * remaining * fraction
    let secondControlWeight = 3 * remaining * fraction * fraction
    let endWeight = fraction * fraction * fraction

    return SionPoint(
      x: (start.x * startWeight)
        + (control1.x * firstControlWeight)
        + (control2.x * secondControlWeight)
        + (end.x * endWeight),
      y: (start.y * startWeight)
        + (control1.y * firstControlWeight)
        + (control2.y * secondControlWeight)
        + (end.y * endWeight)
    )
  }
}

private enum ConnectorRouteSampling {
  static let curveSegmentCount = 24
}

public enum ConnectorRouter {
  public static func route(
    from source: ResolvedConnectorEndpoint,
    to target: ResolvedConnectorEndpoint,
    style: ConnectorRoutingStyle,
    obstacles: [SionRect] = [],
    options: ConnectorRoutingOptions = .standard,
    bezierControlPoints: BezierControlPoints? = nil
  ) -> ConnectorRoute {
    switch style {
    case .straight:
      return ConnectorRoute(start: source.point, segments: [.line(to: target.point)])
    case .curved:
      return curvedRoute(from: source.point, to: target.point, options: options)
    case .orthogonal:
      return orthogonalRoute(
        from: source,
        to: target,
        obstacles: obstacles,
        options: options
      )
    case .bezier:
      return bezierRoute(
        from: source,
        to: target,
        options: options,
        controlPoints: bezierControlPoints
      )
    }
  }

  public static func collapseCollinear(_ points: [SionPoint]) -> [SionPoint] {
    var collapsed: [SionPoint] = []

    for point in points {
      guard point != collapsed.last else {
        continue
      }

      guard collapsed.count > 1 else {
        collapsed.append(point)
        continue
      }

      let first = collapsed[collapsed.count - 2]
      let middle = collapsed[collapsed.count - 1]
      let incoming = middle - first
      let outgoing = point - middle
      let crossProduct = (incoming.dx * outgoing.dy) - (incoming.dy * outgoing.dx)

      if crossProduct == 0, incoming.dot(outgoing) >= 0 {
        collapsed[collapsed.count - 1] = point
        continue
      }

      collapsed.append(point)
    }

    return collapsed
  }

  private static func curvedRoute(
    from source: SionPoint,
    to target: SionPoint,
    options: ConnectorRoutingOptions
  ) -> ConnectorRoute {
    let delta = target - source
    let distance = delta.length
    let fraction = finiteNonnegative(options.curvedOffsetFraction)
    let maximumOffset = finiteNonnegative(options.maximumCurvedOffset)
    let offset = min(distance * fraction, maximumOffset)
    let normal = SionVector(dx: delta.dy, dy: -delta.dx).normalized
    let control = source.interpolated(to: target, fraction: 0.5) + (normal * offset)

    return ConnectorRoute(
      start: source,
      segments: [.quadratic(control: control, to: target)]
    )
  }

  private static func bezierRoute(
    from source: ResolvedConnectorEndpoint,
    to target: ResolvedConnectorEndpoint,
    options: ConnectorRoutingOptions,
    controlPoints: BezierControlPoints?
  ) -> ConnectorRoute {
    if let controlPoints {
      return ConnectorRoute(
        start: source.point,
        segments: [
          .cubic(
            control1: controlPoints.first,
            control2: controlPoints.second,
            to: target.point
          )
        ]
      )
    }

    let delta = target.point - source.point
    let distance = delta.length
    let fraction = finiteNonnegative(options.bezierHandleFraction)
    let minimumLength = finiteNonnegative(options.minimumBezierHandleLength)
    let maximumLength = max(
      minimumLength,
      finiteNonnegative(options.maximumBezierHandleLength)
    )
    let handleLength =
      distance == 0
      ? 0
      : min(max(distance * fraction, minimumLength), maximumLength)
    let sourceDirection = direction(
      source.outwardDirection,
      fallback: delta.normalized
    )
    let targetDirection = direction(
      target.outwardDirection,
      fallback: -delta.normalized
    )
    let first = source.point + (sourceDirection * handleLength)
    let second = target.point + (targetDirection * handleLength)

    return ConnectorRoute(
      start: source.point,
      segments: [.cubic(control1: first, control2: second, to: target.point)]
    )
  }

  private static func orthogonalRoute(
    from source: ResolvedConnectorEndpoint,
    to target: ResolvedConnectorEndpoint,
    obstacles: [SionRect],
    options: ConnectorRoutingOptions
  ) -> ConnectorRoute {
    let stubLength = finiteNonnegative(options.endpointStubLength)
    let sourceDirection = TravelDirection.orthogonal(
      source.outwardDirection,
      fallback: target.point - source.point
    )
    let targetDirection = TravelDirection.orthogonal(
      target.outwardDirection,
      fallback: source.point - target.point
    )
    let expandedObstacles = routingObstacles(
      obstacles,
      source: source.point,
      target: target.point,
      clearance: finiteNonnegative(options.obstacleClearance)
    )
    let sourceStub = clearStub(
      from: source.point,
      direction: sourceDirection,
      length: stubLength,
      obstacles: expandedObstacles
    )
    let targetStub = clearStub(
      from: target.point,
      direction: targetDirection,
      length: stubLength,
      obstacles: expandedObstacles
    )
    let bendPenalty = finiteNonnegative(options.bendPenalty)
    let gridPath =
      OrthogonalPathfinder.path(
        from: sourceStub,
        to: targetStub,
        obstacles: expandedObstacles,
        bendPenalty: bendPenalty,
        departureDirection: sourceStub == source.point ? .none : sourceDirection,
        arrivalOutwardDirection: targetStub == target.point ? .none : targetDirection,
        outerMargin: max(stubLength, finiteNonnegative(options.obstacleClearance))
      )
      ?? orthogonalFallback(
        from: sourceStub,
        to: targetStub,
        obstacles: expandedObstacles,
        sourceDirection: sourceDirection,
        targetDirection: targetDirection,
        margin: max(stubLength, finiteNonnegative(options.obstacleClearance))
      )

    var points = [source.point]
    points.append(contentsOf: gridPath)
    points.append(target.point)
    let collapsed = collapseCollinear(points)
    let segments = collapsed.dropFirst().map { ConnectorRouteSegment.line(to: $0) }

    return ConnectorRoute(start: source.point, segments: segments)
  }

  private static func routingObstacles(
    _ obstacles: [SionRect],
    source: SionPoint,
    target: SionPoint,
    clearance: Double
  ) -> [SionRect] {
    obstacles
      .map(\.standardized)
      .filter { $0.isFinite && !$0.isEmpty }
      .map { $0.expanded(by: clearance) }
      .filter { !$0.contains(source) && !$0.contains(target) }
      .sorted(by: rectComesFirst)
  }

  private static func rectComesFirst(_ left: SionRect, _ right: SionRect) -> Bool {
    let leftValues = [left.minX, left.minY, left.maxX, left.maxY]
    let rightValues = [right.minX, right.minY, right.maxX, right.maxY]

    return leftValues.lexicographicallyPrecedes(rightValues)
  }

  private static func clearStub(
    from point: SionPoint,
    direction: TravelDirection,
    length: Double,
    obstacles: [SionRect]
  ) -> SionPoint {
    guard direction != .none, length > 0 else {
      return point
    }

    let stub = point + (direction.vector * length)
    let segment = SionLineSegment(start: point, end: stub)
    guard obstacles.allSatisfy({ !segment.intersectsInterior(of: $0) }) else {
      return point
    }

    return stub
  }

  private static func orthogonalFallback(
    from source: SionPoint,
    to target: SionPoint,
    obstacles: [SionRect],
    sourceDirection: TravelDirection,
    targetDirection: TravelDirection,
    margin: Double
  ) -> [SionPoint] {
    let safeMargin = max(margin, ConnectorRoutingDefaults.obstacleClearance)
    let bounds = obstacles.reduce(SionRect(x: source.x, y: source.y, width: 0, height: 0)) {
      $0.union($1)
    }.union(SionRect(x: target.x, y: target.y, width: 0, height: 0))
    let left = bounds.minX - safeMargin
    let right = bounds.maxX + safeMargin
    let top = bounds.minY - safeMargin
    let bottom = bounds.maxY + safeMargin
    let candidates = [
      [source, SionPoint(x: target.x, y: source.y), target],
      [source, SionPoint(x: source.x, y: target.y), target],
      [source, SionPoint(x: left, y: source.y), SionPoint(x: left, y: target.y), target],
      [source, SionPoint(x: right, y: source.y), SionPoint(x: right, y: target.y), target],
      [source, SionPoint(x: source.x, y: top), SionPoint(x: target.x, y: top), target],
      [source, SionPoint(x: source.x, y: bottom), SionPoint(x: target.x, y: bottom), target],
    ].map(collapseCollinear)

    return candidates.min { leftPath, rightPath in
      fallbackScore(
        leftPath,
        obstacles: obstacles,
        sourceDirection: sourceDirection,
        targetDirection: targetDirection
      )
        < fallbackScore(
          rightPath,
          obstacles: obstacles,
          sourceDirection: sourceDirection,
          targetDirection: targetDirection
        )
    } ?? [source, target]
  }

  private static func fallbackScore(
    _ points: [SionPoint],
    obstacles: [SionRect],
    sourceDirection: TravelDirection,
    targetDirection: TravelDirection
  ) -> FallbackScore {
    let segments = zip(points, points.dropFirst()).map { first, second in
      SionLineSegment(start: first, end: second)
    }
    let collisions = segments.reduce(0) { count, segment in
      count + obstacles.filter { segment.intersectsInterior(of: $0) }.count
    }
    let firstDirection = segments.first.map { TravelDirection(from: $0.start, to: $0.end) } ?? .none
    let lastDirection = segments.last.map { TravelDirection(from: $0.start, to: $0.end) } ?? .none
    let directionViolations =
      (firstDirection == sourceDirection.opposite ? 1 : 0)
      + (lastDirection == targetDirection ? 1 : 0)
    let length = segments.reduce(0) { $0 + $1.length }

    return FallbackScore(
      collisions: collisions,
      directionViolations: directionViolations,
      bends: max(points.count - 2, 0),
      length: length
    )
  }

  private static func direction(_ direction: SionVector, fallback: SionVector) -> SionVector {
    let normalized = direction.normalized
    return normalized == .zero ? fallback.normalized : normalized
  }

  private static func finiteNonnegative(_ value: Double) -> Double {
    guard value.isFinite else {
      return 0
    }

    return max(value, 0)
  }
}

private struct FallbackScore: Comparable {
  let collisions: Int
  let directionViolations: Int
  let bends: Int
  let length: Double

  static func < (left: FallbackScore, right: FallbackScore) -> Bool {
    if left.collisions != right.collisions {
      return left.collisions < right.collisions
    }

    if left.directionViolations != right.directionViolations {
      return left.directionViolations < right.directionViolations
    }

    if left.bends != right.bends {
      return left.bends < right.bends
    }

    return left.length < right.length
  }
}

private enum TravelAxis: Int, Hashable {
  case none
  case horizontal
  case vertical
}

private enum TravelDirection: Int, Hashable {
  case none
  case north
  case east
  case south
  case west

  var axis: TravelAxis {
    switch self {
    case .none:
      return .none
    case .east, .west:
      return .horizontal
    case .north, .south:
      return .vertical
    }
  }

  var opposite: TravelDirection {
    switch self {
    case .none:
      return .none
    case .north:
      return .south
    case .east:
      return .west
    case .south:
      return .north
    case .west:
      return .east
    }
  }

  var vector: SionVector {
    switch self {
    case .none:
      return .zero
    case .north:
      return .north
    case .east:
      return .east
    case .south:
      return .south
    case .west:
      return .west
    }
  }

  init(from source: SionPoint, to target: SionPoint) {
    let delta = target - source

    if abs(delta.dx) >= abs(delta.dy), delta.dx != 0 {
      self = delta.dx > 0 ? .east : .west
      return
    }

    if delta.dy != 0 {
      self = delta.dy > 0 ? .south : .north
      return
    }

    self = .none
  }

  static func orthogonal(_ vector: SionVector, fallback: SionVector) -> TravelDirection {
    let candidate = vector.normalized == .zero ? fallback : vector

    return TravelDirection(
      from: .zero,
      to: SionPoint(x: candidate.dx, y: candidate.dy)
    )
  }
}

private enum OrthogonalPathfinder {
  private static let minimumOuterMargin = 1.0

  // Obstacle edges form a sparse visibility grid. Dijkstra then trades
  // distance against bends while retaining deterministic tie-breaking.
  //
  // S ──┐  ┌────┐
  //     └──│    │── T
  //        └────┘
  static func path(
    from source: SionPoint,
    to target: SionPoint,
    obstacles: [SionRect],
    bendPenalty: Double,
    departureDirection: TravelDirection,
    arrivalOutwardDirection: TravelDirection,
    outerMargin: Double
  ) -> [SionPoint]? {
    guard source.isFinite, target.isFinite else {
      return nil
    }

    if source == target {
      return [source]
    }

    guard
      let grid = Grid(
        source: source,
        target: target,
        obstacles: obstacles,
        outerMargin: max(outerMargin, minimumOuterMargin)
      )
    else {
      return nil
    }
    guard let sourceNode = grid.node(at: source),
      let targetNode = grid.node(at: target)
    else {
      return nil
    }

    let startState = SearchState(node: sourceNode, direction: departureDirection)
    let startScore = SearchScore(cost: 0, length: 0, bends: 0)
    var scores = [startState: startScore]
    var predecessors: [SearchState: SearchState] = [:]
    var frontier = MinHeap<FrontierEntry>()
    frontier.insert(FrontierEntry(state: startState, score: startScore))

    while let current = frontier.removeMinimum() {
      guard scores[current.state] == current.score else {
        continue
      }

      for neighbor in grid.neighbors(of: current.state.node, obstacles: obstacles) {
        if neighbor.direction == current.state.direction.opposite {
          continue
        }

        let bendChange: BendChange =
          current.state.direction.axis != .none
            && current.state.direction.axis != neighbor.direction.axis
          ? .added
          : .none
        let segmentLength = grid.points[current.state.node].distance(
          to: grid.points[neighbor.node]
        )
        let score = current.score.adding(
          length: segmentLength,
          bendChange: bendChange,
          bendPenalty: bendPenalty
        )
        let state = SearchState(node: neighbor.node, direction: neighbor.direction)

        if let known = scores[state], !score.isBetter(than: known) {
          continue
        }

        scores[state] = score
        predecessors[state] = current.state
        frontier.insert(FrontierEntry(state: state, score: score))
      }
    }

    let goal = bestGoal(
      at: targetNode,
      scores: scores,
      arrivalOutwardDirection: arrivalOutwardDirection,
      bendPenalty: bendPenalty
    )
    guard let goal else {
      return nil
    }

    var states = [goal]
    var current = goal

    while let predecessor = predecessors[current] {
      states.append(predecessor)
      current = predecessor
    }

    guard current == startState else {
      return nil
    }

    return states.reversed().map { grid.points[$0.node] }
  }

  private static func bestGoal(
    at node: Int,
    scores: [SearchState: SearchScore],
    arrivalOutwardDirection: TravelDirection,
    bendPenalty: Double
  ) -> SearchState? {
    let candidates = scores.keys.filter { state in
      guard state.node == node else {
        return false
      }

      return arrivalOutwardDirection == .none
        || state.direction != arrivalOutwardDirection
    }

    return candidates.min { left, right in
      let leftScore = goalScore(
        scores[left],
        direction: left.direction,
        arrivalOutwardDirection: arrivalOutwardDirection,
        bendPenalty: bendPenalty
      )
      let rightScore = goalScore(
        scores[right],
        direction: right.direction,
        arrivalOutwardDirection: arrivalOutwardDirection,
        bendPenalty: bendPenalty
      )

      if leftScore != rightScore {
        return leftScore.isBetter(than: rightScore)
      }

      return left.direction.rawValue < right.direction.rawValue
    }
  }

  private static func goalScore(
    _ score: SearchScore?,
    direction: TravelDirection,
    arrivalOutwardDirection: TravelDirection,
    bendPenalty: Double
  ) -> SearchScore {
    guard let score else {
      return .infinity
    }

    let arrivalAxis = arrivalOutwardDirection.axis
    let bendChange: BendChange =
      arrivalAxis != .none
        && direction.axis != .none
        && direction.axis != arrivalAxis
      ? .added
      : .none

    return score.adding(
      length: 0,
      bendChange: bendChange,
      bendPenalty: bendPenalty
    )
  }
}

private struct Grid {
  // Bound interactive routing before allocating the Cartesian visibility graph.
  private static let maximumNodeCount = 16_384

  let xValues: [Double]
  let yValues: [Double]
  let points: [SionPoint]
  let validNodes: [Bool]

  init?(
    source: SionPoint,
    target: SionPoint,
    obstacles: [SionRect],
    outerMargin: Double
  ) {
    var xs = [source.x, target.x]
    var ys = [source.y, target.y]

    for obstacle in obstacles {
      xs.append(contentsOf: [obstacle.minX, obstacle.maxX])
      ys.append(contentsOf: [obstacle.minY, obstacle.maxY])
    }

    let minimumX = xs.min() ?? min(source.x, target.x)
    let maximumX = xs.max() ?? max(source.x, target.x)
    let minimumY = ys.min() ?? min(source.y, target.y)
    let maximumY = ys.max() ?? max(source.y, target.y)
    xs.append(contentsOf: [minimumX - outerMargin, maximumX + outerMargin])
    ys.append(contentsOf: [minimumY - outerMargin, maximumY + outerMargin])
    let generatedXValues = Array(Set(xs)).sorted()
    let generatedYValues = Array(Set(ys)).sorted()
    let (nodeCount, overflow) = generatedXValues.count.multipliedReportingOverflow(
      by: generatedYValues.count
    )

    guard !overflow, nodeCount <= Self.maximumNodeCount else {
      return nil
    }

    xValues = generatedXValues
    yValues = generatedYValues

    var generatedPoints: [SionPoint] = []
    var generatedValidity: [Bool] = []
    generatedPoints.reserveCapacity(nodeCount)
    generatedValidity.reserveCapacity(nodeCount)

    for y in yValues {
      for x in xValues {
        let point = SionPoint(x: x, y: y)
        generatedPoints.append(point)
        generatedValidity.append(!obstacles.contains { $0.containsInterior(point) })
      }
    }

    points = generatedPoints
    validNodes = generatedValidity
  }

  func node(at point: SionPoint) -> Int? {
    guard let xIndex = xValues.firstIndex(of: point.x),
      let yIndex = yValues.firstIndex(of: point.y)
    else {
      return nil
    }

    let node = (yIndex * xValues.count) + xIndex
    return validNodes[node] ? node : nil
  }

  func neighbors(of node: Int, obstacles: [SionRect]) -> [GridNeighbor] {
    let xIndex = node % xValues.count
    let yIndex = node / xValues.count
    let candidates = [
      (xIndex - 1, yIndex),
      (xIndex, yIndex - 1),
      (xIndex + 1, yIndex),
      (xIndex, yIndex + 1),
    ]
    var neighbors: [GridNeighbor] = []

    for (candidateX, candidateY) in candidates {
      guard xValues.indices.contains(candidateX),
        yValues.indices.contains(candidateY)
      else {
        continue
      }

      let candidate = (candidateY * xValues.count) + candidateX
      guard validNodes[candidate] else {
        continue
      }

      let segment = SionLineSegment(start: points[node], end: points[candidate])
      guard obstacles.allSatisfy({ !segment.intersectsInterior(of: $0) }) else {
        continue
      }

      neighbors.append(
        GridNeighbor(
          node: candidate,
          direction: TravelDirection(from: points[node], to: points[candidate])
        ))
    }

    return neighbors
  }
}

private struct GridNeighbor {
  let node: Int
  let direction: TravelDirection
}

private struct SearchState: Hashable {
  let node: Int
  let direction: TravelDirection
}

private struct SearchScore: Equatable {
  let cost: Double
  let length: Double
  let bends: Int

  static let infinity = SearchScore(
    cost: .infinity,
    length: .infinity,
    bends: .max
  )

  func adding(
    length additionalLength: Double,
    bendChange: BendChange,
    bendPenalty: Double
  ) -> SearchScore {
    return SearchScore(
      cost: cost + additionalLength + (Double(bendChange.count) * bendPenalty),
      length: length + additionalLength,
      bends: bends + bendChange.count
    )
  }

  func isBetter(than other: SearchScore) -> Bool {
    if cost != other.cost {
      return cost < other.cost
    }

    if bends != other.bends {
      return bends < other.bends
    }

    return length < other.length
  }
}

private enum BendChange {
  case none
  case added

  var count: Int {
    switch self {
    case .none:
      return 0
    case .added:
      return 1
    }
  }
}

private struct FrontierEntry: Comparable {
  let state: SearchState
  let score: SearchScore

  static func < (left: FrontierEntry, right: FrontierEntry) -> Bool {
    if left.score != right.score {
      return left.score.isBetter(than: right.score)
    }

    if left.state.node != right.state.node {
      return left.state.node < right.state.node
    }

    return left.state.direction.rawValue < right.state.direction.rawValue
  }
}

private struct MinHeap<Element: Comparable> {
  private var elements: [Element] = []

  mutating func insert(_ element: Element) {
    elements.append(element)
    siftUp(from: elements.count - 1)
  }

  mutating func removeMinimum() -> Element? {
    guard !elements.isEmpty else {
      return nil
    }

    guard elements.count > 1 else {
      return elements.removeLast()
    }

    let minimum = elements[0]
    elements[0] = elements.removeLast()
    siftDown(from: 0)

    return minimum
  }

  private mutating func siftUp(from index: Int) {
    var child = index

    while child > 0 {
      let parent = (child - 1) / 2
      guard elements[child] < elements[parent] else {
        return
      }

      elements.swapAt(child, parent)
      child = parent
    }
  }

  private mutating func siftDown(from index: Int) {
    var parent = index

    while true {
      let leftChild = (parent * 2) + 1
      guard leftChild < elements.count else {
        return
      }

      let rightChild = leftChild + 1
      var smallest = leftChild

      if rightChild < elements.count,
        elements[rightChild] < elements[leftChild]
      {
        smallest = rightChild
      }

      guard elements[smallest] < elements[parent] else {
        return
      }

      elements.swapAt(parent, smallest)
      parent = smallest
    }
  }
}
