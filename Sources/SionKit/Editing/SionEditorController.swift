#if canImport(AppKit)
  import AppKit
  import SionCore

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

    enum Tool: Int, CaseIterable {
      case select
      case shape
      case text
      case connector
      case magnets

      var title: String {
        switch self {
        case .select: "Select"
        case .shape: "Shape"
        case .text: "Text"
        case .connector: "Connector"
        case .magnets: "Connection Points"
        }
      }

      var symbolName: String {
        switch self {
        case .select: "arrow.up.left"
        case .shape: "square.on.circle"
        case .text: "textformat"
        case .connector: "point.topleft.down.to.point.bottomright.curvepath"
        case .magnets: "scope"
        }
      }
    }

    private(set) var selection = Set<ElementID>()
    private(set) var tool = Tool.select
    private var editor: SceneEditor
    private var assets: [AssetID: SionAsset]
    private var history: DocumentHistory
    private var previewPNG: Data?

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
      selection.removeAll()
      undoManagerProvider()?.removeAllActions(withTarget: self)
      notifyObservers()
    }

    func asset(for id: AssetID) -> SionAsset? {
      assets[id]
    }

    func connectorRoute(for element: SceneElement) -> ConnectorRoute? {
      SceneRenderGeometry.connectorRoute(for: element, in: editor.document.scene)
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
      var scene = editor.document.scene
      scene.elements.append(preview)
      return SceneRenderGeometry.connectorRoute(for: preview, in: scene)
    }

    func contentBounds() -> SionRect {
      SceneRenderGeometry.contentBounds(of: editor.document.scene)
    }

    func magnetPoints(for element: SceneElement) -> [SionPoint] {
      element.resolvedMagnets.map(\.endpoint.point)
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
      notifyObservers()
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
        kind: .roundedRectangle(radius: EditorDefaults.cornerRadius)
      )
    }

    @discardableResult
    func insertShape(at point: SionPoint, kind: ShapeKind) throws -> ElementID {
      let size = EditorDefaults.shapeSize
      let frame = SionRect(
        x: point.x - (size.width / 2),
        y: point.y - (size.height / 2),
        width: size.width,
        height: size.height
      )
      let element = SceneElement.shape(frame: frame, kind: kind)

      try perform(name: "Add Shape", command: .insert(elements: [element], at: nil))
      select(element.id)
      return element.id
    }

    @discardableResult
    func insertText(_ text: String, at point: SionPoint) throws -> ElementID {
      let frame = SionRect(
        x: point.x - (EditorDefaults.textSize.width / 2),
        y: point.y - (EditorDefaults.textSize.height / 2),
        width: EditorDefaults.textSize.width,
        height: EditorDefaults.textSize.height
      )
      let element = SceneElement.text(frame: frame, text: text)

      try perform(name: "Add Text", command: .insert(elements: [element], at: nil))
      select(element.id)
      return element.id
    }

    @discardableResult
    func insertImage(
      data: Data,
      mediaType: String,
      fileExtension: String,
      filename: String?,
      pixelSize: SionSize?,
      at point: SionPoint
    ) throws -> ElementID {
      let asset = try SionAsset(
        data: data,
        mediaType: mediaType,
        fileExtension: fileExtension,
        originalFilename: filename,
        pixelSize: pixelSize
      )
      let size = fittedImageSize(pixelSize)
      let frame = SionRect(
        x: point.x - (size.width / 2),
        y: point.y - (size.height / 2),
        width: size.width,
        height: size.height
      )
      let element = SceneElement.image(frame: frame, assetID: asset.id)

      assets[asset.id] = asset
      do {
        try perform(name: "Add Image", command: .insert(elements: [element], at: nil))
      } catch {
        if !SionPackage.referencedAssetIDs(in: editor.document).contains(asset.id) {
          assets[asset.id] = nil
        }
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
        _ = try insertText(source, at: point)
        return Array(selection)
      }

      try perform(name: "Paste Mermaid", command: .insert(elements: elements, at: nil))
      selection = Set(elements.map(\.id))
      notifyObservers()
      return elements.map(\.id)
    }

    func setText(_ text: String, on id: ElementID) throws {
      try perform(name: "Edit Text", command: .setText(elementID: id, text: text))
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

    func toggleMagnet(at point: SionPoint, on id: ElementID, hitTolerance: Double) throws {
      guard let element = editor.document.scene.element(withID: id),
        element.lockState == .editable,
        element.content.connector == nil
      else {
        return
      }

      let frame = element.geometry.frame.standardized
      guard frame.width > 0, frame.height > 0 else { return }

      var magnets = element.expandedMagnets
      let resolvedMagnets = element.resolvedMagnets
      let nearest = resolvedMagnets.enumerated().min { first, second in
        point.distance(to: first.element.endpoint.point)
          < point.distance(to: second.element.endpoint.point)
      }

      if let nearest,
        point.distance(to: nearest.element.endpoint.point)
          <= max(0, hitTolerance)
      {
        magnets.remove(at: nearest.offset)
      } else {
        guard magnets.count < SceneLimits.maximumMagnetsPerElement else { return }

        let localPoint = unrotated(
          point, around: frame.center, radians: element.geometry.rotationRadians)
        let normalizedPosition = SionPoint(
          x: min(1, max(0, (localPoint.x - frame.minX) / frame.width)),
          y: min(1, max(0, (localPoint.y - frame.minY) / frame.height))
        )
        let radialDirection = normalizedPosition - SionPoint(x: 0.5, y: 0.5)
        let outwardDirection = radialDirection == .zero ? SionVector.north : radialDirection
        magnets.append(
          Magnet(
            id: MagnetID("\(EditorDefaults.customMagnetIDPrefix)\(UUID().uuidString.lowercased())"),
            normalizedPosition: normalizedPosition,
            outwardDirection: outwardDirection
          )
        )
      }

      try setMagnetConfiguration(.custom(magnets), on: id)
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
      notifyObservers()
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

      try editor.beginGesture(named: "Resize")
    }

    func resize(_ id: ElementID, to frame: SionRect) throws {
      _ = try editor.updateGesture(with: .setFrame(elementID: id, frame: frame))
      notifyModelChange(notification: .skip)
    }

    func endResize() throws {
      let result = try editor.endGesture()
      guard result == .applied else { return }

      registerUndo(actionName: "Resize")
      notifyModelChange(notification: .done)
    }

    func cancelMove() {
      guard (try? editor.cancelGesture()) == .applied else { return }

      notifyModelChange(notification: .skip)
    }

    func element(at point: SionPoint) -> SceneElement? {
      for element in editor.document.scene.elements.reversed() {
        guard element.visibility == .visible else { continue }

        if let route = SceneRenderGeometry.connectorRoute(
          for: element,
          in: editor.document.scene
        ) {
          if route.polylineSegments.contains(where: {
            distance(from: point, to: $0) <= EditorDefaults.connectorHitTolerance
          }) {
            return element
          }
          continue
        }

        if element.geometry.frame.expanded(by: EditorDefaults.elementHitSlop).contains(point) {
          return element
        }
      }

      return nil
    }

    func connectableElement(at point: SionPoint) -> SceneElement? {
      editor.document.scene.elements.reversed().first { element in
        element.visibility == .visible
          && element.content.connector == nil
          && element.geometry.frame.expanded(by: EditorDefaults.elementHitSlop).contains(point)
      }
    }

    @objc func undoSceneEdit() {
      guard let actionName = editor.undo() else { return }

      undoManagerProvider()?.registerUndo(withTarget: self) { target in
        target.redoSceneEdit()
      }
      undoManagerProvider()?.setActionName(actionName)
      pruneSelection()
      notifyModelChange(notification: .undone)
    }

    @objc func redoSceneEdit() {
      guard let actionName = editor.redo() else { return }

      undoManagerProvider()?.registerUndo(withTarget: self) { target in
        target.undoSceneEdit()
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
        target.undoSceneEdit()
      }
      undoManager.setActionName(actionName)
    }

    private func notifyModelChange(notification: DocumentChangeNotification) {
      // Any edit invalidates the archive's optional rendered preview.
      previewPNG = nil

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
    }

    private func endpoint(
      elementID: ElementID?,
      point: SionPoint,
      use: MagnetUse
    ) -> ConnectionEndpoint {
      guard let elementID else { return .free(point) }

      if let element = editor.document.scene.element(withID: elementID),
        let nearest = element.resolvedMagnets
          .filter({ $0.magnet.connectionDirection.allows(use) })
          .min(by: {
            point.distance(to: $0.endpoint.point) < point.distance(to: $1.endpoint.point)
          }),
        point.distance(to: nearest.endpoint.point) <= EditorDefaults.connectorMagnetSnapTolerance
      {
        return .element(
          elementID,
          attachment: .magnet(nearest.magnet.id),
          fallbackPoint: nearest.endpoint.point
        )
      }

      return .element(elementID, attachment: .automatic, fallbackPoint: point)
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

    private func unrotated(
      _ point: SionPoint,
      around center: SionPoint,
      radians: Double
    ) -> SionPoint {
      guard radians.isFinite, radians != 0 else { return point }

      let cosine = cos(-radians)
      let sine = sin(-radians)
      let offset = point - center
      return SionPoint(
        x: center.x + (offset.dx * cosine) - (offset.dy * sine),
        y: center.y + (offset.dx * sine) + (offset.dy * cosine)
      )
    }
  }

  private enum EditorDefaults {
    static let cornerRadius = 12.0
    static let shapeSize = SionSize(width: 160, height: 96)
    static let textSize = SionSize(width: 220, height: 56)
    static let imageSize = SionSize(width: 240, height: 180)
    static let maximumImageDimension = 480.0
    static let strokeWidth = 1.5
    static let connectorHitTolerance = 6.0
    static let connectorMagnetSnapTolerance = 10.0
    static let elementHitSlop = 2.0
    static let customMagnetIDPrefix = "custom-"
  }

  private enum DocumentChangeNotification {
    case done
    case undone
    case redone
    case skip
  }

  private enum EditorTransferError: Error {
    case assetCollision(AssetID)
  }
#endif
