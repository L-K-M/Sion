import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// Sion stores and exports sRGB components; Cairo and GDK take the same
/// components, so no conversion is needed beyond clamping.
enum SionGtkColorBridge {
  static func rgba(_ color: SionColor) -> GdkRGBA {
    sion_rgba(
      SionPaperColor.clampedUnit(color.red),
      SionPaperColor.clampedUnit(color.green),
      SionPaperColor.clampedUnit(color.blue),
      SionPaperColor.clampedUnit(color.alpha)
    )
  }

  static func modelColor(_ rgba: GdkRGBA) -> SionColor {
    SionColor(
      red: SionPaperColor.clampedUnit(Double(rgba.red)),
      green: SionPaperColor.clampedUnit(Double(rgba.green)),
      blue: SionPaperColor.clampedUnit(Double(rgba.blue)),
      alpha: SionPaperColor.clampedUnit(Double(rgba.alpha))
    )
  }

  /// The paper both applications choose for a backdrop under `ink`.
  static func paperColor(_ backdrop: SionColor, ink: SionColor) -> SionColor {
    SionPaperColor.paper(backdrop, ink: ink)
  }

  static func setSource(_ context: OpaquePointer, _ color: SionColor) {
    cairo_set_source_rgba(
      context,
      SionPaperColor.clampedUnit(color.red),
      SionPaperColor.clampedUnit(color.green),
      SionPaperColor.clampedUnit(color.blue),
      SionPaperColor.clampedUnit(color.alpha)
    )
  }
}
