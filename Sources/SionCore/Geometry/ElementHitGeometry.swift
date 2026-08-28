import Foundation

/// Platform-neutral point hits against a scene element's selectable geometry.
public enum ElementHitGeometry {
  public static func contains(
    _ point: SionPoint,
    in element: SceneElement,
    tolerance: Double = 0
  ) -> Bool {
    guard point.isFinite else { return false }

    let frame = element.geometry.frame.standardized
    let localPoint = InteractionGeometry.unrotated(
      point,
      around: frame.center,
      by: element.geometry.rotationRadians
    )
    let hitTolerance = nonnegativeFinite(tolerance)

    switch element.content {
    case .shape(let content):
      let broadPhaseHit =
        content.kind.hitBounds(in: frame)?.expanded(
          by: element.style.hitExpansion(tolerance: hitTolerance)
        ).contains(localPoint) == true
      if broadPhaseHit,
        content.kind.flattened(in: frame).contains(
          localPoint,
          style: element.style,
          tolerance: hitTolerance
        )
      {
        return true
      }

      // Labels paint separately; their inset box avoids reclaiming frame corners.
      guard
        let labelBounds = content.label?.hitBounds(
          in: frame,
          elementOpacity: element.style.opacity
        )
      else { return false }

      return labelBounds.expanded(by: hitTolerance).contains(localPoint)
    case .path(let content):
      guard
        content.path.hitBounds(in: frame)?.expanded(
          by: element.style.hitExpansion(tolerance: hitTolerance)
        ).contains(localPoint) == true
      else {
        return false
      }

      return content.path.flattened(in: frame).contains(
        localPoint,
        style: element.style,
        tolerance: hitTolerance
      )
    case .text, .image, .group:
      return frame.expanded(by: hitTolerance).contains(localPoint)
    case .connector:
      return false
    }
  }

  private static func nonnegativeFinite(_ value: Double) -> Double {
    value.isFinite ? max(0, value) : 0
  }
}

private struct FlattenedPath {
  let subpaths: [FlattenedSubpath]
  let fillRule: PathFillRule

  func contains(
    _ point: SionPoint,
    style: ElementStyle,
    tolerance: Double
  ) -> Bool {
    guard let bounds else { return false }

    let strokeRadius = style.visibleStroke?.hitExpansion(tolerance: tolerance) ?? 0
    let fillRadius = style.hasVisibleFill ? tolerance : 0
    guard bounds.expanded(by: max(fillRadius, strokeRadius)).contains(point) else {
      return false
    }

    if style.hasVisibleFill {
      if containsFill(point) {
        return true
      }

      if tolerance > 0,
        subpaths.flatMap(\.fillSegments).contains(where: {
          distance(from: point, to: $0) <= tolerance
        })
      {
        return true
      }
    }

    guard let stroke = style.visibleStroke else { return false }

    return StrokeHitGeometry(stroke: stroke, tolerance: tolerance).contains(
      point,
      in: subpaths
    )
  }

  private var bounds: SionRect? {
    let points = subpaths.flatMap(\.points)
    guard let first = points.first else { return nil }

    return points.dropFirst().reduce(
      SionRect(x: first.x, y: first.y, width: 0, height: 0)
    ) { bounds, point in
      bounds.union(SionRect(x: point.x, y: point.y, width: 0, height: 0))
    }
  }

  private func containsFill(_ point: SionPoint) -> Bool {
    let segments = subpaths.flatMap(\.fillSegments)
    guard !segments.isEmpty else { return false }

    if segments.contains(where: { distance(from: point, to: $0) <= HitGeometryDefaults.epsilon }) {
      return true
    }

    switch fillRule {
    case .evenOdd:
      return crossingCount(at: point, segments: segments).isMultiple(of: 2) == false
    case .nonZero:
      return windingNumber(at: point, segments: segments) != 0
    }
  }

