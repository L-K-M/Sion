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
      let hitExpansion = element.style.hitExpansion(tolerance: hitTolerance)
      let broadPhaseHit =
        element.style.hasVisibleArtwork
        && content.kind.passesNormalizedFrameBroadPhase(
          localPoint,
          in: frame,
          expansion: hitExpansion
        )
        && content.kind.passesHitBoundsBroadPhase(
          localPoint,
          in: frame,
          style: element.style,
          expansion: hitExpansion
        )
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
      guard element.style.hasVisibleArtwork else { return false }

      let hitExpansion = element.style.hitExpansion(tolerance: hitTolerance)
      guard
        content.path.passesNormalizedFrameBroadPhase(
          localPoint,
          in: frame,
          expansion: hitExpansion
        ),
        content.path.passesHitBoundsBroadPhase(
          localPoint,
          in: frame,
          style: element.style,
          expansion: hitExpansion
        )
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

  var hasTruncatedSubpath: Bool {
    subpaths.contains { $0.truncationTolerance > 0 }
  }

  private var maximumApproximationTolerance: Double {
    subpaths.reduce(0) { maximum, subpath in
      max(maximum, subpath.approximationTolerance)
    }
  }

  func contains(
    _ point: SionPoint,
    style: ElementStyle,
    tolerance: Double
  ) -> Bool {
    guard let bounds else { return false }

    let fillTolerance = tolerance + maximumApproximationTolerance
    let strokeTolerance = tolerance + maximumApproximationTolerance
    let strokeRadius = style.visibleStroke?.hitExpansion(tolerance: strokeTolerance) ?? 0
    let fillRadius = style.hasVisibleFill ? fillTolerance : 0
    guard bounds.expanded(by: max(fillRadius, strokeRadius)).contains(point) else {
      return false
    }

    if style.hasVisibleFill {
      if containsFill(point) {
        return true
      }

      if subpaths.contains(where: { subpath in
        let boundaryTolerance = tolerance + subpath.approximationTolerance
        guard boundaryTolerance > 0 else { return false }

        return subpath.fillSegments.contains { segment in
          distance(from: point, to: segment) <= boundaryTolerance
        }
      }) {
        return true
      }
    }

    guard let stroke = style.visibleStroke else { return false }

    return StrokeHitGeometry(
      stroke: stroke,
      tolerance: tolerance
    ).contains(point, in: subpaths)
  }

  private var bounds: SionRect? {
    var result: SionRect?
    for subpath in subpaths {
      for point in subpath.points {
        let pointBounds = SionRect(x: point.x, y: point.y, width: 0, height: 0)
        result = result?.union(pointBounds) ?? pointBounds
      }
    }

    return result
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
  let explicitStrokeSegments: [FlattenedStrokeSegment]
  let closure: SubpathClosure
  let approximationTolerance: Double
  let truncationTolerance: Double
  let dashPhaseUncertainty: Double

  var strokeSegments: [FlattenedStrokeSegment] {
    var result = explicitStrokeSegments
    if closure == .closed,
      points.first != points.last,
      let first = points.first,
      let last = points.last
    {
      let direction = (first - last).normalized
      result.append(
        FlattenedStrokeSegment(
          segment: SionLineSegment(start: last, end: first),
          tangentDirectionDelta: 0,
          startTangentDirection: direction,
          endTangentDirection: direction
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
  private var activeStrokeSegments: [FlattenedStrokeSegment] = []
  private var currentPoint: SionPoint?
  private var activeApproximationTolerance = 0.0
  private var activeTruncationTolerance = 0.0
  private var activeDashPhaseUncertainty = 0.0
  private let maximumCurveSubdivisionDepth: Int

  init(
    maximumCurveSubdivisionDepth: Int = HitGeometryDefaults.maximumCurveSubdivisionDepth
  ) {
    self.maximumCurveSubdivisionDepth = maximumCurveSubdivisionDepth
  }

  mutating func move(to point: SionPoint) {
    finishActivePath(closure: .open)
    activePoints = [point]
    activeStrokeSegments = []
    currentPoint = point
  }

  mutating func line(to point: SionPoint) {
    guard let start = startActivePathIfNeeded() else {
      move(to: point)
      return
    }

    let direction = (point - start).normalized
    activeStrokeSegments.append(
      FlattenedStrokeSegment(
        segment: SionLineSegment(start: start, end: point),
        tangentDirectionDelta: 0,
        startTangentDirection: direction,
        endTangentDirection: direction
      )
    )
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

    return FlattenedPath(
      subpaths: subpaths,
      fillRule: fillRule
    )
  }

  private mutating func finishActivePath(closure: SubpathClosure) {
    guard !activePoints.isEmpty else { return }

    subpaths.append(
      FlattenedSubpath(
        points: activePoints,
        explicitStrokeSegments: activeStrokeSegments,
        closure: closure,
        approximationTolerance: activeApproximationTolerance,
        truncationTolerance: activeTruncationTolerance,
        dashPhaseUncertainty: activeDashPhaseUncertainty
      )
    )
    activePoints = []
    activeStrokeSegments = []
    activeApproximationTolerance = 0
    activeTruncationTolerance = 0
    activeDashPhaseUncertainty = 0
  }

  private mutating func startActivePathIfNeeded() -> SionPoint? {
    if let activePoint = activePoints.last {
      return activePoint
    }

    guard let currentPoint else { return nil }

    activePoints = [currentPoint]
    activeStrokeSegments = []
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
    // One split preserves an implicitly closed shallow curve's fill area.
    let needsFillContour = depth == 0 && flatness > 0
    guard flatness > HitGeometryDefaults.curveFlatness || needsFillContour else {
      appendQuadraticLeaf(
        start: start,
        control: control,
        end: end,
        approximationTolerance: flatness
      )
      return
    }
    guard depth < maximumCurveSubdivisionDepth else {
      activeTruncationTolerance = max(activeTruncationTolerance, flatness)
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
    // One split preserves an implicitly closed shallow curve's fill area.
    let needsFillContour = depth == 0 && flatness > 0
    guard flatness > HitGeometryDefaults.curveFlatness || needsFillContour else {
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
      activeTruncationTolerance = max(activeTruncationTolerance, flatness)
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
    activeApproximationTolerance = max(
      activeApproximationTolerance,
      approximationTolerance
    )
    recordDashPhaseUncertainty(
      controlPolygonLength: start.distance(to: control) + control.distance(to: end),
      chordLength: start.distance(to: end)
    )
    activeStrokeSegments.append(
      FlattenedStrokeSegment(
        segment: SionLineSegment(start: start, end: end),
        tangentDirectionDelta: maximumTangentDirectionDelta(
          chord: end - start,
          firstControlEdge: control - start,
          secondControlEdge: end - control
        ),
        startTangentDirection: firstNonzeroDirection(
          control - start,
          end - start
        ),
        endTangentDirection: firstNonzeroDirection(
          end - control,
          end - start
        )
      )
    )
    activePoints.append(end)
  }

  private mutating func appendCubicLeaf(
    start: SionPoint,
    control1: SionPoint,
    control2: SionPoint,
    end: SionPoint,
    approximationTolerance: Double
  ) {
    activeApproximationTolerance = max(
      activeApproximationTolerance,
      approximationTolerance
    )
    recordDashPhaseUncertainty(
      controlPolygonLength: start.distance(to: control1)
        + control1.distance(to: control2)
        + control2.distance(to: end),
      chordLength: start.distance(to: end)
    )
    activeStrokeSegments.append(
      FlattenedStrokeSegment(
        segment: SionLineSegment(start: start, end: end),
        tangentDirectionDelta: maximumTangentDirectionDelta(
          chord: end - start,
          firstControlEdge: control1 - start,
          secondControlEdge: control2 - control1,
          thirdControlEdge: end - control2
        ),
        startTangentDirection: firstNonzeroDirection(
          control1 - start,
          control2 - start,
          end - start
        ),
        endTangentDirection: firstNonzeroDirection(
          end - control2,
          end - control1,
          end - start
        )
      )
    )
    activePoints.append(end)
  }

  private func firstNonzeroDirection(
    _ first: SionVector,
    _ second: SionVector,
    _ third: SionVector = .zero
  ) -> SionVector {
    if first.lengthSquared > 0 {
      return first.normalized
    }
    if second.lengthSquared > 0 {
      return second.normalized
    }

    return third.normalized
  }

  private func maximumTangentDirectionDelta(
    chord: SionVector,
    firstControlEdge: SionVector,
    secondControlEdge: SionVector,
    thirdControlEdge: SionVector = .zero
  ) -> Double {
    let chordDirection = chord.normalized
    guard chordDirection.lengthSquared > 0 else {
      let hasDirection =
        firstControlEdge.lengthSquared > 0
        || secondControlEdge.lengthSquared > 0
        || thirdControlEdge.lengthSquared > 0
      return hasDirection ? 2 : 0
    }

    return max(
      tangentDirectionDelta(firstControlEdge, from: chordDirection),
      tangentDirectionDelta(secondControlEdge, from: chordDirection),
      tangentDirectionDelta(thirdControlEdge, from: chordDirection)
    )
  }

  private func tangentDirectionDelta(
    _ edge: SionVector,
    from chordDirection: SionVector
  ) -> Double {
    let direction = edge.normalized
    guard direction.lengthSquared > 0 else { return 0 }

    return hypot(
      direction.dx - chordDirection.dx,
      direction.dy - chordDirection.dy
    )
  }

  private mutating func recordDashPhaseUncertainty(
    controlPolygonLength: Double,
    chordLength: Double
  ) {
    // A Bezier's control polygon bounds how far flattened dash phase can lag.
    activeDashPhaseUncertainty += max(0, controlPolygonLength - chordLength)
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

private enum DashSeamState {
  case disconnected
  case possiblyConnected
  case connected
}

private struct StrokeHitGeometry {
  let stroke: StrokeStyle
  let tolerance: Double

  private var radius: Double {
    stroke.width / 2
  }

  func contains(_ point: SionPoint, in subpaths: [FlattenedSubpath]) -> Bool {
    let dashPattern = DashPattern(stroke.dashPattern)

    return subpaths.contains { subpath in
      let geometry = StrokeHitGeometry(
        stroke: stroke,
        tolerance: tolerance + subpath.approximationTolerance
      )

      guard let dashPattern else {
        return geometry.contains(point, in: StrokeRun(subpath: subpath))
      }

      return geometry.contains(point, in: subpath, dashPattern: dashPattern)
    }
  }

  private func contains(
    _ point: SionPoint,
    in subpath: FlattenedSubpath,
    dashPattern: DashPattern
  ) -> Bool {
    guard let segments = measuredSegments(in: subpath) else {
      return contains(point, in: StrokeRun(subpath: subpath))
    }
    guard let pathLength = segments.last?.endDistance else {
      return degenerateCapContains(point, in: StrokeRun(subpath: subpath)) ?? false
    }
    guard dashPattern.preservesPhasePrecision(upTo: pathLength) else {
      return contains(point, in: StrokeRun(subpath: subpath))
    }

    let seamState = dashSeamState(
      in: subpath,
      pathLength: pathLength,
      dashPattern: dashPattern
    )

    for segment in segments {
      var phaseUncertainty = subpath.dashPhaseUncertainty
      if subpath.truncationTolerance > 0 {
        // Truncated tangents can shift a query's projected dash position.
        let referenceRadius =
          stroke.lineCap == .square
          ? hypot(radius, radius) : radius
        phaseUncertainty += max(0, tolerance - subpath.approximationTolerance)
        phaseUncertainty += curveTolerance(
          tangentDirectionDelta: segment.tangentDirectionDelta,
          referenceRadius: referenceRadius
        )
      }

      if dashedBodyContains(
        point,
        measuredSegment: segment,
        pathLength: pathLength,
        seamState: seamState,
        dashPattern: dashPattern,
        phaseUncertainty: phaseUncertainty
      ) {
        return true
      }
    }

    for index in segments.indices.dropFirst() {
      let outgoing = segments[index]
      guard
        dashPattern.mayPaintContinuously(
          across: outgoing.startDistance,
          forwardUncertainty: subpath.dashPhaseUncertainty
        )
      else {
        continue
      }

      let incoming = segments[segments.index(before: index)]
      if joinContains(
        point,
        vertex: outgoing.segment.start,
        incomingDirection: incoming.endTangentDirection,
        outgoingDirection: outgoing.startTangentDirection
      ) {
        return true
      }
    }

    guard seamState != .disconnected,
      let incoming = segments.last,
      let outgoing = segments.first
    else {
      return false
    }

    return joinContains(
      point,
      vertex: outgoing.segment.start,
      incomingDirection: incoming.endTangentDirection,
      outgoingDirection: outgoing.startTangentDirection
    )
  }

  private func dashSeamState(
    in subpath: FlattenedSubpath,
    pathLength: Double,
    dashPattern: DashPattern
  ) -> DashSeamState {
    guard subpath.closure == .closed else { return .disconnected }

    return dashPattern.seamState(
      pathLength: pathLength,
      forwardUncertainty: subpath.dashPhaseUncertainty
    )
  }

  private func contains(_ point: SionPoint, in run: StrokeRun) -> Bool {
    if let containsPoint = degenerateCapContains(point, in: run) {
      return containsPoint
    }

    let segments = run.segments
    for (index, flattenedSegment) in segments.enumerated() {
      let startsRun = run.closure == .open && index == segments.startIndex
      let endsRun = run.closure == .open && index == segments.index(before: segments.endIndex)
      let startExtension = startsRun && stroke.lineCap == .square ? radius : 0
      let endExtension = endsRun && stroke.lineCap == .square ? radius : 0
      let referenceRadius =
        stroke.lineCap == .square && (startsRun || endsRun)
        ? hypot(radius, radius) : radius
      let curveTolerance = curveTolerance(
        tangentDirectionDelta: flattenedSegment.tangentDirectionDelta,
        referenceRadius: referenceRadius
      )
      if bodyContains(
        point,
        segment: flattenedSegment.segment,
        startExtension: startExtension,
        endExtension: endExtension,
        additionalTolerance: curveTolerance
      ) {
        return true
      }
    }

    if run.closure == .open, stroke.lineCap == .round,
      let start = run.vertices.first,
      let end = run.vertices.last,
      min(point.distance(to: start), point.distance(to: end)) <= radius + tolerance
    {
      return true
    }

    return joinPoints(in: run).contains { join in
      joinContains(
        point,
        vertex: join.vertex,
        incomingDirection: join.incomingDirection,
        outgoingDirection: join.outgoingDirection
      )
    }
  }

  private func degenerateCapContains(
    _ point: SionPoint,
    in run: StrokeRun
  ) -> Bool? {
    guard run.segments.isEmpty else { return nil }

    // A moveto paints nothing; an explicit zero-length subpath paints its cap.
    guard run.hasStrokeCommand, let origin = run.points.first else { return false }

    switch stroke.lineCap {
    case .butt:
      return false
    case .round:
      return point.distance(to: origin) <= radius + tolerance
    case .square:
      let square = [
        SionPoint(x: origin.x - radius, y: origin.y - radius),
        SionPoint(x: origin.x + radius, y: origin.y - radius),
        SionPoint(x: origin.x + radius, y: origin.y + radius),
        SionPoint(x: origin.x - radius, y: origin.y + radius),
      ]
      return polygonContains(point, polygon: square, tolerance: tolerance)
    }
  }

  private func curveTolerance(
    tangentDirectionDelta: Double,
    referenceRadius: Double
  ) -> Double {
    // Direction error moves a stroke edge by at most radius times unit-vector delta.
    referenceRadius * tangentDirectionDelta
  }

  private func bodyContains(
    _ point: SionPoint,
    segment: SionLineSegment,
    startExtension: Double,
    endExtension: Double,
    paintedStart: Double = 0,
    paintedEnd: Double? = nil,
    additionalTolerance: Double = 0
  ) -> Bool {
    let vector = segment.end - segment.start
    let length = vector.length
    guard length > 0 else { return false }

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

    return hypot(outsideAlong, outsidePerpendicular) <= tolerance + additionalTolerance
      + HitGeometryDefaults.epsilon
  }

  private func dashedBodyContains(
    _ point: SionPoint,
    measuredSegment: MeasuredStrokeSegment,
    pathLength: Double,
    seamState: DashSeamState,
    dashPattern: DashPattern,
    phaseUncertainty: Double
  ) -> Bool {
    let segment = measuredSegment.segment
    let vector = segment.end - segment.start
    let length = measuredSegment.length
    let maximumReferenceRadius =
      stroke.lineCap == .square
      ? hypot(radius, radius) : radius
    let maximumCurveTolerance = curveTolerance(
      tangentDirectionDelta: measuredSegment.tangentDirectionDelta,
      referenceRadius: maximumReferenceRadius
    )
    // Reject remote chords before resolving their dash phase and cap spans.
    guard
      distance(from: point, to: segment)
        <= maximumReferenceRadius + tolerance + maximumCurveTolerance
        + HitGeometryDefaults.epsilon
    else {
      return false
    }

    let direction = vector / length
    let projectedDistance = min(length, max(0, (point - segment.start).dot(direction)))
    let pathDistance = measuredSegment.startDistance + projectedDistance
    let spans = dashPattern.paintedSpans(
      near: pathDistance,
      within: measuredSegment.startDistance...measuredSegment.endDistance,
      pathLength: pathLength,
      seamState: seamState,
      uncertainty: phaseUncertainty
    )

    for span in spans {
      if span.isZeroLengthDash, stroke.lineCap == .butt {
        continue
      }

      let start = span.range.lowerBound - measuredSegment.startDistance
      let end = span.range.upperBound - measuredSegment.startDistance
      let startExtension = span.startsWithCap && stroke.lineCap == .square ? radius : 0
      let endExtension = span.endsWithCap && stroke.lineCap == .square ? radius : 0
      let referenceRadius =
        stroke.lineCap == .square && (span.startsWithCap || span.endsWithCap)
        ? hypot(radius, radius) : radius
      let curveTolerance = curveTolerance(
        tangentDirectionDelta: measuredSegment.tangentDirectionDelta,
        referenceRadius: referenceRadius
      )
      if bodyContains(
        point,
        segment: segment,
        startExtension: startExtension,
        endExtension: endExtension,
        paintedStart: start,
        paintedEnd: end,
        additionalTolerance: curveTolerance
      ) {
        return true
      }

      guard stroke.lineCap == .round else { continue }

      if span.startsWithCap,
        point.distance(to: segment.start + (direction * start))
          <= radius + tolerance + curveTolerance
      {
        return true
      }
      if span.endsWithCap,
        point.distance(to: segment.start + (direction * end))
          <= radius + tolerance + curveTolerance
      {
        return true
      }
    }

    return false
  }

  private func measuredSegments(in subpath: FlattenedSubpath) -> [MeasuredStrokeSegment]? {
    var distance = 0.0
    var result: [MeasuredStrokeSegment] = []

    for flattenedSegment in subpath.strokeSegments {
      let length = flattenedSegment.segment.length
      guard length > 0 else { continue }
      let endDistance = distance + length
      // Collapsed cumulative length makes later dash phase unknowable.
      guard endDistance.isFinite, endDistance > distance else { return nil }

      result.append(
        MeasuredStrokeSegment(
          segment: flattenedSegment.segment,
          startDistance: distance,
          endDistance: endDistance,
          tangentDirectionDelta: flattenedSegment.tangentDirectionDelta,
          startTangentDirection: flattenedSegment.startTangentDirection,
          endTangentDirection: flattenedSegment.endTangentDirection
        )
      )
      distance = endDistance
    }

    return result
  }

  private func joinContains(
    _ point: SionPoint,
    vertex: SionPoint,
    incomingDirection: SionVector,
    outgoingDirection: SionVector
  ) -> Bool {
    let incoming = incomingDirection.normalized
    let outgoing = outgoingDirection.normalized
    guard incoming.lengthSquared > 0, outgoing.lengthSquared > 0 else { return false }

    let turn = cross(incoming, outgoing)
    guard turn != 0 else {
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
      vertex.distance(to: intersection) <= StrokeGeometryDefaults.miterLimit * radius
    {
      polygon = [vertex, incomingOuter, intersection, outgoingOuter]
    }

    return polygonContains(point, polygon: polygon, tolerance: tolerance)
  }

  private func joinPoints(in run: StrokeRun) -> [StrokeJoin] {
    let segments = run.segments
    guard segments.count >= 2 else { return [] }

    if run.closure == .closed {
      return segments.indices.map { index in
        let previousIndex =
          index == segments.startIndex
          ? segments.index(before: segments.endIndex) : segments.index(before: index)
        let incoming = segments[previousIndex]
        let outgoing = segments[index]

        return StrokeJoin(
          vertex: outgoing.segment.start,
          incomingDirection: incoming.endTangentDirection,
          outgoingDirection: outgoing.startTangentDirection
        )
      }
    }

    return segments.indices.dropFirst().map { index in
      let incoming = segments[segments.index(before: index)]
      let outgoing = segments[index]

      return StrokeJoin(
        vertex: outgoing.segment.start,
        incomingDirection: incoming.endTangentDirection,
        outgoingDirection: outgoing.startTangentDirection
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
    guard denominator != 0 else { return nil }

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
    // Zero-length segments do not replace neighboring cap or join tangents.
    segments = subpath.strokeSegments.filter {
      $0.segment.length > 0
    }
    closure = subpath.closure
  }

  var vertices: [SionPoint] {
    guard closure == .closed, points.count > 1, points.first == points.last else {
      return points
    }

    return Array(points.dropLast())
  }

  var hasStrokeCommand: Bool {
    points.count > 1 || closure == .closed
  }

}

private struct FlattenedStrokeSegment {
  let segment: SionLineSegment
  let tangentDirectionDelta: Double
  let startTangentDirection: SionVector
  let endTangentDirection: SionVector
}

private struct StrokeJoin {
  let vertex: SionPoint
  let incomingDirection: SionVector
  let outgoingDirection: SionVector
}

private struct MeasuredStrokeSegment {
  let segment: SionLineSegment
  let startDistance: Double
  let endDistance: Double
  let tangentDirectionDelta: Double
  let startTangentDirection: SionVector
  let endTangentDirection: SionVector

  var length: Double {
    endDistance - startDistance
  }
}

private struct DashPaintSpan {
  let range: ClosedRange<Double>
  let startsWithCap: Bool
  let endsWithCap: Bool
  let isZeroLengthDash: Bool
}

private struct DashPattern {
  private let cumulativeEnds: [Double]
  private let minimumPositiveLength: Double
  private let positivePaintRanges: [ClosedRange<Double>]
  private let period: Double

  init?(_ source: [Double]) {
    // Complex patterns fall back to a solid conservative hit without scanning.
    guard source.count <= HitGeometryDefaults.maximumInteractiveDashPatternCount else {
      return nil
    }

    guard source.allSatisfy({ $0.isFinite && $0 >= 0 }),
      source.contains(where: { $0 > 0 })
    else {
      return nil
    }

    // Zero dashes preserve pattern parity and can still paint caps.
    var lengths = source

    if !lengths.count.isMultiple(of: 2) {
      lengths += lengths
    }

    var total = 0.0
    var minimumPositiveLength = Double.infinity
    var ends: [Double] = []
    var paintRanges: [ClosedRange<Double>] = []
    ends.reserveCapacity(lengths.count)
    paintRanges.reserveCapacity(lengths.count / 2)
    for (index, length) in lengths.enumerated() {
      let start = total
      total += length
      guard total.isFinite else { return nil }
      if length > 0 {
        // Collapsed boundaries cannot preserve renderer dash phase.
        guard total > start else { return nil }

        minimumPositiveLength = min(minimumPositiveLength, length)
      }

      ends.append(total)
      if index.isMultiple(of: 2), length > 0 {
        paintRanges.append(start...total)
      }
    }
    guard total > 0 else { return nil }

    cumulativeEnds = ends
    self.minimumPositiveLength = minimumPositiveLength
    positivePaintRanges = paintRanges
    period = total
  }

  func preservesPhasePrecision(upTo distance: Double) -> Bool {
    let scale = max(period, max(0, distance))
    return scale + minimumPositiveLength > scale
  }

  func mayPaintContinuously(
    across distance: Double,
    forwardUncertainty: Double
  ) -> Bool {
    guard let range = nextPositivePaintRange(atOrAfter: distance) else { return false }

    let maximumDistance = distance + max(0, forwardUncertainty)
    return range.lowerBound < maximumDistance && range.upperBound > distance
  }

  func seamState(
    pathLength: Double,
    forwardUncertainty: Double
  ) -> DashSeamState {
    // Only the initial dash can remain one run across a closed seam.
    guard let initialDash = positivePaintRanges.first,
      initialDash.lowerBound == 0,
      initialDash.upperBound >= pathLength
    else {
      return .disconnected
    }

    let remainingLength = initialDash.upperBound - pathLength
    return forwardUncertainty <= remainingLength ? .connected : .possiblyConnected
  }

  func paintedSpans(
    near distance: Double,
    within segmentRange: ClosedRange<Double>,
    pathLength: Double,
    seamState: DashSeamState,
    uncertainty: Double
  ) -> [DashPaintSpan] {
    candidatePaintRanges(near: distance).compactMap { candidate in
      let isZeroLengthDash = candidate.lowerBound == candidate.upperBound
      let pathStart = max(0, candidate.lowerBound - uncertainty)
      let pathEnd = min(pathLength, candidate.upperBound + uncertainty)
      guard pathStart <= pathEnd else { return nil }

      let start = max(segmentRange.lowerBound, pathStart)
      let end = min(segmentRange.upperBound, pathEnd)
      // A shared vertex belongs to the segment that contains painted length.
      guard start < end || isZeroLengthDash && start == end else { return nil }

      let startsAtPaintBoundary = start == pathStart
      let endsAtPaintBoundary = end == pathEnd
      // An uncertain seam needs both possible caps and the possible join.
      let pathEndsNeedCaps = seamState != .connected
      let startsWithCap =
        startsAtPaintBoundary
        && (pathStart > 0 || pathEndsNeedCaps)
      let endsWithCap =
        endsAtPaintBoundary
        && (pathEnd < pathLength || pathEndsNeedCaps)

      return DashPaintSpan(
        range: start...end,
        startsWithCap: startsWithCap,
        endsWithCap: endsWithCap,
        isZeroLengthDash: isZeroLengthDash
      )
    }
  }

  private func candidatePaintRanges(near distance: Double) -> [ClosedRange<Double>] {
    let currentPhase = phase(at: distance)
    let cycleStart = distance - currentPhase
    let index = entryIndex(containing: currentPhase)
    if index.isMultiple(of: 2) {
      let current = paintRange(at: index, cycleStart: cycleStart)
      let entryStart = index == cumulativeEnds.startIndex ? 0 : cumulativeEnds[index - 1]
      guard
        currentPhase == entryStart,
        let previous = positivePaintRangeEnding(
          at: currentPhase,
          cycleStart: cycleStart
        )
      else {
        return [current]
      }

      // A zero gap leaves two distinct capped dashes at the same point.
      return [previous, current]
    }

    let previous = paintRange(at: index - 1, cycleStart: cycleStart)
    let nextIndex = index + 1
    if nextIndex < cumulativeEnds.count {
      return [previous, paintRange(at: nextIndex, cycleStart: cycleStart)]
    }

    return [previous, paintRange(at: 0, cycleStart: cycleStart + period)]
  }

  private func nextPositivePaintRange(
    atOrAfter distance: Double
  ) -> ClosedRange<Double>? {
    guard let first = positivePaintRanges.first else { return nil }

    let currentPhase = phase(at: distance)
    let cycleStart = distance - currentPhase
    var lower = positivePaintRanges.startIndex
    var upper = positivePaintRanges.endIndex
    while lower < upper {
      let midpoint = lower + ((upper - lower) / 2)
      if positivePaintRanges[midpoint].upperBound <= currentPhase {
        lower = midpoint + 1
        continue
      }

      upper = midpoint
    }

    guard lower < positivePaintRanges.endIndex else {
      return (cycleStart + period + first.lowerBound)...(cycleStart + period + first.upperBound)
    }

    let range = positivePaintRanges[lower]
    return (cycleStart + range.lowerBound)...(cycleStart + range.upperBound)
  }

  private func positivePaintRangeEnding(
    at phase: Double,
    cycleStart: Double
  ) -> ClosedRange<Double>? {
    guard !positivePaintRanges.isEmpty else { return nil }

    if phase == 0 {
      guard let last = positivePaintRanges.last, last.upperBound == period else {
        return nil
      }

      return (cycleStart - period + last.lowerBound)...cycleStart
    }

    var lower = positivePaintRanges.startIndex
    var upper = positivePaintRanges.endIndex
    while lower < upper {
      let midpoint = lower + ((upper - lower) / 2)
      if positivePaintRanges[midpoint].upperBound < phase {
        lower = midpoint + 1
        continue
      }

      upper = midpoint
    }

    guard lower < positivePaintRanges.endIndex else { return nil }

    let range = positivePaintRanges[lower]
    guard range.upperBound == phase else { return nil }

    return (cycleStart + range.lowerBound)...(cycleStart + range.upperBound)
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
  fileprivate func passesNormalizedFrameBroadPhase(
    _ point: SionPoint,
    in frame: SionRect,
    expansion: Double
  ) -> Bool {
    guard case .custom(let path) = self else { return true }

    return path.passesNormalizedFrameBroadPhase(point, in: frame, expansion: expansion)
  }

  fileprivate func contains(
    _ point: SionPoint,
    in frame: SionRect,
    style: ElementStyle,
    tolerance: Double
  ) -> Bool {
    guard
      passesAnalyticBroadPhase(
        point,
        in: frame,
        style: style,
        tolerance: tolerance
      )
    else {
      return false
    }

    if let coarsePath = coarseFlattened(in: frame) {
      guard coarsePath.contains(point, style: style, tolerance: tolerance) else {
        return false
      }

      // A completed coarse path is already identical to the full traversal.
      guard coarsePath.hasTruncatedSubpath else { return true }
    }

    return flattened(in: frame).contains(point, style: style, tolerance: tolerance)
  }

  private func passesAnalyticBroadPhase(
    _ point: SionPoint,
    in frame: SionRect,
    style: ElementStyle,
    tolerance: Double
  ) -> Bool {
    let expansion = style.hitExpansion(tolerance: tolerance)

    switch self {
    case .roundedRectangle(let radius):
      let finiteRadius = radius.isFinite ? radius : 0
      let clampedRadius = min(max(0, finiteRadius), min(frame.width, frame.height) / 2)
      return passesCurvedFrameBroadPhase(
        point,
        in: frame,
        horizontalRadius: clampedRadius,
        verticalRadius: clampedRadius,
        expansion: expansion
      )
    case .ellipse:
      return passesCurvedFrameBroadPhase(
        point,
        in: frame,
        horizontalRadius: frame.width / 2,
        verticalRadius: frame.height / 2,
        expansion: expansion
      )
    case .capsule:
      let radius = min(frame.width, frame.height) / 2
      return passesCurvedFrameBroadPhase(
        point,
        in: frame,
        horizontalRadius: radius,
        verticalRadius: radius,
        expansion: expansion
      )
    case .cylinder:
      let arcHeight = min(
        frame.height * ShapeGeometryDefaults.cylinderArcFraction,
        frame.height / 2
      )
      return passesCurvedFrameBroadPhase(
        point,
        in: frame,
        horizontalRadius: frame.width / 2,
        verticalRadius: arcHeight,
        expansion: expansion
      )
    case .rectangle, .diamond, .triangle, .hexagon, .custom:
      return true
    }
  }

  private func passesCurvedFrameBroadPhase(
    _ point: SionPoint,
    in frame: SionRect,
    horizontalRadius: Double,
    verticalRadius: Double,
    expansion: Double
  ) -> Bool {
    let minimumRadius = min(horizontalRadius, verticalRadius)
    guard minimumRadius > HitGeometryDefaults.epsilon else { return true }

    // Affine-normalize a conservative envelope before building any curves.
    let horizontalInset = max(0, (frame.width / 2) - horizontalRadius)
    let verticalInset = max(0, (frame.height / 2) - verticalRadius)
    let normalizedX =
      max(0, abs(point.x - frame.center.x) - horizontalInset) / horizontalRadius
    let normalizedY =
      max(0, abs(point.y - frame.center.y) - verticalInset) / verticalRadius
    let envelopeScale =
      HitGeometryDefaults.maximumCubicArcEnvelopeScale
      + (expansion / minimumRadius)

    return hypot(normalizedX, normalizedY) <= envelopeScale
  }

  fileprivate func passesHitBoundsBroadPhase(
    _ point: SionPoint,
    in frame: SionRect,
    style: ElementStyle,
    expansion: Double
  ) -> Bool {
    guard case .custom(let path) = self else {
      return frame.expanded(by: expansion).contains(point)
    }

    return path.passesHitBoundsBroadPhase(
      point,
      in: frame,
      style: style,
      expansion: expansion
    )
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
  fileprivate func passesNormalizedFrameBroadPhase(
    _ point: SionPoint,
    in frame: SionRect,
    expansion: Double
  ) -> Bool {
    guard coordinateSpace == .normalized else { return true }

    // Valid normalized control hulls cannot paint beyond the expanded frame.
    return frame.expanded(by: expansion).contains(point)
  }

  fileprivate func passesHitBoundsBroadPhase(
    _ point: SionPoint,
    in frame: SionRect,
    style: ElementStyle,
    expansion: Double
  ) -> Bool {
    // Separate subpaths avoid flattening the empty space between painted islands.
    let hasVisibleFill = style.hasVisibleFill
    let visibleStroke = style.visibleStroke
    var activeBounds: SionRect?
    var activeStart: SionPoint?
    var currentPoint: SionPoint?
    var activeDrawCommandCount = 0
    var activeHasCurve = false
    var activeHasStrokeCommand = false
    var activeHasNonzeroStrokeSegment = false

    func resolve(_ point: SionPoint) -> SionPoint {
      switch coordinateSpace {
      case .normalized:
        return frame.point(atNormalized: point)
      case .localPoints:
        return SionPoint(x: frame.minX + point.x, y: frame.minY + point.y)
      }
    }

    func includeInActiveBounds(_ point: SionPoint) {
      let pointBounds = SionRect(x: point.x, y: point.y, width: 0, height: 0)
      activeBounds = activeBounds?.union(pointBounds) ?? pointBounds
    }

    func beginActiveSubpath(at point: SionPoint) {
      activeStart = point
      includeInActiveBounds(point)
    }

    func resetActiveSubpath() {
      activeBounds = nil
      activeStart = nil
      activeDrawCommandCount = 0
      activeHasCurve = false
      activeHasStrokeCommand = false
      activeHasNonzeroStrokeSegment = false
    }

    func finishActiveSubpath() -> Bool {
      let fillMayPaint =
        hasVisibleFill
        && (activeHasCurve || activeDrawCommandCount >= 2)
      let strokeMayPaint =
        visibleStroke.map { stroke in
          activeHasNonzeroStrokeSegment
            || activeHasStrokeCommand && stroke.lineCap != .butt
        } ?? false
      let finishedBounds = activeBounds
      resetActiveSubpath()

      guard fillMayPaint || strokeMayPaint, let finishedBounds else { return false }

      return finishedBounds.expanded(by: expansion).contains(point)
    }

    for command in commands {
      switch command {
      case .move(let point):
        if finishActiveSubpath() {
          return true
        }

        let resolved = resolve(point)
        beginActiveSubpath(at: resolved)
        currentPoint = resolved
      case .line(let point):
        let end = resolve(point)
        guard let start = currentPoint else {
          beginActiveSubpath(at: end)
          currentPoint = end
          continue
        }
        if activeStart == nil {
          beginActiveSubpath(at: start)
        }

        includeInActiveBounds(end)
        activeDrawCommandCount += 1
        activeHasStrokeCommand = true
        activeHasNonzeroStrokeSegment = activeHasNonzeroStrokeSegment || start != end
        currentPoint = end
      case .quadratic(let control, let point):
        let resolvedControl = resolve(control)
        let end = resolve(point)
        guard let start = currentPoint else {
          beginActiveSubpath(at: end)
          currentPoint = end
          continue
        }
        if activeStart == nil {
          beginActiveSubpath(at: start)
        }

        includeInActiveBounds(resolvedControl)
        includeInActiveBounds(end)
        activeDrawCommandCount += 1
        activeHasCurve = true
        activeHasStrokeCommand = true
        activeHasNonzeroStrokeSegment =
          activeHasNonzeroStrokeSegment
          || start != resolvedControl
          || resolvedControl != end
        currentPoint = end
      case .cubic(let control1, let control2, let point):
        let resolvedControl1 = resolve(control1)
        let resolvedControl2 = resolve(control2)
        let end = resolve(point)
        guard let start = currentPoint else {
          beginActiveSubpath(at: end)
          currentPoint = end
          continue
        }
        if activeStart == nil {
          beginActiveSubpath(at: start)
        }

        includeInActiveBounds(resolvedControl1)
        includeInActiveBounds(resolvedControl2)
        includeInActiveBounds(end)
        activeDrawCommandCount += 1
        activeHasCurve = true
        activeHasStrokeCommand = true
        activeHasNonzeroStrokeSegment =
          activeHasNonzeroStrokeSegment
          || start != resolvedControl1
          || resolvedControl1 != resolvedControl2
          || resolvedControl2 != end
        currentPoint = end
      case .close:
        guard let start = activeStart, let end = currentPoint else { continue }

        activeHasStrokeCommand = true
        activeHasNonzeroStrokeSegment = activeHasNonzeroStrokeSegment || end != start
        if finishActiveSubpath() {
          return true
        }

        // Continue later commands from the closed subpath's origin.
        currentPoint = start
      }
    }

    return finishActiveSubpath()
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
  fileprivate var hasVisibleArtwork: Bool {
    hasVisibleFill || visibleStroke != nil
  }

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
      stroke.color.alpha > 0,
      stroke.mayPaintHitGeometry
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
  fileprivate var mayPaintHitGeometry: Bool {
    guard lineCap == .butt,
      !dashPattern.isEmpty,
      dashPattern.count <= HitGeometryDefaults.maximumInteractiveDashPatternCount,
      dashPattern.count.isMultiple(of: 2)
    else {
      return true
    }

    var hasPositiveEntry = false
    for (index, length) in dashPattern.enumerated() {
      guard length.isFinite, length >= 0 else { return true }
      guard length > 0 else { continue }

      hasPositiveEntry = true
      if index.isMultiple(of: 2) {
        return true
      }
    }

    // An invalid all-zero pattern keeps the solid conservative fallback.
    return hasPositiveEntry == false
  }

  fileprivate func hitExpansion(tolerance: Double) -> Double {
    let radius = width / 2
    let capExpansion = lineCap == .square ? hypot(radius, radius) : radius
    let joinExpansion =
      lineJoin == .miter
      ? radius * StrokeGeometryDefaults.miterLimit
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
  static let maximumCubicArcEnvelopeScale = 1.001
  static let curveFlatness = 0.25
  static let epsilon = 1e-9
  // Share a fixed traversal budget across every curve in one valid path.
  static let flattenedSegmentsPerPathCommand = 16
  static let maximumFlattenedCurveSegmentCount =
    SceneLimits.maximumPathCommandCount * flattenedSegmentsPerPathCommand
  static let maximumInteractiveDashPatternCount = SceneLimits.maximumPathCommandCount
  // An eight-segment conservative preflight rejects curved-shape misses.
  static let maximumBuiltInBroadPhaseSubdivisionDepth = 1
  // Four-curve built-ins use at most 1,024 curve segments.
  static let maximumBuiltInCurveSubdivisionDepth = 8
  static let maximumCurveSubdivisionDepth = 12
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
