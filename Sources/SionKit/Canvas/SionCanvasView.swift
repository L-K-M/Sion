#if canImport(AppKit)
  import AppKit
  import SionCore

  @MainActor
  /// Maps the top-left-origin model into AppKit's flipped view coordinates.
  final class SionCanvasView: NSView, NSTextViewDelegate {
    private enum TextEditingDisposition {
      case commit
      case discard
    }

    private enum Creation {
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

    private enum Drag {
      case move(lastPoint: SionPoint)
      case resize(
        elementID: ElementID,
        handle: ResizeHandle,
        startFrame: SionRect,
        rotationRadians: Double
      )
      case rotate(
        elementID: ElementID,
        center: SionPoint,
        startPoint: SionPoint,
        startRotation: Double
      )
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

    private let editorController: SionEditorController
    private let connectorRouteProvider: SceneRenderGeometry.ConnectorRouteProvider
    private let creationFailureFeedback: @MainActor () -> Void
    private let pasteboard: NSPasteboard
    private var observerID: UUID?
    private var magnificationObservation: NSKeyValueObservation?
    private var drag: Drag?
    private var textEditor: NSScrollView?
    private var editedElementID: ElementID?
    private var inlineTextUndoManager: UndoManager?
    private var editingCanvasBounds: SionRect
    private var canvasExtent: CanvasExtent
    private var textRenderCache: [TextRenderKey: TextRender] = [:]
    private var pasteboardValidation: PasteboardValidation?

    /// Everything that determines one measured text layout. Widths quantize
    /// to half points so a resize drag does not thrash the cache per pixel.
    private struct TextRenderKey: Hashable {
      let content: TextContent
      let widthBucket: Int

      init(content: TextContent, width: CGFloat) {
        self.content = content
        // Floor defines a stable lower edge used by measurement below.
        self.widthBucket = Int(exactly: (width * 2).rounded(.down)) ?? .max
      }
    }

    private struct TextRender {
      let attributed: NSAttributedString
      let measuredHeight: CGFloat
    }

    private struct PasteboardValidation {
      let changeCount: Int
      let isPasteable: Bool
    }

    init(
      editorController: SionEditorController,
      creationFailureFeedback: @escaping @MainActor () -> Void = { NSSound.beep() },
      pasteboard: NSPasteboard = .general,
      connectorRouteProvider: SceneRenderGeometry.ConnectorRouteProvider? = nil
    ) {
      self.editorController = editorController
      self.connectorRouteProvider =
        connectorRouteProvider
        ?? { editorController.connectorRoute(for: $0) }
      self.creationFailureFeedback = creationFailureFeedback
      self.pasteboard = pasteboard
      let scene = editorController.document.scene
      let initialBounds = SceneRenderGeometry.editingCanvasBounds(
        of: scene,
        minimumInfiniteSize: CanvasMetrics.minimumInfiniteSize
      )
      editingCanvasBounds = initialBounds
      canvasExtent = scene.canvas.extent

      super.init(
        frame: NSRect(
          origin: .zero,
          size: NSSize(
            width: initialBounds.width,
            height: initialBounds.height
          )
        )
      )

      wantsLayer = true
      setAccessibilityElement(true)
      setAccessibilityRole(.group)
      setAccessibilityLabel("Diagram canvas")
      updateAccessibilityHelp()
      observerID = editorController.observeChanges { [weak self] in
        guard let self else { return }

        // External edits end model gestures and invalidate view-only previews.
        if self.drag != nil, !self.editorController.hasPendingEditorGesture {
          _ = self.takeActiveDrag()
        }

        self.synchronizeCanvasBounds()
        self.needsDisplay = true
        self.updateAccessibilitySummary()
        self.updateAccessibilityHelp()
        self.window?.invalidateCursorRects(for: self)
        self.refreshCursorForCurrentPointer()
      }
      updateAccessibilitySummary()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
      guard super.resignFirstResponder() else { return false }

      cancelActiveDrag()
      return true
    }

    override func resetCursorRects() {
      super.resetCursorRects()

      let editsAnchors = editorController.anchorEditingState != .inactive
      let cursor: NSCursor =
        editorController.tool == .select && !editsAnchors
        ? .arrow
        : .crosshair
      addCursorRect(bounds, cursor: cursor)
    }

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
      super.updateTrackingAreas()

      if let hoverTrackingArea {
        removeTrackingArea(hoverTrackingArea)
      }

      let area = NSTrackingArea(
        rect: bounds,
        options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp],
        owner: self,
        userInfo: nil
      )
      addTrackingArea(area)
      hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
      cancelActiveDrag()
      updateCursor(at: modelPoint(from: event))
    }

    override func mouseEntered(with event: NSEvent) {
      guard drag == nil else { return }

      updateCursor(at: modelPoint(from: event))
    }

    override func mouseExited(with event: NSEvent) {
      guard drag == nil else { return }

      NSCursor.arrow.set()
    }

    /// Tool and selection changes arrive without mouse movement; re-derive the
    /// cursor whenever the pointer already sits inside the canvas.
    private func refreshCursorForCurrentPointer() {
      guard drag == nil, let window else { return }

      let locationInWindow = window.mouseLocationOutsideOfEventStream
      let locationInView = convert(locationInWindow, from: nil)
      guard bounds.contains(locationInView),
        let hit = window.contentView?.hitTest(locationInWindow),
        hit === self || hit.isDescendant(of: self)
      else { return }

      updateCursor(at: modelPoint(from: locationInView))
    }

    /// The canvas reads as a physical surface: hands for moves, crosshairs
    /// for creation tools, diagonal arrows over resize handles.
    private func updateCursor(at point: SionPoint) {
      cursor(for: point).set()
    }

    private func cursor(for point: SionPoint) -> NSCursor {
      switch editorController.tool {
      case .select:
        if editorController.anchorEditingState != .inactive {
          return .crosshair
        }
      case .rectangle, .circle, .text, .connector:
        return .crosshair
      }

      if let element = editorController.selectedElement,
        element.lockState == .editable,
        element.content.connector == nil,
        let handle = resizeHandle(at: point, for: element)
      {
        return Self.resizeCursor(for: handle)
      }

      if let element = editorController.element(at: point),
        element.lockState == .editable,
        element.content.connector == nil
      {
        return .openHand
      }

      return .arrow
    }

    /// Corner handles take diagonal arrows; edge handles take axis arrows.
    private static func resizeCursor(for handle: ResizeHandle) -> NSCursor {
      switch handle {
      case .northWest, .southEast:
        return northwestSoutheastResizeCursor
      case .northEast, .southWest:
        return northeastSouthwestResizeCursor
      case .north, .south:
        return .resizeUpDown
      case .east, .west:
        return .resizeLeftRight
      }
    }

    private static let northwestSoutheastResizeCursor = makeResizeCursor(
      symbolName: "arrow.up.left.and.arrow.down.right"
    )

    private static let northeastSouthwestResizeCursor = makeResizeCursor(
      symbolName: "arrow.up.right.and.arrow.down.left"
    )

    private static func makeResizeCursor(symbolName: String) -> NSCursor {
      let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
      guard
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
          .withSymbolConfiguration(configuration)
      else {
        return .arrow
      }

      return NSCursor(
        image: symbol,
        hotSpot: NSPoint(x: symbol.size.width / 2, y: symbol.size.height / 2)
      )
    }

    var visibleCenter: SionPoint { visibleCanvasCenter() }

    func commitPendingEdits() {
      commitTextEditing()
    }

    func checkpointPendingEdits() {
      guard let textView = textEditor?.documentView as? NSTextView,
        let id = editedElementID
      else {
        return
      }

      do {
        try editorController.updateTextEdit(textView.string, on: id)
        try editorController.checkpointTextEdit(on: id)
      } catch {
        NSSound.beep()
      }
    }

    func discardPendingEdits() {
      finishTextEditing(.discard)
    }

    func invalidate() {
      cancelActiveDrag()
      guard let observerID else { return }

      editorController.removeObserver(observerID)
      self.observerID = nil
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()

      updateMagnificationObservation()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()

      updateMagnificationObservation()
    }

    /// The scroll view can appear after either move; rebind KVO wherever the
    /// canvas last landed.
    private func updateMagnificationObservation() {
      // Zoom-adaptive grid rendering must re-run whenever magnification
      // changes, including layer-backed scaling that skips normal layout.
      magnificationObservation = enclosingScrollView?.observe(\.magnification) {
        [weak self] _, _ in
        self?.needsDisplay = true
      }
    }

    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)

      drawCanvas()

      NSGraphicsContext.saveGraphicsState()
      applyCanvasTransform()
      drawGrid()
      drawElements()
      drawConnectionMagnets()
      drawCreationPreview()
      drawConnectorPreview()
      drawMarquee()
      NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
      // A new press is the last recovery point when AppKit drops mouse-up.
      cancelActiveDrag()
      commitTextEditing()
      window?.makeFirstResponder(self)

      let point = modelPoint(from: event)
      if handleAnchorEditing(at: point) {
        return
      }

      // Visible connection points remain draggable while a placement tool stays active.
      if editorController.tool != .select,
        let selected = editorController.selectedElement,
        selected.content.connector == nil,
        let source = magnetTarget(at: point, use: .outgoing, elements: [selected])
      {
        beginConnector(from: source)
        return
      }

      switch editorController.tool {
      case .select:
        beginSelection(at: point, event: event)
      case .rectangle, .circle:
        guard let shapeKind = editorController.tool.shapeKind else { return }

        drag = .create(creation: .shape(shapeKind), start: point, current: point)
      case .text:
        drag = .create(creation: .text, start: point, current: point)
      case .connector:
        beginConnector(at: point)
      }
    }

    override func mouseDragged(with event: NSEvent) {
      let point = modelPoint(from: event)
      guard let drag else { return }

      switch drag {
      case .move(let lastPoint):
        let offset = point - lastPoint
        try? editorController.moveSelection(by: offset)
        self.drag = .move(lastPoint: point)
      case .resize(let elementID, let handle, let startFrame, let rotationRadians):
        let frame = InteractionGeometry.resizedFrame(
          startFrame,
          moving: handle,
          to: point,
          minimumSize: CanvasMetrics.minimumElementSize,
          rotationRadians: rotationRadians
        )
        try? editorController.resize(elementID, to: frame)
      case .rotate(let elementID, let center, let startPoint, let startRotation):
        let delta = InteractionGeometry.rotationDelta(
          from: startPoint,
          to: point,
          around: center
        )
        let rotation = snappedRotation(
          startRotation + delta,
          modifierFlags: event.modifierFlags
        )
        try? editorController.rotate(elementID, to: rotation)
      case .cornerRadius(
        let elementID,
        let frame,
        let rotationRadians,
        let startPoint,
        let startRadius
      ):
        let initialPointerRadius = InteractionGeometry.roundedRectangleCornerRadius(
          in: frame,
          draggedTo: startPoint,
          rotationRadians: rotationRadians
        )
        let pointerRadius = InteractionGeometry.roundedRectangleCornerRadius(
          in: frame,
          draggedTo: point,
          rotationRadians: rotationRadians
        )
        let maximumRadius = min(frame.width, frame.height) / 2
        let radius = min(
          maximumRadius,
          max(0, startRadius + pointerRadius - initialPointerRadius)
        )
        try? editorController.setCornerRadius(radius, on: elementID)
      case .create(let creation, let start, _):
        self.drag = .create(creation: creation, start: start, current: point)
        needsDisplay = true
      case .connector(let sourceID, let start, _):
        let target = connectorTarget(at: point, use: .incoming)
        self.drag = .connector(
          sourceID: sourceID,
          start: start,
          current: target.point
        )
        needsDisplay = true
      case .marquee(let origin, _):
        self.drag = .marquee(origin: origin, current: point)
        needsDisplay = true
      }
    }

    override func mouseUp(with event: NSEvent) {
      guard let drag = takeActiveDrag() else { return }
      updateCursor(at: modelPoint(from: event))

      switch drag {
      case .move:
        try? editorController.endMove()
      case .resize:
        try? editorController.endResize()
      case .rotate:
        try? editorController.endRotation()
      case .cornerRadius:
        try? editorController.endCornerRadiusChange()
      case .create(let creation, let start, _):
        finishCreation(creation, from: start, to: modelPoint(from: event))
      case .connector(let sourceID, let start, _):
        let target = connectorTarget(at: modelPoint(from: event), use: .incoming)
        let end = target.point
        guard start.distance(to: end) >= CanvasMetrics.minimumConnectorLength else {
          needsDisplay = true
          return
        }

        do {
          _ = try editorController.insertConnector(
            from: sourceID,
            sourcePoint: start,
            to: target.elementID,
            targetPoint: end
          )
        } catch {
          creationFailureFeedback()
          needsDisplay = true
        }
      case .marquee(let origin, _):
        // Modifier state at release decides replace versus extend, matching
        // the gesture the user believes they performed.
        endMarquee(
          from: origin,
          to: modelPoint(from: event),
          mode: event.modifierFlags.contains(.shift) ? .extend : .replace
        )
      }
    }

    override func keyDown(with event: NSEvent) {
      if event.keyCode == CanvasKeyCode.escape {
        cancelInteraction()
        return
      }

      if event.keyCode == CanvasKeyCode.returnKey,
        let element = editorController.selectedElement,
        element.editableText != nil
      {
        beginTextEditing(element.id)
        return
      }

      if event.keyCode == CanvasKeyCode.tab {
        let traversal: SionEditorController.SelectionTraversal =
          event.modifierFlags.contains(.shift) ? .backward : .forward
        editorController.selectAdjacent(traversal)
        return
      }

      if !editorController.selection.isEmpty,
        let direction = CanvasKeyCode.nudgeDirection(for: event.keyCode)
      {
        let distance =
          event.modifierFlags.contains(.shift)
          ? CanvasMetrics.largeNudgeDistance
          : CanvasMetrics.nudgeDistance
        try? editorController.nudgeSelection(by: direction * distance)
        return
      }

      guard event.keyCode != CanvasKeyCode.delete,
        event.keyCode != CanvasKeyCode.forwardDelete
      else {
        try? editorController.deleteSelection()
        return
      }

      super.keyDown(with: event)
    }

    @objc func delete(_ sender: Any?) {
      try? editorController.deleteSelection()
    }

    /// Escape cancels inwards: text, anchors, a live gesture, then selection.
    /// keyDown covers the canvas as first responder; cancelOperation catches
    /// Escape bubbling from a hosted text editor.
    @objc override func cancelOperation(_ sender: Any?) {
      cancelInteraction()
    }

    private func cancelInteraction() {
      if textEditor != nil {
        discardPendingEdits()
        return
      }

      if editorController.anchorEditingState != .inactive {
        editorController.endAnchorEditing()
        return
      }

      if drag != nil {
        cancelActiveDrag()
        return
      }

      editorController.select(nil)
    }

    /// Only mouse-up commits; every other terminal path cancels the drag.
    func cancelActiveDrag() {
      guard let activeDrag = takeActiveDrag() else { return }
      guard activeDrag.requiresEditorGesture else { return }

      editorController.cancelActiveGesture()
    }

    /// Clear view state before controller callbacks can synchronously notify us.
    private func takeActiveDrag() -> Drag? {
      guard let activeDrag = drag else { return nil }

      drag = nil
      needsDisplay = true
      window?.invalidateCursorRects(for: self)
      NSCursor.arrow.set()
      refreshCursorForCurrentPointer()
      return activeDrag
    }

    @objc override func selectAll(_ sender: Any?) {
      editorController.selectAll()
    }

    /// Semantic actions throw on validation failures; surface them audibly.
    private func attemptEdit(_ action: () throws -> Void) {
      do {
        try action()
      } catch {
        NSLog("Edit action failed: %@", String(describing: error))
        NSSound.beep()
      }
    }

    @objc func toggleGridVisibility(_ sender: Any?) {
      attemptEdit { try editorController.toggleGridVisibility() }
    }

    @objc func duplicate(_ sender: Any?) {
      attemptEdit { try editorController.duplicateSelection() }
    }

    @objc func bringToFront(_ sender: Any?) {
      attemptEdit { try editorController.moveSelectionInZOrder(.front) }
    }

    @objc func bringForward(_ sender: Any?) {
      attemptEdit { try editorController.moveSelectionInZOrder(.forward) }
    }

    @objc func sendBackward(_ sender: Any?) {
      attemptEdit { try editorController.moveSelectionInZOrder(.backward) }
    }

    @objc func sendToBack(_ sender: Any?) {
      attemptEdit { try editorController.moveSelectionInZOrder(.back) }
    }

    @objc func alignLeading(_ sender: Any?) {
      attemptEdit { try editorController.alignSelection(.leading) }
    }

    @objc func alignCenterHorizontally(_ sender: Any?) {
      attemptEdit { try editorController.alignSelection(.centerX) }
    }

    @objc func alignTrailing(_ sender: Any?) {
      attemptEdit { try editorController.alignSelection(.trailing) }
    }

    @objc func alignTop(_ sender: Any?) {
      attemptEdit { try editorController.alignSelection(.top) }
    }

    @objc func alignCenterVertically(_ sender: Any?) {
      attemptEdit { try editorController.alignSelection(.centerY) }
    }

    @objc func alignBottom(_ sender: Any?) {
      attemptEdit { try editorController.alignSelection(.bottom) }
    }

    @objc func distributeHorizontally(_ sender: Any?) {
      attemptEdit { try editorController.distributeSelection(.horizontal) }
    }

    @objc func distributeVertically(_ sender: Any?) {
      attemptEdit { try editorController.distributeSelection(.vertical) }
    }

    @objc func lockSelection(_ sender: Any?) {
      attemptEdit { try editorController.setSelectionLockState(.locked) }
    }

    @objc func unlockSelection(_ sender: Any?) {
      attemptEdit { try editorController.setSelectionLockState(.editable) }
    }

    @objc func hideSelection(_ sender: Any?) {
      attemptEdit { try editorController.hideSelection() }
    }

    @objc func revealHiddenElements(_ sender: Any?) {
      attemptEdit { try editorController.revealHiddenElements() }
    }

    /// AppKit discovers menu validation through Objective-C responder dispatch.
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      switch menuItem.action {
      case #selector(copy(_:)):
        return editorController.canCopySelection
      case #selector(cut(_:)):
        return editorController.canCopySelection && editorController.canDeleteSelection
      case #selector(delete(_:)):
        return editorController.canDeleteSelection
      case #selector(paste(_:)):
        return hasPasteableContent(in: pasteboard)
      case #selector(duplicate(_:)):
        return editorController.canDuplicateSelection
      case #selector(bringToFront(_:)):
        return editorController.canMoveSelectionInZOrder(.front)
      case #selector(bringForward(_:)):
        return editorController.canMoveSelectionInZOrder(.forward)
      case #selector(sendBackward(_:)):
        return editorController.canMoveSelectionInZOrder(.backward)
      case #selector(sendToBack(_:)):
        return editorController.canMoveSelectionInZOrder(.back)
      case #selector(alignLeading(_:)),
        #selector(alignCenterHorizontally(_:)),
        #selector(alignTrailing(_:)),
        #selector(alignTop(_:)),
        #selector(alignCenterVertically(_:)),
        #selector(alignBottom(_:)):
        return editorController.arrangeableSelectionCount > 1
      case #selector(distributeHorizontally(_:)),
        #selector(distributeVertically(_:)):
        return editorController.arrangeableSelectionCount > 2
      case #selector(lockSelection(_:)):
        return editorController.canSetSelectionLockState(.locked)
      case #selector(unlockSelection(_:)):
        return editorController.canSetSelectionLockState(.editable)
      case #selector(hideSelection(_:)):
        return editorController.canHideSelection
      case #selector(revealHiddenElements(_:)):
        return editorController.canRevealHiddenElements
      case #selector(toggleGridVisibility(_:)):
        menuItem.state = editorController.gridVisibility == .visible ? .on : .off

        // Text editing owns the active model gesture; defer the grid command.
        return textEditor == nil
      default:
        return true
      }
    }

    @objc func paste(_ sender: Any?) {
      let point = visibleCanvasCenter()

      if pasteSelection(from: pasteboard, at: point) {
        return
      }

      if pasteImage(from: pasteboard, at: point) {
        return
      }

      guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

      if MermaidImporter.looksLikeMermaid(text) {
        _ = try? editorController.insertMermaid(text, at: point)
        return
      }

      _ = try? editorController.insertText(text, centeredAt: point)
    }

    @objc func copy(_ sender: Any?) {
      guard editorController.canCopySelection else { return }

      _ = copySelection(to: pasteboard)
    }

    @objc func cut(_ sender: Any?) {
      guard editorController.canCopySelection,
        editorController.canDeleteSelection
      else {
        return
      }

      guard copySelection(to: pasteboard) else { return }

      try? editorController.deleteSelection()
    }

    func beginTextEditing(_ id: ElementID) {
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

      let frame = textEditingFrame(for: element).insetBy(dx: -2, dy: -2)
      let textView = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
      textView.isRichText = false
      textView.autoresizingMask = [.width, .height]
      configureTextEditor(textView, text: text, element: element, frame: frame)

      inlineTextUndoManager = UndoManager()
      textView.delegate = self
      textView.allowsUndo = true
      textView.setAccessibilityLabel("Edit element text")

      let scrollView = NSScrollView(frame: frame)
      scrollView.borderType = .lineBorder
      scrollView.hasVerticalScroller = true
      scrollView.documentView = textView
      addSubview(scrollView)

      textEditor = scrollView
      editedElementID = id
      needsDisplay = true
      window?.makeFirstResponder(textView)
      textView.selectAll(nil)
    }

    private func configureTextEditor(
      _ textView: NSTextView,
      text: String,
      element: SceneElement,
      frame: NSRect
    ) {
      let style = element.textStyle ?? .standaloneDefault
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = textAlignment(style.horizontalAlignment)
      paragraph.lineSpacing = finiteNonnegative(style.lineSpacing)
      paragraph.paragraphSpacing = finiteNonnegative(style.paragraphSpacing)
      let font = nsFont(style)
      let color = nsColor(style.color)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
      ]

      textView.textStorage?.setAttributedString(
        NSAttributedString(string: text, attributes: attributes)
      )
      textView.font = font
      textView.textColor = color
      textView.alignment = paragraph.alignment
      textView.defaultParagraphStyle = paragraph
      textView.backgroundColor = .clear
      textView.drawsBackground = false

      let horizontalInset = finiteNonnegative(style.insets.leading)
      let topInset = finiteNonnegative(style.insets.top)
      textView.textContainerInset = NSSize(width: horizontalInset, height: topInset)

      guard let textContainer = textView.textContainer,
        let layoutManager = textView.layoutManager
      else {
        return
      }

      layoutManager.ensureLayout(for: textContainer)
      let contentHeight = layoutManager.usedRect(for: textContainer).height
      let bottomInset = finiteNonnegative(style.insets.bottom)
      let verticalInset: CGFloat
      switch style.verticalAlignment {
      case .top:
        verticalInset = topInset
      case .center:
        verticalInset = max(topInset, (frame.height - contentHeight) / 2)
      case .bottom:
        verticalInset = max(topInset, frame.height - contentHeight - bottomInset)
      }
      textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
    }

    func textDidEndEditing(_ notification: Notification) {
      commitTextEditing()
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView,
        textView === textEditor?.documentView,
        let id = editedElementID
      else {
        return
      }

      do {
        try editorController.updateTextEdit(textView.string, on: id)
      } catch {
        NSSound.beep()
      }
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
      guard view === textEditor?.documentView else { return nil }

      return inlineTextUndoManager
    }

    /// Preview rendering draws every element and no interaction chrome.
    private var rendersOffscreenPreview = false

    /// Renders the document content into a bounded PNG for the archive's
    /// recovery preview. Grid and selection chrome are omitted.
    ///
    /// The explicit flipped context keeps text upright without inheriting a
    /// display's backing scale.
    func renderPreviewPNG(
      maximumDimension: CGFloat = PreviewMetrics.maximumDimension
    ) -> Data? {
      guard maximumDimension.isFinite, maximumDimension > 0 else { return nil }

      let content = editorController.contentBounds()
      guard content.isFinite, content.width > 0, content.height > 0 else { return nil }

      let scale = min(
        1,
        Double(maximumDimension) / max(content.width, content.height)
      )
      let pixelWidth = max(1, Int((content.width * scale).rounded()))
      let pixelHeight = max(1, Int((content.height * scale).rounded()))
      guard
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: pixelWidth,
          pixelsHigh: pixelHeight,
          bitsPerSample: PreviewMetrics.bitsPerSample,
          samplesPerPixel: PreviewMetrics.samplesPerPixel,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .calibratedRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ),
        let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap)
      else {
        return nil
      }

      let previousContext = NSGraphicsContext.current
      defer { NSGraphicsContext.current = previousContext }

      // Map the y-down model into the bitmap's y-up pixel coordinates.
      bitmapContext.cgContext.translateBy(x: 0, y: CGFloat(pixelHeight))
      bitmapContext.cgContext.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
      bitmapContext.cgContext.translateBy(
        x: CGFloat(-content.minX),
        y: CGFloat(-content.minY)
      )
      let renderContext = NSGraphicsContext(
        cgContext: bitmapContext.cgContext,
        flipped: true
      )
      NSGraphicsContext.current = renderContext

      rendersOffscreenPreview = true
      defer { rendersOffscreenPreview = false }

      nsColor(editorController.document.scene.canvas.background).setFill()
      NSBezierPath(rect: nsRect(content)).fill()
      for element in editorController.document.scene.elements
      where element.visibility == .visible {
        draw(element)
      }

      renderContext.flushGraphics()
      let encodedBitmap =
        bitmap.converting(
          to: NSColorSpace.sRGB,
          renderingIntent: NSColorRenderingIntent.default
        ) ?? bitmap

      return encodedBitmap.representation(
        using: NSBitmapImageRep.FileType.png,
        properties: [:]
      )
    }

    private func beginSelection(at point: SionPoint, event: NSEvent) {
      if let element = editorController.selectedElement,
        element.lockState == .editable,
        element.content.connector == nil
      {
        if isRotationHandle(point, for: element) {
          beginRotation(of: element, at: point)
          return
        }

        if isCornerRadiusHandle(point, for: element) {
          beginCornerRadiusChange(of: element, at: point)
          return
        }

        if let handle = resizeHandle(at: point, for: element) {
          beginResize(of: element, using: handle)
          return
        }
      }

      let selectedConnectableElements = editorController.selectedElements.filter {
        $0.content.connector == nil
      }
      if let source = magnetTarget(
        at: point,
        use: .outgoing,
        elements: selectedConnectableElements
      ) {
        beginConnector(from: source)
        return
      }

      guard let element = editorController.element(at: point) else {
        // Shift keeps the current selection as the marquee's base.
        if !event.modifierFlags.contains(.shift) {
          editorController.select(nil)
        }
        drag = .marquee(origin: point, current: point)
        return
      }

      if event.clickCount == CanvasMetrics.textEditClickCount, element.editableText != nil {
        editorController.select(element.id)
        beginTextEditing(element.id)
        return
      }

      if event.modifierFlags.contains(.shift) {
        editorController.select(element.id, mode: .extend)
      } else if !editorController.selection.contains(element.id) {
        // Keep a multi-selection intact when dragging one of its members.
        editorController.select(element.id)
      }

      guard element.lockState == .editable else { return }
      guard editorController.selection.contains(element.id) else { return }
      guard editorController.canMoveSelection else { return }

      do {
        try editorController.beginMove()
        drag = .move(lastPoint: point)
        NSCursor.closedHand.set()
      } catch {
        drag = nil
      }
    }

    private func handleAnchorEditing(at point: SionPoint) -> Bool {
      guard let id = editorController.anchorEditingState.elementID else { return false }

      do {
        let result = try editorController.editAnchor(
          at: point,
          on: id,
          hitTolerance: CanvasMetrics.anchorEditingHitTolerance * inverseMagnification
        )
        switch result {
        case .changed:
          return true
        case .outsideElement, .unavailable:
          editorController.endAnchorEditing()
          return false
        }
      } catch {
        NSSound.beep()
        return true
      }
    }

    private func beginResize(of element: SceneElement, using handle: ResizeHandle) {
      do {
        try editorController.beginResize()
        drag = .resize(
          elementID: element.id,
          handle: handle,
          startFrame: element.geometry.frame.standardized,
          rotationRadians: element.geometry.rotationRadians
        )
      } catch {
        drag = nil
      }
    }

    private func beginRotation(of element: SceneElement, at point: SionPoint) {
      do {
        try editorController.beginRotation()
        drag = .rotate(
          elementID: element.id,
          center: element.geometry.frame.standardized.center,
          startPoint: point,
          startRotation: element.geometry.rotationRadians
        )
      } catch {
        drag = nil
      }
    }

    private func beginCornerRadiusChange(of element: SceneElement, at point: SionPoint) {
      guard let radius = cornerRadius(of: element) else { return }

      do {
        try editorController.beginCornerRadiusChange()
        drag = .cornerRadius(
          elementID: element.id,
          frame: element.geometry.frame.standardized,
          rotationRadians: element.geometry.rotationRadians,
          startPoint: point,
          startRadius: radius
        )
      } catch {
        drag = nil
      }
    }

    private func beginConnector(at point: SionPoint) {
      beginConnector(from: connectorTarget(at: point, use: .outgoing))
    }

    private func beginConnector(from source: ConnectorTarget) {
      editorController.select(source.elementID)
      drag = .connector(
        sourceID: source.elementID,
        start: source.point,
        current: source.point
      )
      needsDisplay = true
    }

    private func finishCreation(
      _ creation: Creation,
      from start: SionPoint,
      to end: SionPoint
    ) {
      let placement = creationPlacement(creation, from: start, to: end)

      do {
        switch creation {
        case .shape(let kind):
          _ = try editorController.insertShape(in: placement.frame, kind: kind)
        case .text:
          let id = try editorController.insertText("Text", in: placement.frame)
          beginTextEditing(id)
        }
      } catch {
        creationFailureFeedback()
      }

      needsDisplay = true
    }

    private func creationPlacement(
      _ creation: Creation,
      from start: SionPoint,
      to end: SionPoint
    ) -> CreationPlacement {
      let placement = InteractionGeometry.creationFrame(
        from: start,
        to: end,
        dragThreshold: CanvasMetrics.creationDragThreshold * inverseMagnification,
        defaultSize: creation.defaultSize,
        minimumSize: CanvasMetrics.minimumElementSize
      )
      guard case .shape(.ellipse) = creation, placement.mode == .drag else {
        return placement
      }

      return CreationPlacement(
        frame: circularFrame(from: start, to: end),
        mode: .drag
      )
    }

    private func circularFrame(from start: SionPoint, to end: SionPoint) -> SionRect {
      let width = abs(end.x - start.x)
      let height = abs(end.y - start.y)
      let minimumSide = max(
        CanvasMetrics.minimumElementSize.width,
        CanvasMetrics.minimumElementSize.height
      )
      let side = max(minimumSide, max(width, height))
      let x = end.x < start.x ? start.x - side : start.x
      let y = end.y < start.y ? start.y - side : start.y

      return SionRect(x: x, y: y, width: side, height: side)
    }

    private func commitTextEditing() {
      finishTextEditing(.commit)
    }

    private func finishTextEditing(_ disposition: TextEditingDisposition) {
      guard let scrollView = textEditor,
        let textView = scrollView.documentView as? NSTextView,
        let id = editedElementID
      else {
        return
      }

      let restoresCanvasFocus = window?.firstResponder === textView
      textView.delegate = nil

      switch disposition {
      case .commit:
        do {
          try editorController.updateTextEdit(textView.string, on: id)
          try editorController.endTextEdit()
        } catch {
          editorController.cancelTextEdit()
          NSSound.beep()
        }
      case .discard:
        editorController.cancelTextEdit()
      }

      textEditor = nil
      editedElementID = nil
      inlineTextUndoManager = nil
      scrollView.removeFromSuperview()
      needsDisplay = true

      // Revert removes the editor without another view requesting focus.
      if restoresCanvasFocus {
        window?.makeFirstResponder(self)
      }
    }

    private func textEditingFrame(for element: SceneElement) -> NSRect {
      guard let connector = element.content.connector,
        let route = editorController.connectorRoute(for: element)
      else {
        return viewRect(for: element.geometry.frame)
      }

      let point = route.point(atFraction: connector.labelPosition)
      let modelFrame = SionRect(
        x: point.x - (CanvasMetrics.connectorLabelSize.width / 2),
        y: point.y - (CanvasMetrics.connectorLabelSize.height / 2),
        width: CanvasMetrics.connectorLabelSize.width,
        height: CanvasMetrics.connectorLabelSize.height
      )
      return viewRect(for: modelFrame)
    }

    private func updateTextEditorFrame() {
      guard let textEditor,
        let id = editedElementID,
        let element = editorController.document.scene.element(withID: id)
      else {
        return
      }

      textEditor.frame = textEditingFrame(for: element).insetBy(dx: -2, dy: -2)
    }

    private func copySelection(to pasteboard: NSPasteboard) -> Bool {
      guard let data = try? editorController.selectionPayloadData(),
        data.count <= SionArchiveConstants.maximumEntryByteCount
      else {
        return false
      }

      let item = NSPasteboardItem()
      guard item.setData(data, forType: PasteboardType.selection) else { return false }

      let text = editorController.selectedElements.compactMap(\.editableText).joined(
        separator: "\n")
      if !text.isEmpty {
        item.setString(text, forType: .string)
      }

      pasteboard.clearContents()
      return pasteboard.writeObjects([item])
    }

    private func hasPasteableContent(in pasteboard: NSPasteboard) -> Bool {
      let changeCount = pasteboard.changeCount
      if let pasteboardValidation,
        pasteboardValidation.changeCount == changeCount
      {
        return pasteboardValidation.isPasteable
      }

      let isPasteable = pasteboardContainsAcceptedContent(pasteboard)
      pasteboardValidation = PasteboardValidation(
        changeCount: changeCount,
        isPasteable: isPasteable
      )
      return isPasteable
    }

    /// Provider-backed data is read once per pasteboard revision.
    private func pasteboardContainsAcceptedContent(_ pasteboard: NSPasteboard) -> Bool {
      if hasPasteableBinaryContent(in: pasteboard) {
        return true
      }

      if pastedImageFile(from: pasteboard) != nil {
        return true
      }

      guard let text = pasteboard.string(forType: .string) else { return false }

      return !text.isEmpty
    }

    private func hasPasteableBinaryContent(in pasteboard: NSPasteboard) -> Bool {
      for type in PasteboardType.binaryPasteTypes {
        guard let data = pasteboard.data(forType: type), !data.isEmpty,
          data.count <= SionArchiveConstants.maximumEntryByteCount
        else {
          continue
        }

        return true
      }

      return false
    }

    private func pastedImageFile(
      from pasteboard: NSPasteboard
    ) -> (url: URL, type: ImagePasteType)? {
      guard
        let fileURL = pasteboard.readObjects(
          forClasses: [NSURL.self],
          options: [.urlReadingFileURLsOnly: true]
        )?.first as? URL,
        let type = ImagePasteType(fileExtension: fileURL.pathExtension),
        isSupportedAssetSize(fileURL)
      else {
        return nil
      }

      return (fileURL, type)
    }

    private func pasteSelection(from pasteboard: NSPasteboard, at point: SionPoint) -> Bool {
      guard let data = pasteboard.data(forType: PasteboardType.selection),
        !data.isEmpty,
        data.count <= SionArchiveConstants.maximumEntryByteCount
      else {
        return false
      }

      let insertedIDs = try? editorController.insertSelectionPayload(data, at: point)
      return insertedIDs?.isEmpty == false
    }

    private func pasteImage(from pasteboard: NSPasteboard, at point: SionPoint) -> Bool {
      if let file = pastedImageFile(from: pasteboard),
        let data = try? Data(contentsOf: file.url)
      {
        return insertPastedImage(
          data: data,
          type: file.type,
          filename: file.url.lastPathComponent,
          at: point
        )
      }

      for (pasteboardType, imageType) in ImagePasteType.preservedPasteboardTypes {
        guard let data = pasteboard.data(forType: pasteboardType),
          !data.isEmpty,
          data.count <= SionArchiveConstants.maximumEntryByteCount
        else {
          continue
        }

        return insertPastedImage(
          data: data,
          type: imageType,
          filename: nil,
          at: point
        )
      }

      if let source = pasteboard.string(forType: .string),
        source.contains("<svg"),
        source.utf8.count <= SionArchiveConstants.maximumEntryByteCount,
        let data = source.data(using: .utf8)
      {
        return insertPastedImage(
          data: data,
          type: .svg,
          filename: nil,
          at: point
        )
      }

      if let data = pasteboard.data(forType: .png),
        !data.isEmpty,
        data.count <= SionArchiveConstants.maximumEntryByteCount
      {
        return insertPastedImage(data: data, type: .png, filename: nil, at: point)
      }

      return false
    }

    private func insertPastedImage(
      data: Data,
      type: ImagePasteType,
      filename: String?,
      at point: SionPoint
    ) -> Bool {
      guard !data.isEmpty,
        data.count <= SionArchiveConstants.maximumEntryByteCount
      else {
        return false
      }

      Task { @MainActor [weak self] in
        let display = await Task.detached(priority: .userInitiated) {
          SafeImageRenditionBuilder.make(from: data)
        }.value
        guard let self, let display else {
          NSSound.beep()
          return
        }

        do {
          try self.editorController.insertImage(
            originalData: data,
            mediaType: type.mediaType,
            fileExtension: type.fileExtension,
            filename: filename,
            pixelSize: display.sourcePixelSize,
            displayPNGData: display.data,
            displayPixelSize: display.pixelSize,
            at: point
          )
        } catch {
          NSSound.beep()
        }
      }

      return true
    }

    private func isSupportedAssetSize(_ url: URL) -> Bool {
      guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
        let fileSize = values.fileSize
      else {
        return false
      }

      return fileSize > 0 && fileSize <= SionArchiveConstants.maximumEntryByteCount
    }

    private func drawCanvas() {
      let canvas = editorController.document.scene.canvas
      switch canvas.extent {
      case .infinite:
        nsColor(canvas.background).setFill()
        bounds.fill()
      case .fixed(let size):
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let page = viewRect(for: SionRect(origin: .zero, size: size))
        nsColor(canvas.background).setFill()
        page.fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: page).stroke()
      }
    }

    private func drawGrid() {
      let grid = editorController.document.scene.canvas.grid
      let magnification = Double(enclosingScrollView?.magnification ?? 1)
      guard
        let plan = CanvasGridRenderGeometry.plan(
          for: grid,
          magnification: magnification
        )
      else { return }

      let canvasBounds: SionRect
      switch editorController.document.scene.canvas.extent {
      case .infinite:
        canvasBounds = editingCanvasBounds
      case .fixed(let size):
        canvasBounds = SionRect(origin: .zero, size: size)
      }
      let drawingBounds = nsRect(canvasBounds).intersection(visibleModelRect())
      guard !drawingBounds.isEmpty else { return }

      guard
        let xIndices = gridLineIndices(
          from: drawingBounds.minX,
          through: drawingBounds.maxX,
          spacing: plan.lineSpacing
        ),
        let yIndices = gridLineIndices(
          from: drawingBounds.minY,
          through: drawingBounds.maxY,
          spacing: plan.lineSpacing
        )
      else {
        return
      }

      let majorPath = NSBezierPath()
      let subdivisionPath = NSBezierPath()
      for index in xIndices {
        let x = CGFloat(Double(index) * plan.lineSpacing)
        let path =
          index.isMultiple(of: plan.linesPerMajor) ? majorPath : subdivisionPath
        path.move(to: NSPoint(x: x, y: drawingBounds.minY))
        path.line(to: NSPoint(x: x, y: drawingBounds.maxY))
      }
      for index in yIndices {
        let y = CGFloat(Double(index) * plan.lineSpacing)
        let path =
          index.isMultiple(of: plan.linesPerMajor) ? majorPath : subdivisionPath
        path.move(to: NSPoint(x: drawingBounds.minX, y: y))
        path.line(to: NSPoint(x: drawingBounds.maxX, y: y))
      }

      let lineWidth = CanvasMetrics.gridScreenLineWidth * inverseMagnification
      NSColor.separatorColor.withAlphaComponent(
        CanvasMetrics.subdivisionGridOpacity
      ).setStroke()
      subdivisionPath.lineWidth = lineWidth
      subdivisionPath.stroke()

      NSColor.separatorColor.withAlphaComponent(
        CanvasMetrics.majorGridOpacity
      ).setStroke()
      majorPath.lineWidth = lineWidth
      majorPath.stroke()
    }

    private func gridLineIndices(
      from minimum: CGFloat,
      through maximum: CGFloat,
      spacing: Double
    ) -> ClosedRange<Int>? {
      let first = floor(Double(minimum) / spacing)
      let last = floor(Double(maximum) / spacing)
      guard first.isFinite,
        last.isFinite,
        let firstIndex = Int(exactly: first),
        let lastIndex = Int(exactly: last),
        firstIndex <= lastIndex
      else {
        return nil
      }

      return firstIndex...lastIndex
    }

    private func drawElements() {
      let scene = editorController.document.scene

      for element in scene.elements where element.visibility == .visible {
        draw(element)
      }
    }

    private func draw(_ element: SceneElement) {
      let drawsArtwork = clampedUnit(element.style.opacity) > 0
      let isSelected = editorController.selection.contains(element.id)
      guard drawsArtwork || isSelected else { return }

      let route = connectorRouteProvider(element)
      guard element.content.connector == nil || route != nil else {
        if !rendersOffscreenPreview, isSelected {
          drawSelection(for: element)
        }

        return
      }

      if drawsArtwork {
        drawArtwork(of: element, route: route)
      }

      // Selection chrome is interaction state, not document content.
      guard !rendersOffscreenPreview, isSelected else {
        return
      }
      if let route {
        drawConnectorSelection(route)
        return
      }

      drawSelection(for: element)
    }

    private func drawArtwork(
      of element: SceneElement,
      route: ConnectorRoute?
    ) {
      let opacity = clampedUnit(element.style.opacity)
      guard opacity > 0 else { return }

      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }

      guard let context = NSGraphicsContext.current?.cgContext else { return }

      let usesTransparencyLayer = requiresTransparencyLayer(element.style)
      if usesTransparencyLayer {
        context.setAlpha(opacity)
        context.setBlendMode(blendMode(element.style.blendMode))
        applyShadow(element.style.shadows.first)

        let bounds = SceneRenderGeometry.paintedBounds(of: element, route: route)
        // Bound the layer to this artwork; a canvas-sized layer would stutter.
        context.beginTransparencyLayer(in: nsRect(bounds), auxiliaryInfo: nil)
      }

      if let route {
        drawConnectorArtwork(element, route: route)
      } else {
        applyRotation(of: element)
        drawNonConnectorArtwork(element)
      }

      if usesTransparencyLayer {
        context.endTransparencyLayer()
      }
    }

    private func drawNonConnectorArtwork(_ element: SceneElement) {
      switch element.content {
      case .shape(let shape):
        let path = shapePath(shape.kind, frame: element.geometry.frame)
        drawStyle(element.style, path: path)
        if let label = shape.label, element.id != editedElementID {
          drawText(label, frame: element.geometry.frame)
        }
      case .path(let content):
        let path = vectorPath(content.path, frame: element.geometry.frame)
        drawStyle(element.style, path: path)
      case .text(let text):
        if element.id != editedElementID {
          drawText(text, frame: element.geometry.frame)
        }
      case .image(let image):
        drawImage(image, frame: element.geometry.frame)
      case .group:
        break
      case .connector:
        break
      }
    }

    private func drawStyle(_ style: ElementStyle, path: NSBezierPath) {
      NSGraphicsContext.saveGraphicsState()

      switch style.fill {
      case .none:
        break
      case .solid(let color):
        nsColor(color).setFill()
        path.fill()
      case .linearGradient(let gradient):
        drawLinearGradient(gradient, in: path)
      }

      if let stroke = style.stroke, stroke.width.isFinite, stroke.width > 0 {
        nsColor(stroke.color).setStroke()
        path.lineWidth = CGFloat(stroke.width)
        let dashPattern = stroke.dashPattern.compactMap { value -> CGFloat? in
          guard value.isFinite, value > 0 else { return nil }

          return CGFloat(value)
        }
        path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        path.lineCapStyle = lineCap(stroke.lineCap)
        path.lineJoinStyle = lineJoin(stroke.lineJoin)
        path.stroke()
      }

      NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLinearGradient(_ gradient: LinearGradientFill, in path: NSBezierPath) {
      guard gradient.stops.count > 1 else {
        if let color = gradient.stops.first?.color {
          nsColor(color).setFill()
          path.fill()
        }

        return
      }

      let bounds = path.bounds
      let start = gradientPoint(gradient.start, in: bounds)
      let end = gradientPoint(gradient.end, in: bounds)
      guard start != end else {
        guard let color = gradient.stops.last?.color else { return }

        nsColor(color).setFill()
        path.fill()
        return
      }
      guard let drawing = paddedGradient(gradient, start: start, end: end, bounds: bounds)
      else {
        return
      }

      let colors = drawing.stops.map { nsColor($0.color) }
      let locations = drawing.stops.map { CGFloat($0.location) }
      let renderedGradient = locations.withUnsafeBufferPointer { buffer in
        NSGradient(
          colors: colors,
          atLocations: buffer.baseAddress,
          colorSpace: NSColorSpace.sRGB
        )
      }
      guard let renderedGradient else { return }

      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }

      path.addClip()
      renderedGradient.draw(from: drawing.start, to: drawing.end, options: [])
    }

    private func gradientPoint(_ point: SionPoint, in bounds: NSRect) -> NSPoint {
      NSPoint(
        x: bounds.minX + (bounds.width * CGFloat(point.x)),
        y: bounds.minY + (bounds.height * CGFloat(point.y))
      )
    }

    private func paddedGradient(
      _ gradient: LinearGradientFill,
      start: NSPoint,
      end: NSPoint,
      bounds: NSRect
    ) -> (start: NSPoint, end: NSPoint, stops: [GradientStop])? {
      let dx = end.x - start.x
      let dy = end.y - start.y
      let squaredLength = (dx * dx) + (dy * dy)
      guard squaredLength > 0 else { return nil }

      let corners = [
        NSPoint(x: bounds.minX, y: bounds.minY),
        NSPoint(x: bounds.maxX, y: bounds.minY),
        NSPoint(x: bounds.maxX, y: bounds.maxY),
        NSPoint(x: bounds.minX, y: bounds.maxY),
      ]
      let projections = corners.map { point in
        (((point.x - start.x) * dx) + ((point.y - start.y) * dy)) / squaredLength
      }
      guard let minimum = projections.min(), let maximum = projections.max() else {
        return nil
      }

      let lowerBound = min(0, minimum)
      let upperBound = max(1, maximum)
      let span = upperBound - lowerBound
      guard span > 0 else { return nil }

      // Extend the sRGB domain across the clip, matching SVG's constant colors
      // before the first point and after the last.
      var stops = gradient.stops.map { stop in
        GradientStop(
          color: stop.color,
          location: Double((CGFloat(stop.location) - lowerBound) / span)
        )
      }
      if let first = stops.first, first.location > 0 {
        stops.insert(GradientStop(color: first.color, location: 0), at: 0)
      }
      if let last = stops.last, last.location < 1 {
        stops.append(GradientStop(color: last.color, location: 1))
      }

      return (
        start: NSPoint(x: start.x + (dx * lowerBound), y: start.y + (dy * lowerBound)),
        end: NSPoint(x: start.x + (dx * upperBound), y: start.y + (dy * upperBound)),
        stops: stops
      )
    }

    private func drawText(_ content: TextContent, frame: SionRect) {
      let style = content.style
      let bounds = nsRect(frame)
      let leading = finiteNonnegative(style.insets.leading)
      let trailing = finiteNonnegative(style.insets.trailing)
      let top = finiteNonnegative(style.insets.top)
      let bottom = finiteNonnegative(style.insets.bottom)
      let rect = NSRect(
        x: bounds.minX + leading,
        y: bounds.minY + top,
        width: max(0, bounds.width - leading - trailing),
        height: max(0, bounds.height - top - bottom)
      )
      let rendered = cachedTextRender(for: content, width: rect.width)
      let drawingRect = verticallyAlignedRect(
        NSRect(x: 0, y: 0, width: rect.width, height: rendered.measuredHeight),
        in: rect,
        alignment: style.verticalAlignment)
      rendered.attributed.draw(
        with: drawingRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    /// Text measurement dominates redraws once routing is cached, so keep one
    /// layout per (text, style, width). Keys carry everything that affects it.
    private func cachedTextRender(for content: TextContent, width: CGFloat) -> TextRender {
      let key = TextRenderKey(content: content, width: width)
      if let cached = textRenderCache[key] {
        return cached
      }

      let style = content.style
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = textAlignment(style.horizontalAlignment)
      paragraph.lineSpacing = finiteNonnegative(style.lineSpacing)
      paragraph.paragraphSpacing = finiteNonnegative(style.paragraphSpacing)

      let attributes: [NSAttributedString.Key: Any] = [
        .font: nsFont(style),
        .foregroundColor: nsColor(style.color),
        .paragraphStyle: paragraph,
      ]
      let attributed = NSAttributedString(string: content.string, attributes: attributes)
      let measured = attributed.boundingRect(
        with: NSSize(
          // The bucket's lower edge is safe for every width mapped to it.
          width: CGFloat(key.widthBucket) / 2,
          height: .greatestFiniteMagnitude
        ),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
      )
      let render = TextRender(
        attributed: attributed,
        measuredHeight: ceil(measured.height)
      )

      if textRenderCache.count >= CanvasMetrics.textRenderCacheLimit {
        let evictionCount = max(
          1,
          CanvasMetrics.textRenderCacheLimit
            / CanvasMetrics.textRenderCacheEvictionDivisor
        )
        // Arbitrary partial eviction avoids a full-cache miss spike.
        let evictedKeys = Array(textRenderCache.keys.prefix(evictionCount))
        for evictedKey in evictedKeys {
          textRenderCache.removeValue(forKey: evictedKey)
        }
      }
      textRenderCache[key] = render
      return render
    }

    private func drawImage(_ content: ImageContent, frame: SionRect) {
      guard let image = editorController.image(for: content) else {
        drawMissingImage(in: frame)
        return
      }

      let bounds = nsRect(frame)
      if content.scalingMode == .tile {
        drawTiled(image, in: bounds, interpolationMode: content.interpolation)
        return
      }

      let drawingRect = imageRect(for: image.size, in: bounds, mode: content.scalingMode)
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: bounds).addClip()
      image.draw(
        in: drawingRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: interpolation(content.interpolation)]
      )
      NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTiled(
      _ image: NSImage,
      in bounds: NSRect,
      interpolationMode: ImageInterpolation
    ) {
      guard image.size.width.isFinite,
        image.size.height.isFinite,
        image.size.width > 0,
        image.size.height > 0
      else {
        return
      }

      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: bounds).addClip()

      // Offscreen previews cover the whole tile; on screen we cull.
      let drawingBounds =
        rendersOffscreenPreview
        ? bounds
        : bounds.intersection(visibleModelRect())
      guard !drawingBounds.isEmpty else {
        NSGraphicsContext.restoreGraphicsState()
        return
      }

      // Quartz repeats the tile as one bounded pattern operation.
      NSGraphicsContext.current?.imageInterpolation = interpolation(interpolationMode)
      NSGraphicsContext.current?.cgContext.setPatternPhase(
        CGSize(width: bounds.minX, height: bounds.minY)
      )
      NSColor(patternImage: image).setFill()
      drawingBounds.fill()

      NSGraphicsContext.restoreGraphicsState()
    }

    private func imageRect(
      for imageSize: NSSize,
      in bounds: NSRect,
      mode: ImageScalingMode
    ) -> NSRect {
      guard mode != .stretch,
        imageSize.width.isFinite,
        imageSize.height.isFinite,
        imageSize.width > 0,
        imageSize.height > 0
      else {
        return bounds
      }

      let widthScale = bounds.width / imageSize.width
      let heightScale = bounds.height / imageSize.height
      let scale =
        mode == .fill
        ? max(widthScale, heightScale)
        : min(widthScale, heightScale)
      let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
      return NSRect(
        x: bounds.midX - (size.width / 2),
        y: bounds.midY - (size.height / 2),
        width: size.width,
        height: size.height
      )
    }

    private func drawMissingImage(in frame: SionRect) {
      let rect = nsRect(frame)
      NSColor.quaternaryLabelColor.setFill()
      rect.fill()
      NSColor.secondaryLabelColor.setStroke()
      NSBezierPath(rect: rect).stroke()
    }

    private func drawConnectorArtwork(_ element: SceneElement, route: ConnectorRoute) {
      guard case .connector(let content) = element.content else { return }

      let path = connectorPath(route)

      drawStyle(element.style, path: path)
      drawDecoration(
        content.sourceDecoration,
        at: route.start,
        toward: route.polylinePoints.dropFirst().first,
        style: element.style
      )
      drawDecoration(
        content.targetDecoration,
        at: route.end,
        toward: route.polylinePoints.dropLast().last,
        style: element.style
      )

      if let label = content.label, element.id != editedElementID {
        let point = route.point(atFraction: content.labelPosition)
        let frame = SionRect(
          x: point.x - (CanvasMetrics.connectorLabelSize.width / 2),
          y: point.y - (CanvasMetrics.connectorLabelSize.height / 2),
          width: CanvasMetrics.connectorLabelSize.width,
          height: CanvasMetrics.connectorLabelSize.height
        )
        drawText(label, frame: frame)
      }
    }

    private func drawConnectorSelection(_ route: ConnectorRoute) {
      let path = connectorPath(route)
      NSColor.controlAccentColor.setStroke()
      guard let selected = path.copy() as? NSBezierPath else { return }
      selected.lineWidth = CanvasMetrics.selectionLineWidth
      selected.setLineDash(
        CanvasMetrics.selectionDash, count: CanvasMetrics.selectionDash.count, phase: 0)
      selected.stroke()
    }

    private func drawDecoration(
      _ decoration: ConnectorDecoration,
      at point: SionPoint,
      toward previous: SionPoint?,
      style: ElementStyle
    ) {
      guard decoration != .none, let previous else { return }

      let angle = atan2(point.y - previous.y, point.x - previous.x)
      var transform = AffineTransform()
      transform.translate(x: point.x, y: point.y)
      transform.rotate(byRadians: angle)

      let path: NSBezierPath
      switch decoration {
      case .none:
        return
      case .openArrow, .filledArrow:
        path = NSBezierPath()
        path.move(to: NSPoint(x: -CanvasMetrics.arrowLength, y: -CanvasMetrics.arrowWidth))
        path.line(to: .zero)
        path.line(to: NSPoint(x: -CanvasMetrics.arrowLength, y: CanvasMetrics.arrowWidth))
        if decoration == .filledArrow {
          path.close()
        }
      case .circle:
        path = NSBezierPath(
          ovalIn: NSRect(
            x: -CanvasMetrics.decorationRadius,
            y: -CanvasMetrics.decorationRadius,
            width: CanvasMetrics.decorationRadius * 2,
            height: CanvasMetrics.decorationRadius * 2
          ))
      case .diamond:
        path = NSBezierPath()
        path.move(to: .zero)
        path.line(
          to: NSPoint(x: -CanvasMetrics.decorationRadius, y: -CanvasMetrics.decorationRadius))
        path.line(to: NSPoint(x: -(CanvasMetrics.decorationRadius * 2), y: 0))
        path.line(
          to: NSPoint(x: -CanvasMetrics.decorationRadius, y: CanvasMetrics.decorationRadius))
        path.close()
      }

      path.transform(using: transform)
      let color = nsColor(style.stroke?.color ?? .primaryInk)
      color.setStroke()
      path.lineWidth = CGFloat(max(style.stroke?.width ?? CanvasMetrics.defaultConnectorWidth, 1))
      path.stroke()
      if decoration == .filledArrow {
        color.setFill()
        path.fill()
      }
    }

    private func drawSelection(for element: SceneElement) {
      let selectionFrame = element.geometry.frame.standardized.expanded(
        by: CanvasMetrics.selectionInset * inverseMagnification
      )
      let selectionCorners = [
        ResizeHandle.northWest,
        .northEast,
        .southEast,
        .southWest,
      ].map {
        InteractionGeometry.resizeHandlePoint(
          $0,
          in: selectionFrame,
          rotationRadians: element.geometry.rotationRadians
        )
      }
      let path = polygonPath(selectionCorners.map(nsPoint))
      NSColor.controlAccentColor.setStroke()
      path.lineWidth = CanvasMetrics.selectionLineWidth * inverseMagnification
      let selectionDash = CanvasMetrics.selectionDash.map {
        $0 * CGFloat(inverseMagnification)
      }
      path.setLineDash(
        selectionDash,
        count: selectionDash.count,
        phase: 0
      )
      path.stroke()

      guard editorController.selectedElement?.id == element.id,
        element.lockState == .editable,
        element.content.connector == nil
      else {
        return
      }

      for handle in ResizeHandle.allCases {
        drawSquareHandle(at: resizeHandlePoint(handle, for: element))
      }

      let north = resizeHandlePoint(.north, for: element)
      let rotation = rotationHandlePoint(for: element)
      let stem = NSBezierPath()
      stem.move(to: nsPoint(north))
      stem.line(to: nsPoint(rotation))
      stem.lineWidth = CanvasMetrics.selectionLineWidth * inverseMagnification
      stem.stroke()
      drawRoundHandle(at: rotation)

      if let radiusHandle = cornerRadiusHandlePoint(for: element) {
        drawDiamondHandle(at: radiusHandle)
      }
    }

    private func drawSquareHandle(at point: SionPoint) {
      let radius = CanvasMetrics.resizeHandleRadius * inverseMagnification
      let rect = NSRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      NSColor.controlBackgroundColor.setFill()
      NSColor.controlAccentColor.setStroke()
      NSBezierPath(rect: rect).fill()
      NSBezierPath(rect: rect).stroke()
    }

    private func drawRoundHandle(at point: SionPoint) {
      let radius = CanvasMetrics.rotationHandleRadius * inverseMagnification
      let rect = NSRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      NSColor.controlBackgroundColor.setFill()
      NSColor.controlAccentColor.setStroke()
      NSBezierPath(ovalIn: rect).fill()
      NSBezierPath(ovalIn: rect).stroke()
    }

    private func drawDiamondHandle(at point: SionPoint) {
      let radius = CanvasMetrics.cornerRadiusHandleRadius * inverseMagnification
      let path = polygonPath([
        NSPoint(x: point.x, y: point.y - radius),
        NSPoint(x: point.x + radius, y: point.y),
        NSPoint(x: point.x, y: point.y + radius),
        NSPoint(x: point.x - radius, y: point.y),
      ])
      NSColor.systemYellow.setFill()
      NSColor.controlAccentColor.setStroke()
      path.fill()
      path.stroke()
    }

    private func drawConnectionMagnets() {
      let scene = editorController.document.scene
      if let id = editorController.anchorEditingState.elementID {
        guard let element = scene.element(withID: id), element.visibility == .visible else {
          return
        }

        for resolved in element.resolvedMagnets {
          drawEditableAnchor(resolved)
        }
        return
      }

      let showsAll = editorController.tool == .connector || isCreatingConnector
      let elements = scene.elements.filter { element in
        guard element.visibility == .visible, element.content.connector == nil else {
          return false
        }

        return showsAll || editorController.selection.contains(element.id)
      }

      for element in elements {
        for resolved in element.resolvedMagnets {
          drawConnectionMagnet(resolved)
        }
      }
    }

    private var isCreatingConnector: Bool {
      guard case .connector = drag else { return false }

      return true
    }

    private func drawConnectionMagnet(_ resolved: ResolvedMagnet) {
      let endpoint = resolved.endpoint.point
      let displayPoint = magnetDisplayPoint(resolved)
      let line = NSBezierPath()
      line.move(to: nsPoint(endpoint))
      line.line(to: nsPoint(displayPoint))
      NSColor.controlAccentColor.withAlphaComponent(CanvasMetrics.magnetStemOpacity).setStroke()
      line.lineWidth = CanvasMetrics.magnetStemWidth * inverseMagnification
      line.stroke()

      let radius = CanvasMetrics.magnetRadius * inverseMagnification
      let dot = NSRect(
        x: displayPoint.x - radius,
        y: displayPoint.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      NSColor.controlBackgroundColor.setFill()
      NSColor.controlAccentColor.setStroke()
      NSBezierPath(ovalIn: dot).fill()
      NSBezierPath(ovalIn: dot).stroke()
    }

    private func drawEditableAnchor(_ resolved: ResolvedMagnet) {
      let point = resolved.endpoint.point
      let radius = CanvasMetrics.anchorEditingRadius * inverseMagnification
      let dot = NSRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      NSColor.systemOrange.setFill()
      NSColor.controlBackgroundColor.setStroke()
      let path = NSBezierPath(ovalIn: dot)
      path.lineWidth = CanvasMetrics.selectionLineWidth * inverseMagnification
      path.fill()
      path.stroke()
    }

    private func drawCreationPreview() {
      guard case .create(let creation, let start, let current) = drag else { return }

      let frame = creationPlacement(creation, from: start, to: current).frame
      let path: NSBezierPath
      switch creation {
      case .shape(let kind):
        path = shapePath(kind, frame: frame)
      case .text:
        path = NSBezierPath(rect: nsRect(frame))
      }

      NSColor.controlAccentColor.withAlphaComponent(CanvasMetrics.creationFillOpacity).setFill()
      NSColor.controlAccentColor.setStroke()
      path.fill()
      path.lineWidth = CanvasMetrics.selectionLineWidth * inverseMagnification
      let previewDash = CanvasMetrics.previewDash.map {
        $0 * CGFloat(inverseMagnification)
      }
      path.setLineDash(previewDash, count: previewDash.count, phase: 0)
      path.stroke()
    }

    private func drawMarquee() {
      guard case .marquee(let origin, let current) = drag else { return }

      let start = NSPoint(x: origin.x, y: origin.y)
      let end = NSPoint(x: current.x, y: current.y)
      let rect = NSRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
      )
      guard
        rect.width >= minimumMarqueeModelSize
          || rect.height >= minimumMarqueeModelSize
      else { return }

      NSColor.controlAccentColor.withAlphaComponent(CanvasMetrics.marqueeFillOpacity).setFill()
      rect.fill()
      NSColor.controlAccentColor.setStroke()
      let border = NSBezierPath(rect: rect)
      border.lineWidth = CanvasMetrics.selectionLineWidth * inverseMagnification
      let marqueeDash = CanvasMetrics.selectionDash.map {
        $0 * CGFloat(inverseMagnification)
      }
      border.setLineDash(
        marqueeDash,
        count: marqueeDash.count,
        phase: 0
      )
      border.stroke()
    }

    /// Commits the rubber band: touched elements join the selection, replacing
    /// it unless Shift extends at release time.
    private func endMarquee(
      from origin: SionPoint,
      to current: SionPoint,
      mode: SionEditorController.SelectionMode
    ) {
      let marqueeRect = SionRect(
        origin: origin,
        size: SionSize(width: current.x - origin.x, height: current.y - origin.y)
      ).standardized
      guard
        marqueeRect.width >= minimumMarqueeModelSize
          || marqueeRect.height >= minimumMarqueeModelSize
      else { return }

      editorController.select(
        editorController.elementIDsIntersecting(marqueeRect),
        mode: mode
      )
    }

    private var minimumMarqueeModelSize: Double {
      CanvasMetrics.minimumMarqueeScreenSize * inverseMagnification
    }

    private func drawConnectorPreview() {
      guard case .connector(let sourceID, let start, let current) = drag else { return }

      let targetID = editorController.connectableElement(at: current)?.id
      guard
        let route = editorController.connectorPreview(
          from: sourceID,
          sourcePoint: start,
          to: targetID,
          targetPoint: current
        )
      else {
        return
      }

      let path = connectorPath(route)
      NSColor.controlAccentColor.setStroke()
      path.lineWidth = 2
      path.setLineDash(CanvasMetrics.previewDash, count: CanvasMetrics.previewDash.count, phase: 0)
      path.stroke()
    }

    private func connectorPath(_ route: ConnectorRoute) -> NSBezierPath {
      let path = NSBezierPath()
      path.move(to: nsPoint(route.start))

      for segment in route.segments {
        switch segment {
        case .line(let to):
          path.line(to: nsPoint(to))
        case .quadratic(let control, let to):
          let current = sionPoint(path.currentPoint)
          let first = current + ((control - current) * (2.0 / 3.0))
          let second = to + ((control - to) * (2.0 / 3.0))
          path.curve(
            to: nsPoint(to),
            controlPoint1: nsPoint(first),
            controlPoint2: nsPoint(second)
          )
        case .cubic(let control1, let control2, let to):
          path.curve(
            to: nsPoint(to),
            controlPoint1: nsPoint(control1),
            controlPoint2: nsPoint(control2)
          )
        }
      }

      return path
    }

    private func shapePath(_ kind: ShapeKind, frame: SionRect) -> NSBezierPath {
      let rect = nsRect(frame)

      switch kind {
      case .rectangle:
        return NSBezierPath(rect: rect)
      case .roundedRectangle(let radius):
        let clampedRadius = min(
          min(rect.width, rect.height) / 2,
          max(0, radius.isFinite ? radius : 0)
        )
        return NSBezierPath(
          roundedRect: rect,
          xRadius: clampedRadius,
          yRadius: clampedRadius
        )
      case .ellipse:
        return NSBezierPath(ovalIn: rect)
      case .capsule:
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
      case .diamond:
        return polygonPath([
          NSPoint(x: rect.midX, y: rect.minY),
          NSPoint(x: rect.maxX, y: rect.midY),
          NSPoint(x: rect.midX, y: rect.maxY),
          NSPoint(x: rect.minX, y: rect.midY),
        ])
      case .triangle:
        return polygonPath([
          NSPoint(x: rect.midX, y: rect.minY),
          NSPoint(x: rect.maxX, y: rect.maxY),
          NSPoint(x: rect.minX, y: rect.maxY),
        ])
      case .hexagon:
        let inset = rect.width * CGFloat(ShapeGeometryDefaults.hexagonInsetFraction)
        return polygonPath([
          NSPoint(x: rect.minX + inset, y: rect.minY),
          NSPoint(x: rect.maxX - inset, y: rect.minY),
          NSPoint(x: rect.maxX, y: rect.midY),
          NSPoint(x: rect.maxX - inset, y: rect.maxY),
          NSPoint(x: rect.minX + inset, y: rect.maxY),
          NSPoint(x: rect.minX, y: rect.midY),
        ])
      case .cylinder:
        return cylinderPath(in: rect)
      case .custom(let path):
        return vectorPath(path, frame: frame)
      }
    }

    private func vectorPath(_ content: VectorPath, frame: SionRect) -> NSBezierPath {
      let path = NSBezierPath()
      let rect = frame.standardized
      var current = NSPoint(x: rect.minX, y: rect.minY)
      var hasCurrent = false

      func point(_ value: SionPoint) -> NSPoint {
        guard content.coordinateSpace == .normalized else {
          return NSPoint(x: rect.minX + value.x, y: rect.minY + value.y)
        }

        return NSPoint(
          x: rect.minX + (rect.width * value.x),
          y: rect.minY + (rect.height * value.y)
        )
      }

      for command in content.commands {
        switch command {
        case .move(let to):
          current = point(to)
          path.move(to: current)
          hasCurrent = true
        case .line(let to):
          if !hasCurrent {
            path.move(to: current)
          }
          current = point(to)
          path.line(to: current)
          hasCurrent = true
        case .quadratic(let control, let to):
          if !hasCurrent {
            path.move(to: current)
          }
          let controlPoint = point(control)
          let end = point(to)
          let first = NSPoint(
            x: current.x + ((controlPoint.x - current.x) * (2 / 3)),
            y: current.y + ((controlPoint.y - current.y) * (2 / 3))
          )
          let second = NSPoint(
            x: end.x + ((controlPoint.x - end.x) * (2 / 3)),
            y: end.y + ((controlPoint.y - end.y) * (2 / 3))
          )
          path.curve(to: end, controlPoint1: first, controlPoint2: second)
          current = end
          hasCurrent = true
        case .cubic(let control1, let control2, let to):
          if !hasCurrent {
            path.move(to: current)
          }
          current = point(to)
          path.curve(to: current, controlPoint1: point(control1), controlPoint2: point(control2))
          hasCurrent = true
        case .close:
          if hasCurrent {
            path.close()
          }
        }
      }

      path.windingRule = content.fillRule == .evenOdd ? .evenOdd : .nonZero
      return path
    }

    private func polygonPath(_ points: [NSPoint]) -> NSBezierPath {
      let path = NSBezierPath()
      guard let first = points.first else { return path }

      path.move(to: first)
      for point in points.dropFirst() {
        path.line(to: point)
      }
      path.close()
      return path
    }

    private func cylinderPath(in rect: NSRect) -> NSBezierPath {
      let arcHeight = min(
        rect.height * CGFloat(ShapeGeometryDefaults.cylinderArcFraction),
        rect.height / 2
      )
      let horizontalControl = (rect.width / 2) * CanvasMetrics.curveControlFactor
      let verticalControl = arcHeight * CanvasMetrics.curveControlFactor
      let path = NSBezierPath()

      path.move(to: NSPoint(x: rect.minX, y: rect.minY + arcHeight))
      path.curve(
        to: NSPoint(x: rect.midX, y: rect.minY),
        controlPoint1: NSPoint(x: rect.minX, y: rect.minY + arcHeight - verticalControl),
        controlPoint2: NSPoint(x: rect.midX - horizontalControl, y: rect.minY)
      )
      path.curve(
        to: NSPoint(x: rect.maxX, y: rect.minY + arcHeight),
        controlPoint1: NSPoint(x: rect.midX + horizontalControl, y: rect.minY),
        controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + arcHeight - verticalControl)
      )
      path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - arcHeight))
      path.curve(
        to: NSPoint(x: rect.midX, y: rect.maxY),
        controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - arcHeight + verticalControl),
        controlPoint2: NSPoint(x: rect.midX + horizontalControl, y: rect.maxY)
      )
      path.curve(
        to: NSPoint(x: rect.minX, y: rect.maxY - arcHeight),
        controlPoint1: NSPoint(x: rect.midX - horizontalControl, y: rect.maxY),
        controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - arcHeight + verticalControl)
      )
      path.close()
      return path
    }

    /// Infinite canvases grow monotonically so a drag cannot move the viewport under the pointer.
    private func synchronizeCanvasBounds() {
      let scene = editorController.document.scene
      let requiredBounds = editorController.editingCanvasBounds(
        minimumInfiniteSize: CanvasMetrics.minimumInfiniteSize
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
      setFrameSize(NSSize(width: nextBounds.width, height: nextBounds.height))
      updateTextEditorFrame()

      guard let scrollView = enclosingScrollView else { return }

      let visibleSize = scrollView.contentView.bounds.size
      let viewCenter = viewPoint(for: preservedCenter)
      let origin = NSPoint(
        x: max(0, viewCenter.x - (visibleSize.width / 2)),
        y: max(0, viewCenter.y - (visibleSize.height / 2))
      )
      scrollView.contentView.scroll(to: origin)
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func applyCanvasTransform() {
      let transform = NSAffineTransform()
      transform.translateX(
        by: -editingCanvasBounds.minX,
        yBy: -editingCanvasBounds.minY
      )
      transform.concat()
    }

    private func applyRotation(of element: SceneElement) {
      guard element.geometry.rotationRadians != 0 else { return }

      let center = element.geometry.frame.center
      let transform = NSAffineTransform()
      transform.translateX(by: center.x, yBy: center.y)
      transform.rotate(byRadians: element.geometry.rotationRadians)
      transform.translateX(by: -center.x, yBy: -center.y)
      transform.concat()
    }

    private func applyShadow(_ style: ShadowStyle?) {
      guard let style,
        style.blurRadius.isFinite,
        style.offset.dx.isFinite,
        style.offset.dy.isFinite
      else {
        return
      }

      let shadow = NSShadow()
      shadow.shadowColor = nsColor(style.color)
      shadow.shadowBlurRadius = max(0, style.blurRadius)
      shadow.shadowOffset = NSSize(width: style.offset.dx, height: style.offset.dy)
      shadow.set()
    }

    private func visibleCanvasCenter() -> SionPoint {
      let visible = visibleRect
      guard enclosingScrollView != nil, visible.width > 0, visible.height > 0 else {
        return editingCanvasBounds.center
      }

      return modelPoint(from: NSPoint(x: visible.midX, y: visible.midY))
    }

    func viewPoint(for modelPoint: SionPoint) -> NSPoint {
      NSPoint(
        x: modelPoint.x - editingCanvasBounds.minX,
        y: modelPoint.y - editingCanvasBounds.minY
      )
    }

    private func viewRect(for modelRect: SionRect) -> NSRect {
      let rect = modelRect.standardized
      let origin = viewPoint(for: SionPoint(x: rect.minX, y: rect.minY))
      return NSRect(origin: origin, size: NSSize(width: rect.width, height: rect.height))
    }

    private func modelPoint(from viewPoint: NSPoint) -> SionPoint {
      SionPoint(
        x: viewPoint.x + editingCanvasBounds.minX,
        y: viewPoint.y + editingCanvasBounds.minY
      )
    }

    private func visibleModelRect() -> NSRect {
      let visible = visibleRect
      return NSRect(
        x: visible.minX + editingCanvasBounds.minX,
        y: visible.minY + editingCanvasBounds.minY,
        width: visible.width,
        height: visible.height
      )
    }

    private func updateAccessibilitySummary() {
      let elementCount = editorController.document.scene.elements.count
      let selectionCount = editorController.selection.count
      setAccessibilityValue(
        "\(elementCount) elements, \(selectionCount) selected"
      )
    }

    private func updateAccessibilityHelp() {
      if editorController.anchorEditingState != .inactive {
        setAccessibilityHelp(
          "Edit connector anchors. Click the object to add; click an anchor to remove; Escape ends."
        )
        return
      }

      setAccessibilityHelp(
        "\(editorController.tool.help). Use Tab to select; use arrow keys to move."
      )
    }

    private func modelPoint(from event: NSEvent) -> SionPoint {
      modelPoint(from: convert(event.locationInWindow, from: nil))
    }

    private var inverseMagnification: Double {
      1 / max(Double(enclosingScrollView?.magnification ?? 1), 0.01)
    }

    private func resizeHandle(at point: SionPoint, for element: SceneElement) -> ResizeHandle? {
      ResizeHandle.allCases.first { handle in
        let handlePoint = InteractionGeometry.resizeHandlePoint(
          handle,
          in: element.geometry.frame,
          rotationRadians: element.geometry.rotationRadians
        )
        return point.distance(to: handlePoint)
          <= CanvasMetrics.handleHitRadius * inverseMagnification
      }
    }

    private func isRotationHandle(_ point: SionPoint, for element: SceneElement) -> Bool {
      let handlePoint = InteractionGeometry.rotationHandlePoint(
        in: element.geometry.frame,
        rotationRadians: element.geometry.rotationRadians,
        offset: CanvasMetrics.rotationHandleOffset * inverseMagnification
      )

      return point.distance(to: handlePoint)
        <= CanvasMetrics.handleHitRadius * inverseMagnification
    }

    private func isCornerRadiusHandle(_ point: SionPoint, for element: SceneElement) -> Bool {
      guard let handlePoint = cornerRadiusHandlePoint(for: element) else { return false }

      return point.distance(to: handlePoint)
        <= CanvasMetrics.handleHitRadius * inverseMagnification
    }

    private func cornerRadius(of element: SceneElement) -> Double? {
      guard case .shape(let shape) = element.content else { return nil }

      switch shape.kind {
      case .rectangle:
        return 0
      case .roundedRectangle(let radius):
        return radius
      case .ellipse, .diamond, .triangle, .hexagon, .capsule, .cylinder, .custom:
        return nil
      }
    }

    private func connectorTarget(at point: SionPoint, use: MagnetUse) -> ConnectorTarget {
      let elements = editorController.document.scene.elements.filter {
        $0.visibility == .visible && $0.content.connector == nil
      }
      if let target = magnetTarget(at: point, use: use, elements: elements) {
        return target
      }

      let element = editorController.connectableElement(at: point)
      return ConnectorTarget(elementID: element?.id, point: point)
    }

    private func magnetTarget(
      at point: SionPoint,
      use: MagnetUse,
      elements: [SceneElement]
    ) -> ConnectorTarget? {
      let tolerance = CanvasMetrics.magnetHitTolerance * inverseMagnification
      var nearest: (distance: Double, target: ConnectorTarget)?

      for element in elements.reversed() {
        for resolved in element.resolvedMagnets
        where resolved.magnet.connectionDirection.allows(use) {
          let displayPoint = magnetDisplayPoint(resolved)
          let distance = point.distance(to: displayPoint)
          guard distance <= tolerance,
            nearest.map({ distance < $0.distance }) ?? true
          else {
            continue
          }

          nearest = (
            distance,
            ConnectorTarget(
              elementID: element.id,
              point: resolved.endpoint.point
            )
          )
        }
      }

      return nearest?.target
    }

    private func magnetDisplayPoint(_ resolved: ResolvedMagnet) -> SionPoint {
      // Keep connector dots separate from the side-resize handles on the outline.
      let offset = CanvasMetrics.magnetOffset * inverseMagnification
      return resolved.endpoint.point + (resolved.endpoint.outwardDirection.normalized * offset)
    }

    private func snappedRotation(
      _ radians: Double,
      modifierFlags: NSEvent.ModifierFlags
    ) -> Double {
      guard modifierFlags.contains(.shift) else { return radians }

      let step = CanvasMetrics.rotationSnapRadians
      return (radians / step).rounded() * step
    }

    private func resizeHandlePoint(
      _ handle: ResizeHandle,
      for element: SceneElement
    ) -> SionPoint {
      InteractionGeometry.resizeHandlePoint(
        handle,
        in: element.geometry.frame,
        rotationRadians: element.geometry.rotationRadians
      )
    }

    private func rotationHandlePoint(for element: SceneElement) -> SionPoint {
      InteractionGeometry.rotationHandlePoint(
        in: element.geometry.frame,
        rotationRadians: element.geometry.rotationRadians,
        offset: CanvasMetrics.rotationHandleOffset * inverseMagnification
      )
    }

    private func cornerRadiusHandlePoint(for element: SceneElement) -> SionPoint? {
      guard let radius = cornerRadius(of: element) else { return nil }
      let frame = element.geometry.frame.standardized
      let maximumRadius = min(frame.width, frame.height) / 2
      let minimumDisplayRadius =
        CanvasMetrics.cornerRadiusHandleMinimumInset
        * inverseMagnification
      let displayRadius = min(maximumRadius, max(radius, minimumDisplayRadius))
      let point = InteractionGeometry.roundedRectangleCornerRadiusHandle(
        in: frame,
        radius: displayRadius,
        rotationRadians: element.geometry.rotationRadians
      )
      let minimumSeparation = CanvasMetrics.handleHitRadius * inverseMagnification
      let overlapsResizeHandle = ResizeHandle.allCases.contains {
        point.distance(to: resizeHandlePoint($0, for: element)) <= minimumSeparation
      }

      return overlapsResizeHandle ? nil : point
    }
  }

  private struct ConnectorTarget {
    let elementID: ElementID?
    let point: SionPoint
  }

  private enum ImagePasteType {
    case png
    case jpeg
    case gif
    case webp
    case pdf
    case svg
    case tiff

    static let svgPasteboardType = NSPasteboard.PasteboardType("public.svg-image")
    static let preservedPasteboardTypes: [(NSPasteboard.PasteboardType, ImagePasteType)] = [
      (.pdf, .pdf),
      (svgPasteboardType, .svg),
      (.tiff, .tiff),
    ]

    init?(fileExtension: String) {
      switch fileExtension.lowercased() {
      case "png": self = .png
      case "jpg", "jpeg": self = .jpeg
      case "gif": self = .gif
      case "webp": self = .webp
      case "pdf": self = .pdf
      case "svg": self = .svg
      case "tif", "tiff": self = .tiff
      default: return nil
      }
    }

    var mediaType: String {
      switch self {
      case .png: "image/png"
      case .jpeg: "image/jpeg"
      case .gif: "image/gif"
      case .webp: "image/webp"
      case .pdf: "application/pdf"
      case .svg: "image/svg+xml"
      case .tiff: "image/tiff"
      }
    }

    var fileExtension: String {
      switch self {
      case .png: "png"
      case .jpeg: "jpg"
      case .gif: "gif"
      case .webp: "webp"
      case .pdf: "pdf"
      case .svg: "svg"
      case .tiff: "tiff"
      }
    }
  }

  private enum CanvasMetrics {
    static let minimumInfiniteSize = SionSize(width: 4_000, height: 3_000)
    static let majorGridOpacity = 0.18
    static let subdivisionGridOpacity = 0.08
    static let gridScreenLineWidth = 0.5
    static let defaultFontSize: CGFloat = 15
    static let selectionInset = 4.0
    static let selectionLineWidth = 1.5
    static let selectionDash: [CGFloat] = [5, 3]
    static let previewDash: [CGFloat] = [7, 4]
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
    static let defaultConnectorWidth = 1.5
    static let curveControlFactor: CGFloat = 0.552_284_749_8
    static let textEditClickCount = 2
    static let connectorLabelSize = SionSize(width: 120, height: 36)
    static let nudgeDistance = 1.0
    static let largeNudgeDistance = 10.0
    static let textRenderCacheLimit = 512
    static let textRenderCacheEvictionDivisor = 4
    static let marqueeFillOpacity = 0.08
    static let minimumMarqueeScreenSize = 2.0
  }

  private enum PreviewMetrics {
    static let maximumDimension: CGFloat = 768
    static let bitsPerSample = 8
    static let samplesPerPixel = 4
  }

  private enum PasteboardType {
    static let selection = NSPasteboard.PasteboardType("ch.lkmc.sion.selection")
    static let binaryPasteTypes: [NSPasteboard.PasteboardType] = [
      selection,
      .pdf,
      ImagePasteType.svgPasteboardType,
      .tiff,
      .png,
    ]
  }

  private enum CanvasKeyCode {
    static let returnKey: UInt16 = 36
    static let escape: UInt16 = 53
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static func nudgeDirection(for keyCode: UInt16) -> SionVector? {
      switch keyCode {
      case leftArrow: .west
      case rightArrow: .east
      case downArrow: .south
      case upArrow: .north
      default: nil
      }
    }
  }

  extension SceneElement {
    fileprivate var editableText: String? {
      switch content {
      case .shape(let shape): shape.label?.string ?? ""
      case .text(let text): text.string
      case .connector(let connector): connector.label?.string ?? ""
      case .path, .image, .group: nil
      }
    }

    fileprivate var textStyle: TextStyle? {
      switch content {
      case .shape(let shape): shape.label?.style ?? .shapeLabelDefault
      case .text(let text): text.style
      case .connector(let connector): connector.label?.style ?? .shapeLabelDefault
      case .path, .image, .group: nil
      }
    }
  }

  private func nsPoint(_ point: SionPoint) -> NSPoint {
    NSPoint(x: point.x, y: point.y)
  }

  private func sionPoint(_ point: NSPoint) -> SionPoint {
    SionPoint(x: point.x, y: point.y)
  }

  private func nsRect(_ rect: SionRect) -> NSRect {
    NSRect(
      x: rect.minX, y: rect.minY, width: rect.standardized.width, height: rect.standardized.height)
  }

  private func nsColor(_ color: SionColor) -> NSColor {
    SionColorBridge.appKitColor(color)
  }

  private func nsFont(_ style: TextStyle) -> NSFont {
    let weight: NSFont.Weight
    switch style.font.weight {
    case .light: weight = .light
    case .regular: weight = .regular
    case .medium: weight = .medium
    case .semibold: weight = .semibold
    case .bold: weight = .bold
    }

    let size =
      style.font.size.isFinite && style.font.size > 0
      ? CGFloat(style.font.size)
      : CanvasMetrics.defaultFontSize

    switch style.font.family {
    case .system:
      return .systemFont(ofSize: size, weight: weight)
    case .named(let name):
      return NSFont(name: name, size: size)
        ?? .systemFont(ofSize: size, weight: weight)
    }
  }

  private func textAlignment(_ alignment: HorizontalTextAlignment) -> NSTextAlignment {
    switch alignment {
    case .leading: .natural
    case .center: .center
    case .trailing: .right
    case .justified: .justified
    }
  }

  private func verticallyAlignedRect(
    _ measured: NSRect,
    in bounds: NSRect,
    alignment: VerticalTextAlignment
  ) -> NSRect {
    let height = max(0, min(bounds.height, ceil(measured.height)))
    let y: CGFloat
    switch alignment {
    case .top: y = bounds.minY
    case .center: y = bounds.midY - (height / 2)
    case .bottom: y = bounds.maxY - height
    }

    return NSRect(x: bounds.minX, y: y, width: bounds.width, height: height)
  }

  private func lineCap(_ cap: StrokeLineCap) -> NSBezierPath.LineCapStyle {
    switch cap {
    case .butt: .butt
    case .round: .round
    case .square: .square
    }
  }

  private func lineJoin(_ join: StrokeLineJoin) -> NSBezierPath.LineJoinStyle {
    switch join {
    case .bevel: .bevel
    case .miter: .miter
    case .round: .round
    }
  }

  private func requiresTransparencyLayer(_ style: ElementStyle) -> Bool {
    clampedUnit(style.opacity) < 1
      || style.blendMode != .normal
      || !style.shadows.isEmpty
  }

  private func blendMode(_ mode: BlendMode) -> CGBlendMode {
    switch mode {
    case .normal: .normal
    case .multiply: .multiply
    case .screen: .screen
    case .overlay: .overlay
    }
  }

  private func interpolation(_ value: ImageInterpolation) -> NSImageInterpolation {
    switch value {
    case .automatic: .default
    case .nearestNeighbor: .none
    case .highQuality: .high
    }
  }

  private func clampedUnit(_ value: Double) -> CGFloat {
    guard value.isFinite else { return 1 }

    return CGFloat(min(1, max(0, value)))
  }

  private func finiteNonnegative(_ value: Double) -> CGFloat {
    guard value.isFinite else { return 0 }

    return CGFloat(max(0, value))
  }
#endif
