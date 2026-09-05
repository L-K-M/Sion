import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// A stable, application-wide palette identity.
package enum SionGtkPaletteKind: String, CaseIterable, Sendable {
  case inspector
  case library
  case history

  package var title: String {
    switch self {
    case .inspector: "Inspector"
    case .library: "Library"
    case .history: "History"
    }
  }

  var definition: SionGtkPaletteDefinition {
    switch self {
    case .inspector:
      SionGtkPaletteDefinition(
        kind: self, contentSize: SionSize(width: 300, height: 320),
        minimumContentSize: SionSize(width: 260, height: 240))
    case .library:
      SionGtkPaletteDefinition(
        kind: self, contentSize: SionSize(width: 280, height: 250),
        minimumContentSize: SionSize(width: 240, height: 180))
    case .history:
      SionGtkPaletteDefinition(
        kind: self, contentSize: SionSize(width: 320, height: 360),
        minimumContentSize: SionSize(width: 260, height: 220))
    }
  }
}

/// Presentation details shared by the attached and floating forms.
package struct SionGtkPaletteDefinition {
  package let kind: SionGtkPaletteKind
  package let contentSize: SionSize
  package let minimumContentSize: SionSize

  package var title: String { kind.title }
}

package enum SionGtkPalettePresentation: Equatable, Sendable {
  case popover
  case panel
}

/// What a palette targets: the front document window and its editor.
@MainActor
package protocol SionGtkPaletteHost: AnyObject {
  var paletteEditorController: SionEditorController { get }
  var canvasVisibleCenter: SionPoint { get }
  var toplevel: UnsafeMutablePointer<GtkWindow>? { get }
  func presentEditorFeedback(_ request: SionEditorFeedbackRequest)
  func beginTextEditing(_ id: ElementID)
  func commitPendingEdits()
}

/// A typed adapter between palette UI and its current front-document target.
/// The factory creates one instance for the popover and another for the
/// floating window; shared selection state lives in the editor controller.
@MainActor
package protocol SionGtkPaletteContent: AnyObject {
  var widget: UnsafeMutablePointer<GtkWidget> { get }
  func retarget(to host: SionGtkPaletteHost?)
  func paletteDidPresent(_ presentation: SionGtkPalettePresentation)
  func paletteDidDismiss(_ presentation: SionGtkPalettePresentation)
}

extension SionGtkPaletteContent {
  package func paletteDidPresent(_ presentation: SionGtkPalettePresentation) {}
  package func paletteDidDismiss(_ presentation: SionGtkPalettePresentation) {}
}

/// Owns exactly one palette per kind across the application. Each palette
/// shows as a transient popover anchored to its toolbar button, or as a
/// floating window once detached, and retargets to the front document.
@MainActor
package final class SionGtkPaletteCenter {
  package static let shared = SionGtkPaletteCenter()

  /// Resolves the front document window whenever a palette needs its target.
  package var frontHost: @MainActor () -> SionGtkPaletteHost? = { nil }

  private var palettes: [SionGtkPaletteKind: SionGtkPalette] = [:]

  private init() {}

  package func palette(for kind: SionGtkPaletteKind) -> SionGtkPalette {
    if let palette = palettes[kind] {
      return palette
    }

    let palette = SionGtkPalette(
      definition: kind.definition,
      host: { [weak self] in self?.frontHost() },
      makeContent: { [weak self] in
        switch kind {
        case .inspector:
          SionGtkInspectorPalette(showAsPanel: { self?.palette(for: .inspector).showPanel() })
        case .library: SionGtkLibraryPalette(globalLibrary: .shared)
        case .history: SionGtkHistoryPalette()
        }
      }
    )
    palettes[kind] = palette
    return palette
  }

  /// Shows the palette attached to `anchor`, or raises its floating window.
  package func present(
    _ kind: SionGtkPaletteKind,
    relativeTo anchor: UnsafeMutablePointer<GtkWidget>?
  ) {
    palette(for: kind).present(relativeTo: anchor)
  }

  /// Call after the front document or its selection changes.
  package func frontDocumentDidChange() {
    for palette in palettes.values where palette.isPresented {
      palette.retarget()
    }
  }

  package func closeAll() {
    for palette in palettes.values {
      palette.close()
    }
  }
}

