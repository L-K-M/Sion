import Foundation

/// One alignment a dragged frame settled on, so the canvas can show where.
package struct SceneSnapGuide: Equatable, Sendable {
  package enum Axis: Equatable, Sendable {
    /// A shared x: the guide is drawn vertically.
    case vertical
    /// A shared y: the guide is drawn horizontally.
    case horizontal
  }

  package let axis: Axis
  /// The coordinate the two frames share, on the guide's own axis.
  package let position: Double
  /// The extent the guide spans on the other axis, covering both frames.
  package let start: Double
  package let end: Double

  package init(axis: Axis, position: Double, start: Double, end: Double) {
    self.axis = axis
    self.position = position
    self.start = min(start, end)
    self.end = max(start, end)
  }
}

package struct SceneSnap: Equatable, Sendable {
  package let offset: SionVector
  package let guides: [SceneSnapGuide]

  package static let none = SceneSnap(offset: .zero, guides: [])

  package init(offset: SionVector, guides: [SceneSnapGuide]) {
    self.offset = offset
    self.guides = guides
  }
}

/// Pure geometry behind alignment snapping: a dragged frame lines its edges or
/// its center up with a neighbour's when they come close enough.
package enum SceneSnapping {
  /// Each axis snaps independently to its nearest candidate, so a frame can
  /// line up horizontally with one neighbour and vertically with another.
  /// Ties go to the earlier neighbour, which keeps repeated drags stable.
  package static func snap(
    _ frame: SionRect,
    to neighbours: [SionRect],
    tolerance: Double
  ) -> SceneSnap {
    let moving = frame.standardized
    let rects = neighbours.map(\.standardized)
    guard tolerance.isFinite, tolerance > 0, moving.isFinite, !rects.isEmpty else {
      return .none
    }

    let horizontal = nearestAlignment(
      sources: [moving.minX, moving.center.x, moving.maxX],
      in: rects.map { [$0.minX, $0.center.x, $0.maxX] },
      tolerance: tolerance
    )
    let vertical = nearestAlignment(
      sources: [moving.minY, moving.center.y, moving.maxY],
      in: rects.map { [$0.minY, $0.center.y, $0.maxY] },
      tolerance: tolerance
    )
    guard horizontal != nil || vertical != nil else { return .none }

    let offset = SionVector(dx: horizontal?.delta ?? 0, dy: vertical?.delta ?? 0)
    let snapped = moving.translated(by: offset)
    var guides: [SceneSnapGuide] = []

    if let horizontal {
      let neighbour = rects[horizontal.neighbourIndex]
      guides.append(
        SceneSnapGuide(
          axis: .vertical,
          position: horizontal.position,
          start: min(snapped.minY, neighbour.minY),
          end: max(snapped.maxY, neighbour.maxY)
        )
      )
    }

    if let vertical {
      let neighbour = rects[vertical.neighbourIndex]
      guides.append(
        SceneSnapGuide(
          axis: .horizontal,
          position: vertical.position,
          start: min(snapped.minX, neighbour.minX),
          end: max(snapped.maxX, neighbour.maxX)
        )
      )
    }

    return SceneSnap(offset: offset, guides: guides)
  }

  private struct Alignment {
    let delta: Double
    let position: Double
    let neighbourIndex: Int
  }

  private static func nearestAlignment(
    sources: [Double],
    in neighbours: [[Double]],
    tolerance: Double
  ) -> Alignment? {
    var best: Alignment?

    for (index, targets) in neighbours.enumerated() {
      for target in targets where target.isFinite {
        for source in sources where source.isFinite {
          let delta = target - source
          guard abs(delta) <= tolerance else { continue }
          guard abs(delta) < abs(best?.delta ?? .infinity) else { continue }

          best = Alignment(delta: delta, position: target, neighbourIndex: index)
        }
      }
    }

    return best
  }
}
