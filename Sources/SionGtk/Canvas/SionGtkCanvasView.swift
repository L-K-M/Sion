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
/// and event-to-model conversion share one source of truth. The model is
/// top-left/y-down like GTK, so the only conversion is the canvas origin and
/// the magnification.
@MainActor
package final class SionGtkCanvasView {
  package static let minimumMagnification = 0.1
  package static let maximumMagnification = 8.0
  package static let zoomStep = 1.2
  package static let fitInsetFactor = 0.88

  enum TextEditingDisposition {
    case commit
    case discard
  }

  enum Creation {
    case shape(ShapeKind)
    case text

    var defaultSize: SionSize {
      switch self {
      case .shape(let kind):
        SionCreationDefaults.shapeSize(for: kind)
      case .text:
        SionCreationDefaults.textSize
      }
    }
  }

  enum Drag {
    /// A move tracks the gesture's start rather than the last frame, so the
    /// offset a snap contributes is not folded into the next delta.
    case move(startPoint: SionPoint, startBounds: SionRect, appliedOffset: SionVector)
    case resize(
      elementID: ElementID,
      handle: ResizeHandle,
      startFrame: SionRect,
      rotationRadians: Double,
      preservesAspectRatio: Bool
    )
    case rotate(
      elementID: ElementID, center: SionPoint, startPoint: SionPoint, startRotation: Double)
    case cornerRadius(
      elementID: ElementID,
      frame: SionRect,
      rotationRadians: Double,
      startPoint: SionPoint,
      startRadius: Double
    )
    case create(creation: Creation, start: SionPoint, current: SionPoint)
    case connector(sourceID: ElementID?, start: SionPoint, current: SionPoint)
    case marquee(origin: SionPoint, current: SionPoint)

    var requiresEditorGesture: Bool {
      switch self {
      case .move, .resize, .rotate, .cornerRadius:
        true
      case .create, .connector, .marquee:
        false
      }
    }
  }

  /// The modifier keys that change a gesture's meaning.
  struct Modifiers: OptionSet {
    let rawValue: Int

    static let shift = Modifiers(rawValue: 1 << 0)

    init(rawValue: Int) {
      self.rawValue = rawValue
    }

    init(_ state: GdkModifierType) {
      self = state.rawValue & GDK_SHIFT_MASK.rawValue != 0 ? .shift : []
    }
  }

  package let editorController: SionEditorController

  /// The widget a window embeds: the scrolled container around the canvas.
  package let widget: UnsafeMutablePointer<GtkWidget>
  /// The drawing area itself, for focus and popover anchoring.
  package let drawingArea: UnsafeMutablePointer<GtkWidget>
  /// The fixed-position layer that holds the drawing area and the text editor.
  let contentLayer: UnsafeMutablePointer<GtkWidget>

  /// Reports every zoom change so the window can show the percentage.
  package var onMagnificationChange: (@MainActor (Double) -> Void)?

  package private(set) var magnification = 1.0

  let connectorRouteProvider: SceneRenderGeometry.ConnectorRouteProvider
  let creationFailureFeedback: @MainActor () -> Void
  let editorFeedback: @MainActor (SionEditorFeedbackRequest) -> Void
  let imageRenditionService: SafeImageRenditionService
  let clipboard: SionGtkCanvasClipboard
  var observerID: UUID?
  var imagePasteTasks: [UUID: Task<Void, Never>] = [:]
  var drag: Drag?
  var isPointerDown = false
  var textEditor: SionGtkInlineTextEditor?
  var editedElementID: ElementID?
  var editingCanvasBounds: SionRect
  var canvasExtent: CanvasExtent
  var textRenderCache: [TextRenderKey: TextRender] = [:]
  var snapGuides: [SceneSnapGuide] = []
  var contextMenu: SionGtkCanvasContextMenu?
  var pendingScrollCenter: SionPoint?
  var lastPointerModelPoint: SionPoint?

  /// A view preference, not document state: it changes how dragging behaves,
  /// not what the drawing contains.
  package private(set) var snapsToObjects = true

  /// How far a connection point sits outside the outline it belongs to.
  package static var magnetDisplayOffset: Double { CanvasMetrics.magnetOffset }

  /// Offscreen rendering draws every element and no interaction chrome.
  var rendersOffscreenPreview = false

  /// Everything that determines one measured text layout. Widths quantize
  /// to half points so a resize drag does not thrash the cache per pixel.
  struct TextRenderKey: Hashable {
    let content: TextContent
    let widthBucket: Int

    init(content: TextContent, width: Double) {
      self.content = content
      self.widthBucket = Int(exactly: (width * 2).rounded(.down)) ?? .max
    }

    var measurementWidth: Double {
      Double(widthBucket) / 2
    }
  }

  final class TextRender {
    let layouts: [OpaquePointer]
    let measuredHeight: Double

    init(layouts: [OpaquePointer], measuredHeight: Double) {
      self.layouts = layouts
      self.measuredHeight = measuredHeight
    }

    deinit {
      for layout in layouts {
        g_object_unref(layout.gobject)
      }
    }
  }

  package convenience init(
    editorController: SionEditorController,
    editorFeedback: @escaping @MainActor (SionEditorFeedbackRequest) -> Void
  ) {
    self.init(
      editorController: editorController,
      creationFailureFeedback: { gdk_display_beep(gdk_display_get_default()) },
      editorFeedback: editorFeedback
    )
  }

  package init(
    editorController: SionEditorController,
    creationFailureFeedback: @escaping @MainActor () -> Void,
    editorFeedback: @escaping @MainActor (SionEditorFeedbackRequest) -> Void = { _ in },
    clipboard: SionGtkCanvasClipboard? = nil,
    connectorRouteProvider: SceneRenderGeometry.ConnectorRouteProvider? = nil,
    imageRenditionService: SafeImageRenditionService = SafeImageRenditionService()
  ) {
    self.editorController = editorController
    self.connectorRouteProvider =
      connectorRouteProvider ?? { editorController.connectorRoute(for: $0) }
    self.creationFailureFeedback = creationFailureFeedback
    self.editorFeedback = editorFeedback
    self.imageRenditionService = imageRenditionService
    self.clipboard = clipboard ?? SionGtkCanvasClipboard()
    let scene = editorController.document.scene
    editingCanvasBounds = SceneRenderGeometry.editingCanvasBounds(
      of: scene,
      minimumInfiniteSize: SionCanvasDefaults.minimumInfiniteSize
    )
    canvasExtent = scene.canvas.extent

    drawingArea = gtk_drawing_area_new()!
    contentLayer = gtk_fixed_new()!
    widget = gtk_scrolled_window_new()!
    gtk_fixed_put(contentLayer.cast(), drawingArea, 0, 0)
    gtk_scrolled_window_set_child(widget.opaque, contentLayer)
    gtk_scrolled_window_set_policy(widget.opaque, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
    gtk_widget_set_focusable(drawingArea, 1)
    gtk_widget_set_can_focus(drawingArea, 1)
    sion_accessible_set_label(drawingArea.opaque, "Diagram canvas")

    installDrawing()
    installInteraction()
    installDropTarget()
    synchronizeContentSize()
    updateAccessibilitySummary()
    updateAccessibilityHelp()

    observerID = editorController.observeChanges { [weak self] in
      guard let self else { return }

      // External edits end model gestures and invalidate view-only previews.
      if self.drag != nil, !self.editorController.hasPendingEditorGesture {
        _ = self.takeActiveDrag()
      }

      self.synchronizeCanvasBounds()
      self.queueRedraw()
      self.updateAccessibilitySummary()
      self.updateAccessibilityHelp()
      self.refreshCursorForCurrentPointer()
    }
  }

  // MARK: Seams the window and document use

  /// The centre of the visible viewport in model coordinates.
  package var visibleCenter: SionPoint {
    visibleCanvasCenter()
  }

  package func commitPendingEdits() {
    commitTextEditing()
  }

  package func checkpointPendingEdits() {
    guard let textEditor, let id = editedElementID else { return }

    do {
      try editorController.updateTextEdit(textEditor.text, on: id)
      try editorController.checkpointTextEdit(on: id)
    } catch {
      creationFailureFeedback()
    }
  }

  package func discardPendingEdits() {
    finishTextEditing(.discard)
  }

  package func grabFocus() {
    gtk_widget_grab_focus(drawingArea)
  }

  /// Releases the observer registration on the editor controller.
  package func invalidate() {
    // Canvas teardown must prevent late rendition results from editing the document.
    for task in imagePasteTasks.values {
      task.cancel()
    }
    imagePasteTasks.removeAll()

    cancelActiveDrag()
    guard let observerID else { return }

    editorController.removeObserver(observerID)
    self.observerID = nil
  }

  /// Whether a menu command applies to the current selection and state,
  /// mirroring `validateMenuItem(_:)`.
  package func canPerform(_ command: SionGtkCommand) -> Bool {
    switch command {
    case .copy:
      return editorController.canCopySelection
    case .cut:
      return editorController.canCopySelection && editorController.canDeleteSelection
    case .delete:
      return editorController.canDeleteSelection
    case .paste:
      return clipboard.hasPasteableContent
    case .duplicate:
      return editorController.canDuplicateSelection
    case .bringToFront:
      return editorController.canMoveSelectionInZOrder(.front)
    case .bringForward:
      return editorController.canMoveSelectionInZOrder(.forward)
    case .sendBackward:
      return editorController.canMoveSelectionInZOrder(.backward)
    case .sendToBack:
      return editorController.canMoveSelectionInZOrder(.back)
    case .alignLeading, .alignCenterHorizontally, .alignTrailing, .alignTop,
      .alignCenterVertically, .alignBottom:
      return editorController.arrangeableSelectionCount > 1
    case .distributeHorizontally, .distributeVertically:
      return editorController.arrangeableSelectionCount > 2
    case .lockSelection:
      return editorController.canSetSelectionLockState(.locked)
    case .unlockSelection:
      return editorController.canSetSelectionLockState(.editable)
    case .hideSelection:
      return editorController.canHideSelection
    case .addSelectionToDocumentLibrary, .addSelectionToGlobalLibrary:
      return editorController.canCopySelection
    case .revealHiddenElements:
      return editorController.canRevealHiddenElements
    case .toggleGridVisibility:
      // Text editing owns the active model gesture; defer the grid command.
      return textEditor == nil
    case .toggleObjectSnapping, .selectAll, .zoomIn, .zoomOut, .actualSize, .zoomToFit:
      return true
    default:
      return false
    }
  }

  /// The check-mark state of a toggle command, nil for plain commands.
  package func isChecked(_ command: SionGtkCommand) -> Bool? {
    switch command {
    case .toggleGridVisibility:
      editorController.gridVisibility == .visible
    case .toggleObjectSnapping:
      snapsToObjects
    default:
      nil
    }
  }

  package func perform(_ command: SionGtkCommand) {
    switch command {
    case .copy: copy()
    case .cut: cut()
    case .paste: paste()
    case .delete: attemptEdit { try editorController.deleteSelection() }
    case .duplicate: attemptEdit { try editorController.duplicateSelection() }
    case .selectAll: editorController.selectAll()
    case .bringToFront: attemptEdit { try editorController.moveSelectionInZOrder(.front) }
    case .bringForward: attemptEdit { try editorController.moveSelectionInZOrder(.forward) }
    case .sendBackward: attemptEdit { try editorController.moveSelectionInZOrder(.backward) }
    case .sendToBack: attemptEdit { try editorController.moveSelectionInZOrder(.back) }
    case .alignLeading: attemptEdit { try editorController.alignSelection(.leading) }
    case .alignCenterHorizontally: attemptEdit { try editorController.alignSelection(.centerX) }
    case .alignTrailing: attemptEdit { try editorController.alignSelection(.trailing) }
    case .alignTop: attemptEdit { try editorController.alignSelection(.top) }
    case .alignCenterVertically: attemptEdit { try editorController.alignSelection(.centerY) }
    case .alignBottom: attemptEdit { try editorController.alignSelection(.bottom) }
    case .distributeHorizontally:
      attemptEdit { try editorController.distributeSelection(.horizontal) }
    case .distributeVertically: attemptEdit { try editorController.distributeSelection(.vertical) }
    case .lockSelection: attemptEdit { try editorController.setSelectionLockState(.locked) }
    case .unlockSelection: attemptEdit { try editorController.setSelectionLockState(.editable) }
    case .hideSelection: attemptEdit { try editorController.hideSelection() }
    case .revealHiddenElements: attemptEdit { try editorController.revealHiddenElements() }
    case .addSelectionToDocumentLibrary:
      addSelectionToLibrary { name in
        try editorController.addSelectionToDocumentLibrary(named: name)
      }
    case .addSelectionToGlobalLibrary:
      addSelectionToLibrary { name in
        let payload = try editorController.selectionPayloadData()
        try SionGlobalLibrary.shared.add(payload: payload, name: name)
      }
    case .toggleGridVisibility: attemptEdit { try editorController.toggleGridVisibility() }
    case .toggleObjectSnapping: toggleObjectSnapping()
    case .zoomIn: zoomIn()
    case .zoomOut: zoomOut()
    case .actualSize: actualSize()
    case .zoomToFit: zoomToFit()
    default: break
    }
  }

  /// Semantic actions throw on validation failures; surface them audibly.
  func attemptEdit(_ action: () throws -> Void) {
    do {
      try action()
    } catch {
      NSLog("Edit action failed: %@", String(describing: error))
      creationFailureFeedback()
    }
  }

  func toggleObjectSnapping() {
    snapsToObjects.toggle()
    guard !snapsToObjects, !snapGuides.isEmpty else { return }

    snapGuides = []
    queueRedraw()
  }

  /// The stored name is the one the inspector would show for the selection,
  /// which is the only name it has until someone renames it in the palette.
  private func addSelectionToLibrary(_ store: (String) throws -> Void) {
    guard editorController.canCopySelection else { return }

    do {
      try store(editorController.selectionLibraryName)
    } catch {
      NSLog("Add to library failed: %@", String(describing: error))
      editorFeedback(.show(.libraryCommandFailed(SionEditorFeedback.LibraryFailure(error))))
    }
  }

  // MARK: Zoom and viewport

  package func zoomIn() {
    setMagnification(magnification * Self.zoomStep)
  }

  package func zoomOut() {
    setMagnification(magnification / Self.zoomStep)
  }

  package func actualSize() {
    setMagnification(1)
  }

  package func zoomToFit() {
    let bounds = editorController.contentBounds()
    let available = viewportSize
    guard bounds.width > 0, bounds.height > 0, available.width > 0, available.height > 0 else {
      return
    }

    let scale =
      min(available.width / bounds.width, available.height / bounds.height)
      * Self.fitInsetFactor
    setMagnification(scale, centeredAt: bounds.center)
  }

  /// Clamps and applies a zoom factor, keeping `center` (the current visible
  /// centre by default) where it is on screen.
  package func setMagnification(_ requested: Double, centeredAt center: SionPoint? = nil) {
    let clamped = min(Self.maximumMagnification, max(Self.minimumMagnification, requested))
    let preserved = center ?? visibleCanvasCenter()
    guard clamped != magnification || center != nil else { return }

    magnification = clamped
    synchronizeContentSize()
    updateTextEditorFrame()
    scroll(toCenter: preserved)
    queueRedraw()
    onMagnificationChange?(magnification)
  }

  var inverseMagnification: Double {
    1 / max(magnification, 0.01)
  }

  /// The scrolled window's visible area in widget coordinates.
  var viewportRect: SionRect {
    let hadjustment = gtk_scrolled_window_get_hadjustment(widget.opaque)
    let vadjustment = gtk_scrolled_window_get_vadjustment(widget.opaque)
    let width = gtk_adjustment_get_page_size(hadjustment)
    let height = gtk_adjustment_get_page_size(vadjustment)
    guard width > 0, height > 0 else {
      return SionRect(
        x: 0, y: 0,
        width: editingCanvasBounds.width * magnification,
        height: editingCanvasBounds.height * magnification)
    }
    return SionRect(
      x: gtk_adjustment_get_value(hadjustment),
      y: gtk_adjustment_get_value(vadjustment),
      width: width,
      height: height
    )
  }

  var viewportSize: SionSize {
    let hadjustment = gtk_scrolled_window_get_hadjustment(widget.opaque)
    let vadjustment = gtk_scrolled_window_get_vadjustment(widget.opaque)
    let width = gtk_adjustment_get_page_size(hadjustment)
    let height = gtk_adjustment_get_page_size(vadjustment)
    guard width > 0, height > 0 else {
      return SionSize(
        width: Double(gtk_widget_get_width(widget)), height: Double(gtk_widget_get_height(widget)))
    }
    return SionSize(width: width, height: height)
  }

  var hasViewport: Bool {
    gtk_adjustment_get_page_size(gtk_scrolled_window_get_hadjustment(widget.opaque)) > 0
  }

  func visibleCanvasCenter() -> SionPoint {
    guard hasViewport else { return editingCanvasBounds.center }

    return modelPoint(fromWidget: viewportRect.center)
  }

  /// The visible area in model coordinates.
  func visibleModelRect() -> SionRect {
    let viewport = viewportRect
    let origin = modelPoint(fromWidget: SionPoint(x: viewport.minX, y: viewport.minY))
    return SionRect(
      x: origin.x, y: origin.y,
      width: viewport.width * inverseMagnification,
      height: viewport.height * inverseMagnification)
  }

  /// Scrolls so `center` sits in the middle of the viewport. The adjustments
  /// learn the new content size on the next layout, so the request is applied
  /// now and again once that layout has run.
  func scroll(toCenter center: SionPoint) {
    pendingScrollCenter = center
    applyPendingScroll()
    MainLoop.performOnNextIteration { [weak self] in
      self?.applyPendingScroll()
      self?.pendingScrollCenter = nil
    }
  }

  private func applyPendingScroll() {
    guard let center = pendingScrollCenter, hasViewport else { return }

    let viewport = viewportRect
    let target = widgetPoint(for: center)
    let hadjustment = gtk_scrolled_window_get_hadjustment(widget.opaque)
    let vadjustment = gtk_scrolled_window_get_vadjustment(widget.opaque)
    gtk_adjustment_set_value(hadjustment, max(0, target.x - (viewport.width / 2)))
    gtk_adjustment_set_value(vadjustment, max(0, target.y - (viewport.height / 2)))
  }

  /// Sizes the drawing area to the canvas at the current zoom.
  func synchronizeContentSize() {
    let width = Int32((editingCanvasBounds.width * magnification).rounded(.up))
    let height = Int32((editingCanvasBounds.height * magnification).rounded(.up))
    gtk_drawing_area_set_content_width(drawingArea.cast(), max(1, width))
    gtk_drawing_area_set_content_height(drawingArea.cast(), max(1, height))
  }

  /// Infinite canvases grow monotonically so a drag cannot move the viewport
  /// under the pointer.
  func synchronizeCanvasBounds() {
    let scene = editorController.document.scene
    let requiredBounds = editorController.editingCanvasBounds(
      minimumInfiniteSize: SionCanvasDefaults.minimumInfiniteSize
    )
    let nextBounds: SionRect
    switch (canvasExtent, scene.canvas.extent) {
    case (.infinite, .infinite):
      nextBounds = editingCanvasBounds.union(requiredBounds)
    default:
      nextBounds = requiredBounds
    }

    guard nextBounds != editingCanvasBounds || canvasExtent != scene.canvas.extent else {
      updateTextEditorFrame()
      return
    }

    let preservedCenter = visibleCanvasCenter()
    editingCanvasBounds = nextBounds
    canvasExtent = scene.canvas.extent
    synchronizeContentSize()
    updateTextEditorFrame()
    if hasViewport {
      scroll(toCenter: preservedCenter)
    }
  }

  // MARK: Coordinates

  func widgetPoint(for modelPoint: SionPoint) -> SionPoint {
    SionPoint(
      x: (modelPoint.x - editingCanvasBounds.minX) * magnification,
      y: (modelPoint.y - editingCanvasBounds.minY) * magnification
    )
  }

  func widgetRect(for modelRect: SionRect) -> SionRect {
    let rect = modelRect.standardized
    let origin = widgetPoint(for: SionPoint(x: rect.minX, y: rect.minY))
    return SionRect(
      x: origin.x, y: origin.y,
      width: rect.width * magnification, height: rect.height * magnification)
  }

  func modelPoint(fromWidget point: SionPoint) -> SionPoint {
    SionPoint(
      x: (point.x * inverseMagnification) + editingCanvasBounds.minX,
      y: (point.y * inverseMagnification) + editingCanvasBounds.minY
    )
  }

  func modelPoint(fromWidgetX x: Double, y: Double) -> SionPoint {
    modelPoint(fromWidget: SionPoint(x: x, y: y))
  }

  func queueRedraw() {
    gtk_widget_queue_draw(drawingArea)
  }

  // MARK: Accessibility

  func updateAccessibilitySummary() {
    let elementCount = editorController.document.scene.elements.count
    let selectionCount = editorController.selection.count
    sion_accessible_set_description(
      drawingArea.opaque, "\(elementCount) elements, \(selectionCount) selected")
  }

  func updateAccessibilityHelp() {
    if editorController.anchorEditingState != .inactive {
      gtk_widget_set_tooltip_text(
        drawingArea,
        "Edit connector anchors. Click the object to add; click an anchor to remove; Escape ends.")
      return
    }

    let tool = editorController.tool
    let mode = tool == .select ? "" : " \(editorController.toolPersistence.summary)."
    accessibilityHelp = "\(tool.help).\(mode) Use Tab to select; use arrow keys to move."
    gtk_widget_set_tooltip_text(drawingArea, nil)
  }

  package private(set) var accessibilityHelp = ""
}

struct ConnectorTarget {
  let elementID: ElementID?
  let point: SionPoint
}

enum CanvasMetrics {
  static let snapTolerance = 7.0
  static let snapGuideLineWidth = 1.0
  static let majorGridOpacity = 0.18
  static let subdivisionGridOpacity = 0.08
  static let gridScreenLineWidth = 0.5
  static let defaultFontSize = 15.0
  static let selectionInset = 4.0
  static let selectionLineWidth = 1.5
  static let selectionDash: [Double] = [5, 3]
  static let previewDash: [Double] = [7, 4]
  static let creationFillOpacity = 0.12
  static let creationDragThreshold = 4.0
  static let magnetRadius = 4.0
  static let magnetOffset = 12.0
  static let magnetHitTolerance = 10.0
  static let magnetStemOpacity = 0.55
  static let magnetStemWidth = 1.0
  static let anchorEditingRadius = 6.0
  static let anchorEditingHitTolerance = 9.0
  static let resizeHandleRadius = 4.5
  static let rotationHandleRadius = 5.0
  static let cornerRadiusHandleRadius = 4.5
  static let cornerRadiusHandleMinimumInset = 14.0
  static let handleHitRadius = 9.0
  static let rotationHandleOffset = 28.0
  static let rotationSnapRadians = Double.pi / 12
  static let minimumElementSize = SionSize(width: 12, height: 12)
  static let arrowLength = 12.0
  static let arrowWidth = 6.0
  static let decorationRadius = 5.0
  static let minimumConnectorLength = 4.0
  static let textEditClickCount = 2
  static let connectorLabelSize = SionSize(width: 120, height: 36)
  static let nudgeDistance = 1.0
  static let largeNudgeDistance = 10.0
  static let textRenderCacheLimit = 512
  static let textRenderCacheEvictionDivisor = 4
  static let marqueeFillOpacity = 0.08
  static let minimumMarqueeScreenSize = 2.0
}

enum PreviewMetrics {
  static let maximumDimension = 768.0
}

/// The system colours the AppKit canvas takes from its appearance, fixed to
/// the GNOME palette here because the document surface stays light whatever
/// the desktop theme is.
enum CanvasColors {
  static let accent = SionColor(red: 0.208, green: 0.518, blue: 0.894)
  static let controlBackground = SionColor.white
  static let separator = SionColor.black
  static let underPageBackground = SionColor(red: 0.80, green: 0.80, blue: 0.80)
  static let systemYellow = SionColor(red: 1.0, green: 0.80, blue: 0.0)
  static let systemOrange = SionColor(red: 1.0, green: 0.584, blue: 0.0)
  static let quaternaryLabel = SionColor(red: 0, green: 0, blue: 0, alpha: 0.1)
  static let secondaryLabel = SionColor(red: 0, green: 0, blue: 0, alpha: 0.5)
  static let selectedTextBackground = SionColor(red: 0.70, green: 0.84, blue: 1.0)
}

extension SceneElement {
  var editableText: String? {
    switch content {
    case .shape(let shape): shape.label?.string ?? ""
    case .text(let text): text.string
    case .connector(let connector): connector.label?.string ?? ""
    case .path, .image, .group: nil
    }
  }

  var preservesAspectRatioWhileResizing: Bool {
    switch content {
    case .image: true
    case .shape, .path, .text, .group, .connector: false
    }
  }

  var textStyle: TextStyle? {
    switch content {
    case .shape(let shape): shape.label?.style ?? .shapeLabelDefault
    case .text(let text): text.style
    case .connector(let connector): connector.label?.style ?? .shapeLabelDefault
    case .path, .image, .group: nil
    }
  }
}

extension SionRect {
  /// The overlap of two rectangles, or an empty rectangle when they miss.
  func intersection(_ other: SionRect) -> SionRect {
    let a = standardized
    let b = other.standardized
    let minX = max(a.minX, b.minX)
    let minY = max(a.minY, b.minY)
    let maxX = min(a.maxX, b.maxX)
    let maxY = min(a.maxY, b.maxY)
    guard maxX > minX, maxY > minY else { return .zero }
    return SionRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}

func clampedUnit(_ value: Double) -> Double {
  guard value.isFinite else { return 1 }

  return min(1, max(0, value))
}

func finiteNonnegative(_ value: Double) -> Double {
  guard value.isFinite else { return 0 }

  return max(0, value)
}