/// One app-global attached or floating presentation for a palette kind.
///
/// GTK popovers cannot be torn off by dragging, so the popover header carries
/// a button that opens the same palette as a window; the window is a real
/// toplevel the window manager moves and resizes.
@MainActor
package final class SionGtkPalette {
  package let definition: SionGtkPaletteDefinition
  package private(set) var presentation: SionGtkPalettePresentation?

  package var isPresented: Bool { presentation != nil }
  package var isFloating: Bool { presentation == .panel }

  private enum PopoverFollowUp {
    case showPanel
  }

  private let host: @MainActor () -> SionGtkPaletteHost?
  private let makeContent: @MainActor () -> SionGtkPaletteContent
  private var popover: UnsafeMutablePointer<GtkWidget>?
  private var popoverContent: SionGtkPaletteContent?
  private var panel: UnsafeMutablePointer<GtkWidget>?
  private var panelContent: SionGtkPaletteContent?
  private var popoverFollowUp: PopoverFollowUp?

  init(
    definition: SionGtkPaletteDefinition,
    host: @escaping @MainActor () -> SionGtkPaletteHost?,
    makeContent: @escaping @MainActor () -> SionGtkPaletteContent
  ) {
    self.definition = definition
    self.host = host
    self.makeContent = makeContent
  }

  /// Shows the attached form, or raises the existing floating form.
  package func present(relativeTo anchor: UnsafeMutablePointer<GtkWidget>?) {
    if presentation == .panel {
      retarget()
      if let panel { gtk_window_present(panel.cast()) }
      return
    }

    guard popover == nil else { return }
    guard let anchor, gtk_widget_get_root(anchor) != nil else {
      showPanel()
      return
    }

    let content = makeContent()
    content.retarget(to: host())
    let popover = gtk_popover_new()!
    gtk_popover_set_position(popover.cast(), GTK_POS_BOTTOM)
    gtk_popover_set_autohide(popover.cast(), 1)
    gtk_popover_set_child(popover.cast(), makePopoverBody(content))
    gtk_widget_set_parent(popover, anchor)
    Signals.connect(popover.gobject, "closed") { [weak self] in
      self?.popoverDidClose()
    }
    self.popover = popover
    popoverContent = content
    gtk_popover_popup(popover.cast())
    presentation = .popover
    content.paletteDidPresent(.popover)
  }

  /// Opens the floating form without first showing a popover.
  package func showPanel() {
    if let popover {
      popoverFollowUp = .showPanel
      gtk_popover_popdown(popover.cast())
      return
    }

    showPanelNow()
  }

  package func close() {
    if let popover {
      popoverFollowUp = nil
      gtk_popover_popdown(popover.cast())
    }
    if presentation == .panel, let panel {
      gtk_window_close(panel.cast())
    }
  }

  /// Re-resolves the target after front-document or selection changes.
  package func retarget() {
    let host = host()
    if presentation == .popover {
      popoverContent?.retarget(to: host)
    }
    if presentation == .panel {
      panelContent?.retarget(to: host)
      if let panel, let toplevel = host?.toplevel, toplevel != panel.cast() {
        gtk_window_set_transient_for(panel.cast(), toplevel)
      }
    }
  }

  private func makePopoverBody(_ content: SionGtkPaletteContent) -> UnsafeMutablePointer<GtkWidget>
  {
    let body = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    let header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
    let title = gtk_label_new(definition.title)!
    gtk_widget_add_css_class(title, "heading")
    gtk_widget_set_hexpand(title, 1)
    gtk_label_set_xalign(title.opaque, 0)
    let detach = gtk_button_new_from_icon_name("window-new-symbolic")!
    gtk_widget_add_css_class(detach, "flat")
    gtk_widget_set_tooltip_text(detach, "Open \(definition.title) as a window")
    sion_accessible_set_label(detach.opaque, "Open \(definition.title) as a window")
    Signals.connect(detach.gobject, "clicked") { [weak self] in
      self?.showPanel()
    }
    gtk_box_append(header.cast(), title)
    gtk_box_append(header.cast(), detach)
    gtk_box_append(body.cast(), header)
    gtk_widget_set_size_request(
      content.widget, Int32(definition.contentSize.width), Int32(definition.contentSize.height))
    gtk_box_append(body.cast(), content.widget)
    return body
  }

  private func popoverDidClose() {
    let followUp = popoverFollowUp
    popoverFollowUp = nil

    if let content = popoverContent {
      content.paletteDidDismiss(.popover)
      content.retarget(to: nil)
    }
    popoverContent = nil
    if let popover {
      self.popover = nil
      MainLoop.performOnNextIteration {
        gtk_widget_unparent(popover)
      }
    }
    if presentation == .popover {
      presentation = nil
    }

    if followUp == .showPanel {
      showPanelNow()
    }
  }

  private func showPanelNow() {
    let panel = ensurePanel()
    let content = ensurePanelContent()
    content.retarget(to: host())
    if let toplevel = host()?.toplevel {
      gtk_window_set_transient_for(panel.cast(), toplevel)
    }

    if presentation != .panel {
      content.paletteDidPresent(.panel)
      presentation = .panel
    }
    gtk_window_present(panel.cast())
  }

  private func ensurePanel() -> UnsafeMutablePointer<GtkWidget> {
    if let panel { return panel }

    let panel = adw_window_new()!
    gtk_window_set_title(panel.cast(), definition.title)
    gtk_window_set_default_size(
      panel.cast(), Int32(definition.contentSize.width), Int32(definition.contentSize.height + 46))
    gtk_window_set_hide_on_close(panel.cast(), 1)
    gtk_window_set_destroy_with_parent(panel.cast(), 0)
    Signals.connectVeto(panel.gobject, "close-request") { [weak self] in
      self?.panelWillClose()
      return false
    }
    self.panel = panel
    return panel
  }

  private func ensurePanelContent() -> SionGtkPaletteContent {
    if let panelContent { return panelContent }

    let content = makeContent()
    let panel = ensurePanel()
    let toolbarView = adw_toolbar_view_new()!
    let headerBar = adw_header_bar_new()!
    adw_toolbar_view_add_top_bar(toolbarView.opaque, headerBar)
    gtk_widget_set_size_request(
      content.widget, Int32(definition.minimumContentSize.width),
      Int32(definition.minimumContentSize.height))
    gtk_widget_set_vexpand(content.widget, 1)
    adw_toolbar_view_set_content(toolbarView.opaque, content.widget)
    adw_window_set_content(panel.cast(), toolbarView)
    panelContent = content
    return content
  }

  private func panelWillClose() {
    if presentation == .panel {
      panelContent?.paletteDidDismiss(.panel)
    }
    panelContent?.retarget(to: nil)
    presentation = nil
  }
}