  private func crossingCount(at point: SionPoint, segments: [SionLineSegment]) -> Int {
    segments.reduce(into: 0) { count, segment in
      let startAbove = segment.start.y > point.y
      let endAbove = segment.end.y > point.y
      guard startAbove != endAbove else { return }

      let intersectionX =
        segment.start.x
        + ((point.y - segment.start.y) * (segment.end.x - segment.start.x)
          / (segment.end.y - segment.start.y))
      if intersectionX > point.x {
        count += 1
      }
    }
  }

  private func windingNumber(at point: SionPoint, segments: [SionLineSegment]) -> Int {
    segments.reduce(into: 0) { winding, segment in
      if segment.start.y <= point.y {
        guard segment.end.y > point.y, side(of: segment, relativeTo: point) > 0 else {
          return
        }

        winding += 1
        return
      }

      guard segment.end.y <= point.y, side(of: segment, relativeTo: point) < 0 else {
        return
      }

      winding -= 1
    }
  }

  private func side(of segment: SionLineSegment, relativeTo point: SionPoint) -> Double {
    ((segment.end.x - segment.start.x) * (point.y - segment.start.y))
      - ((point.x - segment.start.x) * (segment.end.y - segment.start.y))
  }

  private func distance(from point: SionPoint, to segment: SionLineSegment) -> Double {
    let vector = segment.end - segment.start
    let lengthSquared = vector.lengthSquared
    guard lengthSquared > 0 else { return point.distance(to: segment.start) }

    let projection = (point - segment.start).dot(vector) / lengthSquared
    let fraction = min(1, max(0, projection))
    return point.distance(to: segment.start + (vector * fraction))
  }
}

private struct FlattenedSubpath {
  let points: [SionPoint]
  let closure: SubpathClosure

  var strokeSegments: [SionLineSegment] {
    segments(closure: closure)
  }

  // Filling implicitly closes open subpaths, matching Canvas and SVG paint.
  var fillSegments: [SionLineSegment] {
    guard points.count >= 3 else { return [] }

    return segments(closure: .closed)
  }

  private func segments(closure: SubpathClosure) -> [SionLineSegment] {
    guard points.count >= 2 else { return [] }

    var result = zip(points, points.dropFirst()).map(SionLineSegment.init)
    if closure == .closed,
      points.first != points.last,
      let first = points.first,
      let last = points.last
    {
      result.append(SionLineSegment(start: last, end: first))
    }

    return result
  }
}

private struct FlattenedPathBuilder {
  private var subpaths: [FlattenedSubpath] = []
  private var activePoints: [SionPoint] = []
  private var currentPoint: SionPoint?

  mutating func move(to point: SionPoint) {
    finishActivePath(closure: .open)
    activePoints = [point]
    currentPoint = point
  }

  mutating func line(to point: SionPoint) {
    guard startActivePathIfNeeded() != nil else {
      move(to: point)
      return
    }

    activePoints.append(point)
    currentPoint = point
  }

  mutating func quadratic(control: SionPoint, to end: SionPoint) {
    guard let start = startActivePathIfNeeded() else {
      move(to: end)
      return
    }

    appendQuadratic(start: start, control: control, end: end, depth: 0)
    currentPoint = end
  }

  mutating func cubic(control1: SionPoint, control2: SionPoint, to end: SionPoint) {
    guard let start = startActivePathIfNeeded() else {
      move(to: end)
      return
    }

    appendCubic(
      start: start,
      control1: control1,
      control2: control2,
      end: end,
      depth: 0
    )
    currentPoint = end
  }

  mutating func close() {
    guard let start = activePoints.first else { return }

    finishActivePath(closure: .closed)
    currentPoint = start
  }

  mutating func build(fillRule: PathFillRule = .nonZero) -> FlattenedPath {
    finishActivePath(closure: .open)

    return FlattenedPath(subpaths: subpaths, fillRule: fillRule)
  }

  private mutating func finishActivePath(closure: SubpathClosure) {
    guard !activePoints.isEmpty else { return }

    subpaths.append(FlattenedSubpath(points: activePoints, closure: closure))
    activePoints = []
  }

  private mutating func startActivePathIfNeeded() -> SionPoint? {
    if let activePoint = activePoints.last {
      return activePoint
    }

    guard let currentPoint else { return nil }

    activePoints = [currentPoint]
    return currentPoint
  }

