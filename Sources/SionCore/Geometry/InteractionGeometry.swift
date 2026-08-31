import Foundation

public enum ResizeHandle: CaseIterable, Hashable, Sendable {
  case northWest
  case north
  case northEast
  case east
  case southEast
  case south
  case southWest
  case west
}

public enum CreationPlacementMode: Hashable, Sendable {
  case click
  case drag
}

public struct CreationPlacement: Equatable, Sendable {
  public let frame: SionRect
  public let mode: CreationPlacementMode

  public init(frame: SionRect, mode: CreationPlacementMode) {
    self.frame = frame
    self.mode = mode
  }
}

/// Geometry shared by pointer-driven editors on every platform.
public enum InteractionGeometry {
  public static func creationFrame(
    from anchor: SionPoint,
    to pointer: SionPoint,
    dragThreshold: Double,
    defaultSize: SionSize,
    minimumSize: SionSize
  ) -> CreationPlacement {
    let threshold = nonnegativeFinite(dragThreshold)
    guard anchor.distance(to: pointer) > threshold else {
      let frame = SionRect(
        origin: anchor,
        size: SionSize(
          width: creationLength(defaultSize.width, minimum: minimumSize.width),
          height: creationLength(defaultSize.height, minimum: minimumSize.height)
        )
      )

      return CreationPlacement(frame: frame, mode: .click)
    }

    return CreationPlacement(
      frame: dragFrame(from: anchor, to: pointer, minimumSize: minimumSize),
      mode: .drag
    )
  }

  public static func dragFrame(
    from anchor: SionPoint,
    to pointer: SionPoint,
    minimumSize: SionSize
  ) -> SionRect {
    let horizontal = axisExtent(
      fixed: anchor.x,
      moving: pointer.x,
      minimumLength: minimumSize.width,
      fallbackDirection: .increasing
    )
    let vertical = axisExtent(
      fixed: anchor.y,
      moving: pointer.y,
      minimumLength: minimumSize.height,
      fallbackDirection: .increasing
    )

    return SionRect(
      x: horizontal.minimum,
      y: vertical.minimum,
      width: horizontal.length,
      height: vertical.length
    )
  }

  public static func resizeHandlePoint(
    _ handle: ResizeHandle,
    in frame: SionRect,
    rotationRadians: Double = 0
  ) -> SionPoint {
    let rect = frame.standardized
    let point = rect.point(atNormalized: handle.normalizedPosition)

    return rotated(point, around: rect.center, by: rotationRadians)
  }

  /// `aspectRatio` is width over height; when it is supplied the frame keeps
  /// that proportion and the handle's opposite corner or edge stays fixed.
  public static func resizedFrame(
    _ initialFrame: SionRect,
    moving handle: ResizeHandle,
    to pointer: SionPoint,
    minimumSize: SionSize,
    rotationRadians: Double = 0,
    aspectRatio: Double? = nil
  ) -> SionRect {
    let frame = initialFrame.standardized
    let center = frame.center
    let fixedPoint = frame.point(atNormalized: handle.fixedNormalizedPosition)
    let localPointer = unrotated(pointer, around: center, by: rotationRadians)
    var resized = frame

    if let direction = handle.horizontalDirection {
      let horizontal = axisExtent(
        fixed: fixedPoint.x,
        moving: localPointer.x,
        minimumLength: minimumSize.width,
        fallbackDirection: direction
      )
      resized.x = horizontal.minimum
      resized.width = horizontal.length
    }

    if let direction = handle.verticalDirection {
      let vertical = axisExtent(
        fixed: fixedPoint.y,
        moving: localPointer.y,
        minimumLength: minimumSize.height,
        fallbackDirection: direction
      )
      resized.y = vertical.minimum
      resized.height = vertical.length
    }

    if let aspectRatio {
      resized = constrained(
        resized,
        to: aspectRatio,
        handle: handle,
        fixedPoint: fixedPoint,
        minimumSize: minimumSize
      )
    }

    guard rotationRadians != 0 else {
      return resized
    }

    // Resizing changes the center; translate back so the opposite handle stays fixed.
    let fixedWorldPoint = rotated(fixedPoint, around: center, by: rotationRadians)
    let movedFixedPoint = rotated(fixedPoint, around: resized.center, by: rotationRadians)

    return resized.translated(by: fixedWorldPoint - movedFixedPoint)
  }

