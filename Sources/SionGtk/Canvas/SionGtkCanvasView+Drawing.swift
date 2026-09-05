import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// Rendering: the canvas surface, grid, elements, and interaction chrome, in
/// the order `SionCanvasView.draw(_:)` paints them on macOS.
extension SionGtkCanvasView {
  func installDrawing() {
    let box = SignalBox<SionGtkCanvasView>(self)
    let drawFunction: GtkDrawingAreaDrawFunc = { _, context, width, height, data in
      guard let context, let data else { return }
      let canvas = Unmanaged<SignalBox<SionGtkCanvasView>>.fromOpaque(data)
        .takeUnretainedValue().handler
      MainActor.assumeIsolated {
        canvas.draw(context, width: Double(width), height: Double(height))
      }
    }
    gtk_drawing_area_set_draw_func(
      drawingArea.cast(), drawFunction, Unmanaged.passRetained(box).toOpaque(),
      { data in
        guard let data else { return }
        Unmanaged<AnyObject>.fromOpaque(data).release()
      })
  }

  /// Paints the widget: the surface in widget space, then everything else in
  /// model space under the zoom and canvas-origin transform.
  func draw(_ context: OpaquePointer, width: Double, height: Double) {
    drawCanvas(context, width: width, height: height)

    cairo_save(context)
    cairo_scale(context, magnification, magnification)
    cairo_translate(context, -editingCanvasBounds.minX, -editingCanvasBounds.minY)
    drawGrid(context)
    drawElements(context, in: visibleModelRect())
    drawConnectionMagnets(context)
    drawCreationPreview(context)
    drawConnectorPreview(context)
    drawMarquee(context)
    drawSnapGuides(context)
    cairo_restore(context)
  }

  /// Draws every visible element into `context`, which the caller has already
  /// mapped to the model's y-down space. This is the shared seam behind the
  /// archive preview, image export, and printing; interaction chrome is not
  /// document content, so none of it is drawn here.
  package func drawSceneContent(
    _ context: OpaquePointer,
    in bounds: SionRect,
    fillsBackground: Bool
  ) {
    rendersOffscreenPreview = true
    defer { rendersOffscreenPreview = false }

    if fillsBackground {
      SionGtkColorBridge.setSource(context, editorController.document.scene.canvas.background)
      addRect(context, bounds)
      cairo_fill(context)
    }

    for element in editorController.document.scene.elements where element.visibility == .visible {
      draw(element, in: context)
    }
  }

  /// Renders the document content into a bounded PNG for the archive's
  /// recovery preview. Grid and selection chrome are omitted.
  package func renderPreviewPNG(maximumDimension: Double = PreviewMetrics.maximumDimension) -> Data?
  {
    guard maximumDimension.isFinite, maximumDimension > 0 else { return nil }

    let content = editorController.contentBounds()
    guard content.isFinite, content.width > 0, content.height > 0 else { return nil }

    let scale = min(1, maximumDimension / max(content.width, content.height))
    return try? SionGtkSceneImageExporter.data(
      options: SionImageExportOptions(format: .png, scale: .oneX, hasTransparentBackground: false),
      contentBounds: content,
      draw: { [weak self] context, bounds, fillsBackground in
        self?.drawSceneContent(context, in: bounds, fillsBackground: fillsBackground)
      },
      renderScaleOverride: scale,
      backdropOverride: .canvas
    )
  }

  // MARK: Surface and grid

  private func drawCanvas(_ context: OpaquePointer, width: Double, height: Double) {
    let canvas = editorController.document.scene.canvas
    switch canvas.extent {
    case .infinite:
      SionGtkColorBridge.setSource(context, canvas.background)
      cairo_rectangle(context, 0, 0, width, height)
      cairo_fill(context)
    case .fixed(let size):
      SionGtkColorBridge.setSource(context, CanvasColors.underPageBackground)
      cairo_rectangle(context, 0, 0, width, height)
      cairo_fill(context)

      let page = widgetRect(for: SionRect(origin: .zero, size: size))
      SionGtkColorBridge.setSource(context, canvas.background)
      addRect(context, page)
      cairo_fill(context)
      SionGtkColorBridge.setSource(context, CanvasColors.separator.withAlpha(0.1))
      cairo_set_line_width(context, 1)
      addRect(context, page)
      cairo_stroke(context)
    }
  }

  private func drawGrid(_ context: OpaquePointer) {
    let grid = editorController.document.scene.canvas.grid
    guard let plan = CanvasGridRenderGeometry.plan(for: grid, magnification: magnification) else {
      return
    }

    let canvasBounds: SionRect
    switch editorController.document.scene.canvas.extent {
    case .infinite:
      canvasBounds = editingCanvasBounds
    case .fixed(let size):
      canvasBounds = SionRect(origin: .zero, size: size)
    }
    let drawingBounds = canvasBounds.intersection(visibleModelRect())
    guard !drawingBounds.isEmpty else { return }

    guard
      let xIndices = gridLineIndices(
        from: drawingBounds.minX, through: drawingBounds.maxX, spacing: plan.lineSpacing),
      let yIndices = gridLineIndices(
        from: drawingBounds.minY, through: drawingBounds.maxY, spacing: plan.lineSpacing)
    else {
      return
    }

    let lineWidth = CanvasMetrics.gridScreenLineWidth * inverseMagnification
    cairo_set_line_width(context, lineWidth)
    for (isMajor, opacity) in [
      (false, CanvasMetrics.subdivisionGridOpacity), (true, CanvasMetrics.majorGridOpacity),
    ] {
      cairo_new_path(context)
      for index in xIndices where index.isMultiple(of: plan.linesPerMajor) == isMajor {
        let x = Double(index) * plan.lineSpacing
        cairo_move_to(context, x, drawingBounds.minY)
        cairo_line_to(context, x, drawingBounds.maxY)
      }
      for index in yIndices where index.isMultiple(of: plan.linesPerMajor) == isMajor {
        let y = Double(index) * plan.lineSpacing
        cairo_move_to(context, drawingBounds.minX, y)
        cairo_line_to(context, drawingBounds.maxX, y)
      }
      SionGtkColorBridge.setSource(context, CanvasColors.separator.withAlpha(opacity))
      cairo_stroke(context)
    }
  }

  private func gridLineIndices(
    from minimum: Double, through maximum: Double, spacing: Double
  ) -> ClosedRange<Int>? {
    let first = (minimum / spacing).rounded(.down)
    let last = (maximum / spacing).rounded(.down)
    guard first.isFinite, last.isFinite,
      let firstIndex = Int(exactly: first), let lastIndex = Int(exactly: last),
      firstIndex <= lastIndex
    else {
      return nil
    }

    return firstIndex...lastIndex
  }