  private mutating func appendQuadratic(
    start: SionPoint,
    control: SionPoint,
    end: SionPoint,
    depth: Int
  ) {
    // De Casteljau subdivision keeps error stable on large canvases.
    let isFlat =
      distance(from: control, toLineFrom: start, to: end)
      <= HitGeometryDefaults.curveFlatness
    guard !isFlat, depth < HitGeometryDefaults.maximumCurveSubdivisionDepth else {
      activePoints.append(end)
      return
    }

    let startControl = start.interpolated(to: control, fraction: 0.5)
    let controlEnd = control.interpolated(to: end, fraction: 0.5)
    let midpoint = startControl.interpolated(to: controlEnd, fraction: 0.5)
    appendQuadratic(
      start: start,
      control: startControl,
      end: midpoint,
      depth: depth + 1
    )
    appendQuadratic(
      start: midpoint,
      control: controlEnd,
      end: end,
      depth: depth + 1
    )
  }

  private mutating func appendCubic(
    start: SionPoint,
    control1: SionPoint,
    control2: SionPoint,
    end: SionPoint,
    depth: Int
  ) {
    let flatness = max(
      distance(from: control1, toLineFrom: start, to: end),
      distance(from: control2, toLineFrom: start, to: end)
    )
    guard flatness > HitGeometryDefaults.curveFlatness,
      depth < HitGeometryDefaults.maximumCurveSubdivisionDepth
    else {
      activePoints.append(end)
      return
    }

    let first = start.interpolated(to: control1, fraction: 0.5)
    let second = control1.interpolated(to: control2, fraction: 0.5)
    let third = control2.interpolated(to: end, fraction: 0.5)
    let leftControl = first.interpolated(to: second, fraction: 0.5)
    let rightControl = second.interpolated(to: third, fraction: 0.5)
    let midpoint = leftControl.interpolated(to: rightControl, fraction: 0.5)
    appendCubic(
      start: start,
      control1: first,
      control2: leftControl,
      end: midpoint,
      depth: depth + 1
    )
    appendCubic(
      start: midpoint,
      control1: rightControl,
      control2: third,
      end: end,
      depth: depth + 1
    )
  }

  private func distance(
    from point: SionPoint,
    toLineFrom start: SionPoint,
    to end: SionPoint
  ) -> Double {
    let segment = SionLineSegment(start: start, end: end)
    let vector = segment.end - segment.start
    let lengthSquared = vector.lengthSquared
    guard lengthSquared > 0 else { return point.distance(to: segment.start) }

    let projection = (point - segment.start).dot(vector) / lengthSquared
    let fraction = min(1, max(0, projection))
    return point.distance(to: segment.start + (vector * fraction))
  }
}

private enum SubpathClosure {
  case open
  case closed
}

private struct StrokeHitGeometry {
  let stroke: StrokeStyle
  let tolerance: Double

  private var radius: Double {
    stroke.width / 2
  }

  func contains(_ point: SionPoint, in subpaths: [FlattenedSubpath]) -> Bool {
    subpaths.contains { subpath in
      strokeRuns(for: subpath).contains { run in
        contains(point, in: run)
      }
    }
  }

  private func contains(_ point: SionPoint, in run: StrokeRun) -> Bool {
    let segments = run.segments
    for (index, segment) in segments.enumerated() {
      let startsRun = run.closure == .open && index == segments.startIndex
      let endsRun = run.closure == .open && index == segments.index(before: segments.endIndex)
      let startExtension = startsRun && stroke.lineCap == .square ? radius : 0
      let endExtension = endsRun && stroke.lineCap == .square ? radius : 0
      if bodyContains(
        point,
        segment: segment,
        startExtension: startExtension,
        endExtension: endExtension
      ) {
        return true
      }
    }

    if run.closure == .open, stroke.lineCap == .round,
      let start = run.points.first,
      let end = run.points.last,
      min(point.distance(to: start), point.distance(to: end)) <= radius + tolerance
    {
      return true
    }

    return joinPoints(in: run).contains { join in
      joinContains(point, previous: join.previous, vertex: join.vertex, next: join.next)
    }
  }