  /// Reshapes `frame` to `ratio` around the point the handle leaves fixed. An
  /// edge handle drives its own axis and the other follows; a corner follows
  /// whichever axis the pointer pushed further, so the frame reaches the
  /// pointer instead of trailing behind it.
  private static func constrained(
    _ frame: SionRect,
    to ratio: Double,
    handle: ResizeHandle,
    fixedPoint: SionPoint,
    minimumSize: SionSize
  ) -> SionRect {
    guard ratio.isFinite, ratio > 0, frame.width > 0 || frame.height > 0 else {
      return frame
    }

    var width = frame.width
    var height = frame.height
    switch (handle.horizontalDirection, handle.verticalDirection) {
    case (.some, .none):
      height = width / ratio
    case (.none, .some):
      width = height * ratio
    default:
      if width >= height * ratio {
        height = width / ratio
      } else {
        width = height * ratio
      }
    }

    guard width > 0, height > 0, width.isFinite, height.isFinite else { return frame }

    // Reaching a minimum on one axis has to grow the other in step.
    let scale = max(1, max(minimumSize.width / width, minimumSize.height / height))
    width *= scale
    height *= scale

    let fixedNormalized = handle.fixedNormalizedPosition
    return SionRect(
      x: fixedPoint.x - (fixedNormalized.x * width),
      y: fixedPoint.y - (fixedNormalized.y * height),
      width: width,
      height: height
    )
  }

  public static func rotated(
    _ point: SionPoint,
    around center: SionPoint,
    by radians: Double
  ) -> SionPoint {
    let offset = point - center
    let cosine = cos(radians)
    let sine = sin(radians)

    return SionPoint(
      x: center.x + (offset.dx * cosine) - (offset.dy * sine),
      y: center.y + (offset.dx * sine) + (offset.dy * cosine)
    )
  }

  static func rotated(_ vector: SionVector, by radians: Double) -> SionVector {
    let cosine = cos(radians)
    let sine = sin(radians)

    return SionVector(
      dx: (vector.dx * cosine) - (vector.dy * sine),
      dy: (vector.dx * sine) + (vector.dy * cosine)
    )
  }

  public static func unrotated(
    _ point: SionPoint,
    around center: SionPoint,
    by radians: Double
  ) -> SionPoint {
    rotated(point, around: center, by: -radians)
  }

  public static func rotationRadians(
    at point: SionPoint,
    around center: SionPoint,
    offset: Double = 0
  ) -> Double {
    let direction = point - center

    return normalizedAngle(atan2(direction.dy, direction.dx) + offset)
  }

  public static func rotationDelta(
    from start: SionPoint,
    to end: SionPoint,
    around center: SionPoint
  ) -> Double {
    let startAngle = atan2(start.y - center.y, start.x - center.x)
    let endAngle = atan2(end.y - center.y, end.x - center.x)

    return normalizedAngle(endAngle - startAngle)
  }

  public static func rotationHandlePoint(
    in frame: SionRect,
    rotationRadians: Double = 0,
    offset: Double
  ) -> SionPoint {
    let rect = frame.standardized
    let point = SionPoint(
      x: rect.center.x,
      y: rect.minY - nonnegativeFinite(offset)
    )

    return rotated(point, around: rect.center, by: rotationRadians)
  }

  public static func roundedRectangleCornerRadius(
    in frame: SionRect,
    draggedTo pointer: SionPoint,
    rotationRadians: Double = 0
  ) -> Double {
    let rect = frame.standardized
    let localPointer = unrotated(pointer, around: rect.center, by: rotationRadians)

    return clampedCornerRadius(localPointer.x - rect.minX, in: rect)
  }

  public static func roundedRectangleCornerRadiusHandle(
    in frame: SionRect,
    radius: Double,
    rotationRadians: Double = 0
  ) -> SionPoint {
    let rect = frame.standardized
    let clampedRadius = clampedCornerRadius(radius, in: rect)
    let localPoint = SionPoint(
      x: rect.minX + clampedRadius,
      y: rect.minY + clampedRadius
    )

    return rotated(localPoint, around: rect.center, by: rotationRadians)
  }

