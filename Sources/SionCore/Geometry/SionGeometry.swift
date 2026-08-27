import Foundation

/// A canvas point. The origin is at the top-left and positive y points down.
public struct SionPoint: Codable, Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  public static let zero = SionPoint(x: 0, y: 0)

  public var isFinite: Bool {
    x.isFinite && y.isFinite
  }

  public func distance(to other: SionPoint) -> Double {
    (other - self).length
  }

  public func interpolated(to other: SionPoint, fraction: Double) -> SionPoint {
    self + ((other - self) * fraction)
  }
}

public struct SionVector: Codable, Equatable, Hashable, Sendable {
  public var dx: Double
  public var dy: Double

  public init(dx: Double, dy: Double) {
    self.dx = dx
    self.dy = dy
  }

  public static let zero = SionVector(dx: 0, dy: 0)
  public static let north = SionVector(dx: 0, dy: -1)
  public static let east = SionVector(dx: 1, dy: 0)
  public static let south = SionVector(dx: 0, dy: 1)
  public static let west = SionVector(dx: -1, dy: 0)

  public var lengthSquared: Double {
    (dx * dx) + (dy * dy)
  }

  public var length: Double {
    sqrt(lengthSquared)
  }

  public var normalized: SionVector {
    let magnitude = length
    guard magnitude.isFinite, magnitude > 0 else {
      return .zero
    }

    return self / magnitude
  }

  public var isFinite: Bool {
    dx.isFinite && dy.isFinite
  }

  public func dot(_ other: SionVector) -> Double {
    (dx * other.dx) + (dy * other.dy)
  }
}

public struct SionSize: Codable, Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }

  public static let zero = SionSize(width: 0, height: 0)

  public var isFinite: Bool {
    width.isFinite && height.isFinite
  }
}

public struct SionRect: Codable, Equatable, Hashable, Sendable {
  public var origin: SionPoint
  public var size: SionSize

  public init(origin: SionPoint, size: SionSize) {
    self.origin = origin
    self.size = size
  }

  public init(x: Double, y: Double, width: Double, height: Double) {
    origin = SionPoint(x: x, y: y)
    size = SionSize(width: width, height: height)
  }

  public static let zero = SionRect(origin: .zero, size: .zero)

  public var x: Double {
    get { origin.x }
    set { origin.x = newValue }
  }

  public var y: Double {
    get { origin.y }
    set { origin.y = newValue }
  }

  public var width: Double {
    get { size.width }
    set { size.width = newValue }
  }

  public var height: Double {
    get { size.height }
    set { size.height = newValue }
  }

  public var minX: Double {
    min(x, x + width)
  }

  public var minY: Double {
    min(y, y + height)
  }

  public var maxX: Double {
    max(x, x + width)
  }

  public var maxY: Double {
    max(y, y + height)
  }

  public var center: SionPoint {
    SionPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
  }

  public var standardized: SionRect {
    SionRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  public var isFinite: Bool {
    origin.isFinite && size.isFinite
  }

  public var isEmpty: Bool {
    width == 0 || height == 0
  }

  public func contains(_ point: SionPoint) -> Bool {
    point.x >= minX && point.x <= maxX
      && point.y >= minY && point.y <= maxY
  }

  public func containsInterior(_ point: SionPoint) -> Bool {
    point.x > minX && point.x < maxX
      && point.y > minY && point.y < maxY
  }

  public func intersects(_ other: SionRect) -> Bool {
    maxX >= other.minX && other.maxX >= minX
      && maxY >= other.minY && other.maxY >= minY
  }

  public func intersectsInterior(_ other: SionRect) -> Bool {
    maxX > other.minX && other.maxX > minX
      && maxY > other.minY && other.maxY > minY
  }

  public func expanded(by distance: Double) -> SionRect {
    let rect = standardized

    return SionRect(
      x: rect.minX - distance,
      y: rect.minY - distance,
      width: rect.width + (distance * 2),
      height: rect.height + (distance * 2)
    ).standardized
  }

  public func translated(by vector: SionVector) -> SionRect {
    SionRect(origin: origin + vector, size: size)
  }

  public func point(atNormalized normalizedPoint: SionPoint) -> SionPoint {
    let rect = standardized

    return SionPoint(
      x: rect.minX + (rect.width * normalizedPoint.x),
      y: rect.minY + (rect.height * normalizedPoint.y)
    )
  }

  public func union(_ other: SionRect) -> SionRect {
    SionRect(
      x: min(minX, other.minX),
      y: min(minY, other.minY),
      width: max(maxX, other.maxX) - min(minX, other.minX),
      height: max(maxY, other.maxY) - min(minY, other.minY)
    )
  }
}

public struct SionLineSegment: Codable, Equatable, Hashable, Sendable {
  public var start: SionPoint
  public var end: SionPoint