  private func bodyContains(
    _ point: SionPoint,
    segment: SionLineSegment,
    startExtension: Double,
    endExtension: Double
  ) -> Bool {
    let vector = segment.end - segment.start
    let length = vector.length
    guard length > HitGeometryDefaults.epsilon else { return false }

    let direction = vector / length
    let offset = point - segment.start
    let along = offset.dot(direction)
    let perpendicular = abs(cross(offset, direction))
    let outsideAlong = max(0, max((-startExtension) - along, along - length - endExtension))
    let outsidePerpendicular = max(0, perpendicular - radius)

    return hypot(outsideAlong, outsidePerpendicular) <= tolerance
      + HitGeometryDefaults.epsilon
  }

  private func joinContains(
    _ point: SionPoint,
    previous: SionPoint,
    vertex: SionPoint,
    next: SionPoint
  ) -> Bool {
    let incoming = (vertex - previous).normalized
    let outgoing = (next - vertex).normalized
    guard incoming.lengthSquared > 0, outgoing.lengthSquared > 0 else { return false }

    let turn = cross(incoming, outgoing)
    guard abs(turn) > HitGeometryDefaults.epsilon else {
      return stroke.lineJoin == .round
        && incoming.dot(outgoing) < 0
        && point.distance(to: vertex) <= radius + tolerance
    }

    if stroke.lineJoin == .round {
      return point.distance(to: vertex) <= radius + tolerance
    }

    let incomingNormal = SionVector(dx: -incoming.dy, dy: incoming.dx)
    let outgoingNormal = SionVector(dx: -outgoing.dy, dy: outgoing.dx)
    let outerScale = turn > 0 ? -radius : radius
    let incomingOuter = vertex + (incomingNormal * outerScale)
    let outgoingOuter = vertex + (outgoingNormal * outerScale)
    var polygon = [vertex, incomingOuter, outgoingOuter]

    if stroke.lineJoin == .miter,
      let intersection = lineIntersection(
        firstOrigin: incomingOuter,
        firstDirection: incoming,
        secondOrigin: outgoingOuter,
        secondDirection: outgoing
      ),
      vertex.distance(to: intersection) <= HitGeometryDefaults.miterLimit * radius
    {
      polygon = [vertex, incomingOuter, intersection, outgoingOuter]
    }

    return polygonContains(point, polygon: polygon, tolerance: tolerance)
  }

  private func strokeRuns(for subpath: FlattenedSubpath) -> [StrokeRun] {
    var pattern = stroke.dashPattern.filter { $0.isFinite && $0 > 0 }
    guard !pattern.isEmpty else {
      return [StrokeRun(points: subpath.points, closure: subpath.closure)]
    }

    if !pattern.count.isMultiple(of: 2) {
      pattern += pattern
    }

    var patternIndex = pattern.startIndex
    var patternRemaining = pattern[patternIndex]
    var draws = true
    var activePoints: [SionPoint] = []
    var runs: [StrokeRun] = []

    // Dash phase crosses vertices; only painted runs receive caps.
    func finishRun() {
      guard activePoints.count >= 2 else {
        activePoints = []
        return
      }

      runs.append(StrokeRun(points: activePoints, closure: .open))
      activePoints = []
    }

    for segment in subpath.strokeSegments {
      let length = segment.length
      guard length > HitGeometryDefaults.epsilon else { continue }

      var position = 0.0
      while position < length - HitGeometryDefaults.epsilon {
        let step = min(patternRemaining, length - position)
        let start = segment.start.interpolated(to: segment.end, fraction: position / length)
        let end = segment.start.interpolated(
          to: segment.end,
          fraction: (position + step) / length
        )
        if draws {
          if activePoints.last != start {
            activePoints.append(start)
          }
          activePoints.append(end)
        }

        position += step
        patternRemaining -= step
        guard patternRemaining <= HitGeometryDefaults.epsilon else { continue }

        if draws {
          finishRun()
        }
        patternIndex = pattern.index(after: patternIndex)
        if patternIndex == pattern.endIndex {
          patternIndex = pattern.startIndex
        }
        patternRemaining = pattern[patternIndex]
        draws.toggle()
      }
    }
    finishRun()

    mergeClosedSeam(in: subpath, runs: &runs)
    return runs
  }

