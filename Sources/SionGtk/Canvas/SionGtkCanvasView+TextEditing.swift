import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// Inline text editing: a `GtkTextView` placed over the edited element, with
/// the same begin/update/checkpoint/commit/cancel contract as the AppKit field
/// editor.
extension SionGtkCanvasView {
  package func beginTextEditing(_ id: ElementID) {
    commitTextEditing()

    guard let element = editorController.document.scene.element(withID: id),
      element.lockState == .editable,
      let text = element.editableText
    else {
      return
    }

    do {
      try editorController.beginTextEdit(on: id)
    } catch {
      return
    }

    let editor = SionGtkInlineTextEditor(
      text: text,
      style: element.textStyle ?? .standaloneDefault,
      paperColor: inlineEditorPaperColor(for: element),
      magnification: magnification
    )
    editor.onChange = { [weak self] text in
      guard let self, let id = self.editedElementID else { return }
      do {
        try self.editorController.updateTextEdit(text, on: id)
      } catch {
        self.creationFailureFeedback()
      }
      self.updateTextEditorFrame()
    }
    editor.onFocusLost = { [weak self] in
      self?.commitTextEditing()
    }
    editor.onEscape = { [weak self] in
      self?.cancelInteraction()
    }
    gtk_fixed_put(contentLayer.cast(), editor.widget, 0, 0)
    textEditor = editor
    editedElementID = id
    updateTextEditorFrame()
    queueRedraw()
    editor.focusAndSelectAll()
  }

  func commitTextEditing() {
    finishTextEditing(.commit)
  }

  func finishTextEditing(_ disposition: TextEditingDisposition) {
    guard let editor = textEditor, let id = editedElementID else { return }

    let restoresCanvasFocus = editor.hasFocus
    editor.detachHandlers()

    switch disposition {
    case .commit:
      do {
        try editorController.updateTextEdit(editor.text, on: id)
        try editorController.endTextEdit()
      } catch {
        editorController.cancelTextEdit()
        creationFailureFeedback()
      }
    case .discard:
      editorController.cancelTextEdit()
    }

    textEditor = nil
    editedElementID = nil
    gtk_fixed_remove(contentLayer.cast(), editor.widget)
    queueRedraw()

    // Revert removes the editor without another widget requesting focus.
    if restoresCanvasFocus {
      grabFocus()
    }
  }

  /// The element's frame, or a label-sized box on a connector's route.
  func textEditingFrame(for element: SceneElement) -> SionRect {
    guard let connector = element.content.connector,
      let route = editorController.connectorRoute(for: element)
    else {
      return element.geometry.frame.standardized
    }

    return connectorLabelFrame(route: route, position: connector.labelPosition)
  }

  func updateTextEditorFrame() {
    guard let textEditor, let id = editedElementID,
      let element = editorController.document.scene.element(withID: id)
    else {
      return
    }

    let frame = widgetRect(for: textEditingFrame(for: element).expanded(by: 2))
    gtk_fixed_move(contentLayer.cast(), textEditor.widget, frame.minX, frame.minY)
    textEditor.setSize(width: frame.width, height: frame.height)
    // A fill edited from the inspector while the editor is open changes the
    // surface the text is being written on.
    textEditor.update(
      paperColor: inlineEditorPaperColor(for: element), magnification: magnification)
  }

  /// The inline editor mirrors the surface the element is drawn on, so the
  /// document's own ink keeps the contrast it has on the canvas: a shape's
  /// label sits on its fill, everything else on the page. A surface that
  /// would swallow the ink is replaced, never dimmed.
  func inlineEditorPaperColor(for element: SceneElement) -> SionColor {
    let backdrop: SionColor
    if case .shape = element.content, case .solid(let fill) = element.style.fill {
      backdrop = fill
    } else {
      backdrop = editorController.document.scene.canvas.background
    }

    return SionPaperColor.paper(backdrop, ink: element.textStyle?.color ?? .primaryInk)
  }
}

