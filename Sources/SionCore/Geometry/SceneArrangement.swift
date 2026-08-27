import Foundation

public enum SceneAlignmentEdge: String, CaseIterable, Equatable, Hashable, Sendable {
  case leading
  case centerX
  case trailing
  case top
  case centerY
  case bottom
}

public enum SceneDistributionAxis: String, CaseIterable, Equatable, Hashable, Sendable {
  case horizontal
  case vertical
}

/// Pure geometry behind the Arrange menu: alignment shares an edge or center,
/// distribution equalizes the gaps between frames while pinning the extremes.
public enum SceneArrangement {
  /// One translation per frame, parallel to the input order.
  public static func alignedOffsets(
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

  /// One translation per frame, parallel to the input order. The two extreme
  /// frames stay put; the rest move so all gaps are equal. Frames wider than
  /// the span overlap gracefully (gaps go negative uniformly).
  public static func distributedOffsets(
    _ frames: [SionRect],
    axis: SceneDistributionAxis
  ) -> [SionVector] {
    guard frames.count >= 3 else {
      return frames.map { _ in .zero }
    }

    let ordered = frames.enumerated().sorted { left, right in
      minimum(left.element.standardized, axis: axis)
        < minimum(right.element.standardized, axis: axis)
    }
    let sizes = ordered.map { size(of: $0.element.standardized, axis: axis) }
    let span =
      maximum(ordered.last!.element.standardized, axis: axis)
      - minimum(ordered.first!.element.standardized, axis: axis)
    let gap = (span - sizes.reduce(0, +)) / Double(ordered.count - 1)

    var offsets = [SionVector](repeating: .zero, count: frames.count)
    var cursor = minimum(ordered.first!.element.standardized, axis: axis)
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
