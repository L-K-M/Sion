import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// The document window: a menu bar, a header bar with the editing tools, zoom
/// controls, and palette buttons, the scrolled canvas, and the feedback banner
/// overlay. It mirrors `SionDocumentWindowController` on macOS and owns the
/// `win.` actions every menu command resolves to.
@MainActor
package final class SionGtkDocumentWindow: SionGtkPaletteHost {
  package let document: SionGtkDocument
  package let canvasView: SionGtkCanvasView
  package let window: UnsafeMutablePointer<GtkWidget>

  /// Called once the window has closed and released its document.
  package var onClose: (@MainActor () -> Void)?
  /// Called when this window becomes the active one.
  package var onBecameActive: (@MainActor () -> Void)?
  /// Rewrites the shared Edit menu's undo and redo titles for this document.
  package var updateUndoTitles: (@MainActor (_ undo: String, _ redo: String) -> Void)?

  private let feedbackPresenter: SionGtkEditorFeedbackPresenter
  private var actions: [SionGtkCommand: OpaquePointer] = [:]
  private var toolButtons: [SionEditorController.Tool: UnsafeMutablePointer<GtkWidget>] = [:]
  private var paletteButtons: [SionGtkPaletteKind: UnsafeMutablePointer<GtkWidget>] = [:]
  private var toolPressCount: Int32 = 1
  private var lastToolActivation: (tool: SionEditorController.Tool, at: Date)?
  private var windowTitle: OpaquePointer?
  private var zoomLabel: UnsafeMutablePointer<GtkWidget>?
  private var observerID: UUID?
  private var undoObservers: [NSObjectProtocol] = []
  private var isSynchronizingTools = false
  private var isInitialZoomPending = true
  private var isClosing = false

  package init(
    document: SionGtkDocument,
    application: UnsafeMutablePointer<GtkApplication>,
    menuModel: UnsafeMutablePointer<GMenuModel>?
  ) {
    self.document = document
    let feedbackPresenter = SionGtkEditorFeedbackPresenter()
    self.feedbackPresenter = feedbackPresenter
    canvasView = SionGtkCanvasView(
      editorController: document.editingController,
      editorFeedback: { feedbackPresenter.handle($0) }
    )
    window = adw_application_window_new(application)!
    gtk_window_set_default_size(
      window.cast(), Int32(WindowMetrics.initialSize.width),
      Int32(WindowMetrics.initialSize.height))
    gtk_window_set_icon_name(window.cast(), "ch.lkmc.Sion")

    document.attach(window: self)
    installActions()
    configureContent(menuModel: menuModel)
    installObservers()
    synchronizeUI()
  }

  // MARK: Palette host

  package var paletteEditorController: SionEditorController {
    document.editingController
  }

  package var canvasVisibleCenter: SionPoint {
    canvasView.visibleCenter
  }

  package var toplevel: UnsafeMutablePointer<GtkWindow>? {
    window.cast()
  }

  package func presentEditorFeedback(_ request: SionEditorFeedbackRequest) {
    feedbackPresenter.handle(request)
  }

  package func beginTextEditing(_ id: ElementID) {
    canvasView.beginTextEditing(id)
  }

  // MARK: Canvas seams the document uses

  package func commitPendingEdits() {
    canvasView.commitPendingEdits()
  }

  package func checkpointPendingEdits() {
    canvasView.checkpointPendingEdits()
  }

  package func discardPendingEdits() {
    canvasView.discardPendingEdits()
  }

  package func renderPreviewPNG() -> Data? {
    canvasView.renderPreviewPNG()
  }

  package var isActive: Bool {
    gtk_window_is_active(window.cast()) != 0
  }

  package func present() {
    gtk_window_present(window.cast())
    canvasView.grabFocus()
  }

  /// Runs the document's close check, then destroys the window if allowed.
  package func requestClose() {
    guard !isClosing else { return }

    document.canClose { [weak self] allowed in
      guard allowed else { return }
      self?.performClose()
    }
  }

  private func performClose() {
    guard !isClosing else { return }
    isClosing = true

    if let observerID {
      document.editingController.removeObserver(observerID)
      self.observerID = nil
    }
    for observer in undoObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    undoObservers.removeAll()
    feedbackPresenter.invalidate()
    canvasView.invalidate()
    document.close()
    onClose?()
    gtk_window_destroy(window.cast())
  }

  // MARK: Commands

  package func isEnabled(_ command: SionGtkCommand) -> Bool {
    if command.isCanvasCommand {
      return canvasView.canPerform(command)
    }
    switch command {
    case .undo: return document.undoManager.canUndo
    case .redo: return document.undoManager.canRedo
    case .revertToSaved: return document.canRevert
    default: return true
    }
  }

  package func perform(_ command: SionGtkCommand) {
    if command.isCanvasCommand {
      canvasView.perform(command)
      synchronizeActions()
      return
    }

    switch command {
    case .undo:
      document.undoManager.undo()
    case .redo:
      document.undoManager.redo()
    case .close:
      requestClose()
    case .save:
      document.save()
    case .saveAs:
      document.saveAs()
    case .revertToSaved:
      document.revertToSaved()
    case .importMermaid:
      document.importMermaid()
    case .exportImage:
      document.exportImage()
    case .exportSVG:
      document.exportSVG()
    case .exportMermaid:
      document.exportMermaid()
    case .pageSetup:
      document.pageSetup()
    case .printDocument:
      document.printDocument()
    case .showInspector:
      presentPalette(.inspector)
    case .showLibrary:
      presentPalette(.library)
    case .showHistory:
      presentPalette(.history)
    case .toggleFullScreen:
      if gtk_window_is_fullscreen(window.cast()) != 0 {
        gtk_window_unfullscreen(window.cast())
      } else {
        gtk_window_fullscreen(window.cast())
      }
    case .minimize:
      gtk_window_minimize(window.cast())
    default:
      break
    }
    synchronizeActions()
  }

  private func installActions() {
    let map = OpaquePointer(window)
    for command in SionGtkCommand.allCases where command.scope == .window {
      let action: OpaquePointer?
      if command.isToggle {
        action = g_simple_action_new_stateful(command.rawValue, nil, g_variant_new_boolean(0))
      } else {
        action = g_simple_action_new(command.rawValue, nil)
      }
      guard let action else { continue }
      Signals.connect(action.gobject, "activate") { [weak self] _ in
        self?.perform(command)
      }
      g_action_map_add_action(map, action)
      actions[command] = action
    }
  }

  /// Enables what applies to the selection and state, and mirrors toggle
  /// states, as `validateMenuItem(_:)` does on macOS.
  package func synchronizeActions() {
    for (command, action) in actions {
      g_simple_action_set_enabled(action, isEnabled(command) ? 1 : 0)
      if command.isToggle, let checked = canvasView.isChecked(command) {
        g_simple_action_set_state(action, g_variant_new_boolean(checked ? 1 : 0))
      }
    }
    if isActive {
      updateUndoTitles?(
        document.undoManager.undoMenuItemTitle, document.undoManager.redoMenuItemTitle)
    }
  }

  // MARK: Content

  private func configureContent(menuModel: UnsafeMutablePointer<GMenuModel>?) {
    let toolbarView = adw_toolbar_view_new()!
    if let menuModel {
      let menuBar = gtk_popover_menu_bar_new_from_model(menuModel)
      adw_toolbar_view_add_top_bar(toolbarView.opaque, menuBar)
    }

    let headerBar = adw_header_bar_new()!
    let title = adw_window_title_new(document.displayName, nil)!
    windowTitle = OpaquePointer(title)
    adw_header_bar_set_title_widget(headerBar.opaque, title)
    adw_header_bar_pack_start(headerBar.opaque, makeToolsControl())
    adw_header_bar_pack_start(headerBar.opaque, makeZoomControl())
    for kind in [SionGtkPaletteKind.history, .library, .inspector] {
      adw_header_bar_pack_end(headerBar.opaque, makePaletteButton(kind))
    }
    adw_toolbar_view_add_top_bar(toolbarView.opaque, headerBar)

    let overlay = gtk_overlay_new()!
    gtk_overlay_set_child(overlay.opaque, canvasView.widget)
    gtk_widget_set_vexpand(canvasView.widget, 1)
    gtk_widget_set_hexpand(canvasView.widget, 1)
    feedbackPresenter.attach(to: overlay)
    adw_toolbar_view_set_content(toolbarView.opaque, overlay)
    adw_application_window_set_content(window.cast(), toolbarView)

    Signals.connectVeto(window.gobject, "close-request") { [weak self] in
      self?.requestClose()
      return true
    }
    Signals.connect(window.gobject, "notify::is-active") { [weak self] _ in
      guard let self, self.isActive else { return }
      self.onBecameActive?()
      self.synchronizeActions()
    }
    Signals.connectResize(canvasView.drawingArea.gobject) { [weak self] _, _ in
      self?.applyInitialZoomIfNeeded()
    }
  }

  private func makeToolsControl() -> UnsafeMutablePointer<GtkWidget> {
    let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    gtk_widget_add_css_class(box, "linked")
    sion_accessible_set_label(box.opaque, "Editing tool")
    var group: UnsafeMutablePointer<GtkWidget>?
    for tool in SionEditorController.Tool.allCases {
      let button = gtk_toggle_button_new()!
      gtk_button_set_child(button.cast(), SionGtkToolGlyph.makeWidget(for: tool))
      if let group {
        gtk_toggle_button_set_group(button.cast(), group.cast())
      } else {
        group = button
      }
      sion_accessible_set_label(button.opaque, tool.title)
      gtk_widget_set_tooltip_text(button, tool.help)

      // The click gesture runs before the button so the click count is known
      // when the button reports the click: one click arms a single use, a
      // double click keeps the tool.
      let press = gtk_gesture_click_new()!
      gtk_event_controller_set_propagation_phase(press, GTK_PHASE_CAPTURE)
      Signals.connect(press.gobject, "pressed") { [weak self] count, _, _ in
        self?.toolPressCount = count
      }
      gtk_widget_add_controller(button, press)

      Signals.connect(button.gobject, "clicked") { [weak self] in
        guard let self, !self.isSynchronizingTools else { return }
        let clickCount = Int(self.toolPressCount)
        self.toolPressCount = 1
        self.selectTool(tool, clickCount: clickCount)
      }
      gtk_box_append(box.cast(), button)
      toolButtons[tool] = button
    }
    return box
  }

  private func makeZoomControl() -> UnsafeMutablePointer<GtkWidget> {
    let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
    let buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    gtk_widget_add_css_class(buttons, "linked")
    sion_accessible_set_label(buttons.opaque, "Canvas zoom")
    for (icon, title, command) in [
      ("zoom-out-symbolic", "Zoom Out", SionGtkCommand.zoomOut),
      ("zoom-fit-best-symbolic", "Zoom to Fit", .zoomToFit),
      ("zoom-in-symbolic", "Zoom In", .zoomIn),
    ] {
      let button = gtk_button_new_from_icon_name(icon)!
      gtk_widget_set_tooltip_text(button, title)
      sion_accessible_set_label(button.opaque, title)
      Signals.connect(button.gobject, "clicked") { [weak self] in
        self?.perform(command)
        self?.canvasView.grabFocus()
      }
      gtk_box_append(buttons.cast(), button)
    }
    gtk_box_append(box.cast(), buttons)

    let label = gtk_label_new(zoomPercentageText)!
    gtk_label_set_width_chars(label.opaque, 5)
    gtk_label_set_xalign(label.opaque, 0)
    gtk_widget_add_css_class(label, "numeric")
    sion_accessible_set_label(label.opaque, "Zoom level")
    gtk_box_append(box.cast(), label)
    zoomLabel = label
    canvasView.onMagnificationChange = { [weak self] _ in
      self?.synchronizeZoomPercentage()
    }
    return box
  }

  private func makePaletteButton(_ kind: SionGtkPaletteKind) -> UnsafeMutablePointer<GtkWidget> {
    let icon: String
    switch kind {
    case .inspector: icon = "document-properties-symbolic"
    case .library: icon = "view-grid-symbolic"
    case .history: icon = "document-open-recent-symbolic"
    }
    let button = gtk_button_new_from_icon_name(icon)!
    gtk_widget_set_tooltip_text(button, kind.title)
    sion_accessible_set_label(button.opaque, kind.title)
    Signals.connect(button.gobject, "clicked") { [weak self] in
      self?.presentPalette(kind)
    }
    paletteButtons[kind] = button
    return button
  }

  private func presentPalette(_ kind: SionGtkPaletteKind) {
    SionGtkPaletteCenter.shared.present(kind, relativeTo: paletteButtons[kind])
  }

  // MARK: Tools

  /// One click arms a single use; the second click upgrades the same tool in
  /// place. A keyboard press carries no click count, so choosing a tool that
  /// is still armed again counts as the double click.
  package func selectTool(_ tool: SionEditorController.Tool, clickCount: Int) {
    let now = Date()
    let keepsToolActive = clickCount >= 2 || isRepeatActivation(of: tool, at: now)
    lastToolActivation = (tool, now)
    document.editingController.setTool(tool, persistence: keepsToolActive ? .sticky : .oneShot)
    canvasView.grabFocus()
  }

  private func isRepeatActivation(of tool: SionEditorController.Tool, at moment: Date) -> Bool {
    guard let lastToolActivation,
      lastToolActivation.tool == tool,
      document.editingController.tool == tool
    else {
      return false
    }

    return moment.timeIntervalSince(lastToolActivation.at) <= Self.doubleClickInterval
  }

  private static var doubleClickInterval: TimeInterval {
    guard let settings = gtk_settings_get_default() else { return 0.4 }
    let milliseconds = sion_object_get_int(settings.gobject, "gtk-double-click-time")
    return milliseconds > 0 ? Double(milliseconds) / 1_000 : 0.4
  }

  /// The active tool advertises the mode it is in; the others advertise the
  /// gesture that makes a tool stay active, which is the only hidden one.
  private func toolTip(for tool: SionEditorController.Tool) -> String {
    let controller = document.editingController
    guard tool != .select else { return tool.help }
    guard tool == controller.tool else {
      return "\(tool.help). Double-click to keep the tool active"
    }

    return "\(tool.help). \(controller.toolPersistence.summary)"
  }

  package var toolAccessibilityValue: String {
    let controller = document.editingController
    let tool = controller.tool
    guard tool != .select else { return tool.title }

    return "\(tool.title). \(controller.toolPersistence.summary)"
  }

  // MARK: Synchronisation

  private func installObservers() {
    observerID = document.editingController.observeChanges { [weak self] in
      self?.synchronizeUI()
    }
    document.onStateChange = { [weak self] in
      self?.synchronizeTitle()
      self?.synchronizeActions()
    }
    let center = NotificationCenter.default
    for name in [
      SionUndoManager.didUndoChangeNotification, SionUndoManager.didRedoChangeNotification,
      SionUndoManager.didCloseUndoGroupNotification,
    ] {
      undoObservers.append(
        center.addObserver(forName: name, object: document.undoManager, queue: nil) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.synchronizeActions() }
        })
    }
    if let display = gdk_display_get_default(), let clipboard = gdk_display_get_clipboard(display) {
      Signals.connect(clipboard.gobject, "changed") { [weak self] in
        self?.synchronizeActions()
      }
    }
  }

  private func synchronizeUI() {
    let controller = document.editingController
    isSynchronizingTools = true
    for (tool, button) in toolButtons {
      let isActive = tool == controller.tool
      if (gtk_toggle_button_get_active(button.cast()) != 0) != isActive {
        gtk_toggle_button_set_active(button.cast(), isActive ? 1 : 0)
      }
      gtk_widget_set_tooltip_text(button, toolTip(for: tool))
    }
    isSynchronizingTools = false
    if let toolsBox = toolButtons[.select].flatMap({ gtk_widget_get_parent($0) }) {
      sion_accessible_set_description(toolsBox.opaque, toolAccessibilityValue)
    }
    synchronizeTitle()
    synchronizeActions()
  }

  private func synchronizeTitle() {
    gtk_window_set_title(window.cast(), document.displayName)
    guard let windowTitle else { return }
    adw_window_title_set_title(windowTitle, document.displayName)
    adw_window_title_set_subtitle(windowTitle, document.isDocumentEdited ? "Edited" : "")
  }

  private var zoomPercentageText: String {
    "\(Int((canvasView.magnification * 100).rounded()))%"
  }

  private func synchronizeZoomPercentage() {
    guard let zoomLabel else { return }
    let text = zoomPercentageText
    guard String(gtkString: gtk_label_get_text(zoomLabel.opaque)) != text else { return }
    gtk_label_set_text(zoomLabel.opaque, text)
  }

  private func applyInitialZoomIfNeeded() {
    guard isInitialZoomPending else { return }
    guard gtk_widget_get_width(canvasView.drawingArea) > 0,
      gtk_widget_get_height(canvasView.drawingArea) > 0
    else {
      return
    }

    isInitialZoomPending = false
    guard !document.editingController.document.scene.elements.isEmpty else { return }

    canvasView.zoomToFit()
  }

  private enum WindowMetrics {
    static let initialSize = SionSize(width: 1_180, height: 780)
  }
}
