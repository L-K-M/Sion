import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// The Library palette: the built-in shapes first, then whatever the document
/// and the person have put by for reuse. Mirrors `LibraryPaletteController`.
@MainActor
final class SionGtkLibraryPalette: SionGtkPaletteContent {
  /// Which library an item belongs to. Document items travel in the archive
  /// and undo with it; global ones belong to the person, not the file.
  enum Scope: Int, CaseIterable {
    case document
    case global

    var sectionTitle: String {
      switch self {
      case .document: "This Document"
      case .global: "All Documents"
      }
    }
  }

  struct ItemReference: Equatable {
    let scope: Scope
    let id: String
  }

  enum LibraryShape: Int, CaseIterable {
    case rectangle
    case roundedRectangle
    case ellipse
    case diamond
    case triangle
    case hexagon
    case capsule
    case cylinder

    var title: String {
      switch self {
      case .rectangle: "Rectangle"
      case .roundedRectangle: "Rounded Rectangle"
      case .ellipse: "Ellipse"
      case .diamond: "Diamond"
      case .triangle: "Triangle"
      case .hexagon: "Hexagon"
      case .capsule: "Capsule"
      case .cylinder: "Cylinder"
      }
    }

    var kind: ShapeKind {
      switch self {
      case .rectangle: .rectangle
      case .roundedRectangle: .roundedRectangle(radius: SceneElementDefaults.cornerRadius)
      case .ellipse: .ellipse
      case .diamond: .diamond
      case .triangle: .triangle
      case .hexagon: .hexagon
      case .capsule: .capsule
      case .cylinder: .cylinder
      }
    }
  }

  let widget: UnsafeMutablePointer<GtkWidget>

  private let globalLibrary: SionGlobalLibrary
  private let stack = paletteStack()
  private let storedItems = gtk_box_new(GTK_ORIENTATION_VERTICAL, InspectorMetrics.spacing)!
  private weak var host: SionGtkPaletteHost?
  private var observerID: UUID?
  private var globalObserver: NSObjectProtocol?
  private var displayedDocumentStorage: PortableValue?
  private var hasRenderedItems = false
  private var builtInButtons: [UnsafeMutablePointer<GtkWidget>] = []
  private var itemButtons: [UnsafeMutablePointer<GtkWidget>] = []

