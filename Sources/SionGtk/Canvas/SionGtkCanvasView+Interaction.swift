import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// Pointer and keyboard handling. GTK controllers feed `handlePress`,
/// `handleMotion`, `handleRelease`, and `handleKey`, which tests call directly.
extension SionGtkCanvasView {
  func installInteraction() {
    let click = gtk_gesture_click_new()!
    gtk_gesture_single_set_button(click, UInt32(GDK_BUTTON_PRIMARY))
    Signals.connect(click.gobject, "pressed") { [weak self] count, x, y in
      guard let self else { return }
      let state = gtk_event_controller_get_current_event_state(click)
      self.handlePress(
        at: self.modelPoint(fromWidgetX: x, y: y), modifiers: Modifiers(state),
        clickCount: Int(count))
    }
    Signals.connect(click.gobject, "released") { [weak self] _, x, y in
      guard let self else { return }
      let state = gtk_event_controller_get_current_event_state(click)
      self.handleRelease(at: self.modelPoint(fromWidgetX: x, y: y), modifiers: Modifiers(state))
    }
    // A gesture GTK takes away mid-drag never releases; only a release commits.
    Signals.connect(click.gobject, "cancel") { [weak self] _ in
      self?.cancelActiveDrag()
    }
    gtk_widget_add_controller(drawingArea, click)

    let secondary = gtk_gesture_click_new()!
    gtk_gesture_single_set_button(secondary, UInt32(GDK_BUTTON_SECONDARY))
    Signals.connect(secondary.gobject, "pressed") { [weak self] _, x, y in
      self?.handleContextMenuRequest(atWidgetX: x, y: y)
    }
    gtk_widget_add_controller(drawingArea, secondary)

    let motion = gtk_event_controller_motion_new()!
    Signals.connect(motion.gobject, "motion") { [weak self] x, y in
      guard let self else { return }
      let state = gtk_event_controller_get_current_event_state(motion)
      self.handleMotion(to: self.modelPoint(fromWidgetX: x, y: y), modifiers: Modifiers(state))
    }
    Signals.connect(motion.gobject, "leave") { [weak self] in
      guard let self, self.drag == nil else { return }
      self.lastPointerModelPoint = nil
      self.setCursor("default")
    }
    gtk_widget_add_controller(drawingArea, motion)

    let key = gtk_event_controller_key_new()!
    Signals.connectKey(key.gobject, "key-pressed") { [weak self] keyval, _, state in
      self?.handleKey(keyval: keyval, modifiers: Modifiers(state)) ?? false
    }
    gtk_widget_add_controller(drawingArea, key)

    let focus = gtk_event_controller_focus_new()!
    Signals.connect(focus.gobject, "leave") { [weak self] in
      self?.cancelActiveDrag()
    }
    gtk_widget_add_controller(drawingArea, focus)

    // Control-scroll and pinch zoom are how the desktop zooms a document.
    let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL)!
    Signals.connectScroll(scroll.gobject, "scroll") { [weak self] _, dy in
      guard let self else { return false }
      let state = gtk_event_controller_get_current_event_state(scroll)
      guard state.rawValue & GDK_CONTROL_MASK.rawValue != 0 else { return false }
      let center = self.lastPointerModelPoint
      self.setMagnification(
        dy < 0 ? self.magnification * Self.zoomStep : self.magnification / Self.zoomStep,
        centeredAt: center)
      return true
    }
    gtk_widget_add_controller(drawingArea, scroll)

