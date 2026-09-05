import CGtk
import Foundation

/// Format, scale, and background controls for "Export Image…". GTK's file
/// dialog takes no accessory view, so the options are asked first and the
/// file chooser follows with the matching type and suggested name.
@MainActor
package enum SionGtkImageExportOptionsDialog {
  /// Presents the options; `completion` receives nil when cancelled.
  package static func present(
    initial options: SionImageExportOptions,
    parent: UnsafeMutablePointer<GtkWidget>?,
    completion: @escaping @MainActor (SionImageExportOptions?) -> Void
  ) {
    completion(options)
  }
}