  // MARK: Elements

  private func drawElements(_ context: OpaquePointer, in visibleRect: SionRect) {
    guard !visibleRect.isEmpty else { return }

    for element in editorController.elementsForRendering(intersecting: visibleRect) {
      draw(element, in: context)
    }
  }

  private func draw(_ element: SceneElement, in context: OpaquePointer) {
    let drawsArtwork = clampedUnit(element.style.opacity) > 0
    let isSelected = editorController.selection.contains(element.id)
    guard drawsArtwork || isSelected else { return }

    let route = connectorRouteProvider(element)
    guard element.content.connector == nil || route != nil else {
      if !rendersOffscreenPreview, isSelected {
        drawSelection(context, for: element)
      }
      return
    }

    if drawsArtwork {
      drawArtwork(context, of: element, route: route)
    }

    // Selection chrome is interaction state, not document content.
    guard !rendersOffscreenPreview, isSelected else { return }
    if let route {
      drawConnectorSelection(context, route)
      return
    }

    drawSelection(context, for: element)
  }

  private func drawArtwork(
    _ context: OpaquePointer, of element: SceneElement, route: ConnectorRoute?
  ) {
    let opacity = clampedUnit(element.style.opacity)
    guard opacity > 0 else { return }

    cairo_save(context)
    defer { cairo_restore(context) }

    let usesGroup = requiresTransparencyLayer(element.style)
    if usesGroup {
      // Bound the group to this artwork; a canvas-sized group would stutter.
      let bounds = SceneRenderGeometry.paintedBounds(of: element, route: route)
      if let shadow = element.style.shadows.first {
        drawShadow(context, shadow, of: element, route: route, bounds: bounds, opacity: opacity)
      }
      addRect(context, bounds.expanded(by: 1))
      cairo_clip(context)
      cairo_push_group(context)
    }

    if let route {
      drawConnectorArtwork(context, element, route: route)
    } else {
      applyRotation(context, of: element)
      drawNonConnectorArtwork(context, element)
    }

    if usesGroup {
      cairo_pop_group_to_source(context)
      cairo_set_operator(context, blendOperator(element.style.blendMode))
      cairo_paint_with_alpha(context, opacity)
    }
  }

  /// Cairo has no shadow primitive: the artwork's coverage is rendered into a
  /// mask, blurred, and painted in the shadow colour behind the artwork.
  private func drawShadow(
    _ context: OpaquePointer,
    _ style: ShadowStyle,
    of element: SceneElement,
    route: ConnectorRoute?,
    bounds: SionRect,
    opacity: Double
  ) {
    guard style.blurRadius.isFinite, style.offset.dx.isFinite, style.offset.dy.isFinite else {
      return
    }

    let blur = max(0, style.blurRadius)
    let padding = blur * 3 + 2
    let region = bounds.standardized.expanded(by: padding)
    let pixelScale = min(4, max(1, magnification))
    let width = Int32((region.width * pixelScale).rounded(.up))
    let height = Int32((region.height * pixelScale).rounded(.up))
    guard width > 0, height > 0, width * height < 16_000_000,
      let mask = cairo_image_surface_create(CAIRO_FORMAT_A8, width, height),
      let maskContext = cairo_create(mask)
    else {
      return
    }
    defer {
      cairo_destroy(maskContext)
      cairo_surface_destroy(mask)
    }

    cairo_scale(maskContext, pixelScale, pixelScale)
    cairo_translate(maskContext, -region.minX, -region.minY)
    if let route {
      drawConnectorArtwork(maskContext, element, route: route)
    } else {
      applyRotation(maskContext, of: element)
      drawNonConnectorArtwork(maskContext, element)
    }
    cairo_surface_flush(mask)
    if blur > 0 {
      SionGtkBlur.blurAlpha(mask, radius: blur * pixelScale)
    }

    cairo_save(context)
    cairo_translate(context, region.minX + style.offset.dx, region.minY + style.offset.dy)
    cairo_scale(context, 1 / pixelScale, 1 / pixelScale)
    SionGtkColorBridge.setSource(context, style.color.withAlpha(style.color.alpha * opacity))
    cairo_mask_surface(context, mask, 0, 0)
    cairo_restore(context)
  }

  private func drawNonConnectorArtwork(_ context: OpaquePointer, _ element: SceneElement) {
    switch element.content {
    case .shape(let shape):
      addShapePath(context, shape.kind, frame: element.geometry.frame)
      drawStyle(context, element.style)
      if case .cylinder = shape.kind {
        for detail in ShapeGeometryRecipe.cylinder.detailStrokes {
          addVectorPath(context, detail, frame: element.geometry.frame)
          drawStroke(context, element.style.stroke)
        }
      }
      if let label = shape.label, element.id != editedElementID {
        drawText(context, label, frame: element.geometry.frame)
      }
    case .path(let content):
      addVectorPath(context, content.path, frame: element.geometry.frame)
      drawStyle(context, element.style)
    case .text(let text):
      if element.id != editedElementID {
        drawText(context, text, frame: element.geometry.frame)
      }
    case .image(let image):
      drawImage(context, image, frame: element.geometry.frame)
      // An image takes no fill, but a border frames it like any other object.
      addRect(context, element.geometry.frame)
      drawStroke(context, element.style.stroke)
    case .group, .connector:
      cairo_new_path(context)
    }
  }

  /// Fills and strokes the current path with the element's style, consuming it.
  private func drawStyle(_ context: OpaquePointer, _ style: ElementStyle) {
    switch style.fill {
    case .none:
      break
    case .solid(let color):
      SionGtkColorBridge.setSource(context, color)
      cairo_fill_preserve(context)
    case .linearGradient(let gradient):
      drawLinearGradient(context, gradient)
    }

    drawStroke(context, style.stroke)
  }

  /// Strokes the current path, consuming it.
  private func drawStroke(_ context: OpaquePointer, _ stroke: StrokeStyle?) {
    guard let stroke, stroke.width.isFinite, stroke.width > 0 else {
      cairo_new_path(context)
      return
    }

    SionGtkColorBridge.setSource(context, stroke.color)
    cairo_set_line_width(context, stroke.width)
    setDash(context, stroke.dashPattern)
    cairo_set_line_cap(context, lineCap(stroke.lineCap))
    cairo_set_line_join(context, lineJoin(stroke.lineJoin))
    cairo_set_miter_limit(context, StrokeGeometryDefaults.miterLimit)
    cairo_stroke(context)
    cairo_set_dash(context, nil, 0, 0)
  }

