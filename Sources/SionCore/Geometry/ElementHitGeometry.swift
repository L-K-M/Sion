import Foundation

/// Platform-neutral point hits against a scene element's selectable geometry.
package enum ElementHitGeometry {
  package static func contains(
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
        content.kind.contains(
          localPoint,
          in: frame,
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
  let approximationTolerance: Double
  let truncationTolerance: Double
  let dashPhaseUncertainty: Double

  func contains(
    _ point: SionPoint,
    style: ElementStyle,
    tolerance: Double
  ) -> Bool {
    guard let bounds else { return false }

    let fillTolerance = tolerance + approximationTolerance
    let strokeTolerance = tolerance + truncationTolerance
    let strokeRadius = style.visibleStroke?.hitExpansion(tolerance: strokeTolerance) ?? 0
    let fillRadius = style.hasVisibleFill ? fillTolerance : 0
    guard bounds.expanded(by: max(fillRadius, strokeRadius)).contains(point) else {
      return false
    }

    if style.hasVisibleFill {
      if containsFill(point) {
        return true
      }

      if fillTolerance > 0,
        subpaths.flatMap(\.fillSegments).contains(where: {
          distance(from: point, to: $0) <= fillTolerance
        })
      {
        return true
      }
    }

    guard var stroke = style.visibleStroke else { return false }

    // Preserve selection with a conservative margin when the path exhausts its budget.
    if truncationTolerance > 0 {
      stroke.dashPattern = []
    }

    return StrokeHitGeometry(
      stroke: stroke,
      tolerance: strokeTolerance,
      phaseUncertainty: dashPhaseUncertainty
    ).contains(point, in: subpaths)
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
  let segmentApproximationTolerances: [Double]
  let closure: SubpathClosure

  var strokeSegments: [FlattenedStrokeSegment] {
    guard points.count >= 2 else { return [] }

    var result = zip(points, points.dropFirst()).enumerated().map { index, points in
      FlattenedStrokeSegment(
        segment: SionLineSegment(start: points.0, end: points.1),
        approximationTolerance: segmentApproximationTolerances[index]
      )
    }
    if closure == .closed,
      points.first != points.last,
      let first = points.first,
      let last = points.last
    {
      result.append(
        FlattenedStrokeSegment(
          segment: SionLineSegment(start: last, end: first),
          approximationTolerance: 0
        )
      )
    }

    return result
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
  private var activeSegmentApproximationTolerances: [Double] = []
  private var currentPoint: SionPoint?
  private var approximationTolerance = 0.0
  private var truncationTolerance = 0.0
  private var dashPhaseUncertainty = 0.0
  private let maximumCurveSubdivisionDepth: Int

  init(
    maximumCurveSubdivisionDepth: Int = HitGeometryDefaults.maximumCurveSubdivisionDepth
  ) {
    self.maximumCurveSubdivisionDepth = maximumCurveSubdivisionDepth
  }

  mutating func move(to point: SionPoint) {
    finishActivePath(closure: .open)
    activePoints = [point]
    activeSegmentApproximationTolerances = []
    currentPoint = point
  }

  mutating func line(to point: SionPoint) {
    guard startActivePathIfNeeded() != nil else {
      move(to: point)
      return
    }

    activePoints.append(point)
    activeSegmentApproximationTolerances.append(0)
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

    return FlattenedPath(
      subpaths: subpaths,
      fillRule: fillRule,
      approximationTolerance: approximationTolerance,
      truncationTolerance: truncationTolerance,
      dashPhaseUncertainty: dashPhaseUncertainty
    )
  }

  private mutating func finishActivePath(closure: SubpathClosure) {
    guard !activePoints.isEmpty else { return }

    subpaths.append(
      FlattenedSubpath(
        points: activePoints,
        segmentApproximationTolerances: activeSegmentApproximationTolerances,
        closure: closure
      )
    )
    activePoints = []
    activeSegmentApproximationTolerances = []
  }

  private mutating func startActivePathIfNeeded() -> SionPoint? {
    if let activePoint = activePoints.last {
      return activePoint
    }

    guard let currentPoint else { return nil }

    activePoints = [currentPoint]
    activeSegmentApproximationTolerances = []
    return currentPoint
  }

  private mutating func appendQuadratic(
    start: SionPoint,
    control: SionPoint,
    end: SionPoint,
    depth: Int
  ) {
    // De Casteljau subdivision keeps error stable on large canvases.
    let flatness = distance(from: control, toLineFrom: start, to: end)
    guard flatness > HitGeometryDefaults.curveFlatness else {
      appendQuadraticLeaf(
        start: start,
        control: control,
        end: end,
        approximationTolerance: flatness
      )
      return
    }
    guard depth < maximumCurveSubdivisionDepth else {
      truncationTolerance = max(truncationTolerance, flatness)
      appendQuadraticLeaf(
        start: start,
        control: control,
        end: end,
        approximationTolerance: flatness
      )
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
    guard flatness > HitGeometryDefaults.curveFlatness else {
      appendCubicLeaf(
        start: start,
        control1: control1,
        control2: control2,
        end: end,
        approximationTolerance: flatness
      )
      return
    }
    guard depth < maximumCurveSubdivisionDepth else {
      truncationTolerance = max(truncationTolerance, flatness)
      appendCubicLeaf(
        start: start,
        control1: control1,
        control2: control2,
        end: end,
        approximationTolerance: flatness
      )
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

  private mutating func appendQuadraticLeaf(
    start: SionPoint,
    control: SionPoint,
    end: SionPoint,
    approximationTolerance: Double
  ) {
    self.approximationTolerance = max(self.approximationTolerance, approximationTolerance)
    recordDashPhaseUncertainty(
      controlPolygonLength: start.distance(to: control) + control.distance(to: end),
      chordLength: start.distance(to: end)
    )
    activePoints.append(end)
    activeSegmentApproximationTolerances.append(approximationTolerance)
  }

  private mutating func appendCubicLeaf(
    start: SionPoint,
    control1: SionPoint,
    control2: SionPoint,
    end: SionPoint,
    approximationTolerance: Double
  ) {
    self.approximationTolerance = max(self.approximationTolerance, approximationTolerance)
    recordDashPhaseUncertainty(
      controlPolygonLength: start.distance(to: control1)
        + control1.distance(to: control2)
        + control2.distance(to: end),
      chordLength: start.distance(to: end)
    )
    activePoints.append(end)
    activeSegmentApproximationTolerances.append(approximationTolerance)
  }

  private mutating func recordDashPhaseUncertainty(
    controlPolygonLength: Double,
    chordLength: Double
  ) {
    // A Bezier's control polygon bounds how far flattened dash phase can lag.
    dashPhaseUncertainty += max(0, controlPolygonLength - chordLength)
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
  let phaseUncertainty: Double

  private var radius: Double {
    stroke.width / 2
  }

  func contains(_ point: SionPoint, in subpaths: [FlattenedSubpath]) -> Bool {
    guard let dashPattern = DashPattern(stroke.dashPattern) else {
      return subpaths.contains { subpath in
        contains(point, in: StrokeRun(subpath: subpath))
      }
    }

    return subpaths.contains { subpath in
      contains(point, in: subpath, dashPattern: dashPattern)
    }
  }

  private func contains(
    _ point: SionPoint,
    in subpath: FlattenedSubpath,
    dashPattern: DashPattern
  ) -> Bool {
    let segments = measuredSegments(in: subpath)
    guard let pathLength = segments.last?.endDistance else { return false }

    let joinsAtSeam =
      subpath.closure == .closed
      && dashPattern.mayBePainted(before: pathLength, uncertainty: phaseUncertainty)
      && dashPattern.mayBePainted(after: 0, uncertainty: phaseUncertainty)

    for segment in segments {
      if dashedBodyContains(
        point,
        measuredSegment: segment,
        pathLength: pathLength,
        closure: subpath.closure,
        joinsAtSeam: joinsAtSeam,
        dashPattern: dashPattern
      ) {
        return true
      }
    }

    for index in segments.indices.dropFirst() {
      let outgoing = segments[index]
      guard
        dashPattern.mayBePainted(
          before: outgoing.startDistance,
          uncertainty: phaseUncertainty
        ),
        dashPattern.mayBePainted(
          after: outgoing.startDistance,
          uncertainty: phaseUncertainty
        )
      else {
        continue
      }

      let incoming = segments[segments.index(before: index)]
      if joinContains(
        point,
        previous: incoming.segment.start,
        vertex: outgoing.segment.start,
        next: outgoing.segment.end
      ) {
        return true
      }
    }

    guard joinsAtSeam,
      let incoming = segments.last,
      let outgoing = segments.first
    else {
      return false
    }

    return joinContains(
      point,
      previous: incoming.segment.start,
      vertex: outgoing.segment.start,
      next: outgoing.segment.end
    )
  }

  private func contains(_ point: SionPoint, in run: StrokeRun) -> Bool {
    let segments = run.segments
    for (index, flattenedSegment) in segments.enumerated() {
      let startsRun = run.closure == .open && index == segments.startIndex
      let endsRun = run.closure == .open && index == segments.index(before: segments.endIndex)
      let startExtension = startsRun && stroke.lineCap == .square ? radius : 0
      let endExtension = endsRun && stroke.lineCap == .square ? radius : 0
      if bodyContains(
        point,
        segment: flattenedSegment.segment,
        startExtension: startExtension,
        endExtension: endExtension
      ) {
        return true
      }

      // A flattened curve can turn within its positional error near a chord endpoint.
      if flattenedSegment.approximationTolerance > 0,
        distance(from: point, to: flattenedSegment.segment)
          <= radius + tolerance + flattenedSegment.approximationTolerance
      {
        return true
      }
    }

    if curvedSquareCapContains(point, in: run) {
      return true
    }

    if run.closure == .open, stroke.lineCap == .round,
      let start = run.vertices.first,
      let end = run.vertices.last,
      min(point.distance(to: start), point.distance(to: end)) <= radius + tolerance
    {
      return true
    }

    return joinPoints(in: run).contains { join in
      joinContains(point, previous: join.previous, vertex: join.vertex, next: join.next)
    }
  }

  private func curvedSquareCapContains(_ point: SionPoint, in run: StrokeRun) -> Bool {
    guard run.closure == .open, stroke.lineCap == .square else { return false }

    let capRadius = hypot(radius, radius)
    if let first = run.segments.first,
      first.approximationTolerance > 0,
      point.distance(to: first.segment.start)
        <= capRadius + tolerance + first.approximationTolerance
    {
      return true
    }

    guard let last = run.segments.last, last.approximationTolerance > 0 else {
      return false
    }

    return point.distance(to: last.segment.end)
      <= capRadius + tolerance + last.approximationTolerance
  }

  private func bodyContains(
    _ point: SionPoint,
    segment: SionLineSegment,
    startExtension: Double,
    endExtension: Double,
    paintedStart: Double = 0,
    paintedEnd: Double? = nil
  ) -> Bool {
    let vector = segment.end - segment.start
    let length = vector.length
    guard length > HitGeometryDefaults.epsilon else { return false }

    let direction = vector / length
    let offset = point - segment.start
    let along = offset.dot(direction)
    let perpendicular = abs(cross(offset, direction))
    let end = paintedEnd ?? length
    let outsideAlong = max(
      0,
      max(
        paintedStart - startExtension - along,
        along - end - endExtension
      )
    )
    let outsidePerpendicular = max(0, perpendicular - radius)

    return hypot(outsideAlong, outsidePerpendicular) <= tolerance
      + HitGeometryDefaults.epsilon
  }

  private func dashedBodyContains(
    _ point: SionPoint,
    measuredSegment: MeasuredStrokeSegment,
    pathLength: Double,
    closure: SubpathClosure,
    joinsAtSeam: Bool,
    dashPattern: DashPattern
  ) -> Bool {
    let segment = measuredSegment.segment
    let vector = segment.end - segment.start
    let length = measuredSegment.length
    let direction = vector / length
    let projectedDistance = min(length, max(0, (point - segment.start).dot(direction)))
    let pathDistance = measuredSegment.startDistance + projectedDistance
    let spans = dashPattern.paintedSpans(
      near: pathDistance,
      within: measuredSegment.startDistance...measuredSegment.endDistance,
      pathLength: pathLength,
      closure: closure,
      joinsAtSeam: joinsAtSeam,
      uncertainty: phaseUncertainty
    )

    for span in spans {
      let start = span.range.lowerBound - measuredSegment.startDistance
      let end = span.range.upperBound - measuredSegment.startDistance
      if curvedPaintEnvelopeContains(
        point,
        measuredSegment: measuredSegment,
        start: start,
        end: end,
        span: span
      ) {
        return true
      }

      let startExtension = span.startsWithCap && stroke.lineCap == .square ? radius : 0
      let endExtension = span.endsWithCap && stroke.lineCap == .square ? radius : 0
      if bodyContains(
        point,
        segment: segment,
        startExtension: startExtension,
        endExtension: endExtension,
        paintedStart: start,
        paintedEnd: end
      ) {
        return true
      }

      guard stroke.lineCap == .round else { continue }

      if span.startsWithCap,
        point.distance(to: segment.start + (direction * start)) <= radius + tolerance
      {
        return true
      }
      if span.endsWithCap,
        point.distance(to: segment.start + (direction * end)) <= radius + tolerance
      {
        return true
      }
    }

    return false
  }

  private func curvedPaintEnvelopeContains(
    _ point: SionPoint,
    measuredSegment: MeasuredStrokeSegment,
    start: Double,
    end: Double,
    span: DashPaintSpan
  ) -> Bool {
    let approximationTolerance = measuredSegment.approximationTolerance
    guard approximationTolerance > 0 else { return false }

    let vector = measuredSegment.segment.end - measuredSegment.segment.start
    let direction = vector / measuredSegment.length
    let paintedSegment = SionLineSegment(
      start: measuredSegment.segment.start + (direction * start),
      end: measuredSegment.segment.start + (direction * end)
    )
    let hitRadius = radius + tolerance + approximationTolerance
    if distance(from: point, to: paintedSegment) <= hitRadius {
      return true
    }

    guard stroke.lineCap == .square else { return false }

    let squareCapRadius = hypot(radius, radius) + tolerance + approximationTolerance
    if span.startsWithCap, point.distance(to: paintedSegment.start) <= squareCapRadius {
      return true
    }

    return span.endsWithCap && point.distance(to: paintedSegment.end) <= squareCapRadius
  }

  private func measuredSegments(in subpath: FlattenedSubpath) -> [MeasuredStrokeSegment] {
    var distance = 0.0
    var result: [MeasuredStrokeSegment] = []

    for flattenedSegment in subpath.strokeSegments {
      let length = flattenedSegment.segment.length
      guard length > HitGeometryDefaults.epsilon else { continue }

      result.append(
        MeasuredStrokeSegment(
          segment: flattenedSegment.segment,
          startDistance: distance,
          endDistance: distance + length,
          approximationTolerance: flattenedSegment.approximationTolerance
        )
      )
      distance += length
    }

    return result
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

  private func joinPoints(in run: StrokeRun) -> [StrokeJoin] {
    let points = run.vertices
    guard points.count >= 2 else { return [] }

    if run.closure == .closed {
      return points.indices.map { index in
        let previousIndex =
          index == points.startIndex
          ? points.index(before: points.endIndex) : points.index(before: index)
        let nextIndex =
          points.index(after: index) == points.endIndex
          ? points.startIndex : points.index(after: index)

        return StrokeJoin(
          previous: points[previousIndex],
          vertex: points[index],
          next: points[nextIndex]
        )
      }
    }

    guard points.count >= 3 else { return [] }

    return points.indices.dropFirst().dropLast().map { index in
      StrokeJoin(
        previous: points[points.index(before: index)],
        vertex: points[index],
        next: points[points.index(after: index)]
      )
    }
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
  let segments: [FlattenedStrokeSegment]
  let closure: SubpathClosure

  init(subpath: FlattenedSubpath) {
    points = subpath.points
    segments = subpath.strokeSegments
    closure = subpath.closure
  }

  var vertices: [SionPoint] {
    guard closure == .closed, points.count > 1, points.first == points.last else {
      return points
    }

    return Array(points.dropLast())
  }

}

private struct FlattenedStrokeSegment {
  let segment: SionLineSegment
  let approximationTolerance: Double
}

private struct StrokeJoin {
  let previous: SionPoint
  let vertex: SionPoint
  let next: SionPoint
}

private struct MeasuredStrokeSegment {
  let segment: SionLineSegment
  let startDistance: Double
  let endDistance: Double
  let approximationTolerance: Double

  var length: Double {
    endDistance - startDistance
  }
}

private struct DashPaintSpan {
  let range: ClosedRange<Double>
  let startsWithCap: Bool
  let endsWithCap: Bool
}

private struct DashPattern {
  private let cumulativeEnds: [Double]
  private let period: Double

  init?(_ source: [Double]) {
    var lengths = source.filter { $0.isFinite && $0 > 0 }
    guard !lengths.isEmpty else { return nil }

    if !lengths.count.isMultiple(of: 2) {
      lengths += lengths
    }

    var total = 0.0
    var ends: [Double] = []
    ends.reserveCapacity(lengths.count)
    for length in lengths {
      total += length
      guard total.isFinite else { return nil }

      ends.append(total)
    }
    guard total > 0 else { return nil }

    cumulativeEnds = ends
    period = total
  }

  func isPainted(after distance: Double) -> Bool {
    entryIndex(containing: phase(at: distance)).isMultiple(of: 2)
  }

  func isPainted(before distance: Double) -> Bool {
    let currentPhase = phase(at: distance)
    let precedingPhase = currentPhase > 0 ? currentPhase.nextDown : period.nextDown
    return entryIndex(containing: precedingPhase).isMultiple(of: 2)
  }

  func mayBePainted(after distance: Double, uncertainty: Double) -> Bool {
    guard uncertainty > 0 else { return isPainted(after: distance) }

    return paintMayOccur(near: distance, uncertainty: uncertainty)
  }

  func mayBePainted(before distance: Double, uncertainty: Double) -> Bool {
    guard uncertainty > 0 else { return isPainted(before: distance) }

    return paintMayOccur(near: distance, uncertainty: uncertainty)
  }

  func paintedSpans(
    near distance: Double,
    within segmentRange: ClosedRange<Double>,
    pathLength: Double,
    closure: SubpathClosure,
    joinsAtSeam: Bool,
    uncertainty: Double
  ) -> [DashPaintSpan] {
    candidatePaintRanges(near: distance).compactMap { candidate in
      let pathStart = max(0, candidate.lowerBound - uncertainty)
      let pathEnd = min(pathLength, candidate.upperBound + uncertainty)
      guard pathStart <= pathEnd else { return nil }

      let start = max(segmentRange.lowerBound, pathStart)
      let end = min(segmentRange.upperBound, pathEnd)
      // A shared vertex belongs to the segment that contains painted length.
      guard start < end else { return nil }

      let startsAtPaintBoundary = start == pathStart
      let endsAtPaintBoundary = end == pathEnd
      let pathStartNeedsCap = closure == .open || !joinsAtSeam
      let pathEndNeedsCap = closure == .open || !joinsAtSeam
      let startsWithCap =
        startsAtPaintBoundary
        && (pathStart > 0 || pathStartNeedsCap)
      let endsWithCap =
        endsAtPaintBoundary
        && (pathEnd < pathLength || pathEndNeedsCap)

      return DashPaintSpan(
        range: start...end,
        startsWithCap: startsWithCap,
        endsWithCap: endsWithCap
      )
    }
  }

  private func paintMayOccur(near distance: Double, uncertainty: Double) -> Bool {
    candidatePaintRanges(near: distance).contains { candidate in
      distance >= candidate.lowerBound - uncertainty
        && distance <= candidate.upperBound + uncertainty
    }
  }

  private func candidatePaintRanges(near distance: Double) -> [ClosedRange<Double>] {
    let currentPhase = phase(at: distance)
    let cycleStart = distance - currentPhase
    let index = entryIndex(containing: currentPhase)
    if index.isMultiple(of: 2) {
      return [paintRange(at: index, cycleStart: cycleStart)]
    }

    let previous = paintRange(at: index - 1, cycleStart: cycleStart)
    let nextIndex = index + 1
    if nextIndex < cumulativeEnds.count {
      return [previous, paintRange(at: nextIndex, cycleStart: cycleStart)]
    }

    return [previous, paintRange(at: 0, cycleStart: cycleStart + period)]
  }

  private func paintRange(at index: Int, cycleStart: Double) -> ClosedRange<Double> {
    let start = index == cumulativeEnds.startIndex ? 0 : cumulativeEnds[index - 1]
    return (cycleStart + start)...(cycleStart + cumulativeEnds[index])
  }

  private func entryIndex(containing phase: Double) -> Int {
    var lower = cumulativeEnds.startIndex
    var upper = cumulativeEnds.endIndex
    while lower < upper {
      let midpoint = lower + ((upper - lower) / 2)
      if phase < cumulativeEnds[midpoint] {
        upper = midpoint
        continue
      }

      lower = midpoint + 1
    }

    return min(lower, cumulativeEnds.index(before: cumulativeEnds.endIndex))
  }

  private func phase(at distance: Double) -> Double {
    let remainder = distance.truncatingRemainder(dividingBy: period)
    return remainder >= 0 ? remainder : remainder + period
  }
}

extension ShapeKind {
  fileprivate func contains(
    _ point: SionPoint,
    in frame: SionRect,
    style: ElementStyle,
    tolerance: Double
  ) -> Bool {
    if let coarsePath = coarseFlattened(in: frame) {
      guard coarsePath.contains(point, style: style, tolerance: tolerance) else {
        return false
      }

      // A completed coarse path is already identical to the full traversal.
      guard coarsePath.truncationTolerance > 0 else { return true }
    }

    return flattened(in: frame).contains(point, style: style, tolerance: tolerance)
  }

  fileprivate func hitBounds(in frame: SionRect) -> SionRect? {
    guard case .custom(let path) = self else { return frame }

    return path.hitBounds(in: frame)
  }

  fileprivate func flattened(
    in frame: SionRect,
    maximumBuiltInCurveSubdivisionDepth: Int = HitGeometryDefaults
      .maximumBuiltInCurveSubdivisionDepth
  ) -> FlattenedPath {
    switch self {
    case .rectangle:
      return polygon([
        SionPoint(x: frame.minX, y: frame.minY),
        SionPoint(x: frame.maxX, y: frame.minY),
        SionPoint(x: frame.maxX, y: frame.maxY),
        SionPoint(x: frame.minX, y: frame.maxY),
      ])
    case .roundedRectangle(let radius):
      return roundedRectangle(
        in: frame,
        radius: radius,
        maximumCurveSubdivisionDepth: maximumBuiltInCurveSubdivisionDepth
      )
    case .ellipse:
      return ellipse(
        in: frame,
        maximumCurveSubdivisionDepth: maximumBuiltInCurveSubdivisionDepth
      )
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
      return roundedRectangle(
        in: frame,
        radius: min(frame.width, frame.height) / 2,
        maximumCurveSubdivisionDepth: maximumBuiltInCurveSubdivisionDepth
      )
    case .cylinder:
      return cylinder(
        in: frame,
        maximumCurveSubdivisionDepth: maximumBuiltInCurveSubdivisionDepth
      )
    case .custom(let path):
      return path.flattened(in: frame)
    }
  }

  private func coarseFlattened(in frame: SionRect) -> FlattenedPath? {
    switch self {
    case .roundedRectangle, .ellipse, .capsule, .cylinder:
      return flattened(
        in: frame,
        maximumBuiltInCurveSubdivisionDepth: HitGeometryDefaults
          .maximumBuiltInBroadPhaseSubdivisionDepth
      )
    case .rectangle, .diamond, .triangle, .hexagon, .custom:
      return nil
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

  private func roundedRectangle(
    in frame: SionRect,
    radius: Double,
    maximumCurveSubdivisionDepth: Int
  ) -> FlattenedPath {
    let finiteRadius = radius.isFinite ? radius : 0
    let clampedRadius = min(max(0, finiteRadius), min(frame.width, frame.height) / 2)
    guard clampedRadius > 0 else {
      return ShapeKind.rectangle.flattened(in: frame)
    }

    let control = clampedRadius * HitGeometryDefaults.arcControlFactor
    var builder = FlattenedPathBuilder(
      maximumCurveSubdivisionDepth: maximumCurveSubdivisionDepth
    )
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

  private func ellipse(
    in frame: SionRect,
    maximumCurveSubdivisionDepth: Int
  ) -> FlattenedPath {
    let horizontalRadius = frame.width / 2
    let verticalRadius = frame.height / 2
    let horizontalControl = horizontalRadius * HitGeometryDefaults.arcControlFactor
    let verticalControl = verticalRadius * HitGeometryDefaults.arcControlFactor
    var builder = FlattenedPathBuilder(
      maximumCurveSubdivisionDepth: maximumCurveSubdivisionDepth
    )
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

  private func cylinder(
    in frame: SionRect,
    maximumCurveSubdivisionDepth: Int
  ) -> FlattenedPath {
    let arcHeight = min(
      frame.height * ShapeGeometryDefaults.cylinderArcFraction,
      frame.height / 2
    )
    let horizontalControl = (frame.width / 2) * HitGeometryDefaults.arcControlFactor
    let verticalControl = arcHeight * HitGeometryDefaults.arcControlFactor
    var builder = FlattenedPathBuilder(
      maximumCurveSubdivisionDepth: maximumCurveSubdivisionDepth
    )
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
    let curveCount = commands.reduce(into: 0) { count, command in
      switch command {
      case .quadratic, .cubic:
        count += 1
      case .move, .line, .close:
        break
      }
    }
    var builder = FlattenedPathBuilder(
      maximumCurveSubdivisionDepth: HitGeometryDefaults.subdivisionDepth(
        curveCount: curveCount
      )
    )

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
    let capExpansion = lineCap == .square ? hypot(radius, radius) : radius
    let joinExpansion =
      lineJoin == .miter
      ? radius * HitGeometryDefaults.miterLimit
      : radius

    return max(capExpansion, joinExpansion) + tolerance
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
  // Share a fixed traversal budget across every curve in one valid path.
  static let flattenedSegmentsPerPathCommand = 16
  static let maximumFlattenedCurveSegmentCount =
    SceneLimits.maximumPathCommandCount * flattenedSegmentsPerPathCommand
  // A 32-segment conservative preflight rejects distant curved-shape misses.
  static let maximumBuiltInBroadPhaseSubdivisionDepth = 3
  // Four-curve built-ins use at most 1,024 curve segments.
  static let maximumBuiltInCurveSubdivisionDepth = 8
  static let maximumCurveSubdivisionDepth = 12
  // StrokeStyle has no override, so mirror NSBezierPath's default.
  static let miterLimit = 10.0

  static func subdivisionDepth(curveCount: Int) -> Int {
    guard curveCount > 0 else { return maximumCurveSubdivisionDepth }

    let segmentsPerCurve = max(1, maximumFlattenedCurveSegmentCount / curveCount)
    var depth = 0
    var segmentCount = 1
    while depth < maximumCurveSubdivisionDepth,
      segmentCount <= segmentsPerCurve / 2
    {
      depth += 1
      segmentCount *= 2
    }

    return depth
  }
}