  private func mergeClosedSeam(
    in subpath: FlattenedSubpath,
    runs: inout [StrokeRun]
  ) {
    guard subpath.closure == .closed,
      runs.count > 1,
      let seam = subpath.points.first,
      runs.first?.points.first == seam,
      runs.last?.points.last == seam,
      let first = runs.first,
      let last = runs.last
    else { return }

    runs.removeLast()
    runs.removeFirst()
    runs.insert(
      StrokeRun(points: last.points + first.points.dropFirst(), closure: .open),
      at: 0
    )
  }

  private func joinPoints(in run: StrokeRun) -> [StrokeJoin] {
    guard run.points.count >= 3 else { return [] }

    var joins = run.points.indices.dropFirst().dropLast().map { index in
      StrokeJoin(
        previous: run.points[run.points.index(before: index)],
        vertex: run.points[index],
        next: run.points[run.points.index(after: index)]
      )
    }
    if run.closure == .closed,
      let first = run.points.first,
      let last = run.points.last,
      run.points.count > 2
    {
      joins.append(StrokeJoin(previous: last, vertex: first, next: run.points[1]))
      joins.append(
        StrokeJoin(
          previous: run.points[run.points.count - 2],
          vertex: last,
          next: first
        )
      )
    }

    return joins
  }

  private func lineIntersection(
    firstOrigin: SionPoint,
    firstDirection: SionVector,
    secondOrigin: SionPoint,
    secondDirection: SionVector
  ) -> SionPoint? {
    let denominator = cross(firstDirection, secondDirection)
    guard abs(denominator) > HitGeometryDefaults.epsilon else { return nil }

    let distance = cross(secondOrigin - firstOrigin, secondDirection) / denominator
    return firstOrigin + (firstDirection * distance)
  }

  private func polygonContains(
    _ point: SionPoint,
    polygon: [SionPoint],
    tolerance: Double
  ) -> Bool {
    guard polygon.count >= 3 else { return false }

    var inside = false
    for index in polygon.indices {
      let nextIndex =
        polygon.index(after: index) == polygon.endIndex
        ? polygon.startIndex
        : polygon.index(after: index)
      let segment = SionLineSegment(start: polygon[index], end: polygon[nextIndex])
      if distance(from: point, to: segment) <= tolerance + HitGeometryDefaults.epsilon {
        return true
      }

      let crosses = (segment.start.y > point.y) != (segment.end.y > point.y)
      guard crosses else { continue }

      let intersectionX =
        segment.start.x
        + ((point.y - segment.start.y) * (segment.end.x - segment.start.x)
          / (segment.end.y - segment.start.y))
      if intersectionX > point.x {
        inside.toggle()
      }
    }

    return inside
  }

  private func distance(from point: SionPoint, to segment: SionLineSegment) -> Double {
    let vector = segment.end - segment.start
    let lengthSquared = vector.lengthSquared
    guard lengthSquared > 0 else { return point.distance(to: segment.start) }

    let projection = (point - segment.start).dot(vector) / lengthSquared
    let fraction = min(1, max(0, projection))
    return point.distance(to: segment.start + (vector * fraction))
  }

  private func cross(_ first: SionVector, _ second: SionVector) -> Double {
    (first.dx * second.dy) - (first.dy * second.dx)
  }
}

private struct StrokeRun {
  let points: [SionPoint]
  let closure: SubpathClosure

  var segments: [SionLineSegment] {
    guard points.count >= 2 else { return [] }

    var result = zip(points, points.dropFirst()).map(SionLineSegment.init)
    if closure == .closed, points.first != points.last,
      let first = points.first,
      let last = points.last
    {
      result.append(SionLineSegment(start: last, end: first))
    }

    return result
  }
}

private struct StrokeJoin {
  let previous: SionPoint
  let vertex: SionPoint
  let next: SionPoint
}

