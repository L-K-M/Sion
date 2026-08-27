import Foundation

public struct CanvasGridRenderPlan: Equatable, Sendable {
  public let lineSpacing: Double
  public let linesPerMajor: Int

  fileprivate init(lineSpacing: Double, linesPerMajor: Int) {
    self.lineSpacing = lineSpacing
    self.linesPerMajor = linesPerMajor
  }
}

public enum CanvasGridRenderGeometry {
  public static func plan(
    for grid: CanvasGrid,
    magnification: Double
  ) -> CanvasGridRenderPlan? {
    guard grid.visibility == .visible,
      grid.spacing.isFinite,
      grid.spacing > 0,
      grid.subdivisions > 0,
      grid.subdivisions <= SceneLimits.maximumGridSubdivisions,
      magnification.isFinite,
      magnification > 0
    else {
      return nil
    }

    let nativeSpacing = grid.spacing / Double(grid.subdivisions)
    let nativeScreenSpacing = nativeSpacing * magnification
    var majorScreenSpacing = grid.spacing * magnification
    guard nativeSpacing.isFinite,
      nativeSpacing > 0,
      nativeScreenSpacing.isFinite,
      nativeScreenSpacing > 0,
      majorScreenSpacing.isFinite,
      majorScreenSpacing > 0
    else {
      return nil
    }

    var majorNativeUnits = grid.subdivisions
    while majorScreenSpacing < GridRenderMetrics.minimumMajorScreenSpacing {
      let nextUnits = majorNativeUnits.multipliedReportingOverflow(
        by: GridRenderMetrics.coarseningFactor
      )
      let nextScreenSpacing =
        majorScreenSpacing * Double(GridRenderMetrics.coarseningFactor)
      guard !nextUnits.overflow,
        nextScreenSpacing.isFinite,
        nextScreenSpacing > majorScreenSpacing
      else {
        return nil
      }

      majorNativeUnits = nextUnits.partialValue
      majorScreenSpacing = nextScreenSpacing
    }

    // Draw only configured lattice lines, coarsened enough to cap density.
    let lineStride = smallestReadableDivisor(
      of: majorNativeUnits,
      nativeScreenSpacing: nativeScreenSpacing
    )
    let lineSpacing = nativeSpacing * Double(lineStride)
    guard lineSpacing.isFinite, lineSpacing > 0 else { return nil }

    return CanvasGridRenderPlan(
      lineSpacing: lineSpacing,
      linesPerMajor: majorNativeUnits / lineStride
    )
  }

  private static func smallestReadableDivisor(
    of value: Int,
    nativeScreenSpacing: Double
  ) -> Int {
    divisors(of: value).first { divisor in
      nativeScreenSpacing * Double(divisor) >= GridRenderMetrics.minimumLineScreenSpacing
    } ?? value
  }

  private static func divisors(of value: Int) -> [Int] {
    var remainder = value
    var prime = 2
    var factors: [(prime: Int, exponent: Int)] = []

    while prime <= remainder / prime {
      var exponent = 0
      while remainder.isMultiple(of: prime) {
        remainder /= prime
        exponent += 1
      }
      if exponent > 0 {
        factors.append((prime, exponent))
      }

      prime = prime == 2 ? 3 : prime + 2
    }
    if remainder > 1 {
      factors.append((remainder, 1))
    }

    var divisors = [1]
    for factor in factors {
      let existing = divisors
      var multiplier = 1
      for _ in 0..<factor.exponent {
        multiplier *= factor.prime
        divisors.append(contentsOf: existing.map { $0 * multiplier })
      }
    }

    return divisors.sorted()
  }
}

private enum GridRenderMetrics {
  static let minimumLineScreenSpacing = 4.0
  static let minimumMajorScreenSpacing = 8.0
  static let coarseningFactor = 2
}
