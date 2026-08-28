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

    static func modelColor(_ color: NSColor) -> SionColor {
      guard let converted = color.usingColorSpace(.sRGB) else { return .black }

      return SionColor(
        red: clampedUnit(Double(converted.redComponent)),
        green: clampedUnit(Double(converted.greenComponent)),
        blue: clampedUnit(Double(converted.blueComponent)),
        alpha: clampedUnit(Double(converted.alphaComponent))
      )
    }

    private static func clampedUnit(_ value: Double) -> Double {
      guard value.isFinite else { return 1 }

      return min(1, max(0, value))
    }
  }
#endif
