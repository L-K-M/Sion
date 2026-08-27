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

    private enum ResizeCorner: CaseIterable {
      case topLeft
      case topRight
      case bottomLeft
      case bottomRight
    }

    private enum Drag {
      case move(lastPoint: SionPoint)
      case resize(elementID: ElementID, corner: ResizeCorner, startFrame: SionRect)
      case connector(sourceID: ElementID?, start: SionPoint, current: SionPoint)
    }

    private let editorController: SionEditorController
    private var observerID: UUID?
    private var drag: Drag?
    private var textEditor: NSScrollView?
    private var editedElementID: ElementID?
    private var inlineTextUndoManager: UndoManager?
    private var editingCanvasBounds: SionRect
    private var canvasExtent: CanvasExtent

    init(editorController: SionEditorController) {
      self.editorController = editorController
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
      setAccessibilityHelp("Use Tab to select elements and arrow keys to move them")
      observerID = editorController.observeChanges { [weak self] in
        guard let self else { return }

        self.synchronizeCanvasBounds()
        self.needsDisplay = true
        self.updateAccessibilitySummary()
      }
      updateAccessibilitySummary()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

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
      guard let observerID else { return }

      editorController.removeObserver(observerID)
      self.observerID = nil
    }

    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)

      drawCanvas()

      NSGraphicsContext.saveGraphicsState()
      applyCanvasTransform()
      drawGrid()
      drawElements()
      drawConnectorPreview()
      NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
      commitTextEditing()
      window?.makeFirstResponder(self)

      let point = modelPoint(from: event)
      switch editorController.tool {
      case .select:
        beginSelection(at: point, event: event)
      case .shape:
        if let id = try? editorController.insertShape(at: point) {
          editorController.setTool(.select)
          editorController.select(id)
        }
      case .text:
        if let id = try? editorController.insertText("Text", at: point) {
          editorController.setTool(.select)
          beginTextEditing(id)
        }
      case .connector:
        let source = editorController.connectableElement(at: point)
        editorController.select(source?.id)
        drag = .connector(sourceID: source?.id, start: point, current: point)
      case .magnets:
        editMagnets(at: point)
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
      case .resize(let elementID, let corner, let startFrame):
        let frame = resizedFrame(startFrame, moving: corner, to: point)
        try? editorController.resize(elementID, to: frame)
      case .connector(let sourceID, let start, _):
        self.drag = .connector(sourceID: sourceID, start: start, current: point)
        needsDisplay = true
      }
    }

    override func mouseUp(with event: NSEvent) {
      guard let drag else { return }
      self.drag = nil

      switch drag {
      case .move:
        try? editorController.endMove()
      case .resize:
        try? editorController.endResize()
      case .connector(let sourceID, let start, _):
        let end = modelPoint(from: event)
        guard start.distance(to: end) >= CanvasMetrics.minimumConnectorLength else {
          needsDisplay = true
          return
        }

        let targetID = editorController.connectableElement(at: end)?.id
        _ = try? editorController.insertConnector(
          from: sourceID,
          sourcePoint: start,
          to: targetID,
          targetPoint: end
        )
      }
    }

    override func keyDown(with event: NSEvent) {
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

    @objc override func selectAll(_ sender: Any?) {
      editorController.selectAll()
    }

    @objc func paste(_ sender: Any?) {
      let point = visibleCanvasCenter()
      let pasteboard = NSPasteboard.general

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

      _ = try? editorController.insertText(text, at: point)
    }

    @objc func copy(_ sender: Any?) {
      _ = copySelection(to: .general)
    }

    @objc func cut(_ sender: Any?) {
      guard copySelection(to: .general) else { return }

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

    private func beginSelection(at point: SionPoint, event: NSEvent) {
      if let element = editorController.selectedElement,
        element.lockState == .editable,
        element.content.connector == nil,
        let corner = resizeCorner(at: point, frame: element.geometry.frame)
      {
        do {
          try editorController.beginResize()
          drag = .resize(
            elementID: element.id,
            corner: corner,
            startFrame: element.geometry.frame.standardized
          )
        } catch {
          drag = nil
        }
        return
      }

      guard let element = editorController.element(at: point) else {
        editorController.select(nil)
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
      } catch {
        drag = nil
      }
    }

    private func editMagnets(at point: SionPoint) {
      guard let element = editorController.element(at: point),
        element.lockState == .editable,
        element.content.connector == nil
      else {
        editorController.select(nil)
        return
      }

      editorController.select(element.id)
      let magnification = max(enclosingScrollView?.magnification ?? 1, 0.01)
      try? editorController.toggleMagnet(
        at: point,
        on: element.id,
        hitTolerance: CanvasMetrics.magnetHitTolerance / Double(magnification)
      )
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

    private func pasteSelection(from pasteboard: NSPasteboard, at point: SionPoint) -> Bool {
      guard let data = pasteboard.data(forType: PasteboardType.selection),
        data.count <= SionArchiveConstants.maximumEntryByteCount
      else {
        return false
      }

      let insertedIDs = try? editorController.insertSelectionPayload(data, at: point)
      return insertedIDs?.isEmpty == false
    }

    private func pasteImage(from pasteboard: NSPasteboard, at point: SionPoint) -> Bool {
      if let fileURL = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      )?.first as? URL,
        let type = ImagePasteType(fileExtension: fileURL.pathExtension),
        isSupportedAssetSize(fileURL),
        let data = try? Data(contentsOf: fileURL)
      {
        return insertPastedImage(
          data: data,
          type: type,
          filename: fileURL.lastPathComponent,
          at: point
        )
      }

      let preservedTypes: [(NSPasteboard.PasteboardType, ImagePasteType)] = [
        (.pdf, .pdf),
        (ImagePasteType.svgPasteboardType, .svg),
        (.tiff, .tiff),
      ]
      for (pasteboardType, imageType) in preservedTypes {
        guard let data = pasteboard.data(forType: pasteboardType),
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
      guard data.count <= SionArchiveConstants.maximumEntryByteCount else { return false }

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

      return fileSize <= SionArchiveConstants.maximumEntryByteCount
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

      guard grid.visibility == .visible else { return }

      let spacing = max(CanvasMetrics.minimumGridSpacing, CGFloat(grid.spacing))
      let canvasBounds: SionRect
      switch editorController.document.scene.canvas.extent {
      case .infinite:
        canvasBounds = editingCanvasBounds
      case .fixed(let size):
        canvasBounds = SionRect(origin: .zero, size: size)
      }
      let drawingBounds = nsRect(canvasBounds).intersection(visibleModelRect())
      guard !drawingBounds.isEmpty else { return }

      let path = NSBezierPath()
      var x = floor(drawingBounds.minX / spacing) * spacing
      while x <= drawingBounds.maxX {
        path.move(to: NSPoint(x: x, y: drawingBounds.minY))
        path.line(to: NSPoint(x: x, y: drawingBounds.maxY))
        x += spacing
      }

      var y = floor(drawingBounds.minY / spacing) * spacing
      while y <= drawingBounds.maxY {
        path.move(to: NSPoint(x: drawingBounds.minX, y: y))
        path.line(to: NSPoint(x: drawingBounds.maxX, y: y))
        y += spacing
      }

      NSColor.separatorColor.withAlphaComponent(CanvasMetrics.gridOpacity).setStroke()
      path.lineWidth = CanvasMetrics.gridLineWidth
      path.stroke()
    }

    private func drawElements() {
      let scene = editorController.document.scene

      for element in scene.elements where element.visibility == .visible {
        draw(element)
      }
    }

    private func draw(_ element: SceneElement) {
      if let route = editorController.connectorRoute(for: element) {
        drawConnector(element, route: route)
        return
      }

      NSGraphicsContext.saveGraphicsState()
      applyRotation(of: element)
      applyShadow(element.style.shadows.first)

      switch element.content {
      case .shape(let shape):
        let path = shapePath(shape.kind, frame: element.geometry.frame)
        drawStyle(element.style, path: path)
        if let label = shape.label {
          drawText(label, frame: element.geometry.frame)
        }
      case .path(let content):
        let path = vectorPath(content.path, frame: element.geometry.frame)
        drawStyle(element.style, path: path)
      case .text(let text):
        drawText(text, frame: element.geometry.frame)
      case .image(let image):
        drawImage(image, frame: element.geometry.frame)
      case .group:
        break
      case .connector:
        break
      }

      NSGraphicsContext.restoreGraphicsState()

      guard editorController.selection.contains(element.id) else { return }

      drawSelection(for: element)
    }

    private func drawStyle(_ style: ElementStyle, path: NSBezierPath) {
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current?.compositingOperation = compositingOperation(style.blendMode)
      let opacity = clampedUnit(style.opacity)

      switch style.fill {
      case .none:
        break
      case .solid(let color):
        nsColor(color).withAlphaComponent(opacity).setFill()
        path.fill()
      case .linearGradient(let gradient):
        let stops = gradient.stops.sorted { $0.location < $1.location }
        let colors = stops.map {
          nsColor($0.color).withAlphaComponent(opacity)
        }
        let locations = stops.map { CGFloat($0.location) }
        if colors.count > 1 {
          let renderedGradient = locations.withUnsafeBufferPointer { buffer in
            NSGradient(
              colors: colors,
              atLocations: buffer.baseAddress,
              colorSpace: .deviceRGB
            )
          }
          renderedGradient?.draw(in: path, angle: gradientAngle(gradient))
        } else if let color = colors.first {
          color.setFill()
          path.fill()
        }
      }

      if let stroke = style.stroke, stroke.width.isFinite, stroke.width > 0 {
        nsColor(stroke.color).withAlphaComponent(opacity).setStroke()
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
        with: rect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
      )
      let drawingRect = verticallyAlignedRect(
        measured, in: rect, alignment: style.verticalAlignment)
      attributed.draw(with: drawingRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func drawImage(_ content: ImageContent, frame: SionRect) {
      guard let asset = editorController.asset(for: content.displayAssetID),
        let image = NSImage(data: asset.data)
      else {
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

      let drawingBounds = bounds.intersection(visibleModelRect())
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

    private func drawConnector(_ element: SceneElement, route: ConnectorRoute) {
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

      if let label = content.label {
        let point = route.point(atFraction: content.labelPosition)
        let frame = SionRect(
          x: point.x - (CanvasMetrics.connectorLabelSize.width / 2),
          y: point.y - (CanvasMetrics.connectorLabelSize.height / 2),
          width: CanvasMetrics.connectorLabelSize.width,
          height: CanvasMetrics.connectorLabelSize.height
        )
        drawText(label, frame: frame)
      }

      guard editorController.selection.contains(element.id) else { return }

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
      let opacity = clampedUnit(style.opacity)
      let color = nsColor(style.stroke?.color ?? .primaryInk).withAlphaComponent(opacity)
      color.setStroke()
      path.lineWidth = CGFloat(max(style.stroke?.width ?? CanvasMetrics.defaultConnectorWidth, 1))
      path.stroke()
      if decoration == .filledArrow {
        color.setFill()
        path.fill()
      }
    }

    private func drawSelection(for element: SceneElement) {
      let rect = nsRect(element.geometry.frame).insetBy(
        dx: -CanvasMetrics.selectionInset,
        dy: -CanvasMetrics.selectionInset
      )
      let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
      NSColor.controlAccentColor.setStroke()
      path.lineWidth = CanvasMetrics.selectionLineWidth
      path.setLineDash(
        CanvasMetrics.selectionDash, count: CanvasMetrics.selectionDash.count, phase: 0)
      path.stroke()

      guard element.lockState == .editable, element.content.connector == nil else { return }

      for corner in ResizeCorner.allCases {
        let point = resizePoint(corner, frame: element.geometry.frame)
        let handle = NSRect(
          x: point.x - CanvasMetrics.resizeHandleRadius,
          y: point.y - CanvasMetrics.resizeHandleRadius,
          width: CanvasMetrics.resizeHandleRadius * 2,
          height: CanvasMetrics.resizeHandleRadius * 2
        )
        NSColor.controlBackgroundColor.setFill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: handle).fill()
        NSBezierPath(rect: handle).stroke()
      }

      for point in editorController.magnetPoints(for: element) {
        let center = nsPoint(point)
        let dot = NSRect(
          x: center.x - CanvasMetrics.magnetRadius,
          y: center.y - CanvasMetrics.magnetRadius,
          width: CanvasMetrics.magnetRadius * 2,
          height: CanvasMetrics.magnetRadius * 2
        )
        NSColor.controlBackgroundColor.setFill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(ovalIn: dot).fill()
        NSBezierPath(ovalIn: dot).stroke()
      }
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
      let requiredBounds = SceneRenderGeometry.editingCanvasBounds(
        of: scene,
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

    private func modelPoint(from event: NSEvent) -> SionPoint {
      modelPoint(from: convert(event.locationInWindow, from: nil))
    }

    private func resizeCorner(at point: SionPoint, frame: SionRect) -> ResizeCorner? {
      ResizeCorner.allCases.first { corner in
        point.distance(to: resizePoint(corner, frame: frame)) <= CanvasMetrics.resizeHitRadius
      }
    }

    private func resizePoint(_ corner: ResizeCorner, frame: SionRect) -> SionPoint {
      let rect = frame.standardized
      switch corner {
      case .topLeft: return SionPoint(x: rect.minX, y: rect.minY)
      case .topRight: return SionPoint(x: rect.maxX, y: rect.minY)
      case .bottomLeft: return SionPoint(x: rect.minX, y: rect.maxY)
      case .bottomRight: return SionPoint(x: rect.maxX, y: rect.maxY)
      }
    }

    private func resizedFrame(
      _ start: SionRect,
      moving corner: ResizeCorner,
      to point: SionPoint
    ) -> SionRect {
      let opposite: SionPoint
      switch corner {
      case .topLeft:
        opposite = SionPoint(x: start.maxX, y: start.maxY)
      case .topRight:
        opposite = SionPoint(x: start.minX, y: start.maxY)
      case .bottomLeft:
        opposite = SionPoint(x: start.maxX, y: start.minY)
      case .bottomRight:
        opposite = SionPoint(x: start.minX, y: start.minY)
      }

      let width = max(CanvasMetrics.minimumElementSize, abs(point.x - opposite.x))
      let height = max(CanvasMetrics.minimumElementSize, abs(point.y - opposite.y))
      let x = point.x < opposite.x ? opposite.x - width : opposite.x
      let y = point.y < opposite.y ? opposite.y - height : opposite.y
      return SionRect(x: x, y: y, width: width, height: height)
    }
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
    static let gridOpacity = 0.18
    static let gridLineWidth = 0.5
    static let minimumGridSpacing: CGFloat = 4
    static let defaultFontSize: CGFloat = 15
    static let selectionInset = 4.0
    static let selectionLineWidth = 1.5
    static let selectionDash: [CGFloat] = [5, 3]
    static let previewDash: [CGFloat] = [7, 4]
    static let magnetRadius = 4.0
    static let magnetHitTolerance = 10.0
    static let resizeHandleRadius = 4.5
    static let resizeHitRadius = 9.0
    static let minimumElementSize = 12.0
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
  }

  private enum PasteboardType {
    static let selection = NSPasteboard.PasteboardType("ch.lkmc.sion.selection")
  }

  private enum CanvasKeyCode {
    static let returnKey: UInt16 = 36
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
    NSColor(
      calibratedRed: clampedUnit(color.red),
      green: clampedUnit(color.green),
      blue: clampedUnit(color.blue),
      alpha: clampedUnit(color.alpha)
    )
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

  private func compositingOperation(_ mode: BlendMode) -> NSCompositingOperation {
    switch mode {
    case .normal: .sourceOver
    case .multiply: .multiply
    case .screen: .screen
    case .overlay: .sourceOver
    }
  }

  private func interpolation(_ value: ImageInterpolation) -> NSImageInterpolation {
    switch value {
    case .automatic: .default
    case .nearestNeighbor: .none
    case .highQuality: .high
    }
  }

  private func gradientAngle(_ gradient: LinearGradientFill) -> CGFloat {
    let delta = gradient.end - gradient.start
    guard delta.dx.isFinite, delta.dy.isFinite else { return 0 }

    return atan2(delta.dy, delta.dx) * 180 / .pi
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
