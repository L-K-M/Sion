#if canImport(AppKit)
  import AppKit
  import SionCore

  /// Shared placement defaults keep click and drag creation consistent.
  enum SionCreationDefaults {
    static let rectangleSize = SionSize(width: 160, height: 96)
    static let circleSize = SionSize(width: 120, height: 120)
    static let textSize = SionSize(width: 220, height: 56)

    static func shapeSize(for kind: ShapeKind) -> SionSize {
      switch kind {
      case .ellipse:
        circleSize
      case .rectangle, .roundedRectangle, .diamond, .triangle, .hexagon, .capsule,
        .cylinder, .custom:
        rectangleSize
      }
    }
  }

  @MainActor
  /// The sole UI gateway to scene edits, selection, assets, and native undo.
  final class SionEditorController: NSObject {
    enum DocumentChange {
      case done
      case undone
      case redone
    }

    enum SelectionMode {
      case replace
      case extend
    }

    enum SelectionTraversal {
      case forward
      case backward
    }

    enum AnchorEditingState: Equatable {
      case inactive
      case editing(ElementID)

      var elementID: ElementID? {
        guard case .editing(let id) = self else { return nil }

        return id
      }
    }

    enum AnchorEditResult: Equatable {
      case changed
      case outsideElement
      case unavailable
    }

    enum Tool: Int, CaseIterable {
      case select
      case rectangle
      case circle
      case text
      case connector

      var title: String {
        switch self {
        case .select: "Select"
        case .rectangle: "Rectangle"
        case .circle: "Circle"
        case .text: "Text"
        case .connector: "Connector"
        }
      }

      var symbolName: String {
        switch self {
        case .select: "arrow.up.left"
        case .rectangle: "rectangle"
        case .circle: "circle"
        case .text: "textformat"
        case .connector: "point.topleft.down.to.point.bottomright.curvepath"
        }
      }

      var help: String {
        switch self {
        case .select: "Select and transform objects"
        case .rectangle: "Click or drag to create a rectangle"
        case .circle: "Click or drag to create a circle"
        case .text: "Click or drag to create a text box"
        case .connector: "Drag between objects or connection points"
        }
      }

      var shapeKind: ShapeKind? {
        switch self {
        case .rectangle:
          .roundedRectangle(radius: SceneElementDefaults.cornerRadius)
        case .circle:
          .ellipse
        case .select, .text, .connector:
          nil
        }
      }
    }

    private(set) var selection = Set<ElementID>()
    private(set) var tool = Tool.select
    private(set) var anchorEditingState = AnchorEditingState.inactive
    private var editor: SceneEditor
    private var assets: [AssetID: SionAsset]
    private var history: DocumentHistory
    private var previewPNG: Data?
    private var pendingTextEdit: PendingTextEdit?
    private var routeCache: [ElementID: ConnectorRoute]
    private let imageCache: NSCache<NSString, NSImage>

    private let undoManagerProvider: () -> UndoManager?
    private let didChange: (DocumentChange) -> Void
    private var observers: [UUID: () -> Void] = [:]

    init(
      package: SionPackage,
      undoManagerProvider: @escaping () -> UndoManager?,
      didChange: @escaping (DocumentChange) -> Void
    ) throws {
      editor = try SceneEditor(document: package.document)
      assets = package.assets
      history = package.history
      previewPNG = package.previewPNG
      pendingTextEdit = nil
      routeCache = [:]
      imageCache = NSCache()
      imageCache.countLimit = EditorDefaults.imageCacheLimit
      imageCache.totalCostLimit = EditorDefaults.imageCacheTotalCostLimit
      self.undoManagerProvider = undoManagerProvider
      self.didChange = didChange

      super.init()
    }

    var document: SionDocument { editor.document }

    var selectedElements: [SceneElement] {
      editor.document.scene.elements.filter { selection.contains($0.id) }
    }

    var selectedElement: SceneElement? {
      guard selection.count == 1, let id = selection.first else { return nil }

      return editor.document.scene.element(withID: id)
    }

    var canMoveSelection: Bool {
      let elements = selectedElements
      guard !elements.isEmpty, elements.allSatisfy({ $0.lockState == .editable }) else {
        return false
      }

      return elements.contains { element in
        guard let connector = element.content.connector else { return true }

        return connector.manualRoute != nil
          || connector.source.elementID == nil
          || connector.target.elementID == nil
      }
    }

    var historyRevisions: [HistoryRevision] { history.revisions }

    func selectionPayloadData() throws -> Data {
      let payload = try SceneSelectionPayload(
        package: packageForArchiving(),
        selectedElementIDs: selection
      )
      return try payload.dataRepresentation()
    }

    @discardableResult
    func insertSelectionPayload(_ data: Data, at point: SionPoint) throws -> [ElementID] {
      let payload = try SceneSelectionPayload(data: data)
      let occupiedIDs = Set(editor.document.scene.elements.map(\.id))
      let insertion = try payload.insertion(centeredAt: point, excluding: occupiedIDs)
      let insertedAssetIDs = try mergeAssets(insertion.assets)
      let transaction = SceneTransaction(
        name: "Paste",
        command: .insert(elements: insertion.elements, at: nil)
      )

      let result: EditorOperationResult
      do {
        result = try editor.perform(transaction)
      } catch {
        removeAssets(insertedAssetIDs)
        throw error
      }

      guard result == .applied else {
        removeAssets(insertedAssetIDs)
        return []
      }

      let insertedIDs = insertion.elements.map(\.id)
      selection = Set(insertedIDs)
      registerUndo(actionName: transaction.name)
      notifyModelChange(notification: .done)
      return insertedIDs
    }

    func packageForArchiving() -> SionPackage {
      SionPackage(
        document: editor.document,
        assets: assets,
        history: history,
        previewPNG: previewPNG
      )
    }

    func commitArchivedHistory(_ committedHistory: DocumentHistory) {
      history = committedHistory
      notifyObservers()
    }

    func load(_ package: SionPackage) throws {
      editor = try SceneEditor(document: package.document)
      assets = package.assets
      history = package.history
      previewPNG = package.previewPNG
      pendingTextEdit = nil
      anchorEditingState = .inactive
      routeCache.removeAll()
      imageCache.removeAllObjects()
      selection.removeAll()
      undoManagerProvider()?.removeAllActions(withTarget: self)
      notifyObservers()
    }

    func asset(for id: AssetID) -> SionAsset? {
      assets[id]
    }

    /// Decodes display renditions once; IDs are content addressed, so entries
    /// stay valid until the asset is dropped. NSCache evicts under pressure.
    func image(for content: ImageContent) -> NSImage? {
      let key = NSString(string: content.displayAssetID.rawValue)
      if let cached = imageCache.object(forKey: key) {
        return cached
      }

      guard let asset = asset(for: content.displayAssetID),
        let image = NSImage(data: asset.data)
      else {
        return nil
      }

      imageCache.setObject(image, forKey: key, cost: asset.data.count)
      return image
    }

    func connectorRoute(for element: SceneElement) -> ConnectorRoute? {
      if let cached = routeCache[element.id] {
        return cached
      }

      guard
        let route = SceneRenderGeometry.connectorRoute(
          for: element,
          in: editor.document.scene
        )
      else {
        return nil
      }

      routeCache[element.id] = route
      return route
    }

    /// Routes once per scene state; bounds, drawing, and hit testing share it.
    func editingCanvasBounds(minimumInfiniteSize: SionSize) -> SionRect {
      SceneRenderGeometry.editingCanvasBounds(
        of: editor.document.scene,
        minimumInfiniteSize: minimumInfiniteSize,
        connectorRoutes: { [weak self] element in
          self?.connectorRoute(for: element) ?? nil
        }
      )
    }

    func connectorPreview(
      from sourceID: ElementID?,
      sourcePoint: SionPoint,
      to targetID: ElementID?,
      targetPoint: SionPoint
    ) -> ConnectorRoute? {
      let preview = SceneElement.connector(
        source: endpoint(elementID: sourceID, point: sourcePoint, use: .outgoing),
        target: endpoint(elementID: targetID, point: targetPoint, use: .incoming)
      )
      let currentScene = editor.document.scene
      let scene = SionScene(
        canvas: currentScene.canvas,
        elements: currentScene.elements + [preview],
        extensions: currentScene.extensions
      )
      return SceneRenderGeometry.connectorRoute(for: preview, in: scene)
    }

    func contentBounds() -> SionRect {
      SceneRenderGeometry.contentBounds(of: editor.document.scene)
    }

    @discardableResult
    func observeChanges(_ observer: @escaping () -> Void) -> UUID {
      let id = UUID()
      observers[id] = observer
      return id
    }

    func removeObserver(_ id: UUID) {
      observers[id] = nil
    }

    func setTool(_ newTool: Tool) {
      guard tool != newTool else { return }

      tool = newTool
      anchorEditingState = .inactive
      notifyObservers()
    }

    func beginAnchorEditing(on id: ElementID) {
      guard selectedElement?.id == id,
        let element = editor.document.scene.element(withID: id),
        element.lockState == .editable,
        element.content.connector == nil
      else {
        endAnchorEditing()
        return
      }

      let nextState = AnchorEditingState.editing(id)
      guard anchorEditingState != nextState else { return }

      anchorEditingState = nextState
      notifyObservers()
    }

    func endAnchorEditing() {
      guard anchorEditingState != .inactive else { return }

      anchorEditingState = .inactive
      notifyObservers()
    }

    @discardableResult
    func editAnchor(
      at point: SionPoint,
      on id: ElementID,
      hitTolerance: Double
    ) throws -> AnchorEditResult {
      guard anchorEditingState == .editing(id),
        let element = editor.document.scene.element(withID: id),
        element.lockState == .editable,
        element.content.connector == nil
      else {
        return .unavailable
      }

      let frame = element.geometry.frame.standardized
      guard frame.width > 0, frame.height > 0 else { return .unavailable }

      var anchors = element.expandedMagnets
      let nearest = element.resolvedMagnets.enumerated().min { first, second in
        point.distance(to: first.element.endpoint.point)
          < point.distance(to: second.element.endpoint.point)
      }
      let tolerance = hitTolerance.isFinite ? max(0, hitTolerance) : 0
      if let nearest,
        point.distance(to: nearest.element.endpoint.point) <= tolerance
      {
        anchors.remove(at: nearest.offset)
        try setMagnetConfiguration(.custom(anchors), on: id)
        return .changed
      }

      let localPoint = InteractionGeometry.unrotated(
        point,
        around: frame.center,
        by: element.geometry.rotationRadians
      )
      guard frame.contains(localPoint) else { return .outsideElement }
      guard anchors.count < SceneLimits.maximumMagnetsPerElement else { return .unavailable }

      anchors.append(customAnchor(for: element, at: localPoint, in: frame))
      try setMagnetConfiguration(.custom(anchors), on: id)
      return .changed
    }

    func select(_ id: ElementID?, mode: SelectionMode = .replace) {
      let previous = selection

      guard let id else {
        selection.removeAll()
        notifySelectionChange(from: previous)
        return
      }

      if mode == .extend {
        if !selection.insert(id).inserted {
          selection.remove(id)
        }
      } else {
        selection = [id]
      }

      notifySelectionChange(from: previous)
    }

    func selectAll() {
      let previous = selection
      selection = Set(
        editor.document.scene.elements.lazy.filter {
          $0.visibility == .visible && $0.lockState == .editable
        }.map(\.id))
      notifySelectionChange(from: previous)
    }

    func selectAdjacent(_ traversal: SelectionTraversal) {
      let elements = editor.document.scene.elements.filter {
        $0.visibility == .visible && $0.lockState == .editable
      }
      guard !elements.isEmpty else {
        select(nil)
        return
      }

      guard let selectedID = selection.first,
        let index = elements.firstIndex(where: { $0.id == selectedID })
      else {
        select(traversal == .forward ? elements[0].id : elements[elements.count - 1].id)
        return
      }

      let offset = traversal == .forward ? 1 : -1
      let nextIndex = (index + offset + elements.count) % elements.count
      select(elements[nextIndex].id)
    }

    func nudgeSelection(by offset: SionVector) throws {
      guard canMoveSelection else { return }

      try perform(name: "Move", command: .translate(elementIDs: selection, by: offset))
    }

    @discardableResult
    func insertShape(at point: SionPoint) throws -> ElementID {
      try insertShape(
        at: point,
        kind: .roundedRectangle(radius: SceneElementDefaults.cornerRadius)
      )
    }

    @discardableResult
    func insertShape(at point: SionPoint, kind: ShapeKind) throws -> ElementID {
      // Click insertion anchors the default frame at the pointer.
      let frame = SionRect(
        origin: point,
        size: SionCreationDefaults.shapeSize(for: kind)
      )

      return try insertShape(in: frame, kind: kind)
    }

    @discardableResult
    func insertShape(in frame: SionRect, kind: ShapeKind) throws -> ElementID {
      let element = SceneElement.shape(frame: frame.standardized, kind: kind)

      try perform(name: "Add Shape", command: .insert(elements: [element], at: nil))
      select(element.id)
      return element.id
    }

    @discardableResult
    func insertShape(centeredAt point: SionPoint, kind: ShapeKind) throws -> ElementID {
      let size = SionCreationDefaults.shapeSize(for: kind)
      let frame = SionRect(
        x: point.x - (size.width / 2),
        y: point.y - (size.height / 2),
        width: size.width,
        height: size.height
      )

      return try insertShape(in: frame, kind: kind)
    }

    @discardableResult
    func insertText(_ text: String, at point: SionPoint) throws -> ElementID {
      let frame = SionRect(
        origin: point,
        size: SionCreationDefaults.textSize
      )

      return try insertText(text, in: frame)
    }

    @discardableResult
    func insertText(_ text: String, in frame: SionRect) throws -> ElementID {
      let element = SceneElement.text(frame: frame.standardized, text: text)

      try perform(name: "Add Text", command: .insert(elements: [element], at: nil))
      select(element.id)
      return element.id
    }

    @discardableResult
    func insertText(_ text: String, centeredAt point: SionPoint) throws -> ElementID {
      let size = SionCreationDefaults.textSize
      let frame = SionRect(
        x: point.x - (size.width / 2),
        y: point.y - (size.height / 2),
        width: size.width,
        height: size.height
      )

      return try insertText(text, in: frame)
    }

    @discardableResult
    func insertImage(
      originalData: Data,
      mediaType: String,
      fileExtension: String,
      filename: String?,
      pixelSize: SionSize?,
      displayPNGData: Data,
      displayPixelSize: SionSize,
      at point: SionPoint
    ) throws -> ElementID {
      let originalAsset = try SionAsset(
        data: originalData,
        mediaType: mediaType,
        fileExtension: fileExtension,
        originalFilename: filename,
        pixelSize: pixelSize
      )
      let displayAsset = try SionAsset.safeDisplayPNG(
        data: displayPNGData,
        pixelSize: displayPixelSize
      )
      let size = fittedImageSize(pixelSize)
      let frame = SionRect(
        x: point.x - (size.width / 2),
        y: point.y - (size.height / 2),
        width: size.width,
        height: size.height
      )
      let element = SceneElement.image(
        frame: frame,
        assetID: originalAsset.id,
        displayAssetID: displayAsset.id
      )

      var incomingAssets = [originalAsset.id: originalAsset]
      if displayAsset.id != originalAsset.id {
        incomingAssets[displayAsset.id] = displayAsset
      }
      let insertedAssetIDs = try mergeAssets(incomingAssets)

      do {
        try perform(name: "Add Image", command: .insert(elements: [element], at: nil))
      } catch {
        removeAssets(insertedAssetIDs)
        throw error
      }

      select(element.id)
      return element.id
    }

    @discardableResult
    func insertConnector(
      from sourceID: ElementID?,
      sourcePoint: SionPoint,
      to targetID: ElementID?,
      targetPoint: SionPoint
    ) throws -> ElementID {
      let source = endpoint(elementID: sourceID, point: sourcePoint, use: .outgoing)
      let target = endpoint(elementID: targetID, point: targetPoint, use: .incoming)
      let element = SceneElement.connector(source: source, target: target)

      try perform(name: "Add Connector", command: .insert(elements: [element], at: nil))
      select(element.id)
      return element.id
    }

    func insertMermaid(_ source: String, at point: SionPoint) throws -> [ElementID] {
      let elements = MermaidImporter.elements(from: source, centeredAt: point)
      guard !elements.isEmpty else {
        _ = try insertText(source, centeredAt: point)
        return Array(selection)
      }

      try perform(name: "Paste Mermaid", command: .insert(elements: elements, at: nil))
      selection = Set(elements.map(\.id))
      notifyObservers()
      return elements.map(\.id)
    }

    func beginTextEdit(on id: ElementID) throws {
      guard pendingTextEdit == nil else {
        throw SceneEditingError.gestureAlreadyActive
      }

      try editor.beginGesture(named: EditorActionName.editText)
      pendingTextEdit = PendingTextEdit(elementID: id)
    }

    func updateTextEdit(_ text: String, on id: ElementID) throws {
      guard var pendingTextEdit, pendingTextEdit.elementID == id else {
        throw SceneEditingError.noActiveGesture
      }

      let result = try editor.updateGesture(with: .setText(elementID: id, text: text))
      guard result == .applied else { return }

      if !pendingTextEdit.didMarkDocumentChanged {
        pendingTextEdit.didMarkDocumentChanged = true
        self.pendingTextEdit = pendingTextEdit
        didChange(.done)
      }

      notifyModelChange(notification: .skip)
    }

    func endTextEdit() throws {
      guard let pendingTextEdit else { return }

      let result = try editor.endGesture()
      self.pendingTextEdit = nil

      guard result == .applied else {
        if pendingTextEdit.didMarkDocumentChanged {
          didChange(.undone)
        }
        return
      }

      if !pendingTextEdit.didMarkDocumentChanged {
        didChange(.done)
      }
      registerUndo(actionName: EditorActionName.editText)
    }

    func checkpointTextEdit(on id: ElementID) throws {
      guard let pendingTextEdit, pendingTextEdit.elementID == id else {
        throw SceneEditingError.noActiveGesture
      }

      let result = try editor.endGesture()
      self.pendingTextEdit = nil

      switch result {
      case .applied:
        if !pendingTextEdit.didMarkDocumentChanged {
          didChange(.done)
        }
        registerUndo(actionName: EditorActionName.editText)
      case .noChange:
        if pendingTextEdit.didMarkDocumentChanged {
          didChange(.undone)
        }
      }

      try editor.beginGesture(named: EditorActionName.editText)
      self.pendingTextEdit = PendingTextEdit(elementID: id)
    }

    func cancelTextEdit() {
      guard let pendingTextEdit else { return }

      let result = try? editor.cancelGesture()
      self.pendingTextEdit = nil

      if pendingTextEdit.didMarkDocumentChanged {
        didChange(.undone)
      }
      guard result == .applied else { return }

      notifyModelChange(notification: .skip)
    }

    func setRoutingStyle(_ style: ConnectorRoutingStyle, on id: ElementID) throws {
      try perform(
        name: "Change Connector Route",
        command: .setConnectorRouting(elementID: id, style: style, manualRoute: nil)
      )
    }

    func setMagnetConfiguration(_ configuration: MagnetConfiguration, on id: ElementID) throws {
      try perform(
        name: "Change Magnets",
        command: .setMagnetConfiguration(elementID: id, configuration: configuration)
      )
    }

    func setFillColor(_ color: SionColor, on id: ElementID) throws {
      guard var element = editor.document.scene.element(withID: id) else { return }

      element.style.fill = .solid(color)
      try perform(name: "Change Fill", command: .setStyle(elementID: id, style: element.style))
    }

    func setStrokeColor(_ color: SionColor, on id: ElementID) throws {
      guard var element = editor.document.scene.element(withID: id) else { return }

      if var stroke = element.style.stroke {
        stroke.color = color
        element.style.stroke = stroke
      } else {
        element.style.stroke = StrokeStyle(color: color, width: EditorDefaults.strokeWidth)
      }
      try perform(name: "Change Stroke", command: .setStyle(elementID: id, style: element.style))
    }

    func setStrokeWidth(_ width: Double, on id: ElementID) throws {
      guard width >= 0,
        var element = editor.document.scene.element(withID: id)
      else {
        return
      }

      if var stroke = element.style.stroke {
        stroke.width = width
        element.style.stroke = width == 0 ? nil : stroke
      } else if width > 0 {
        element.style.stroke = StrokeStyle(color: .primaryInk, width: width)
      }
      try perform(name: "Change Stroke", command: .setStyle(elementID: id, style: element.style))
    }

    func restoreRevision(identifier: String) throws {
      guard let revision = history.revisions.first(where: { $0.identifier == identifier }) else {
        return
      }

      let restored = try SionArchive.document(from: revision, assets: assets)
      let transaction = SceneTransaction(
        name: "Restore Revision",
        command: .replaceScene(restored.scene)
      )
      let result = try editor.perform(transaction)
      guard result == .applied else { return }

      pruneSelection()
      registerUndo(actionName: transaction.name)
      notifyModelChange(notification: .done)
    }

    func deleteSelection() throws {
      guard !selection.isEmpty else { return }

      let removed = selection
      try perform(name: "Delete", command: .remove(elementIDs: removed))
      selection.removeAll()
      notifySelectionChange(from: removed)
    }

    func beginMove() throws {
      guard canMoveSelection else { return }

      try editor.beginGesture(named: "Move")
    }

    func moveSelection(by offset: SionVector) throws {
      guard !selection.isEmpty, offset != .zero else { return }

      _ = try editor.updateGesture(with: .translate(elementIDs: selection, by: offset))
      notifyModelChange(notification: .skip)
    }

    func endMove() throws {
      let result = try editor.endGesture()
      guard result == .applied else { return }

      registerUndo(actionName: "Move")
      notifyModelChange(notification: .done)
    }

    func beginResize() throws {
      guard selectedElement != nil else { return }

      try beginTransform(.resize)
    }

    func resize(_ id: ElementID, to frame: SionRect) throws {
      _ = try editor.updateGesture(with: .setFrame(elementID: id, frame: frame))
      notifyModelChange(notification: .skip)
    }

    func endResize() throws {
      try endTransform(.resize)
    }

    func beginRotation() throws {
      guard selectedElement != nil else { return }

      try beginTransform(.rotate)
    }

    func rotate(_ id: ElementID, to radians: Double) throws {
      _ = try editor.updateGesture(
        with: .setRotation(elementID: id, radians: radians)
      )
      notifyModelChange(notification: .skip)
    }

    func endRotation() throws {
      try endTransform(.rotate)
    }

    func beginCornerRadiusChange() throws {
      guard selectedElement != nil else { return }

      try beginTransform(.cornerRadius)
    }

    func setCornerRadius(_ radius: Double, on id: ElementID) throws {
      _ = try editor.updateGesture(
        with: .setShapeKind(
          elementID: id,
          kind: .roundedRectangle(radius: max(0, radius))
        )
      )
      notifyModelChange(notification: .skip)
    }

    func endCornerRadiusChange() throws {
      try endTransform(.cornerRadius)
    }

    private func beginTransform(_ transform: ElementTransform) throws {
      try editor.beginGesture(named: transform.actionName)
    }

    private func endTransform(_ transform: ElementTransform) throws {
      let result = try editor.endGesture()
      guard result == .applied else { return }

      registerUndo(actionName: transform.actionName)
      notifyModelChange(notification: .done)
    }

    func cancelMove() {
      guard (try? editor.cancelGesture()) == .applied else { return }

      notifyModelChange(notification: .skip)
    }

    func element(at point: SionPoint) -> SceneElement? {
      for element in editor.document.scene.elements.reversed() {
        guard element.visibility == .visible else { continue }

        if element.content.connector != nil {
          if let route = connectorRoute(for: element),
            route.polylineSegments.contains(where: {
              distance(from: point, to: $0) <= EditorDefaults.connectorHitTolerance
            })
          {
            return element
          }
          continue
        }

        let frame = element.geometry.frame.standardized
        let localPoint = InteractionGeometry.unrotated(
          point,
          around: frame.center,
          by: element.geometry.rotationRadians
        )
        if frame.expanded(by: EditorDefaults.elementHitSlop).contains(localPoint) {
          return element
        }
      }

      return nil
    }

    func connectableElement(at point: SionPoint) -> SceneElement? {
      editor.document.scene.elements.reversed().first { element in
        guard element.visibility == .visible, element.content.connector == nil else {
          return false
        }

        let frame = element.geometry.frame.standardized
        let localPoint = InteractionGeometry.unrotated(
          point,
          around: frame.center,
          by: element.geometry.rotationRadians
        )
        return frame.expanded(by: EditorDefaults.elementHitSlop).contains(localPoint)
      }
    }

    @objc func undoSceneEdit() {
      guard let actionName = editor.undo() else { return }

      undoManagerProvider()?.registerUndo(withTarget: self) { target in
        Self.performUndo(.redo, on: target)
      }
      undoManagerProvider()?.setActionName(actionName)
      pruneSelection()
      notifyModelChange(notification: .undone)
    }

    @objc func redoSceneEdit() {
      guard let actionName = editor.redo() else { return }

      undoManagerProvider()?.registerUndo(withTarget: self) { target in
        Self.performUndo(.undo, on: target)
      }
      undoManagerProvider()?.setActionName(actionName)
      pruneSelection()
      notifyModelChange(notification: .redone)
    }

    private func perform(name: String, command: SceneCommand) throws {
      let result = try editor.perform(SceneTransaction(name: name, command: command))
      guard result == .applied else { return }

      registerUndo(actionName: name)
      notifyModelChange(notification: .done)
    }

    private func registerUndo(actionName: String) {
      guard let undoManager = undoManagerProvider() else { return }

      undoManager.registerUndo(withTarget: self) { target in
        Self.performUndo(.undo, on: target)
      }
      undoManager.setActionName(actionName)
    }

    private nonisolated static func performUndo(
      _ direction: UndoDirection,
      on target: SionEditorController
    ) {
      // NSUndoManager invokes registrations on the main responder thread.
      MainActor.assumeIsolated {
        switch direction {
        case .undo:
          target.undoSceneEdit()
        case .redo:
          target.redoSceneEdit()
        }
      }
    }

    private func notifyModelChange(notification: DocumentChangeNotification) {
      // Every notification reaching this funnel mutates the document, so the
      // rendered preview and cached routes are stale. Selection-only changes
      // notify observers directly and keep both caches.
      previewPNG = nil
      routeCache.removeAll()

      switch notification {
      case .done:
        didChange(.done)
      case .undone:
        didChange(.undone)
      case .redone:
        didChange(.redone)
      case .skip:
        break
      }
      notifyObservers()
    }

    private func notifySelectionChange(from previous: Set<ElementID>) {
      guard selection != previous else { return }

      anchorEditingState = .inactive
      notifyObservers()
    }

    private func notifyObservers() {
      for observer in observers.values {
        observer()
      }
    }

    private func pruneSelection() {
      let existing = Set(editor.document.scene.elements.map(\.id))
      selection.formIntersection(existing)

      guard let editedID = anchorEditingState.elementID,
        selection.contains(editedID),
        let element = editor.document.scene.element(withID: editedID),
        element.lockState == .editable,
        element.content.connector == nil
      else {
        anchorEditingState = .inactive
        return
      }
    }

    private func customAnchor(
      for element: SceneElement,
      at localPoint: SionPoint,
      in frame: SionRect
    ) -> Magnet {
      let placement = anchorPlacement(for: element, at: localPoint, in: frame)
      let normalizedPosition = SionPoint(
        x: (placement.point.x - frame.minX) / frame.width,
        y: (placement.point.y - frame.minY) / frame.height
      )

      return Magnet(
        id: MagnetID(
          "\(EditorDefaults.customAnchorIDPrefix)\(UUID().uuidString.lowercased())"
        ),
        normalizedPosition: normalizedPosition,
        outwardDirection: placement.outwardDirection
      )
    }

    private func anchorPlacement(
      for element: SceneElement,
      at point: SionPoint,
      in frame: SionRect
    ) -> AnchorPlacement {
      if case .shape(let content) = element.content {
        switch content.kind {
        case .rectangle, .roundedRectangle:
          let edge = RectangleAnchorEdge.nearest(to: point, in: frame)
          return AnchorPlacement(
            point: edge.project(point, onto: frame),
            outwardDirection: edge.outwardDirection
          )
        case .ellipse, .diamond, .triangle, .hexagon, .capsule, .cylinder, .custom:
          break
        }
      }

      let clampedPoint = SionPoint(
        x: min(frame.maxX, max(frame.minX, point.x)),
        y: min(frame.maxY, max(frame.minY, point.y))
      )
      let radialDirection = clampedPoint - frame.center
      return AnchorPlacement(
        point: clampedPoint,
        outwardDirection: radialDirection == .zero ? .north : radialDirection
      )
    }

    private func endpoint(
      elementID: ElementID?,
      point: SionPoint,
      use: MagnetUse
    ) -> ConnectionEndpoint {
      guard let elementID else { return .free(point) }
      let element = editor.document.scene.element(withID: elementID)

      return ConnectorAttachmentResolver.endpoint(
        attachingTo: element,
        at: point,
        use: use,
        magnetSnapDistance: EditorDefaults.connectorMagnetSnapTolerance
      )
    }

    private func mergeAssets(_ incomingAssets: [AssetID: SionAsset]) throws -> Set<AssetID> {
      var insertedIDs = Set<AssetID>()

      for id in incomingAssets.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let incoming = incomingAssets[id] else { continue }

        if let existing = assets[id] {
          guard existing.data == incoming.data else {
            removeAssets(insertedIDs)
            throw EditorTransferError.assetCollision(id)
          }
          continue
        }

        assets[id] = incoming
        insertedIDs.insert(id)
      }

      return insertedIDs
    }

    private func removeAssets(_ ids: Set<AssetID>) {
      for id in ids {
        assets[id] = nil
        imageCache.removeObject(forKey: NSString(string: id.rawValue))
      }
    }

    private func fittedImageSize(_ pixelSize: SionSize?) -> SionSize {
      guard let pixelSize, pixelSize.width > 0, pixelSize.height > 0 else {
        return EditorDefaults.imageSize
      }

      guard pixelSize.isFinite else { return EditorDefaults.imageSize }

      let scale = min(
        1,
        EditorDefaults.maximumImageDimension / max(pixelSize.width, pixelSize.height)
      )
      return SionSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    private func distance(from point: SionPoint, to segment: SionLineSegment) -> Double {
      let vector = segment.end - segment.start
      let lengthSquared = vector.lengthSquared
      guard lengthSquared > 0 else { return point.distance(to: segment.start) }

      let projected = (point - segment.start).dot(vector) / lengthSquared
      let fraction = min(1, max(0, projected))
      let nearest = segment.start + (vector * fraction)
      return point.distance(to: nearest)
    }

  }

  private enum EditorDefaults {
    static let imageSize = SionSize(width: 240, height: 180)
    static let maximumImageDimension = 480.0
    static let strokeWidth = 1.5
    static let connectorHitTolerance = 6.0
    static let connectorMagnetSnapTolerance = 10.0
    static let elementHitSlop = 2.0
    static let customAnchorIDPrefix = "custom-"
    static let imageCacheLimit = 256
    static let imageCacheTotalCostLimit = 128 * 1024 * 1024
  }

  private struct AnchorPlacement {
    let point: SionPoint
    let outwardDirection: SionVector
  }

  private enum RectangleAnchorEdge: CaseIterable {
    case north
    case east
    case south
    case west

    static func nearest(to point: SionPoint, in frame: SionRect) -> RectangleAnchorEdge {
      allCases.min {
        $0.distance(to: point, in: frame) < $1.distance(to: point, in: frame)
      } ?? .north
    }

    var outwardDirection: SionVector {
      switch self {
      case .north: .north
      case .east: .east
      case .south: .south
      case .west: .west
      }
    }

    func distance(to point: SionPoint, in frame: SionRect) -> Double {
      switch self {
      case .north: abs(point.y - frame.minY)
      case .east: abs(frame.maxX - point.x)
      case .south: abs(frame.maxY - point.y)
      case .west: abs(point.x - frame.minX)
      }
    }

    func project(_ point: SionPoint, onto frame: SionRect) -> SionPoint {
      switch self {
      case .north:
        SionPoint(x: point.x, y: frame.minY)
      case .east:
        SionPoint(x: frame.maxX, y: point.y)
      case .south:
        SionPoint(x: point.x, y: frame.maxY)
      case .west:
        SionPoint(x: frame.minX, y: point.y)
      }
    }
  }

  private enum EditorActionName {
    static let editText = "Edit Text"
  }

  private struct PendingTextEdit {
    let elementID: ElementID
    var didMarkDocumentChanged = false
  }

  private enum DocumentChangeNotification {
    case done
    case undone
    case redone
    case skip
  }

  private enum UndoDirection {
    case undo
    case redo
  }

  private enum ElementTransform {
    case resize
    case rotate
    case cornerRadius

    var actionName: String {
      switch self {
      case .resize: "Resize"
      case .rotate: "Rotate"
      case .cornerRadius: "Change Corner Radius"
      }
    }
  }

  private enum EditorTransferError: Error {
    case assetCollision(AssetID)
  }
#endif