  private func drawLinearGradient(_ context: OpaquePointer, _ gradient: LinearGradientFill) {
    guard gradient.stops.count > 1 else {
      if let color = gradient.stops.first?.color {
        SionGtkColorBridge.setSource(context, color)
        cairo_fill_preserve(context)
      }
      return
    }

    var x1 = 0.0
    var y1 = 0.0
    var x2 = 0.0
    var y2 = 0.0
    cairo_path_extents(context, &x1, &y1, &x2, &y2)
    let bounds = SionRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    let start = bounds.point(atNormalized: gradient.start)
    let end = bounds.point(atNormalized: gradient.end)
    guard start != end else {
      if let color = gradient.stops.last?.color {
        SionGtkColorBridge.setSource(context, color)
        cairo_fill_preserve(context)
      }
      return
    }
    guard let drawing = paddedGradient(gradient, start: start, end: end, bounds: bounds) else {
      return
    }

    let pattern = cairo_pattern_create_linear(
      drawing.start.x, drawing.start.y, drawing.end.x, drawing.end.y)
    for stop in drawing.stops {
      cairo_pattern_add_color_stop_rgba(
        pattern, stop.location,
        clampedUnit(stop.color.red), clampedUnit(stop.color.green), clampedUnit(stop.color.blue),
        clampedUnit(stop.color.alpha))
    }
    cairo_set_source(context, pattern)
    cairo_fill_preserve(context)
    cairo_pattern_destroy(pattern)
  }

  /// Extends the sRGB domain across the clip, matching SVG's constant colours
  /// before the first point and after the last.
  private func paddedGradient(
    _ gradient: LinearGradientFill, start: SionPoint, end: SionPoint, bounds: SionRect
  ) -> (start: SionPoint, end: SionPoint, stops: [GradientStop])? {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let squaredLength = (dx * dx) + (dy * dy)
    guard squaredLength > 0 else { return nil }

    let corners = [
      SionPoint(x: bounds.minX, y: bounds.minY), SionPoint(x: bounds.maxX, y: bounds.minY),
      SionPoint(x: bounds.maxX, y: bounds.maxY), SionPoint(x: bounds.minX, y: bounds.maxY),
    ]
    let projections = corners.map { point in
      (((point.x - start.x) * dx) + ((point.y - start.y) * dy)) / squaredLength
    }
    guard let minimum = projections.min(), let maximum = projections.max() else { return nil }

    let lowerBound = min(0, minimum)
    let upperBound = max(1, maximum)
    let span = upperBound - lowerBound
    guard span > 0 else { return nil }

    var stops = gradient.stops.map { stop in
      GradientStop(color: stop.color, location: (stop.location - lowerBound) / span)
    }
    if let first = stops.first, first.location > 0 {
      stops.insert(GradientStop(color: first.color, location: 0), at: 0)
    }
    if let last = stops.last, last.location < 1 {
      stops.append(GradientStop(color: last.color, location: 1))
    }

    return (
      start: SionPoint(x: start.x + (dx * lowerBound), y: start.y + (dy * lowerBound)),
      end: SionPoint(x: start.x + (dx * upperBound), y: start.y + (dy * upperBound)),
      stops: stops
    )
  }

  // MARK: Text

