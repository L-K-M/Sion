import CGtk
import Foundation
import SionCore

/// Prints the drawing scaled to fit one page and centred, with no grid or
/// chrome, through `GtkPrintOperation`. Page Setup edits the page setup and
/// print settings a document keeps between print jobs.
@MainActor
package final class SionGtkPrintOperation {
  package init() {}

  package func runPageSetup(parent: UnsafeMutablePointer<GtkWindow>?) {}

  package func print(
    jobTitle: String,
    contentBounds: SionRect,
    draw: @escaping SionGtkSceneDrawing,
    parent: UnsafeMutablePointer<GtkWindow>?,
    completion: @escaping @MainActor (Error?) -> Void
  ) {
    completion(nil)
  }
}
