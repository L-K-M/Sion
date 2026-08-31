#if canImport(AppKit)
  import AppKit
  import SionCore

  /// Sion stores and exports sRGB components, so AppKit colors must retain that
  /// interpretation on every display color space.
  enum SionColorBridge {
    static func appKitColor(_ color: SionColor) -> NSColor {
      NSColor(
        srgbRed: CGFloat(clampedUnit(color.red)),
        green: CGFloat(clampedUnit(color.green)),
        blue: CGFloat(clampedUnit(color.blue)),
        alpha: CGFloat(clampedUnit(color.alpha))
      )
    }

    /// Picks the opaque paper a surface should present so `ink` drawn on it
    /// stays readable. The backdrop is flattened onto white; when it would sink
    /// into the ink it is replaced by the opposite extreme. Nothing here reads
    /// the system appearance, so a document surface never turns dark with it.
    static func paperColor(_ backdrop: SionColor, ink: SionColor) -> NSColor {
      let paper = flattenedOntoWhite(backdrop)
      let inkIsLight = isLight(flattenedOntoWhite(ink))
      guard isLight(paper) == inkIsLight else { return appKitColor(paper) }

      return appKitColor(inkIsLight ? .primaryInk : .white)
    }

    static func modelColor(_ color: NSColor) -> SionColor {
      guard let converted = color.usingColorSpace(.sRGB) else { return .black }

      return SionColor(
        red: clampedUnit(Double(converted.redComponent)),
        green: clampedUnit(Double(converted.greenComponent)),
        blue: clampedUnit(Double(converted.blueComponent)),
        alpha: clampedUnit(Double(converted.alphaComponent))
      )
    }

    private static func flattenedOntoWhite(_ color: SionColor) -> SionColor {
      let alpha = clampedUnit(color.alpha)
      return SionColor(
        red: overWhite(clampedUnit(color.red), alpha: alpha),
        green: overWhite(clampedUnit(color.green), alpha: alpha),
        blue: overWhite(clampedUnit(color.blue), alpha: alpha)
      )
    }

    private static func overWhite(_ component: Double, alpha: Double) -> Double {
      (component * alpha) + (1 - alpha)
    }

    private static func isLight(_ color: SionColor) -> Bool {
      let brightness = (0.299 * color.red) + (0.587 * color.green) + (0.114 * color.blue)
      return brightness >= PaperMetrics.lightnessPivot
    }

    private static func clampedUnit(_ value: Double) -> Double {
      guard value.isFinite else { return 1 }

      return min(1, max(0, value))
    }
  }

  private enum PaperMetrics {
    /// Paper and ink on the same side of this read as the same tone.
    static let lightnessPivot = 0.6
  }
#endif