  func drawText(_ context: OpaquePointer, _ content: TextContent, frame: SionRect) {
    let style = content.style
    let bounds = frame.standardized
    let leading = finiteNonnegative(style.insets.leading)
    let trailing = finiteNonnegative(style.insets.trailing)
    let top = finiteNonnegative(style.insets.top)
    let bottom = finiteNonnegative(style.insets.bottom)
    let rect = SionRect(
      x: bounds.minX + leading,
      y: bounds.minY + top,
      width: max(0, bounds.width - leading - trailing),
      height: max(0, bounds.height - top - bottom)
    )
    let rendered = cachedTextRender(for: content, width: rect.width, context: context)
    let drawingRect = verticallyAlignedRect(
      height: rendered.measuredHeight, in: rect, alignment: style.verticalAlignment)

    cairo_save(context)
    addRect(context, SionRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
    cairo_clip(context)
    SionGtkColorBridge.setSource(context, style.color)
    var y = drawingRect.minY
    let paragraphSpacing = finiteNonnegative(style.paragraphSpacing)
    for layout in rendered.layouts {
      pango_cairo_update_layout(context, layout)
      cairo_move_to(context, drawingRect.minX, y)
      pango_cairo_show_layout(context, layout)
      var inkRect = PangoRectangle()
      var logicalRect = PangoRectangle()
      pango_layout_get_pixel_extents(layout, &inkRect, &logicalRect)
      y += Double(logicalRect.height) + paragraphSpacing
    }
    cairo_restore(context)
  }

  /// Text measurement dominates redraws once routing is cached, so keep one
  /// layout per (text, style, width). Paragraph spacing has no Pango
  /// equivalent, so a text with more than one paragraph and spacing between
  /// them becomes one layout per paragraph, stacked at draw time.
  func cachedTextRender(for content: TextContent, width: Double, context: OpaquePointer)
    -> TextRender
  {
    let key = TextRenderKey(content: content, width: width)
    if let cached = textRenderCache[key] {
      return cached
    }

    let style = content.style
    let paragraphSpacing = finiteNonnegative(style.paragraphSpacing)
    let paragraphs =
      paragraphSpacing > 0
      ? content.string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      : [content.string]
    var layouts: [OpaquePointer] = []
    var height = 0.0
    for (index, paragraph) in paragraphs.enumerated() {
      guard let layout = pango_cairo_create_layout(context) else { continue }
      configure(layout, text: paragraph, style: style, width: key.measurementWidth)
      var inkRect = PangoRectangle()
      var logicalRect = PangoRectangle()
      pango_layout_get_pixel_extents(layout, &inkRect, &logicalRect)
      height += Double(logicalRect.height)
      if index < paragraphs.count - 1 {
        height += paragraphSpacing
      }
      layouts.append(layout)
    }
    let render = TextRender(layouts: layouts, measuredHeight: height.rounded(.up))

    if textRenderCache.count >= CanvasMetrics.textRenderCacheLimit {
      let evictionCount = max(
        1, CanvasMetrics.textRenderCacheLimit / CanvasMetrics.textRenderCacheEvictionDivisor)
      // Arbitrary partial eviction avoids a full-cache miss spike.
      for evictedKey in Array(textRenderCache.keys.prefix(evictionCount)) {
        textRenderCache.removeValue(forKey: evictedKey)
      }
    }
    textRenderCache[key] = render
    return render
  }

  /// Applies a text style to a Pango layout: font, colour is the caller's,
  /// wrapping at `width`, alignment, and line spacing.
  func configure(_ layout: OpaquePointer, text: String, style: TextStyle, width: Double) {
    pango_layout_set_text(layout, text, -1)
    let description = SionGtkFonts.description(for: style)
    pango_layout_set_font_description(layout, description)
    pango_font_description_free(description)
    if width.isFinite, width > 0 {
      pango_layout_set_width(layout, Int32(min(Double(Int32.max / 2), width * Double(PANGO_SCALE))))
    }
    pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR)
    switch style.horizontalAlignment {
    case .leading:
      pango_layout_set_alignment(layout, PANGO_ALIGN_LEFT)
    case .center:
      pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER)
    case .trailing:
      pango_layout_set_alignment(layout, PANGO_ALIGN_RIGHT)
    case .justified:
      pango_layout_set_alignment(layout, PANGO_ALIGN_LEFT)
      pango_layout_set_justify(layout, 1)
    }
    let lineSpacing = finiteNonnegative(style.lineSpacing)
    pango_layout_set_spacing(layout, Int32(lineSpacing * Double(PANGO_SCALE)))
  }

  private func verticallyAlignedRect(
    height measured: Double, in bounds: SionRect, alignment: VerticalTextAlignment
  ) -> SionRect {
    let height = max(0, min(bounds.height, measured.rounded(.up)))
    let y: Double
    switch alignment {
    case .top: y = bounds.minY
    case .center: y = bounds.center.y - (height / 2)
    case .bottom: y = bounds.maxY - height
    }

    return SionRect(x: bounds.minX, y: y, width: bounds.width, height: height)
  }

  // MARK: Images

  private func drawImage(_ context: OpaquePointer, _ content: ImageContent, frame: SionRect) {
    guard let image = editorController.image(for: content, decode: SionGtkDecodedImage.decode)
    else {
      drawMissingImage(context, in: frame)
      return
    }

    let bounds = frame.standardized
    cairo_save(context)
    addRect(context, bounds)
    cairo_clip(context)

    if content.scalingMode == .tile {
      drawTiled(context, image, in: bounds, interpolation: content.interpolation)
      cairo_restore(context)
      return
    }

    let drawingRect = imageRect(for: image.size, in: bounds, mode: content.scalingMode)
    cairo_translate(context, drawingRect.minX, drawingRect.minY)
    cairo_scale(
      context, drawingRect.width / image.size.width, drawingRect.height / image.size.height)
    cairo_set_source_surface(context, image.surface, 0, 0)
    cairo_pattern_set_filter(cairo_get_source(context), filter(content.interpolation))
    cairo_paint(context)
    cairo_restore(context)
  }

  private func drawTiled(
    _ context: OpaquePointer, _ image: SionGtkDecodedImage, in bounds: SionRect,
    interpolation: ImageInterpolation
  ) {
    guard image.size.width > 0, image.size.height > 0 else { return }

    // Offscreen previews cover the whole tile; on screen we cull.
    let drawingBounds = rendersOffscreenPreview ? bounds : bounds.intersection(visibleModelRect())
    guard !drawingBounds.isEmpty else { return }

    let pattern = cairo_pattern_create_for_surface(image.surface)
    cairo_pattern_set_extend(pattern, CAIRO_EXTEND_REPEAT)
    cairo_pattern_set_filter(pattern, filter(interpolation))
    var matrix = cairo_matrix_t()
    cairo_matrix_init_translate(&matrix, -bounds.minX, -bounds.minY)
    cairo_pattern_set_matrix(pattern, &matrix)
    cairo_set_source(context, pattern)
    addRect(context, drawingBounds)
    cairo_fill(context)
    cairo_pattern_destroy(pattern)
  }

  private func imageRect(for imageSize: SionSize, in bounds: SionRect, mode: ImageScalingMode)
    -> SionRect
  {
    guard mode != .stretch, imageSize.isFinite, imageSize.width > 0, imageSize.height > 0 else {
      return bounds
    }

    let widthScale = bounds.width / imageSize.width
    let heightScale = bounds.height / imageSize.height
    let scale = mode == .fill ? max(widthScale, heightScale) : min(widthScale, heightScale)
    let size = SionSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return SionRect(
      x: bounds.center.x - (size.width / 2), y: bounds.center.y - (size.height / 2),
      width: size.width, height: size.height)
  }

  private func drawMissingImage(_ context: OpaquePointer, in frame: SionRect) {
    SionGtkColorBridge.setSource(context, CanvasColors.quaternaryLabel)
    addRect(context, frame)
    cairo_fill(context)
    SionGtkColorBridge.setSource(context, CanvasColors.secondaryLabel)
    cairo_set_line_width(context, 1)
    addRect(context, frame)
    cairo_stroke(context)
  }

  // MARK: Connectors

  private func drawConnectorArtwork(
    _ context: OpaquePointer, _ element: SceneElement, route: ConnectorRoute
  ) {
    guard case .connector(let content) = element.content else { return }

    addConnectorPath(context, route)
    drawStyle(context, element.style)
    drawDecoration(
      context, content.sourceDecoration, at: route.start,
      toward: route.polylinePoints.dropFirst().first, style: element.style)
    drawDecoration(
      context, content.targetDecoration, at: route.end,
      toward: route.polylinePoints.dropLast().last, style: element.style)

    if let label = content.label, element.id != editedElementID {
      drawText(
        context, label, frame: connectorLabelFrame(route: route, position: content.labelPosition))
    }
  }

  func connectorLabelFrame(route: ConnectorRoute, position: Double) -> SionRect {
    let point = route.point(atFraction: position)
    return SionRect(
      x: point.x - (CanvasMetrics.connectorLabelSize.width / 2),
      y: point.y - (CanvasMetrics.connectorLabelSize.height / 2),
      width: CanvasMetrics.connectorLabelSize.width,
      height: CanvasMetrics.connectorLabelSize.height
    )
  }

  private func drawConnectorSelection(_ context: OpaquePointer, _ route: ConnectorRoute) {
    addConnectorPath(context, route)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_set_line_width(context, CanvasMetrics.selectionLineWidth)
    setDash(context, CanvasMetrics.selectionDash)
    cairo_stroke(context)
    cairo_set_dash(context, nil, 0, 0)
  }

  private func drawDecoration(
    _ context: OpaquePointer,
    _ decoration: ConnectorDecoration,
    at point: SionPoint,
    toward previous: SionPoint?,
    style: ElementStyle
  ) {
    // SVG decorations inherit a visible connector stroke; never synthesize one.
    guard decoration != .none, let previous, let stroke = style.stroke,
      stroke.width.isFinite, stroke.width > 0
    else {
      return
    }

    let angle = atan2(point.y - previous.y, point.x - previous.x)
    cairo_save(context)
    defer { cairo_restore(context) }
    cairo_translate(context, point.x, point.y)
    cairo_rotate(context, angle)

    let radius = CanvasMetrics.decorationRadius
    switch decoration {
    case .none:
      return
    case .openArrow, .filledArrow:
      cairo_move_to(context, -CanvasMetrics.arrowLength, -CanvasMetrics.arrowWidth)
      cairo_line_to(context, 0, 0)
      cairo_line_to(context, -CanvasMetrics.arrowLength, CanvasMetrics.arrowWidth)
      if decoration == .filledArrow {
        cairo_close_path(context)
      }
    case .circle:
      cairo_new_sub_path(context)
      cairo_arc(context, 0, 0, radius, 0, 2 * .pi)
    case .diamond:
      cairo_move_to(context, 0, 0)
      cairo_line_to(context, -radius, -radius)
      cairo_line_to(context, -(radius * 2), 0)
      cairo_line_to(context, -radius, radius)
      cairo_close_path(context)
    }

    SionGtkColorBridge.setSource(context, stroke.color)
    // Closed SVG markers use the connector stroke as their fill.
    switch decoration {
    case .none:
      return
    case .openArrow:
      cairo_set_line_width(context, max(stroke.width, 1))
      cairo_set_dash(context, nil, 0, 0)
      cairo_set_line_cap(context, CAIRO_LINE_CAP_BUTT)
      cairo_set_line_join(context, CAIRO_LINE_JOIN_MITER)
      cairo_stroke(context)
    case .filledArrow, .circle, .diamond:
      cairo_fill(context)
    }
  }

  // MARK: Selection chrome

  private func drawSelection(_ context: OpaquePointer, for element: SceneElement) {
    let selectionFrame = element.geometry.frame.standardized.expanded(
      by: CanvasMetrics.selectionInset * inverseMagnification)
    let corners = [ResizeHandle.northWest, .northEast, .southEast, .southWest].map {
      InteractionGeometry.resizeHandlePoint(
        $0, in: selectionFrame, rotationRadians: element.geometry.rotationRadians)
    }
    addPolygon(context, corners)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_set_line_width(context, CanvasMetrics.selectionLineWidth * inverseMagnification)
    setDash(context, CanvasMetrics.selectionDash.map { $0 * inverseMagnification })
    cairo_stroke(context)
    cairo_set_dash(context, nil, 0, 0)

    guard editorController.selectedElement?.id == element.id,
      element.lockState == .editable,
      element.content.connector == nil
    else {
      return
    }

    for handle in ResizeHandle.allCases {
      drawSquareHandle(context, at: resizeHandlePoint(handle, for: element))
    }

    let north = resizeHandlePoint(.north, for: element)
    let rotation = rotationHandlePoint(for: element)
    cairo_move_to(context, north.x, north.y)
    cairo_line_to(context, rotation.x, rotation.y)
    cairo_set_line_width(context, CanvasMetrics.selectionLineWidth * inverseMagnification)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_stroke(context)
    drawRoundHandle(context, at: rotation)

    if let radiusHandle = cornerRadiusHandlePoint(for: element) {
      drawDiamondHandle(context, at: radiusHandle)
    }
  }

  private func drawSquareHandle(_ context: OpaquePointer, at point: SionPoint) {
    let radius = CanvasMetrics.resizeHandleRadius * inverseMagnification
    cairo_rectangle(context, point.x - radius, point.y - radius, radius * 2, radius * 2)
    fillAndStrokeHandle(context)
  }

  private func drawRoundHandle(_ context: OpaquePointer, at point: SionPoint) {
    let radius = CanvasMetrics.rotationHandleRadius * inverseMagnification
    cairo_new_sub_path(context)
    cairo_arc(context, point.x, point.y, radius, 0, 2 * .pi)
    fillAndStrokeHandle(context)
  }

  private func fillAndStrokeHandle(_ context: OpaquePointer) {
    SionGtkColorBridge.setSource(context, CanvasColors.controlBackground)
    cairo_fill_preserve(context)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_set_line_width(context, 1 * inverseMagnification)
    cairo_stroke(context)
  }

  private func drawDiamondHandle(_ context: OpaquePointer, at point: SionPoint) {
    let radius = CanvasMetrics.cornerRadiusHandleRadius * inverseMagnification
    addPolygon(
      context,
      [
        SionPoint(x: point.x, y: point.y - radius), SionPoint(x: point.x + radius, y: point.y),
        SionPoint(x: point.x, y: point.y + radius), SionPoint(x: point.x - radius, y: point.y),
      ])
    SionGtkColorBridge.setSource(context, CanvasColors.systemYellow)
    cairo_fill_preserve(context)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_set_line_width(context, 1 * inverseMagnification)
    cairo_stroke(context)
  }

  private func drawConnectionMagnets(_ context: OpaquePointer) {
    let scene = editorController.document.scene
    if let id = editorController.anchorEditingState.elementID {
      guard let element = scene.element(withID: id), element.visibility == .visible else { return }

      for resolved in element.resolvedMagnets {
        drawEditableAnchor(context, resolved)
      }
      return
    }

    let showsAll = editorController.tool == .connector || isCreatingConnector
    let elements = scene.elements.filter { element in
      guard element.visibility == .visible, element.content.connector == nil else { return false }

      return showsAll || editorController.selection.contains(element.id)
    }

    for element in elements {
      for resolved in element.resolvedMagnets {
        drawConnectionMagnet(context, resolved)
      }
    }
  }

  var isCreatingConnector: Bool {
    guard case .connector = drag else { return false }

    return true
  }

  private func drawConnectionMagnet(_ context: OpaquePointer, _ resolved: ResolvedMagnet) {
    let endpoint = resolved.endpoint.point
    let displayPoint = magnetDisplayPoint(resolved)
    cairo_move_to(context, endpoint.x, endpoint.y)
    cairo_line_to(context, displayPoint.x, displayPoint.y)
    SionGtkColorBridge.setSource(
      context, CanvasColors.accent.withAlpha(CanvasMetrics.magnetStemOpacity))
    cairo_set_line_width(context, CanvasMetrics.magnetStemWidth * inverseMagnification)
    cairo_stroke(context)

    let radius = CanvasMetrics.magnetRadius * inverseMagnification
    cairo_new_sub_path(context)
    cairo_arc(context, displayPoint.x, displayPoint.y, radius, 0, 2 * .pi)
    fillAndStrokeHandle(context)
  }

  private func drawEditableAnchor(_ context: OpaquePointer, _ resolved: ResolvedMagnet) {
    let point = resolved.endpoint.point
    let radius = CanvasMetrics.anchorEditingRadius * inverseMagnification
    cairo_new_sub_path(context)
    cairo_arc(context, point.x, point.y, radius, 0, 2 * .pi)
    SionGtkColorBridge.setSource(context, CanvasColors.systemOrange)
    cairo_fill_preserve(context)
    SionGtkColorBridge.setSource(context, CanvasColors.controlBackground)
    cairo_set_line_width(context, CanvasMetrics.selectionLineWidth * inverseMagnification)
    cairo_stroke(context)
  }

  private func drawCreationPreview(_ context: OpaquePointer) {
    guard case .create(let creation, let start, let current) = drag else { return }

    let frame = creationPlacement(creation, from: start, to: current).frame
    switch creation {
    case .shape(let kind):
      addShapePath(context, kind, frame: frame)
    case .text:
      addRect(context, frame)
    }

    SionGtkColorBridge.setSource(
      context, CanvasColors.accent.withAlpha(CanvasMetrics.creationFillOpacity))
    cairo_fill_preserve(context)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_set_line_width(context, CanvasMetrics.selectionLineWidth * inverseMagnification)
    setDash(context, CanvasMetrics.previewDash.map { $0 * inverseMagnification })
    cairo_stroke(context)
    cairo_set_dash(context, nil, 0, 0)
  }

  /// The alignments the current drag settled on, drawn only while it lasts.
  private func drawSnapGuides(_ context: OpaquePointer) {
    guard !snapGuides.isEmpty else { return }

    for guide in snapGuides {
      switch guide.axis {
      case .vertical:
        cairo_move_to(context, guide.position, guide.start)
        cairo_line_to(context, guide.position, guide.end)
      case .horizontal:
        cairo_move_to(context, guide.start, guide.position)
        cairo_line_to(context, guide.end, guide.position)
      }
    }
    cairo_set_line_width(context, CanvasMetrics.snapGuideLineWidth * inverseMagnification)
    SionGtkColorBridge.setSource(context, .accent)
    cairo_stroke(context)
  }

  private func drawMarquee(_ context: OpaquePointer) {
    guard case .marquee(let origin, let current) = drag else { return }

    let rect = SionRect(
      x: min(origin.x, current.x), y: min(origin.y, current.y),
      width: abs(current.x - origin.x), height: abs(current.y - origin.y))
    guard rect.width >= minimumMarqueeModelSize || rect.height >= minimumMarqueeModelSize else {
      return
    }

    addRect(context, rect)
    SionGtkColorBridge.setSource(
      context, CanvasColors.accent.withAlpha(CanvasMetrics.marqueeFillOpacity))
    cairo_fill_preserve(context)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_set_line_width(context, CanvasMetrics.selectionLineWidth * inverseMagnification)
    setDash(context, CanvasMetrics.selectionDash.map { $0 * inverseMagnification })
    cairo_stroke(context)
    cairo_set_dash(context, nil, 0, 0)
  }

  private func drawConnectorPreview(_ context: OpaquePointer) {
    guard case .connector(let sourceID, let start, let current) = drag else { return }

    let targetID = editorController.connectableElement(at: current)?.id
    guard
      let route = editorController.connectorPreview(
        from: sourceID, sourcePoint: start, to: targetID, targetPoint: current)
    else {
      return
    }

    addConnectorPath(context, route)
    SionGtkColorBridge.setSource(context, CanvasColors.accent)
    cairo_set_line_width(context, 2)
    setDash(context, CanvasMetrics.previewDash)
    cairo_stroke(context)
    cairo_set_dash(context, nil, 0, 0)
  }

  // MARK: Paths

  func addRect(_ context: OpaquePointer, _ rect: SionRect) {
    let standardized = rect.standardized
    cairo_rectangle(
      context, standardized.minX, standardized.minY, standardized.width, standardized.height)
  }

  func addPolygon(_ context: OpaquePointer, _ points: [SionPoint]) {
    guard let first = points.first else { return }

    cairo_move_to(context, first.x, first.y)
    for point in points.dropFirst() {
      cairo_line_to(context, point.x, point.y)
    }
    cairo_close_path(context)
  }

  func addRoundedRect(_ context: OpaquePointer, _ rect: SionRect, radius: Double) {
    let r = rect.standardized
    let clamped = min(radius, r.width / 2, r.height / 2)
    guard clamped > 0 else {
      addRect(context, r)
      return
    }
    cairo_new_sub_path(context)
    cairo_arc(context, r.maxX - clamped, r.minY + clamped, clamped, -.pi / 2, 0)
    cairo_arc(context, r.maxX - clamped, r.maxY - clamped, clamped, 0, .pi / 2)
    cairo_arc(context, r.minX + clamped, r.maxY - clamped, clamped, .pi / 2, .pi)
    cairo_arc(context, r.minX + clamped, r.minY + clamped, clamped, .pi, 3 * .pi / 2)
    cairo_close_path(context)
  }

  func addEllipse(_ context: OpaquePointer, in rect: SionRect) {
    let r = rect.standardized
    guard r.width > 0, r.height > 0 else { return }
    cairo_save(context)
    cairo_translate(context, r.center.x, r.center.y)
    cairo_scale(context, r.width / 2, r.height / 2)
    cairo_new_sub_path(context)
    cairo_arc(context, 0, 0, 1, 0, 2 * .pi)
    cairo_close_path(context)
    cairo_restore(context)
  }

  func addConnectorPath(_ context: OpaquePointer, _ route: ConnectorRoute) {
    cairo_move_to(context, route.start.x, route.start.y)
    var current = route.start
    for segment in route.segments {
      switch segment {
      case .line(let to):
        cairo_line_to(context, to.x, to.y)
        current = to
      case .quadratic(let control, let to):
        let first = current + ((control - current) * (2.0 / 3.0))
        let second = to + ((control - to) * (2.0 / 3.0))
        cairo_curve_to(context, first.x, first.y, second.x, second.y, to.x, to.y)
        current = to
      case .cubic(let control1, let control2, let to):
        cairo_curve_to(context, control1.x, control1.y, control2.x, control2.y, to.x, to.y)
        current = to
      }
    }
  }

  func addShapePath(_ context: OpaquePointer, _ kind: ShapeKind, frame: SionRect) {
    let rect = frame.standardized
    switch kind {
    case .rectangle:
      addRect(context, rect)
    case .roundedRectangle(let radius):
      addRoundedRect(context, rect, radius: max(0, radius.isFinite ? radius : 0))
    case .ellipse:
      addEllipse(context, in: rect)
    case .capsule:
      addRoundedRect(context, rect, radius: min(rect.width, rect.height) / 2)
    case .diamond:
      addPolygon(
        context,
        [
          SionPoint(x: rect.center.x, y: rect.minY), SionPoint(x: rect.maxX, y: rect.center.y),
          SionPoint(x: rect.center.x, y: rect.maxY), SionPoint(x: rect.minX, y: rect.center.y),
        ])
    case .triangle:
      addPolygon(
        context,
        [
          SionPoint(x: rect.center.x, y: rect.minY), SionPoint(x: rect.maxX, y: rect.maxY),
          SionPoint(x: rect.minX, y: rect.maxY),
        ])
    case .hexagon:
      let inset = rect.width * ShapeGeometryDefaults.hexagonInsetFraction
      addPolygon(
        context,
        [
          SionPoint(x: rect.minX + inset, y: rect.minY),
          SionPoint(x: rect.maxX - inset, y: rect.minY),
          SionPoint(x: rect.maxX, y: rect.center.y), SionPoint(x: rect.maxX - inset, y: rect.maxY),
          SionPoint(x: rect.minX + inset, y: rect.maxY), SionPoint(x: rect.minX, y: rect.center.y),
        ])
    case .cylinder:
      addVectorPath(context, ShapeGeometryRecipe.cylinder.outerOutline, frame: frame)
    case .custom(let path):
      addVectorPath(context, path, frame: frame)
    }
  }

  func addVectorPath(_ context: OpaquePointer, _ content: VectorPath, frame: SionRect) {
    let rect = frame.standardized
    var current = SionPoint(x: rect.minX, y: rect.minY)
    var subpathStart = current
    var hasCurrent = false

    func point(_ value: SionPoint) -> SionPoint {
      guard content.coordinateSpace == .normalized else {
        return SionPoint(x: rect.minX + value.x, y: rect.minY + value.y)
      }
      return SionPoint(
        x: rect.minX + (rect.width * value.x), y: rect.minY + (rect.height * value.y))
    }

    cairo_new_path(context)
    for command in content.commands {
      switch command {
      case .move(let to):
        current = point(to)
        subpathStart = current
        cairo_move_to(context, current.x, current.y)
        hasCurrent = true
      case .line(let to):
        if !hasCurrent {
          cairo_move_to(context, current.x, current.y)
          subpathStart = current
        }
        current = point(to)
        cairo_line_to(context, current.x, current.y)
        hasCurrent = true
      case .quadratic(let control, let to):
        if !hasCurrent {
          cairo_move_to(context, current.x, current.y)
          subpathStart = current
        }
        let controlPoint = point(control)
        let end = point(to)
        let first = current + ((controlPoint - current) * (2.0 / 3.0))
        let second = end + ((controlPoint - end) * (2.0 / 3.0))
        cairo_curve_to(context, first.x, first.y, second.x, second.y, end.x, end.y)
        current = end
        hasCurrent = true
      case .cubic(let control1, let control2, let to):
        if !hasCurrent {
          cairo_move_to(context, current.x, current.y)
          subpathStart = current
        }
        current = point(to)
        let c1 = point(control1)
        let c2 = point(control2)
        cairo_curve_to(context, c1.x, c1.y, c2.x, c2.y, current.x, current.y)
        hasCurrent = true
      case .close:
        if hasCurrent {
          cairo_close_path(context)
          // Keep converter state at the closed subpath's origin.
          current = subpathStart
        }
      }
    }
    cairo_set_fill_rule(
      context, content.fillRule == .evenOdd ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
  }

  func applyRotation(_ context: OpaquePointer, of element: SceneElement) {
    guard element.geometry.rotationRadians != 0 else { return }

    let center = element.geometry.frame.center
    cairo_translate(context, center.x, center.y)
    cairo_rotate(context, element.geometry.rotationRadians)
    cairo_translate(context, -center.x, -center.y)
  }

  func setDash(_ context: OpaquePointer, _ pattern: [Double]) {
    // Validation guarantees finite non-negative entries; filtering here could
    // only silently flip dash/gap parity.
    guard !pattern.isEmpty, pattern.contains(where: { $0 > 0 }) else {
      cairo_set_dash(context, nil, 0, 0)
      return
    }
    pattern.withUnsafeBufferPointer { buffer in
      cairo_set_dash(context, buffer.baseAddress, Int32(buffer.count), 0)
    }
  }

  private func lineCap(_ cap: StrokeLineCap) -> cairo_line_cap_t {
    switch cap {
    case .butt: CAIRO_LINE_CAP_BUTT
    case .round: CAIRO_LINE_CAP_ROUND
    case .square: CAIRO_LINE_CAP_SQUARE
    }
  }

  private func lineJoin(_ join: StrokeLineJoin) -> cairo_line_join_t {
    switch join {
    case .bevel: CAIRO_LINE_JOIN_BEVEL
    case .miter: CAIRO_LINE_JOIN_MITER
    case .round: CAIRO_LINE_JOIN_ROUND
    }
  }

  private func requiresTransparencyLayer(_ style: ElementStyle) -> Bool {
    clampedUnit(style.opacity) < 1 || style.blendMode != .normal || !style.shadows.isEmpty
  }

  private func blendOperator(_ mode: BlendMode) -> cairo_operator_t {
    switch mode {
    case .normal: CAIRO_OPERATOR_OVER
    case .multiply: CAIRO_OPERATOR_MULTIPLY
    case .screen: CAIRO_OPERATOR_SCREEN
    case .overlay: CAIRO_OPERATOR_OVERLAY
    }
  }

  private func filter(_ value: ImageInterpolation) -> cairo_filter_t {
    switch value {
    case .automatic: CAIRO_FILTER_GOOD
    case .nearestNeighbor: CAIRO_FILTER_NEAREST
    case .highQuality: CAIRO_FILTER_BEST
    }
  }
}

