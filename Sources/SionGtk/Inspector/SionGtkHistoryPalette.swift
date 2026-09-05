import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// The History palette: every retained revision, newest first as stored, each
/// a button that restores it. Undo restores the current drawing.
@MainActor
final class SionGtkHistoryPalette: SionGtkPaletteContent {
  let widget: UnsafeMutablePointer<GtkWidget>

  private let stack = paletteStack()
  private weak var host: SionGtkPaletteHost?
  private var observerID: UUID?
  private var displayedRevisionIDs: [String]?

  init() {
    widget = scrollingPaletteBody(stack)
    refresh()
  }

  func retarget(to host: SionGtkPaletteHost?) {
    if let observerID {
      self.host?.paletteEditorController.removeObserver(observerID)
    }

    self.host = host
    observerID = host?.paletteEditorController.observeChanges { [weak self] in
      self?.refresh()
    }
    displayedRevisionIDs = nil
    refresh()
  }

  private func refresh() {
    let revisions = host?.paletteEditorController.historyRevisions ?? []
    let revisionIDs = revisions.map(\.identifier)
    guard revisionIDs != displayedRevisionIDs else { return }
    displayedRevisionIDs = revisionIDs

    removeAllChildren(of: stack)

    guard !revisions.isEmpty else {
      let label = gtk_label_new("No saved revisions")!
      gtk_label_set_xalign(label.opaque, 0)
      gtk_box_append(stack.cast(), label)
      return
    }

    for revision in revisions {
      let title =
        "\(revision.intent.displayName) · \(HistoryDateFormatter.shared.string(from: revision.savedAt))"
      let button = gtk_button_new_with_label(title)!
      gtk_widget_add_css_class(button, "flat")
      gtk_widget_set_halign(button, GTK_ALIGN_FILL)
      if let label = gtk_button_get_child(button.cast()) {
        gtk_label_set_xalign(label.opaque, 0)
        gtk_label_set_ellipsize(label.opaque, PANGO_ELLIPSIZE_END)
      }
      gtk_widget_set_tooltip_text(
        button, "Restore this revision. Undo restores the current drawing.")
      let identifier = revision.identifier
      Signals.connect(button.gobject, "clicked") { [weak self] in
        self?.restoreRevision(identifier)
      }
      gtk_box_append(stack.cast(), button)
    }
  }

  var revisionButtonCount: Int {
    var count = 0
    var child = gtk_widget_get_first_child(stack)
    while let current = child {
      if gtkInstance(current.gobject, isA: gtk_button_get_type()) { count += 1 }
      child = gtk_widget_get_next_sibling(current)
    }
    return count
  }

  func restoreRevision(_ identifier: String) {
    guard let host else { return }

    host.commitPendingEdits()
    try? host.paletteEditorController.restoreRevision(identifier: identifier)
  }
}

enum HistoryDateFormatter {
  nonisolated(unsafe) static let shared: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}

extension SaveIntent {
  var displayName: String {
    switch self {
    case .manual: "Saved"
    case .autosave: "Autosaved"
    case .saveAs: "Saved As"
    }
  }
}