  init(globalLibrary: SionGlobalLibrary) {
    self.globalLibrary = globalLibrary
    widget = scrollingPaletteBody(stack)

    for shape in LibraryShape.allCases {
      let button = libraryButton(shape.title, glyph: .shape(shape.kind))
      Signals.connect(button.gobject, "clicked") { [weak self] in
        self?.addShape(shape)
      }
      gtk_box_append(stack.cast(), button)
      builtInButtons.append(button)
    }
    let textButton = libraryButton("Text", glyph: .text)
    Signals.connect(textButton.gobject, "clicked") { [weak self] in
      self?.addText()
    }
    gtk_box_append(stack.cast(), textButton)
    builtInButtons.append(textButton)
    gtk_box_append(stack.cast(), storedItems)

    globalObserver = NotificationCenter.default.addObserver(
      forName: SionGlobalLibrary.didChangeNotification, object: nil, queue: nil
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshItems(force: true) }
    }
    refreshItems(force: true)
  }

  deinit {
    if let globalObserver {
      NotificationCenter.default.removeObserver(globalObserver)
    }
  }

  func retarget(to host: SionGtkPaletteHost?) {
    if let observerID {
      self.host?.paletteEditorController.removeObserver(observerID)
    }

    self.host = host
    observerID = host?.paletteEditorController.observeChanges { [weak self] in
      self?.refreshItems()
    }
    refreshItems(force: true)
  }

  /// Places a stored item at the middle of what the document is showing. This
  /// is where an entry's bytes are read: a row is drawn without opening it.
  func insert(_ reference: ItemReference) {
    guard let host else { return }

    do {
      let bytes = try payload(for: reference)
      _ = try host.paletteEditorController.insertSelectionPayload(
        bytes, at: host.canvasVisibleCenter, undoName: LibraryCopy.insertUndoName)
    } catch {
      NSLog("Library insertion failed: %@", String(describing: error))
      report(.itemUnavailable)
    }
  }

  func rename(_ reference: ItemReference, to name: String) {
    applyUpdate(on: reference) { editor in
      try editor.renameDocumentLibraryItem(id: reference.id, to: name)
    } global: { library in
      try library.rename(id: reference.id, to: name)
    }
  }

  func remove(_ reference: ItemReference) {
    applyUpdate(on: reference) { editor in
      try editor.removeDocumentLibraryItem(id: reference.id)
    } global: { library in
      try library.remove(id: reference.id)
    }
  }

  func entry(for reference: ItemReference) -> SceneLibraryEntry? {
    switch reference.scope {
    case .document:
      host?.paletteEditorController.documentLibrary.entry(id: reference.id)
    case .global:
      globalLibrary.entry(id: reference.id)
    }
  }

  var displayedItemCount: Int { itemButtons.count }

  private func payload(for reference: ItemReference) throws -> Data {
    switch reference.scope {
    case .document:
      guard let item = host?.paletteEditorController.documentLibrary.item(id: reference.id) else {
        throw SceneLibraryError.itemNotFound(reference.id)
      }
      return item.payload
    case .global:
      return try globalLibrary.payload(id: reference.id)
    }
  }

  func addShape(_ shape: LibraryShape) {
    guard let host else { return }

    _ = try? host.paletteEditorController.insertShape(
      centeredAt: host.canvasVisibleCenter, kind: shape.kind)
  }

  func addText() {
    guard let host,
      let id = try? host.paletteEditorController.insertText(
        "Text", centeredAt: host.canvasVisibleCenter)
    else {
      return
    }

    host.beginTextEditing(id)
  }

  /// One place for the two stores, so the callers above stay symmetrical
  /// even though only one of them is undoable.
  private func applyUpdate(
    on reference: ItemReference,
    document: (SionEditorController) throws -> Void,
    global: (SionGlobalLibrary) throws -> Void
  ) {
    do {
      switch reference.scope {
      case .document:
        guard let editor = host?.paletteEditorController else {
          report(.unavailable)
          break
        }
        try document(editor)
      case .global:
        try global(globalLibrary)
      }
    } catch {
      NSLog("Library update failed: %@", String(describing: error))
      report(SionEditorFeedback.LibraryFailure(error))
    }

    refreshItems(force: true)
  }

  /// Rebuilt only when a library actually changed: the stored value is
  /// compared before it is decoded, because a drag posts a change per event.
  private func refreshItems(force: Bool = false) {
    let storage = host?.paletteEditorController.documentLibraryStorage
    guard force || !hasRenderedItems || storage != displayedDocumentStorage else { return }

    displayedDocumentStorage = storage
    hasRenderedItems = true
    removeAllChildren(of: storedItems)
    itemButtons.removeAll()

    let documentEntries = host?.paletteEditorController.documentLibrary.entries ?? []
    let items =
      documentEntries.map { (ItemReference(scope: .document, id: $0.id), $0.name) }
      + globalLibrary.entries.map { (ItemReference(scope: .global, id: $0.id), $0.name) }

    for scope in Scope.allCases {
      let scoped = items.filter { $0.0.scope == scope }
      guard !scoped.isEmpty else { continue }

      let header = gtk_label_new(scope.sectionTitle)!
      gtk_widget_add_css_class(header, "caption-heading")
      gtk_widget_add_css_class(header, "dim-label")
      gtk_label_set_xalign(header.opaque, 0)
      gtk_box_append(storedItems.cast(), header)
      for (reference, name) in scoped {
        let button = itemButton(reference, name: name)
        gtk_box_append(storedItems.cast(), button)
        itemButtons.append(button)
      }
    }

    updateEnabledState()
  }

  /// Every row puts something into a drawing, so with no front document
  /// there is nothing any of them could do.
  private func updateEnabledState() {
    for button in builtInButtons + itemButtons {
      gtk_widget_set_sensitive(button, host != nil ? 1 : 0)
    }
  }

  private func report(_ failure: SionEditorFeedback.LibraryFailure) {
    guard let host else {
      gdk_display_beep(gdk_display_get_default())
      return
    }

    host.presentEditorFeedback(.show(.libraryCommandFailed(failure)))
  }

  private func itemButton(_ reference: ItemReference, name: String) -> UnsafeMutablePointer<
    GtkWidget
  > {
    let button = libraryButton(name, glyph: .storedItem)
    gtk_widget_set_tooltip_text(button, "\(name) — \(reference.scope.sectionTitle)")
    Signals.connect(button.gobject, "clicked") { [weak self] in
      self?.insert(reference)
    }

    // A right click offers rename and removal, as the macOS row's menu does.
    let secondary = gtk_gesture_click_new()!
    gtk_gesture_single_set_button(secondary, UInt32(GDK_BUTTON_SECONDARY))
    Signals.connect(secondary.gobject, "pressed") { [weak self] _, x, y in
      self?.showItemMenu(for: reference, on: button, x: x, y: y)
    }
    gtk_widget_add_controller(button, secondary)
    return button
  }

  private func showItemMenu(
    for reference: ItemReference, on button: UnsafeMutablePointer<GtkWidget>, x: Double, y: Double
  ) {
    let popover = gtk_popover_new()!
    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    for (title, action) in [
      (LibraryCopy.renameTitle, { [weak self] in self?.promptForName(reference) }),
      (LibraryCopy.removeTitle, { [weak self] in self?.remove(reference) }),
    ] as [(String, @MainActor () -> Void)] {
      let item = gtk_button_new_with_label(title)!
      gtk_widget_add_css_class(item, "flat")
      if let label = gtk_button_get_child(item.cast()) {
        gtk_label_set_xalign(label.opaque, 0)
      }
      Signals.connect(item.gobject, "clicked") {
        gtk_popover_popdown(popover.cast())
        action()
      }
      gtk_box_append(box.cast(), item)
    }
    gtk_popover_set_child(popover.cast(), box)
    gtk_widget_set_parent(popover, button)
    var rectangle = GdkRectangle(x: Int32(x), y: Int32(y), width: 1, height: 1)
    gtk_popover_set_pointing_to(popover.cast(), &rectangle)
    Signals.connect(popover.gobject, "closed") {
      MainLoop.performOnNextIteration { gtk_widget_unparent(popover) }
    }
    gtk_popover_popup(popover.cast())
  }

  /// A one-field prompt; the palette it is asked from may be a floating window.
  private func promptForName(_ reference: ItemReference) {
    guard let entry = entry(for: reference) else { return }

    let field = gtk_entry_new()!
    gtk_editable_set_text(field.opaque, entry.name)
    let dialog = adw_alert_dialog_new(LibraryCopy.renamePrompt, nil)!
    adw_alert_dialog_set_extra_child(dialog.cast(), field)
    adw_alert_dialog_add_response(dialog.cast(), "cancel", LibraryCopy.cancelTitle)
    adw_alert_dialog_add_response(dialog.cast(), "rename", LibraryCopy.renameConfirmTitle)
    adw_alert_dialog_set_response_appearance(dialog.cast(), "rename", ADW_RESPONSE_SUGGESTED)
    adw_alert_dialog_set_default_response(dialog.cast(), "rename")
    adw_alert_dialog_set_close_response(dialog.cast(), "cancel")
    Signals.connect(dialog.gobject, "response") { [weak self] response in
      let id = response.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
      guard id == "rename", let name = String(gtkString: gtk_editable_get_text(field.opaque)) else {
        return
      }
      self?.rename(reference, to: name)
    }
    adw_dialog_present(dialog, widget)
  }

  private enum Glyph {
    case shape(ShapeKind)
    case text
    case storedItem
  }

  private func libraryButton(_ title: String, glyph: Glyph) -> UnsafeMutablePointer<GtkWidget> {
    let button = gtk_button_new()!
    gtk_widget_add_css_class(button, "flat")
    let content = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
    switch glyph {
    case .shape(let kind):
      gtk_box_append(content.cast(), SionGtkShapeGlyph.makeWidget(kind))
    case .text:
      gtk_box_append(content.cast(), SionGtkToolGlyph.makeWidget(for: .text))
    case .storedItem:
      gtk_box_append(content.cast(), gtk_image_new_from_icon_name("edit-copy-symbolic"))
    }
    let label = gtk_label_new(title)!
    gtk_label_set_xalign(label.opaque, 0)
    gtk_label_set_ellipsize(label.opaque, PANGO_ELLIPSIZE_END)
    gtk_widget_set_hexpand(label, 1)
    gtk_box_append(content.cast(), label)
    gtk_button_set_child(button.cast(), content)
    sion_accessible_set_label(button.opaque, title)
    return button
  }
}