extension ShapeKind {
  fileprivate func hitBounds(in frame: SionRect) -> SionRect? {
    guard case .custom(let path) = self else { return frame }

    return path.hitBounds(in: frame)
  }

  fileprivate func flattened(in frame: SionRect) -> FlattenedPath {
    switch self {
    case .rectangle:
      return polygon([
        SionPoint(x: frame.minX, y: frame.minY),
        SionPoint(x: frame.maxX, y: frame.minY),
        SionPoint(x: frame.maxX, y: frame.maxY),
        SionPoint(x: frame.minX, y: frame.maxY),
      ])
    case .roundedRectangle(let radius):
      return roundedRectangle(in: frame, radius: radius)
    case .ellipse:
      return ellipse(in: frame)
    case .diamond:
      return polygon([
        SionPoint(x: frame.center.x, y: frame.minY),
        SionPoint(x: frame.maxX, y: frame.center.y),
        SionPoint(x: frame.center.x, y: frame.maxY),
        SionPoint(x: frame.minX, y: frame.center.y),
      ])
    case .triangle:
      return polygon([
        SionPoint(x: frame.center.x, y: frame.minY),
        SionPoint(x: frame.maxX, y: frame.maxY),
        SionPoint(x: frame.minX, y: frame.maxY),
      ])
    case .hexagon:
      let inset = frame.width * ShapeGeometryDefaults.hexagonInsetFraction
      return polygon([
        SionPoint(x: frame.minX + inset, y: frame.minY),
        SionPoint(x: frame.maxX - inset, y: frame.minY),
        SionPoint(x: frame.maxX, y: frame.center.y),
        SionPoint(x: frame.maxX - inset, y: frame.maxY),
        SionPoint(x: frame.minX + inset, y: frame.maxY),
        SionPoint(x: frame.minX, y: frame.center.y),
      ])
    case .capsule:
      return roundedRectangle(in: frame, radius: min(frame.width, frame.height) / 2)
    case .cylinder:
      return cylinder(in: frame)
    case .custom(let path):
      return path.flattened(in: frame)
    }
  }

  private func polygon(_ points: [SionPoint]) -> FlattenedPath {
    var builder = FlattenedPathBuilder()
    guard let first = points.first else { return builder.build() }

    builder.move(to: first)
    for point in points.dropFirst() {
      builder.line(to: point)
    }
    builder.close()

    return builder.build()
  }

  private func roundedRectangle(in frame: SionRect, radius: Double) -> FlattenedPath {
    let finiteRadius = radius.isFinite ? radius : 0
    let clampedRadius = min(max(0, finiteRadius), min(frame.width, frame.height) / 2)
    guard clampedRadius > 0 else {
      return ShapeKind.rectangle.flattened(in: frame)
    }

    let control = clampedRadius * HitGeometryDefaults.arcControlFactor
    var builder = FlattenedPathBuilder()
    builder.move(to: SionPoint(x: frame.minX + clampedRadius, y: frame.minY))
    builder.line(to: SionPoint(x: frame.maxX - clampedRadius, y: frame.minY))
    builder.cubic(
      control1: SionPoint(x: frame.maxX - clampedRadius + control, y: frame.minY),
      control2: SionPoint(x: frame.maxX, y: frame.minY + clampedRadius - control),
      to: SionPoint(x: frame.maxX, y: frame.minY + clampedRadius)
    )
    builder.line(to: SionPoint(x: frame.maxX, y: frame.maxY - clampedRadius))
    builder.cubic(
      control1: SionPoint(x: frame.maxX, y: frame.maxY - clampedRadius + control),
      control2: SionPoint(x: frame.maxX - clampedRadius + control, y: frame.maxY),
      to: SionPoint(x: frame.maxX - clampedRadius, y: frame.maxY)
    )
    builder.line(to: SionPoint(x: frame.minX + clampedRadius, y: frame.maxY))
    builder.cubic(
      control1: SionPoint(x: frame.minX + clampedRadius - control, y: frame.maxY),
      control2: SionPoint(x: frame.minX, y: frame.maxY - clampedRadius + control),
      to: SionPoint(x: frame.minX, y: frame.maxY - clampedRadius)
    )
    builder.line(to: SionPoint(x: frame.minX, y: frame.minY + clampedRadius))
    builder.cubic(
      control1: SionPoint(x: frame.minX, y: frame.minY + clampedRadius - control),
      control2: SionPoint(x: frame.minX + clampedRadius - control, y: frame.minY),
      to: SionPoint(x: frame.minX + clampedRadius, y: frame.minY)
    )
    builder.close()

    return builder.build()
  }