extension SionColor {
  func withAlpha(_ alpha: Double) -> SionColor {
    SionColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}

/// Font descriptions for text styles: the desktop's interface font stands in
/// for the system font.
enum SionGtkFonts {
  nonisolated(unsafe) private static var cachedSystemFamily: String?

  static var systemFamily: String {
    if let cachedSystemFamily { return cachedSystemFamily }
    var family = "Cantarell"
    if let settings = gtk_settings_get_default(),
      let name = String(
        takingOwnershipOf: sion_object_get_string(settings.gobject, "gtk-font-name"))
    {
      // "Cantarell 11" → the family is everything before the trailing size.
      let parts = name.split(separator: " ")
      if parts.count > 1, Double(parts.last ?? "") != nil {
        family = parts.dropLast().joined(separator: " ")
      } else if !name.isEmpty {
        family = name
      }
    }
    cachedSystemFamily = family
    return family
  }

  static func description(for style: TextStyle) -> OpaquePointer {
    let description = pango_font_description_new()!
    switch style.font.family {
    case .system:
      pango_font_description_set_family(description, systemFamily)
    case .named(let name):
      pango_font_description_set_family(description, name)
    }
    let weight: PangoWeight
    switch style.font.weight {
    case .light: weight = PANGO_WEIGHT_LIGHT
    case .regular: weight = PANGO_WEIGHT_NORMAL
    case .medium: weight = PANGO_WEIGHT_MEDIUM
    case .semibold: weight = PANGO_WEIGHT_SEMIBOLD
    case .bold: weight = PANGO_WEIGHT_BOLD
    }
    pango_font_description_set_weight(description, weight)
    let size =
      style.font.size.isFinite && style.font.size > 0
      ? style.font.size : CanvasMetrics.defaultFontSize
    pango_font_description_set_absolute_size(description, size * Double(PANGO_SCALE))
    return description
  }
}

/// A decoded display rendition: a Cairo image surface plus its pixel size.
final class SionGtkDecodedImage {
  let surface: OpaquePointer
  let size: SionSize

