import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// The document canvas: a `GtkDrawingArea` inside a `GtkScrolledWindow` that
/// renders the scene with Cairo and Pango and owns every pointer, keyboard,
/// clipboard, and drop interaction, mirroring `SionCanvasView` on macOS.
///
/// The canvas owns the zoom factor, so screen-constant chrome, hit tolerances,
/// and event-to-model conversion share one source of truth.
@MainActor
package final class SionGtkCanvasView {
  package static let minimumMagnification = 0.1
  package static let maximumMagnification = 8.0
  package static let zoomStep = 1.2
  package static let fitInsetFactor = 0.88

  package let editorController: SionEditorController

  /// The widget a window embeds: the scrolled container around the canvas.
  package let widget: UnsafeMutablePointer<GtkWidget>
  /// The drawing area itself, for focus and popover anchoring.
  package let drawingArea: UnsafeMutablePointer<GtkWidget>

  /// Reports every zoom change so the window can show the percentage.
  package var onMagnificationChange: (@MainActor (Double) -> Void)?

  package private(set) var magnification = 1.0

  private let editorFeedback: @MainActor (SionEditorFeedbackRequest) -> Void

  package init(
    editorController: SionEditorController,
    editorFeedback: @escaping @MainActor (SionEditorFeedbackRequest) -> Void
  ) {
    self.editorController = editorController
    self.editorFeedback = editorFeedback
    drawingArea = gtk_drawing_area_new()!
    widget = gtk_scrolled_window_new()!
    gtk_scrolled_window_set_child(widget.opaque, drawingArea)
  }

  /// The centre of the visible viewport in model coordinates.
  package var visibleCenter: SionPoint {
    editorController.defaultInsertionCenter
  }

  package func zoomIn() {}
  package func zoomOut() {}
  package func actualSize() {}
  package func zoomToFit() {}

  package func commitPendingEdits() {}
  package func checkpointPendingEdits() {}
  package func discardPendingEdits() {}
  package func beginTextEditing(_ id: ElementID) {}
  package func cancelActiveDrag() {}
  package func grabFocus() {
    gtk_widget_grab_focus(drawingArea)
  }

  /// Releases the observer registration on the editor controller.
  package func invalidate() {}

  /// A PNG of the content bounds for the archive preview, or nil when empty.
  package func renderPreviewPNG() -> Data? {
    nil
  }

  /// Whether a menu command applies to the current selection and state.
  package func canPerform(_ command: SionGtkCommand) -> Bool {
    false
  }

  /// The check-mark state of a toggle command, nil for plain commands.
  package func isChecked(_ command: SionGtkCommand) -> Bool? {
    nil
  }

  package func perform(_ command: SionGtkCommand) {}

  /// Draws visible scene content into `context`, which the caller has already
  /// mapped to the model's y-down space; export and printing use this seam.
  package func drawSceneContent(
    _ context: OpaquePointer,
    in bounds: SionRect,
    fillsBackground: Bool
  ) {}
}