  private func ellipse(in frame: SionRect) -> FlattenedPath {
    let horizontalRadius = frame.width / 2
    let verticalRadius = frame.height / 2
    let horizontalControl = horizontalRadius * HitGeometryDefaults.arcControlFactor
    let verticalControl = verticalRadius * HitGeometryDefaults.arcControlFactor
    var builder = FlattenedPathBuilder()
    builder.move(to: SionPoint(x: frame.center.x, y: frame.minY))
    builder.cubic(
      control1: SionPoint(x: frame.center.x + horizontalControl, y: frame.minY),
      control2: SionPoint(x: frame.maxX, y: frame.center.y - verticalControl),
      to: SionPoint(x: frame.maxX, y: frame.center.y)
    )
    builder.cubic(
      control1: SionPoint(x: frame.maxX, y: frame.center.y + verticalControl),
      control2: SionPoint(x: frame.center.x + horizontalControl, y: frame.maxY),
      to: SionPoint(x: frame.center.x, y: frame.maxY)
    )
    builder.cubic(
      control1: SionPoint(x: frame.center.x - horizontalControl, y: frame.maxY),
      control2: SionPoint(x: frame.minX, y: frame.center.y + verticalControl),
      to: SionPoint(x: frame.minX, y: frame.center.y)
    )
    builder.cubic(
      control1: SionPoint(x: frame.minX, y: frame.center.y - verticalControl),
      control2: SionPoint(x: frame.center.x - horizontalControl, y: frame.minY),
      to: SionPoint(x: frame.center.x, y: frame.minY)
    )
    builder.close()

    return builder.build()
  }

  private func cylinder(in frame: SionRect) -> FlattenedPath {
    let arcHeight = min(
      frame.height * ShapeGeometryDefaults.cylinderArcFraction,
      frame.height / 2
    )
    let horizontalControl = (frame.width / 2) * HitGeometryDefaults.arcControlFactor
    let verticalControl = arcHeight * HitGeometryDefaults.arcControlFactor
    var builder = FlattenedPathBuilder()
    builder.move(to: SionPoint(x: frame.minX, y: frame.minY + arcHeight))
    builder.cubic(
      control1: SionPoint(x: frame.minX, y: frame.minY + arcHeight - verticalControl),
      control2: SionPoint(x: frame.center.x - horizontalControl, y: frame.minY),
      to: SionPoint(x: frame.center.x, y: frame.minY)
    )
    builder.cubic(
      control1: SionPoint(x: frame.center.x + horizontalControl, y: frame.minY),
      control2: SionPoint(x: frame.maxX, y: frame.minY + arcHeight - verticalControl),
      to: SionPoint(x: frame.maxX, y: frame.minY + arcHeight)
    )
    builder.line(to: SionPoint(x: frame.maxX, y: frame.maxY - arcHeight))
    builder.cubic(
      control1: SionPoint(x: frame.maxX, y: frame.maxY - arcHeight + verticalControl),
      control2: SionPoint(x: frame.center.x + horizontalControl, y: frame.maxY),
      to: SionPoint(x: frame.center.x, y: frame.maxY)
    )
    builder.cubic(
      control1: SionPoint(x: frame.center.x - horizontalControl, y: frame.maxY),
      control2: SionPoint(x: frame.minX, y: frame.maxY - arcHeight + verticalControl),
      to: SionPoint(x: frame.minX, y: frame.maxY - arcHeight)
    )
    builder.close()

    return builder.build()
  }
}

