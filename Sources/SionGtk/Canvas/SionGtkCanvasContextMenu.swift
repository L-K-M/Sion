import CGtk
import Foundation
import SionCore
import SionKit

/// The canvas's right-click menu: the same commands as the main menu, sent to
/// the same `win.` actions, so the window's enable rules decide what either
/// menu offers.
@MainActor
final class SionGtkCanvasContextMenu {
  private let popover: UnsafeMutablePointer<GtkWidget>

  init(parent: UnsafeMutablePointer<GtkWidget>) {
    let built = SionGtkMenuBuilder.build(SionGtkMenuTree.canvasContextMenu)
    popover = gtk_popover_menu_new_from_model(built.model)!
    g_object_unref(built.menu.gobject)
    gtk_popover_set_has_arrow(popover.cast(), 0)
    gtk_widget_set_halign(popover, GTK_ALIGN_START)
    gtk_widget_set_parent(popover, parent)
  }

  deinit {
    gtk_widget_unparent(popover)
  }

  func popup(atWidgetX x: Double, y: Double) {
    var rectangle = GdkRectangle(x: Int32(x), y: Int32(y), width: 1, height: 1)
    gtk_popover_set_pointing_to(popover.cast(), &rectangle)
    gtk_popover_popup(popover.cast())
  }
}

extension SionGtkCanvasView {
  /// A right click acts on what is under it, so the menu it opens always
  /// describes what it would change: an element outside the selection
  /// replaces it, one inside keeps the whole selection, and bare canvas
  /// clears it.
  func handleContextMenuRequest(atWidgetX x: Double, y: Double) {
    cancelActiveDrag()
    commitTextEditing()
    grabFocus()

    let point = modelPoint(fromWidgetX: x, y: y)
    if let element = editorController.element(at: point) {
      if !editorController.selection.contains(element.id) {
        editorController.select(element.id)
      }
    } else {
      editorController.select(nil)
    }

    if contextMenu == nil {
      contextMenu = SionGtkCanvasContextMenu(parent: drawingArea)
    }
    contextMenu?.popup(atWidgetX: x, y: y)
  }
}