/// The text view the canvas hosts while an element's text is being edited.
@MainActor
final class SionGtkInlineTextEditor {
  let widget: UnsafeMutablePointer<GtkWidget>
  private let textView: UnsafeMutablePointer<GtkWidget>
  private let buffer: UnsafeMutablePointer<GtkTextBuffer>
  private let style: TextStyle
  private let cssProvider: UnsafeMutablePointer<GtkCssProvider>
  private let cssClass: String
  private var paperColor: SionColor
  private var magnification: Double
  private var frameHeight = 0.0
  private var handlersDetached = false

  var onChange: (@MainActor (String) -> Void)?
  var onFocusLost: (@MainActor () -> Void)?
  var onEscape: (@MainActor () -> Void)?

  nonisolated(unsafe) private static var nextIdentifier = 0

  init(text: String, style: TextStyle, paperColor: SionColor, magnification: Double) {
    self.style = style
    self.paperColor = paperColor
    self.magnification = magnification
    Self.nextIdentifier += 1
    cssClass = "sion-inline-editor-\(Self.nextIdentifier)"

    textView = gtk_text_view_new()!
    buffer = gtk_text_view_get_buffer(textView.cast())!
    gtk_text_buffer_set_enable_undo(buffer, 1)
    gtk_text_buffer_set_text(buffer, text, -1)
    gtk_text_view_set_wrap_mode(textView.cast(), GTK_WRAP_WORD_CHAR)
    gtk_text_view_set_accepts_tab(textView.cast(), 0)
    gtk_widget_add_css_class(textView, cssClass)
    sion_accessible_set_label(textView.opaque, "Edit element text")
    switch style.horizontalAlignment {
    case .leading: gtk_text_view_set_justification(textView.cast(), GTK_JUSTIFY_LEFT)
    case .center: gtk_text_view_set_justification(textView.cast(), GTK_JUSTIFY_CENTER)
    case .trailing: gtk_text_view_set_justification(textView.cast(), GTK_JUSTIFY_RIGHT)
    case .justified: gtk_text_view_set_justification(textView.cast(), GTK_JUSTIFY_FILL)
    }

    widget = gtk_scrolled_window_new()!
    gtk_scrolled_window_set_policy(widget.opaque, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
    gtk_scrolled_window_set_has_frame(widget.opaque, 1)
    gtk_scrolled_window_set_child(widget.opaque, textView)
    gtk_widget_add_css_class(widget, cssClass)

    cssProvider = gtk_css_provider_new()!
    if let display = gdk_display_get_default() {
      gtk_style_context_add_provider_for_display(
        display, cssProvider.opaque, UInt32(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
    }
    applyStyle()

    Signals.connect(buffer.gobject, "changed") { [weak self] in
      guard let self, !self.handlersDetached else { return }
      self.applyVerticalAlignment()
      self.onChange?(self.text)
    }
    let focus = gtk_event_controller_focus_new()!
    Signals.connect(focus.gobject, "leave") { [weak self] in
      guard let self, !self.handlersDetached else { return }
      self.onFocusLost?()
    }
    gtk_widget_add_controller(textView, focus)
    let key = gtk_event_controller_key_new()!
    gtk_event_controller_set_propagation_phase(key, GTK_PHASE_CAPTURE)
    Signals.connectKey(key.gobject, "key-pressed") { [weak self] keyval, _, _ in
      guard let self, !self.handlersDetached, keyval == UInt32(GDK_KEY_Escape) else { return false }
      self.onEscape?()
      return true
    }
    gtk_widget_add_controller(textView, key)
  }

  deinit {
    if let display = gdk_display_get_default() {
      gtk_style_context_remove_provider_for_display(display, cssProvider.opaque)
    }
    g_object_unref(cssProvider.gobject)
  }

  var text: String {
    var start = GtkTextIter()
    var end = GtkTextIter()
    gtk_text_buffer_get_bounds(buffer, &start, &end)
    return String(takingOwnershipOf: gtk_text_buffer_get_text(buffer, &start, &end, 1)) ?? ""
  }

  var hasFocus: Bool {
    gtk_widget_has_focus(textView) != 0
  }

  func focusAndSelectAll() {
    gtk_widget_grab_focus(textView)
    var start = GtkTextIter()
    var end = GtkTextIter()
    gtk_text_buffer_get_bounds(buffer, &start, &end)
    gtk_text_buffer_select_range(buffer, &start, &end)
  }

  /// Stops reporting changes once the canvas has decided the editor's fate.
  func detachHandlers() {
    handlersDetached = true
  }

  func setSize(width: Double, height: Double) {
    frameHeight = height
    gtk_widget_set_size_request(
      widget, Int32(max(1, width.rounded())), Int32(max(1, height.rounded())))
    applyVerticalAlignment()
  }

  func update(paperColor: SionColor, magnification: Double) {
    guard paperColor != self.paperColor || magnification != self.magnification else { return }
    self.paperColor = paperColor
    self.magnification = magnification
    applyStyle()
  }

  /// The editor is a separate widget outside the zoomed drawing, so its font
  /// and insets scale with the magnification by hand.
  private func applyStyle() {
    let size =
      (style.font.size.isFinite && style.font.size > 0
        ? style.font.size : CanvasMetrics.defaultFontSize)
      * magnification
    let family: String
    switch style.font.family {
    case .system: family = SionGtkFonts.systemFamily
    case .named(let name): family = name
    }
    let weight: Int
    switch style.font.weight {
    case .light: weight = 300
    case .regular: weight = 400
    case .medium: weight = 500
    case .semibold: weight = 600
    case .bold: weight = 700
    }
    let ink = style.color
    let css = """
      .\(cssClass), .\(cssClass) text {
        font-family: "\(family)";
        font-size: \(size)px;
        font-weight: \(weight);
        color: \(cssColor(ink));
        caret-color: \(cssColor(ink));
        background-color: \(cssColor(paperColor));
      }
      .\(cssClass) text selection {
        background-color: \(cssColor(CanvasColors.selectedTextBackground));
        color: \(cssColor(ink));
      }
      """
    gtk_css_provider_load_from_string(cssProvider, css)

    gtk_text_view_set_left_margin(
      textView.cast(), Int32((finiteNonnegative(style.insets.leading) * magnification).rounded()))
    gtk_text_view_set_right_margin(
      textView.cast(), Int32((finiteNonnegative(style.insets.trailing) * magnification).rounded()))
    gtk_text_view_set_pixels_below_lines(
      textView.cast(), Int32((finiteNonnegative(style.lineSpacing) * magnification).rounded()))
    applyVerticalAlignment()
  }

  /// Centred and bottom-aligned text moves down as the frame allows.
  private func applyVerticalAlignment() {
    let topInset = finiteNonnegative(style.insets.top) * magnification
    let bottomInset = finiteNonnegative(style.insets.bottom) * magnification
    let contentHeight = measuredContentHeight()
    let verticalInset: Double
    switch style.verticalAlignment {
    case .top:
      verticalInset = topInset
    case .center:
      verticalInset = max(topInset, (frameHeight - contentHeight) / 2)
    case .bottom:
      verticalInset = max(topInset, frameHeight - contentHeight - bottomInset)
    }
    gtk_text_view_set_top_margin(textView.cast(), Int32(verticalInset.rounded()))
  }

  private func measuredContentHeight() -> Double {
    guard let context = gtk_widget_get_pango_context(textView),
      let layout = pango_layout_new(context)
    else {
      return 0
    }
    defer { g_object_unref(layout.gobject) }
    pango_layout_set_text(layout, text, -1)
    let description = SionGtkFonts.description(for: style)
    pango_font_description_set_absolute_size(
      description, Double(pango_font_description_get_size(description)) * magnification)
    pango_layout_set_font_description(layout, description)
    pango_font_description_free(description)
    let width = Double(gtk_widget_get_width(textView))
    if width > 0 {
      pango_layout_set_width(layout, Int32(width * Double(PANGO_SCALE)))
    }
    pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
    var inkRect = PangoRectangle()
    var logicalRect = PangoRectangle()
    pango_layout_get_pixel_extents(layout, &inkRect, &logicalRect)
    return Double(logicalRect.height)
  }

  private func cssColor(_ color: SionColor) -> String {
    let red = Int((clampedUnit(color.red) * 255).rounded())
    let green = Int((clampedUnit(color.green) * 255).rounded())
    let blue = Int((clampedUnit(color.blue) * 255).rounded())
    return "rgba(\(red), \(green), \(blue), \(clampedUnit(color.alpha)))"
  }
}