/// Wraps a palette's stack in a vertically scrolling body, which keeps every
/// labelled entry reachable inside a fixed-size palette.
@MainActor
func scrollingPaletteBody(_ stack: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<
  GtkWidget
> {
  let scrolled = gtk_scrolled_window_new()!
  gtk_scrolled_window_set_policy(scrolled.opaque, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
  gtk_scrolled_window_set_child(scrolled.opaque, stack)
  gtk_widget_set_vexpand(scrolled, 1)
  gtk_widget_set_hexpand(scrolled, 1)
  return scrolled
}

enum InspectorMetrics {
  static let spacing: Int32 = 10
  static let inset: Int32 = 14
  static let minimumStrokeWidth = 0.0
  static let maximumStrokeWidth = 12.0
  static let strokeWidthTickCount = 13
}

/// A labelled row: a dim label and a control that takes the remaining width.
@MainActor
func paletteRow(label: String, control: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<
  GtkWidget
> {
  let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, InspectorMetrics.spacing)!
  let labelView = gtk_label_new(label)!
  gtk_widget_add_css_class(labelView, "dim-label")
  gtk_label_set_xalign(labelView.opaque, 0)
  gtk_widget_set_hexpand(control, 1)
  gtk_box_append(row.cast(), labelView)
  gtk_box_append(row.cast(), control)
  return row
}

@MainActor
func paletteStack() -> UnsafeMutablePointer<GtkWidget> {
  let stack = gtk_box_new(GTK_ORIENTATION_VERTICAL, InspectorMetrics.spacing)!
  gtk_widget_set_margin_top(stack, InspectorMetrics.inset)
  gtk_widget_set_margin_bottom(stack, InspectorMetrics.inset)
  gtk_widget_set_margin_start(stack, InspectorMetrics.inset)
  gtk_widget_set_margin_end(stack, InspectorMetrics.inset)
  return stack
}

@MainActor
func removeAllChildren(of box: UnsafeMutablePointer<GtkWidget>) {
  while let child = gtk_widget_get_first_child(box) {
    gtk_box_remove(box.cast(), child)
  }
}