  init(surface: OpaquePointer, size: SionSize) {
    self.surface = surface
    self.size = size
  }

  deinit {
    cairo_surface_destroy(surface)
  }

  /// Decodes PNG (or any GdkPixbuf-readable) bytes for the controller's cache,
  /// reporting the retained pixel bytes so the cache is charged like AppKit's.
  static func decode(_ data: Data) -> (image: SionGtkDecodedImage, decodedByteCount: Int)? {
    guard let pixbuf = SionGtkPixbuf.load(data) else { return nil }
    defer { g_object_unref(pixbuf.gobject) }
    let width = Int(gdk_pixbuf_get_width(pixbuf))
    let height = Int(gdk_pixbuf_get_height(pixbuf))
    guard width > 0, height > 0,
      let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height)),
      let context = cairo_create(surface)
    else {
      return nil
    }
    gdk_cairo_set_source_pixbuf(context, pixbuf, 0, 0)
    cairo_paint(context)
    cairo_destroy(context)
    let image = SionGtkDecodedImage(
      surface: surface, size: SionSize(width: Double(width), height: Double(height)))
    return (image, width * height * 4)
  }
}

enum SionGtkPixbuf {
  /// Loads a pixbuf from in-memory bytes through a `GdkPixbufLoader`.
  static func load(_ data: Data) -> OpaquePointer? {
    guard let loader = gdk_pixbuf_loader_new() else { return nil }
    defer { g_object_unref(loader.gobject) }
    let written = data.withUnsafeBytes { buffer -> Bool in
      guard let base = buffer.baseAddress else { return false }
      return gdk_pixbuf_loader_write(
        loader, base.assumingMemoryBound(to: guchar.self), gsize(buffer.count), nil) != 0
    }
    guard written, gdk_pixbuf_loader_close(loader, nil) != 0,
      let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader)
    else {
      _ = gdk_pixbuf_loader_close(loader, nil)
      return nil
    }
    g_object_ref(pixbuf.gobject)
    return pixbuf
  }
}