  public init(start: SionPoint, end: SionPoint) {
    self.start = start
    self.end = end
  }

  public var length: Double {
    start.distance(to: end)
  }

  public var isHorizontal: Bool {
    start.y == end.y
  }

  public var isVertical: Bool {
    start.x == end.x
  }

  /// Boundary contact is allowed so orthogonal routes can follow obstacle edges.
  public func intersectsInterior(of rect: SionRect) -> Bool {
    let obstacle = rect.standardized
    guard obstacle.width > 0, obstacle.height > 0 else {
      return false
    }

    if isHorizontal {
      guard start.y > obstacle.minY, start.y < obstacle.maxY else {
        return false
      }

      return max(min(start.x, end.x), obstacle.minX)
        < min(max(start.x, end.x), obstacle.maxX)
    }

    if isVertical {
      guard start.x > obstacle.minX, start.x < obstacle.maxX else {
        return false
      }

      return max(min(start.y, end.y), obstacle.minY)
        < min(max(start.y, end.y), obstacle.maxY)
    }

    return intersectsInteriorOnBothAxes(of: obstacle)
  }

  private func intersectsInteriorOnBothAxes(of rect: SionRect) -> Bool {
    let delta = end - start
    var lowerBound = 0.0
    var upperBound = 1.0

    guard
      clip(
        origin: start.x,
        delta: delta.dx,
        minimum: rect.minX,
        maximum: rect.maxX,
        lowerBound: &lowerBound,
        upperBound: &upperBound
      )
    else {
      return false
    }

    guard
      clip(
        origin: start.y,
        delta: delta.dy,
        minimum: rect.minY,
        maximum: rect.maxY,
        lowerBound: &lowerBound,
        upperBound: &upperBound
      )
    else {
      return false
    }

    guard lowerBound < upperBound else {
      return false
    }

    let midpoint = start.interpolated(to: end, fraction: (lowerBound + upperBound) / 2)
    return rect.containsInterior(midpoint)
  }

  private func clip(
    origin: Double,
    delta: Double,
    minimum: Double,
    maximum: Double,
    lowerBound: inout Double,
    upperBound: inout Double
  ) -> Bool {
    guard delta != 0 else {
      return origin > minimum && origin < maximum
    }

    let first = (minimum - origin) / delta
    let second = (maximum - origin) / delta
    lowerBound = max(lowerBound, min(first, second))
    upperBound = min(upperBound, max(first, second))

    return lowerBound <= upperBound
  }
}

public func + (point: SionPoint, vector: SionVector) -> SionPoint {
  SionPoint(x: point.x + vector.dx, y: point.y + vector.dy)
}

public func - (point: SionPoint, vector: SionVector) -> SionPoint {
  SionPoint(x: point.x - vector.dx, y: point.y - vector.dy)
}

public func - (left: SionPoint, right: SionPoint) -> SionVector {
  SionVector(dx: left.x - right.x, dy: left.y - right.y)
}

public prefix func - (vector: SionVector) -> SionVector {
  SionVector(dx: -vector.dx, dy: -vector.dy)
}

public func + (left: SionVector, right: SionVector) -> SionVector {
  SionVector(dx: left.dx + right.dx, dy: left.dy + right.dy)
}

public func - (left: SionVector, right: SionVector) -> SionVector {
  SionVector(dx: left.dx - right.dx, dy: left.dy - right.dy)
}

public func * (vector: SionVector, scalar: Double) -> SionVector {
  SionVector(dx: vector.dx * scalar, dy: vector.dy * scalar)
}

public func * (scalar: Double, vector: SionVector) -> SionVector {
  vector * scalar
}

public func / (vector: SionVector, scalar: Double) -> SionVector {
  guard scalar != 0 else {
    return .zero
  }

  return SionVector(dx: vector.dx / scalar, dy: vector.dy / scalar)
}