/// Draws a shape outline in the widget's foreground colour for the library.
enum SionGtkShapeGlyph {
  @MainActor
  static func makeWidget(_ kind: ShapeKind) -> UnsafeMutablePointer<GtkWidget> {
    let area = gtk_drawing_area_new()!
    gtk_drawing_area_set_content_width(area.cast(), 16)
    gtk_drawing_area_set_content_height(area.cast(), 16)
    gtk_widget_set_valign(area, GTK_ALIGN_CENTER)
    let box = SignalBox<ShapeKind>(kind)
    let drawFunction: GtkDrawingAreaDrawFunc = { area, context, width, height, data in
      guard let context, let data else { return }
      let kind = Unmanaged<SignalBox<ShapeKind>>.fromOpaque(data).takeUnretainedValue().handler
      var color = GdkRGBA()
      if let area {
        gtk_widget_get_color(area.cast(), &color)
      }
      cairo_set_source_rgba(
        context, Double(color.red), Double(color.green), Double(color.blue), Double(color.alpha))
      SionGtkShapeGlyph.draw(kind, in: context, width: Double(width), height: Double(height))
    }
    gtk_drawing_area_set_draw_func(
      area.cast(), drawFunction, Unmanaged.passRetained(box).toOpaque(),
      { data in
        guard let data else { return }
        Unmanaged<AnyObject>.fromOpaque(data).release()
      })
    return area
  }