    let zoom = gtk_gesture_zoom_new()!
    var pinchStart = 1.0
    Signals.connect(zoom.gobject, "begin") { [weak self] _ in
      pinchStart = self?.magnification ?? 1
    }
    Signals.connectScale(zoom.gobject) { [weak self] scale in
      self?.setMagnification(pinchStart * scale)
    }
    gtk_widget_add_controller(drawingArea, zoom)
  }

  // MARK: Presses

  /// A primary press: the last recovery point when a release was lost, then
  /// anchor editing, magnet drags, or the active tool.
  func handlePress(at point: SionPoint, modifiers: Modifiers, clickCount: Int) {
    cancelActiveDrag()
    commitTextEditing()
    grabFocus()
    isPointerDown = true
    lastPointerModelPoint = point

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
      beginSelection(at: point, modifiers: modifiers, clickCount: clickCount)
    case .rectangle, .circle:
      guard let shapeKind = editorController.tool.shapeKind else { return }

      drag = .create(creation: .shape(shapeKind), start: point, current: point)
    case .text:
      drag = .create(creation: .text, start: point, current: point)
    case .connector:
      beginConnector(at: point)
    }
    queueRedraw()
  }

  func handleMotion(to point: SionPoint, modifiers: Modifiers) {
    lastPointerModelPoint = point
    guard isPointerDown, let drag else {
      if isPointerDown == false {
        updateCursor(at: point)
      }
      return
    }

    switch drag {
    case .move(let startPoint, let startBounds, let appliedOffset):
      let requested = point - startPoint
      let snap = objectSnap(for: startBounds.translated(by: requested))
      let offset = requested + snap.offset
      try? editorController.moveSelection(by: offset - appliedOffset)
      self.drag = .move(startPoint: startPoint, startBounds: startBounds, appliedOffset: offset)
      if snapGuides != snap.guides {
        snapGuides = snap.guides
        queueRedraw()
      }
    case .resize(let elementID, let handle, let startFrame, let rotationRadians, let preserves):
      // Shift inverts the element's own convention: an image keeps its
      // proportions unless asked not to, everything else the other way round.
      let constrainsAspect = preserves != modifiers.contains(.shift)
      let frame = InteractionGeometry.resizedFrame(
        startFrame,
        moving: handle,
        to: point,
        minimumSize: CanvasMetrics.minimumElementSize,
        rotationRadians: rotationRadians,
        aspectRatio: constrainsAspect ? aspectRatio(of: startFrame) : nil
      )
      try? editorController.resize(elementID, to: frame)
    case .rotate(let elementID, let center, let startPoint, let startRotation):
      let delta = InteractionGeometry.rotationDelta(from: startPoint, to: point, around: center)
      let rotation = snappedRotation(startRotation + delta, modifiers: modifiers)
      try? editorController.rotate(elementID, to: rotation)
    case .cornerRadius(
      let elementID, let frame, let rotationRadians, let startPoint, let startRadius):
      let initialPointerRadius = InteractionGeometry.roundedRectangleCornerRadius(
        in: frame, draggedTo: startPoint, rotationRadians: rotationRadians)
      let pointerRadius = InteractionGeometry.roundedRectangleCornerRadius(
        in: frame, draggedTo: point, rotationRadians: rotationRadians)
      let maximumRadius = min(frame.width, frame.height) / 2
      let radius = min(maximumRadius, max(0, startRadius + pointerRadius - initialPointerRadius))
      try? editorController.setCornerRadius(radius, on: elementID)
    case .create(let creation, let start, _):
      self.drag = .create(creation: creation, start: start, current: point)
      queueRedraw()
    case .connector(let sourceID, let start, _):
      let target = connectorTarget(at: point, use: .incoming)
      self.drag = .connector(sourceID: sourceID, start: start, current: target.point)
      queueRedraw()
    case .marquee(let origin, _):
      self.drag = .marquee(origin: origin, current: point)
      queueRedraw()
    }
  }

  func handleRelease(at point: SionPoint, modifiers: Modifiers) {
    isPointerDown = false
    guard let drag = takeActiveDrag() else { return }
    updateCursor(at: point)

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
      finishCreation(creation, from: start, to: point)
    case .connector(let sourceID, let start, _):
      let target = connectorTarget(at: point, use: .incoming)
      let end = target.point
      guard start.distance(to: end) >= CanvasMetrics.minimumConnectorLength else {
        queueRedraw()
        return
      }

      do {
        _ = try editorController.insertConnector(
          from: sourceID, sourcePoint: start, to: target.elementID, targetPoint: end)
        // A magnet drag started under a placement tool completes the connector
        // tool only, so an armed placement tool survives it.
        editorController.toolDidComplete(.connector)
      } catch {
        creationFailureFeedback()
        queueRedraw()
      }
    case .marquee(let origin, _):
      // Modifier state at release decides replace versus extend, matching
      // the gesture the user believes they performed.
      endMarquee(from: origin, to: point, mode: modifiers.contains(.shift) ? .extend : .replace)
    }
  }

  // MARK: Keyboard

  /// Returns true when the key was consumed.
  func handleKey(keyval: UInt32, modifiers: Modifiers) -> Bool {
    switch keyval {
    case UInt32(GDK_KEY_Escape):
      cancelInteraction()
      return true
    case UInt32(GDK_KEY_Return), UInt32(GDK_KEY_KP_Enter):
      guard let element = editorController.selectedElement, element.editableText != nil else {
        return false
      }
      beginTextEditing(element.id)
      return true
    case UInt32(GDK_KEY_Tab), UInt32(GDK_KEY_ISO_Left_Tab):
      let traversal: SionEditorController.SelectionTraversal =
        modifiers.contains(.shift) || keyval == UInt32(GDK_KEY_ISO_Left_Tab) ? .backward : .forward
      editorController.selectAdjacent(traversal)
      return true
    case UInt32(GDK_KEY_Delete), UInt32(GDK_KEY_BackSpace), UInt32(GDK_KEY_KP_Delete):
      try? editorController.deleteSelection()
      return true
    default:
      break
    }

    if !editorController.selection.isEmpty, let direction = nudgeDirection(for: keyval) {
      let distance =
        modifiers.contains(.shift) ? CanvasMetrics.largeNudgeDistance : CanvasMetrics.nudgeDistance
      try? editorController.nudgeSelection(by: direction * distance)
      return true
    }

    return false
  }

  private func nudgeDirection(for keyval: UInt32) -> SionVector? {
    switch keyval {
    case UInt32(GDK_KEY_Left), UInt32(GDK_KEY_KP_Left): .west
    case UInt32(GDK_KEY_Right), UInt32(GDK_KEY_KP_Right): .east
    case UInt32(GDK_KEY_Down), UInt32(GDK_KEY_KP_Down): .south
    case UInt32(GDK_KEY_Up), UInt32(GDK_KEY_KP_Up): .north
    default: nil
    }
  }

  /// Escape cancels inwards: text, anchors, a live gesture, then selection.
  func cancelInteraction() {
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

  /// Only a release commits; every other terminal path cancels the drag.
  package func cancelActiveDrag() {
    isPointerDown = false
    guard let activeDrag = takeActiveDrag() else { return }
    guard activeDrag.requiresEditorGesture else { return }

    editorController.cancelActiveGesture()
  }

  /// Clear view state before controller callbacks can synchronously notify us.
  func takeActiveDrag() -> Drag? {
    guard let activeDrag = drag else { return nil }

    drag = nil
    snapGuides = []
    queueRedraw()
    setCursor("default")
    refreshCursorForCurrentPointer()
    return activeDrag
  }

  // MARK: Selection gestures

  private func beginSelection(at point: SionPoint, modifiers: Modifiers, clickCount: Int) {
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
    if let source = magnetTarget(at: point, use: .outgoing, elements: selectedConnectableElements) {
      beginConnector(from: source)
      return
    }

    guard let element = editorController.element(at: point) else {
      // Shift keeps the current selection as the marquee's base.
      if !modifiers.contains(.shift) {
        editorController.select(nil)
      }
      drag = .marquee(origin: point, current: point)
      return
    }

    if clickCount == CanvasMetrics.textEditClickCount, element.editableText != nil {
      editorController.select(element.id)
      isPointerDown = false
      beginTextEditing(element.id)
      return
    }

    if modifiers.contains(.shift) {
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
      drag = .move(startPoint: point, startBounds: selectionBounds(), appliedOffset: .zero)
      setCursor("grabbing")
    } catch {
      drag = nil
    }
  }

  private func handleAnchorEditing(at point: SionPoint) -> Bool {
    guard let id = editorController.anchorEditingState.elementID else { return false }

    do {
      let result = try editorController.editAnchor(
        at: point, on: id,
        hitTolerance: CanvasMetrics.anchorEditingHitTolerance * inverseMagnification)
      switch result {
      case .changed:
        return true
      case .outsideElement, .unavailable:
        editorController.endAnchorEditing()
        return false
      }
    } catch {
      creationFailureFeedback()
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
        rotationRadians: element.geometry.rotationRadians,
        preservesAspectRatio: element.preservesAspectRatioWhileResizing
      )
    } catch {
      drag = nil
    }
  }

  /// The proportion a constrained resize holds: what the frame had when the
  /// drag began, not the artwork's own.
  private func aspectRatio(of frame: SionRect) -> Double? {
    let standardized = frame.standardized
    guard standardized.width > 0, standardized.height > 0 else { return nil }

    return standardized.width / standardized.height
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
    drag = .connector(sourceID: source.elementID, start: source.point, current: source.point)
    queueRedraw()
  }

  private func finishCreation(_ creation: Creation, from start: SionPoint, to end: SionPoint) {
    let placement = creationPlacement(creation, from: start, to: end)
    let activeTool = editorController.tool

    do {
      switch creation {
      case .shape(let kind):
        _ = try editorController.insertShape(in: placement.frame, kind: kind)
      case .text:
        let id = try editorController.insertText("Text", in: placement.frame)
        beginTextEditing(id)
      }
      // Only a committed insertion spends a one-shot tool; a throw skips this.
      editorController.toolDidComplete(activeTool)
    } catch {
      creationFailureFeedback()
    }

    queueRedraw()
  }

  func creationPlacement(_ creation: Creation, from start: SionPoint, to end: SionPoint)
    -> CreationPlacement
  {
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

    return CreationPlacement(frame: circularFrame(from: start, to: end), mode: .drag)
  }

  private func circularFrame(from start: SionPoint, to end: SionPoint) -> SionRect {
    let width = abs(end.x - start.x)
    let height = abs(end.y - start.y)
    let minimumSide = max(
      CanvasMetrics.minimumElementSize.width, CanvasMetrics.minimumElementSize.height)
    let side = max(minimumSide, max(width, height))
    let x = end.x < start.x ? start.x - side : start.x
    let y = end.y < start.y ? start.y - side : start.y

    return SionRect(x: x, y: y, width: side, height: side)
  }

  /// The union of what is being dragged, which is what lines up with the
  /// rest. A rotated element does not sit on its stored frame's edges, so
  /// this measures the box it actually occupies — what the user sees.
  private func selectionBounds() -> SionRect {
    let frames = editorController.selectedElements
      .filter { $0.content.connector == nil }
      .map { InteractionGeometry.rotatedBounds(of: $0.geometry) }

    return frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }
  }

  /// Everything the drag could line up with: visible, unselected, and framed.
  private func objectSnap(for proposedBounds: SionRect) -> SceneSnap {
    // A connector-only selection has no frame of its own to line up.
    guard snapsToObjects, proposedBounds.isFinite,
      proposedBounds.width > 0 || proposedBounds.height > 0
    else {
      return .none
    }

    let selection = editorController.selection
    let neighbours = editorController.document.scene.elements
      .filter {
        $0.visibility == .visible && $0.content.connector == nil && !selection.contains($0.id)
      }
      .map { InteractionGeometry.rotatedBounds(of: $0.geometry) }

    return SceneSnapping.snap(
      proposedBounds, to: neighbours, tolerance: CanvasMetrics.snapTolerance * inverseMagnification)
  }

  /// Commits the rubber band: touched elements join the selection, replacing
  /// it unless Shift extends at release time.
  private func endMarquee(
    from origin: SionPoint, to current: SionPoint, mode: SionEditorController.SelectionMode
  ) {
    let marqueeRect = SionRect(
      origin: origin,
      size: SionSize(width: current.x - origin.x, height: current.y - origin.y)
    ).standardized
    guard
      marqueeRect.width >= minimumMarqueeModelSize || marqueeRect.height >= minimumMarqueeModelSize
    else {
      return
    }

    editorController.select(editorController.elementIDsIntersecting(marqueeRect), mode: mode)
  }

  var minimumMarqueeModelSize: Double {
    CanvasMetrics.minimumMarqueeScreenSize * inverseMagnification
  }

  // MARK: Hit geometry

  func resizeHandle(at point: SionPoint, for element: SceneElement) -> ResizeHandle? {
    ResizeHandle.allCases.first { handle in
      let handlePoint = InteractionGeometry.resizeHandlePoint(
        handle, in: element.geometry.frame, rotationRadians: element.geometry.rotationRadians)
      return point.distance(to: handlePoint) <= CanvasMetrics.handleHitRadius * inverseMagnification
    }
  }

  func isRotationHandle(_ point: SionPoint, for element: SceneElement) -> Bool {
    point.distance(to: rotationHandlePoint(for: element))
      <= CanvasMetrics.handleHitRadius * inverseMagnification
  }

  func isCornerRadiusHandle(_ point: SionPoint, for element: SceneElement) -> Bool {
    guard let handlePoint = cornerRadiusHandlePoint(for: element) else { return false }

    return point.distance(to: handlePoint) <= CanvasMetrics.handleHitRadius * inverseMagnification
  }

  func cornerRadius(of element: SceneElement) -> Double? {
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

  func connectorTarget(at point: SionPoint, use: MagnetUse) -> ConnectorTarget {
    let elements = editorController.document.scene.elements.filter {
      $0.visibility == .visible && $0.content.connector == nil
    }
    if let target = magnetTarget(at: point, use: use, elements: elements) {
      return target
    }

    let element = editorController.connectableElement(at: point)
    return ConnectorTarget(elementID: element?.id, point: point)
  }

  func magnetTarget(at point: SionPoint, use: MagnetUse, elements: [SceneElement])
    -> ConnectorTarget?
  {
    let tolerance = CanvasMetrics.magnetHitTolerance * inverseMagnification
    var nearest: (distance: Double, target: ConnectorTarget)?

    for element in elements.reversed() {
      for resolved in element.resolvedMagnets
      where resolved.magnet.connectionDirection.allows(use) {
        let distance = point.distance(to: magnetDisplayPoint(resolved))
        guard distance <= tolerance, nearest.map({ distance < $0.distance }) ?? true else {
          continue
        }

        nearest = (distance, ConnectorTarget(elementID: element.id, point: resolved.endpoint.point))
      }
    }

    return nearest?.target
  }

  func magnetDisplayPoint(_ resolved: ResolvedMagnet) -> SionPoint {
    // Keep connector dots separate from the side-resize handles on the outline.
    let offset = CanvasMetrics.magnetOffset * inverseMagnification
    return resolved.endpoint.point + (resolved.endpoint.outwardDirection.normalized * offset)
  }

  private func snappedRotation(_ radians: Double, modifiers: Modifiers) -> Double {
    guard modifiers.contains(.shift) else { return radians }

    let step = CanvasMetrics.rotationSnapRadians
    return (radians / step).rounded() * step
  }

  func resizeHandlePoint(_ handle: ResizeHandle, for element: SceneElement) -> SionPoint {
    InteractionGeometry.resizeHandlePoint(
      handle, in: element.geometry.frame, rotationRadians: element.geometry.rotationRadians)
  }

  func rotationHandlePoint(for element: SceneElement) -> SionPoint {
    InteractionGeometry.rotationHandlePoint(
      in: element.geometry.frame,
      rotationRadians: element.geometry.rotationRadians,
      offset: CanvasMetrics.rotationHandleOffset * inverseMagnification
    )
  }

  func cornerRadiusHandlePoint(for element: SceneElement) -> SionPoint? {
    guard let radius = cornerRadius(of: element) else { return nil }
    let frame = element.geometry.frame.standardized
    let maximumRadius = min(frame.width, frame.height) / 2
    let minimumDisplayRadius = CanvasMetrics.cornerRadiusHandleMinimumInset * inverseMagnification
    let displayRadius = min(maximumRadius, max(radius, minimumDisplayRadius))
    let point = InteractionGeometry.roundedRectangleCornerRadiusHandle(
      in: frame, radius: displayRadius, rotationRadians: element.geometry.rotationRadians)
    let minimumSeparation = CanvasMetrics.handleHitRadius * inverseMagnification
    let overlapsResizeHandle = ResizeHandle.allCases.contains {
      point.distance(to: resizeHandlePoint($0, for: element)) <= minimumSeparation
    }

    return overlapsResizeHandle ? nil : point
  }

  // MARK: Cursors

  /// Tool and selection changes arrive without pointer movement; re-derive the
  /// cursor whenever the pointer already sits inside the canvas.
  func refreshCursorForCurrentPointer() {
    guard drag == nil, let point = lastPointerModelPoint else { return }

    updateCursor(at: point)
  }

  /// The canvas reads as a physical surface: hands for moves, crosshairs
  /// for creation tools, diagonal arrows over resize handles.
  private func updateCursor(at point: SionPoint) {
    setCursor(cursorName(for: point))
  }

  func cursorName(for point: SionPoint) -> String {
    switch editorController.tool {
    case .select:
      if editorController.anchorEditingState != .inactive {
        return "crosshair"
      }
    case .rectangle, .circle, .text, .connector:
      return "crosshair"
    }

    if let element = editorController.selectedElement,
      element.lockState == .editable,
      element.content.connector == nil,
      let handle = resizeHandle(at: point, for: element)
    {
      switch handle {
      case .northWest, .southEast: return "nwse-resize"
      case .northEast, .southWest: return "nesw-resize"
      case .north, .south: return "ns-resize"
      case .east, .west: return "ew-resize"
      }
    }

    if let element = editorController.element(at: point),
      element.lockState == .editable,
      element.content.connector == nil
    {
      return "grab"
    }

    return "default"
  }

  func setCursor(_ name: String) {
    gtk_widget_set_cursor_from_name(drawingArea, name)
  }
}

extension Signals {
  /// `(instance, double, user_data)`: `GtkGestureZoom::scale-changed`.
  @discardableResult
  static func connectScale(_ instance: gpointer, handler: @escaping @MainActor (Double) -> Void)
    -> gulong
  {
    typealias Handler = @MainActor (Double) -> Void
    let trampoline: @convention(c) (gpointer?, Double, gpointer?) -> Void = { _, scale, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(scale) }
    }
    return sion_signal_connect(
      instance, "scale-changed", unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }
}