/// A separable box blur applied three times, which approximates a Gaussian
/// closely enough for drop shadows.
enum SionGtkBlur {
  static func blurAlpha(_ surface: OpaquePointer, radius: Double) {
    guard cairo_image_surface_get_format(surface) == CAIRO_FORMAT_A8 else { return }
    let width = Int(cairo_image_surface_get_width(surface))
    let height = Int(cairo_image_surface_get_height(surface))
    let stride = Int(cairo_image_surface_get_stride(surface))
    guard width > 0, height > 0, let data = cairo_image_surface_get_data(surface) else { return }

    // Three box passes of this width match a Gaussian of the given sigma;
    // the blur radius is treated as the sigma, as Core Graphics does.
    let boxRadius = max(1, Int((radius * sqrt(3.0 / 4.0)).rounded()))
    var buffer = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        buffer[y * width + x] = data[y * stride + x]
      }
    }
    var scratch = [UInt8](repeating: 0, count: width * height)
    for _ in 0..<3 {
      boxBlurHorizontal(&buffer, into: &scratch, width: width, height: height, radius: boxRadius)
      boxBlurVertical(&scratch, into: &buffer, width: width, height: height, radius: boxRadius)
    }
    for y in 0..<height {
      for x in 0..<width {
        data[y * stride + x] = buffer[y * width + x]
      }
    }
    cairo_surface_mark_dirty(surface)
  }

  private static func boxBlurHorizontal(
    _ source: inout [UInt8], into destination: inout [UInt8], width: Int, height: Int, radius: Int
  ) {
    let window = Double(radius * 2 + 1)
    for y in 0..<height {
      let row = y * width
      var sum = 0
      for x in -radius...radius {
        sum += Int(source[row + min(width - 1, max(0, x))])
      }
      for x in 0..<width {
        destination[row + x] = UInt8(min(255, (Double(sum) / window).rounded()))
        let leaving = min(width - 1, max(0, x - radius))
        let entering = min(width - 1, max(0, x + radius + 1))
        sum += Int(source[row + entering]) - Int(source[row + leaving])
      }
    }
  }

  private static func boxBlurVertical(
    _ source: inout [UInt8], into destination: inout [UInt8], width: Int, height: Int, radius: Int
  ) {
    let window = Double(radius * 2 + 1)
    for x in 0..<width {
      var sum = 0
      for y in -radius...radius {
        sum += Int(source[min(height - 1, max(0, y)) * width + x])
      }
      for y in 0..<height {
        destination[y * width + x] = UInt8(min(255, (Double(sum) / window).rounded()))
        let leaving = min(height - 1, max(0, y - radius))
        let entering = min(height - 1, max(0, y + radius + 1))
        sum += Int(source[entering * width + x]) - Int(source[leaving * width + x])
      }
    }
  }
}