  nonisolated static func draw(
    _ kind: ShapeKind, in context: OpaquePointer, width: Double, height: Double
  ) {
    let frame = SionRect(x: 1.75, y: 2.75, width: width - 3.5, height: height - 5.5)
    cairo_set_line_width(context, 1.5)
    cairo_set_line_join(context, CAIRO_LINE_JOIN_ROUND)
    SionGtkShapePaths.add(kind, frame: frame, to: context)
    cairo_stroke(context)
  }
}

/// Shape outlines shared by glyphs; the canvas has the same geometry inline.
enum SionGtkShapePaths {
  nonisolated static func add(_ kind: ShapeKind, frame rect: SionRect, to context: OpaquePointer) {
    switch kind {
    case .rectangle:
      cairo_rectangle(context, rect.minX, rect.minY, rect.width, rect.height)
    case .roundedRectangle(let radius):
      rounded(context, rect, radius: min(radius, rect.width / 2, rect.height / 2))
    case .capsule:
      rounded(context, rect, radius: min(rect.width, rect.height) / 2)
    case .ellipse:
      cairo_save(context)
      cairo_translate(context, rect.center.x, rect.center.y)
      cairo_scale(context, rect.width / 2, rect.height / 2)
      cairo_new_sub_path(context)
      cairo_arc(context, 0, 0, 1, 0, 2 * .pi)
      cairo_restore(context)
    case .diamond:
      polygon(
        context,
        [
          SionPoint(x: rect.center.x, y: rect.minY), SionPoint(x: rect.maxX, y: rect.center.y),
          SionPoint(x: rect.center.x, y: rect.maxY), SionPoint(x: rect.minX, y: rect.center.y),
        ])
    case .triangle:
      polygon(
        context,
        [
          SionPoint(x: rect.center.x, y: rect.minY), SionPoint(x: rect.maxX, y: rect.maxY),
          SionPoint(x: rect.minX, y: rect.maxY),
        ])
    case .hexagon:
      let inset = rect.width * ShapeGeometryDefaults.hexagonInsetFraction
      polygon(
        context,
        [
          SionPoint(x: rect.minX + inset, y: rect.minY),
          SionPoint(x: rect.maxX - inset, y: rect.minY),
          SionPoint(x: rect.maxX, y: rect.center.y), SionPoint(x: rect.maxX - inset, y: rect.maxY),
          SionPoint(x: rect.minX + inset, y: rect.maxY), SionPoint(x: rect.minX, y: rect.center.y),
        ])
    case .cylinder, .custom:
      // The glyph only hints at the shape; a body with an elliptical lid reads
      // as the cylinder.
      let lid = rect.height * 0.28
      cairo_move_to(context, rect.minX, rect.minY + lid / 2)
      cairo_line_to(context, rect.minX, rect.maxY - lid / 2)
      cairo_save(context)
      cairo_translate(context, rect.center.x, rect.maxY - lid / 2)
      cairo_scale(context, rect.width / 2, lid / 2)
      cairo_arc(context, 0, 0, 1, .pi, 2 * .pi)
      cairo_restore(context)
      cairo_line_to(context, rect.maxX, rect.minY + lid / 2)
      cairo_save(context)
      cairo_translate(context, rect.center.x, rect.minY + lid / 2)
      cairo_scale(context, rect.width / 2, lid / 2)
      cairo_arc(context, 0, 0, 1, 0, 2 * .pi)
      cairo_restore(context)
    }
  }

  private nonisolated static func rounded(_ context: OpaquePointer, _ r: SionRect, radius: Double) {
    let clamped = max(0, radius)
    cairo_new_sub_path(context)
    cairo_arc(context, r.maxX - clamped, r.minY + clamped, clamped, -.pi / 2, 0)
    cairo_arc(context, r.maxX - clamped, r.maxY - clamped, clamped, 0, .pi / 2)
    cairo_arc(context, r.minX + clamped, r.maxY - clamped, clamped, .pi / 2, .pi)
    cairo_arc(context, r.minX + clamped, r.minY + clamped, clamped, .pi, 3 * .pi / 2)
    cairo_close_path(context)
  }

  private nonisolated static func polygon(_ context: OpaquePointer, _ points: [SionPoint]) {
    guard let first = points.first else { return }
    cairo_move_to(context, first.x, first.y)
    for point in points.dropFirst() {
      cairo_line_to(context, point.x, point.y)
    }
    cairo_close_path(context)
  }
}

private enum LibraryCopy {
  static let insertUndoName = "Place Library Item"
  static let renameTitle = "Rename…"
  static let removeTitle = "Remove from Library"
  static let renamePrompt = "Rename Library Item"
  static let renameConfirmTitle = "Rename"
  static let cancelTitle = "Cancel"
}