  private static func clampedCornerRadius(_ radius: Double, in frame: SionRect) -> Double {
    let maximumRadius = min(frame.width, frame.height) / 2
    guard radius.isFinite else {
      return 0
    }

    return min(max(radius, 0), maximumRadius)
  }

  private static func creationLength(_ proposed: Double, minimum: Double) -> Double {
    let validMinimum = nonnegativeFinite(minimum)
    guard proposed.isFinite else {
      return validMinimum
    }

    return max(abs(proposed), validMinimum)
  }

  private static func nonnegativeFinite(_ value: Double) -> Double {
    guard value.isFinite else {
      return 0
    }

    return max(0, value)
  }

  private static func normalizedAngle(_ radians: Double) -> Double {
    atan2(sin(radians), cos(radians))
  }

  private static func axisExtent(
    fixed: Double,
    moving: Double,
    minimumLength: Double,
    fallbackDirection: AxisDirection
  ) -> AxisExtent {
    let direction: AxisDirection
    if moving < fixed {
      direction = .decreasing
    } else if moving > fixed {
      direction = .increasing
    } else {
      direction = fallbackDirection
    }

    let length = max(abs(moving - fixed), nonnegativeFinite(minimumLength))
    switch direction {
    case .decreasing:
      return AxisExtent(minimum: fixed - length, maximum: fixed)
    case .increasing:
      return AxisExtent(minimum: fixed, maximum: fixed + length)
    }
  }
}

public enum ConnectorAttachmentResolver {
  public static func endpoint(
    attachingTo element: SceneElement?,
    at point: SionPoint,
    use: MagnetUse,
    magnetSnapDistance: Double
  ) -> ConnectionEndpoint {
    guard let element else {
      return .free(point)
    }

    let snapDistance = magnetSnapDistance.isFinite ? max(0, magnetSnapDistance) : 0
    let maximumDistanceSquared = snapDistance * snapDistance
    var nearest: ResolvedMagnet?
    var nearestDistanceSquared = Double.infinity

    // Declaration order resolves equal-distance magnets consistently.
    for candidate in element.resolvedMagnets
    where candidate.magnet.connectionDirection.allows(use) {
      let distanceSquared = (candidate.endpoint.point - point).lengthSquared
      guard distanceSquared < nearestDistanceSquared else {
        continue
      }

      nearest = candidate
      nearestDistanceSquared = distanceSquared
    }

    guard let nearest, nearestDistanceSquared <= maximumDistanceSquared else {
      return .element(element.id, attachment: .automatic, fallbackPoint: point)
    }

    return .element(
      element.id,
      attachment: .magnet(nearest.magnet.id),
      fallbackPoint: nearest.endpoint.point
    )
  }
}

private enum AxisDirection {
  case decreasing
  case increasing
}

private struct AxisExtent {
  let minimum: Double
  let maximum: Double

  var length: Double {
    maximum - minimum
  }
}

extension ResizeHandle {
  fileprivate var normalizedPosition: SionPoint {
    switch self {
    case .northWest: SionPoint(x: 0, y: 0)
    case .north: SionPoint(x: 0.5, y: 0)
    case .northEast: SionPoint(x: 1, y: 0)
    case .east: SionPoint(x: 1, y: 0.5)
    case .southEast: SionPoint(x: 1, y: 1)
    case .south: SionPoint(x: 0.5, y: 1)
    case .southWest: SionPoint(x: 0, y: 1)
    case .west: SionPoint(x: 0, y: 0.5)
    }
  }

  fileprivate var fixedNormalizedPosition: SionPoint {
    let moving = normalizedPosition

    return SionPoint(x: 1 - moving.x, y: 1 - moving.y)
  }

  fileprivate var horizontalDirection: AxisDirection? {
    switch self {
    case .northWest, .southWest, .west:
      .decreasing
    case .northEast, .southEast, .east:
      .increasing
    case .north, .south:
      nil
    }
  }

  fileprivate var verticalDirection: AxisDirection? {
    switch self {
    case .northWest, .north, .northEast:
      .decreasing
    case .southEast, .south, .southWest:
      .increasing
    case .east, .west:
      nil
    }
  }
}