extension VectorPath {
  fileprivate func hitBounds(in frame: SionRect) -> SionRect? {
    var result: SionRect?

    func resolve(_ point: SionPoint) -> SionPoint {
      switch coordinateSpace {
      case .normalized:
        return frame.point(atNormalized: point)
      case .localPoints:
        return SionPoint(x: frame.minX + point.x, y: frame.minY + point.y)
      }
    }

    func include(_ point: SionPoint) {
      let pointBounds = SionRect(x: point.x, y: point.y, width: 0, height: 0)
      result = result?.union(pointBounds) ?? pointBounds
    }

    for command in commands {
      switch command {
      case .move(let point), .line(let point):
        include(resolve(point))
      case .quadratic(let control, let point):
        include(resolve(control))
        include(resolve(point))
      case .cubic(let control1, let control2, let point):
        include(resolve(control1))
        include(resolve(control2))
        include(resolve(point))
      case .close:
        continue
      }
    }

    return result
  }

  fileprivate func flattened(in frame: SionRect) -> FlattenedPath {
    var builder = FlattenedPathBuilder()

    func resolve(_ point: SionPoint) -> SionPoint {
      switch coordinateSpace {
      case .normalized:
        return frame.point(atNormalized: point)
      case .localPoints:
        return SionPoint(x: frame.minX + point.x, y: frame.minY + point.y)
      }
    }

    for command in commands {
      switch command {
      case .move(let point):
        builder.move(to: resolve(point))
      case .line(let point):
        builder.line(to: resolve(point))
      case .quadratic(let control, let point):
        builder.quadratic(control: resolve(control), to: resolve(point))
      case .cubic(let control1, let control2, let point):
        builder.cubic(
          control1: resolve(control1),
          control2: resolve(control2),
          to: resolve(point)
        )
      case .close:
        builder.close()
      }
    }

    return builder.build(fillRule: fillRule)
  }
}

extension ElementStyle {
  fileprivate var hasVisibleFill: Bool {
    guard opacity > 0 else { return false }

    switch fill {
    case .none:
      return false
    case .solid(let color):
      return color.alpha > 0
    case .linearGradient(let gradient):
      return gradient.stops.contains { $0.color.alpha > 0 }
    }
  }

  fileprivate var visibleStroke: StrokeStyle? {
    guard opacity > 0,
      let stroke,
      stroke.width.isFinite,
      stroke.width > 0,
      stroke.color.alpha > 0
    else {
      return nil
    }

    return stroke
  }

  fileprivate func hitExpansion(tolerance: Double) -> Double {
    max(
      hasVisibleFill ? tolerance : 0,
      visibleStroke?.hitExpansion(tolerance: tolerance) ?? 0
    )
  }
}

extension StrokeStyle {
  fileprivate func hitExpansion(tolerance: Double) -> Double {
    let radius = width / 2
    let joinExpansion =
      lineJoin == .miter
      ? radius * HitGeometryDefaults.miterLimit
      : radius

    return joinExpansion + tolerance
  }
}

extension TextContent {
  fileprivate func hitBounds(in frame: SionRect, elementOpacity: Double) -> SionRect? {
    guard !string.isEmpty, elementOpacity > 0, style.color.alpha > 0 else { return nil }

    let leading = nonnegativeFinite(style.insets.leading)
    let trailing = nonnegativeFinite(style.insets.trailing)
    let top = nonnegativeFinite(style.insets.top)
    let bottom = nonnegativeFinite(style.insets.bottom)

    return SionRect(
      x: frame.minX + leading,
      y: frame.minY + top,
      width: max(0, frame.width - leading - trailing),
      height: max(0, frame.height - top - bottom)
    )
  }

  private func nonnegativeFinite(_ value: Double) -> Double {
    value.isFinite ? max(0, value) : 0
  }
}

private enum HitGeometryDefaults {
  static let arcControlFactor = 0.552_284_749_8
  static let curveFlatness = 0.25
  static let epsilon = 1e-9
  static let maximumCurveSubdivisionDepth = 12
  // StrokeStyle has no override, so mirror NSBezierPath's default.
  static let miterLimit = 10.0
}
