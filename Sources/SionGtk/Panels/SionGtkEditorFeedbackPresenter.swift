import CGtk
import Foundation
import SionKit

/// Shows editor feedback as a banner over the canvas, mirroring
/// `SionEditorFeedbackPresenter` on macOS.
@MainActor
package final class SionGtkEditorFeedbackPresenter {
  package init() {}

  /// Hosts the banner in a `GtkOverlay` above the scrolled canvas.
  package func attach(to overlay: UnsafeMutablePointer<GtkWidget>) {}

  package func handle(_ request: SionEditorFeedbackRequest) {}

  package func invalidate() {}
}
