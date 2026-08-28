import Foundation

package enum SceneAlignmentEdge: String, CaseIterable, Equatable, Hashable, Sendable {
  case leading
  case centerX
  case trailing
  case top
  case centerY
  case bottom
}

package enum SceneDistributionAxis: String, CaseIterable, Equatable, Hashable, Sendable {
  case horizontal
  case vertical
}

/// Pure geometry behind the Arrange menu: alignment shares an edge or center,
/// distribution equalizes gaps across the selection's original span.
package enum SceneArrangement {
  /// One translation per frame, parallel to the input order.
  package static func alignedOffsets(
    _ frames: [SionRect],
    edge: SceneAlignmentEdge
  ) -> [SionVector] {
    let rects = frames.map(\.standardized)
    guard let union = rects.reduce(nil, { $0?.union($1) ?? $1 }) else {
      return []
    }

    return rects.map { rect in
      switch edge {
      case .leading:
        return SionVector(dx: union.minX - rect.minX, dy: 0)
      case .centerX:
        return SionVector(dx: union.center.x - rect.center.x, dy: 0)
      case .trailing:
        return SionVector(dx: union.maxX - rect.maxX, dy: 0)
      case .top:
        return SionVector(dx: 0, dy: union.minY - rect.minY)
      case .centerY:
        return SionVector(dx: 0, dy: union.center.y - rect.center.y)
      case .bottom:
        return SionVector(dx: 0, dy: union.maxY - rect.maxY)
      }
    }
  }

  /// One translation per frame, parallel to the input order. The near union
  /// edge stays put and the final frame lands on the far union edge. Frames
  /// wider than the span overlap gracefully (gaps go negative uniformly).
  package static func distributedOffsets(
    _ frames: [SionRect],
    axis: SceneDistributionAxis
  ) -> [SionVector] {
    guard frames.count >= 3 else {
      return frames.map { _ in .zero }
    }

    let ordered = frames.enumerated().sorted { left, right in
      let leftMinimum = minimum(left.element.standardized, axis: axis)
      let rightMinimum = minimum(right.element.standardized, axis: axis)
      // Swift's sort is not stable; tie-break on input order so repeated
      // distributions of tied frames are deterministic.
      return leftMinimum == rightMinimum
        ? left.offset < right.offset
        : leftMinimum < rightMinimum
    }
    let sizes = ordered.map { size(of: $0.element.standardized, axis: axis) }
    let nearEdge = minimum(ordered[0].element.standardized, axis: axis)
    let farEdge = frames.reduce(nearEdge) { current, frame in
      max(current, maximum(frame.standardized, axis: axis))
    }
    let span = farEdge - nearEdge
    let gap = (span - sizes.reduce(0, +)) / Double(ordered.count - 1)

    var offsets = [SionVector](repeating: .zero, count: frames.count)
    var cursor = nearEdge
    for (entry, size) in zip(ordered, sizes) {
      let current = minimum(entry.element.standardized, axis: axis)
      let offset = cursor - current
      offsets[entry.offset] =
        axis == .horizontal
        ? SionVector(dx: offset, dy: 0)
        : SionVector(dx: 0, dy: offset)
      cursor += size + gap
    }

    return offsets
  }

  private static func minimum(_ rect: SionRect, axis: SceneDistributionAxis) -> Double {
    axis == .horizontal ? rect.minX : rect.minY
  }

  private static func maximum(_ rect: SionRect, axis: SceneDistributionAxis) -> Double {
    axis == .horizontal ? rect.maxX : rect.maxY
  }

  private static func size(of rect: SionRect, axis: SceneDistributionAxis) -> Double {
    axis == .horizontal ? rect.width : rect.height
  }
}
