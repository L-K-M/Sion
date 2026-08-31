#if canImport(AppKit)
  import AppKit
  import SionCore

  /// The editable area an infinite canvas always offers.
  enum SionCanvasDefaults {
    static let minimumInfiniteSize = SionSize(width: 4_000, height: 3_000)
  }

  extension ElementContent {
    /// A group paints nothing of its own, so it casts no shadow either. The
    /// editing commands enforce this, not just the controls that expose it.
    var supportsShadow: Bool {
      switch self {
      case .shape, .path, .text, .image, .connector: true
      case .group: false
      }
    }
  }

  /// The drop shadow a newly enabled shadow starts from, and the range the
  /// inspector offers for it.
  enum SionShadowDefaults {
    static let style = ShadowStyle(
      color: SionColor(red: 0, green: 0, blue: 0, alpha: 0.35),
      offset: SionVector(dx: 0, dy: 2),
      blurRadius: 6
    )
    static let minimumBlurRadius = 0.0
    static let maximumBlurRadius = 40.0
  }

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

    enum ConnectorInsertionError: LocalizedError, Equatable {
      case selfLoopNotSupported(ElementID)

      var errorDescription: String? {
        switch self {
        case .selfLoopNotSupported:
          "Connectors cannot start and end on the same element."
        }
      }
    }

    private enum RenderContextChange {
      case rebuild
      case update(Set<ElementID>)
      case unchanged
    }

    enum MermaidInsertionResult: Equatable {
      case diagram(elementIDs: [ElementID])
      case sourceText(elementID: ElementID, omissions: [MermaidImportOmission])
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
        case .rectangle: "Rounded Rectangle"
        case .circle: "Circle"
        case .text: "Text"
        case .connector: "Connector"
        }
      }

      var symbolName: String {
        switch self {
        case .select: "arrow.up.left"
        case .rectangle: "rectangle.rounded"
        case .circle: "circle"
        case .text: "textformat"
        case .connector: "point.topleft.down.to.point.bottomright.curvepath"
        }
      }

      var help: String {
        switch self {
        case .select: "Select and transform objects"
        case .rectangle: "Click or drag to create a rounded rectangle"
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

    /// How long a chosen tool stays active. One click arms a single use; a
    /// double click keeps the tool until another one is chosen.
    enum ToolPersistence: Equatable {
      case oneShot
      case sticky

      /// Shown in the toolbar tooltip and spoken as the control's value, so the
      /// mode stays discoverable without custom drawing.
      var summary: String {
        switch self {
        case .oneShot: "Reverts to Select after one use"
        case .sticky: "Stays active until another tool is chosen"
        }
      }
    }

    private(set) var selection = Set<ElementID>()
    private(set) var tool = Tool.select
    private(set) var toolPersistence = ToolPersistence.sticky
    private(set) var anchorEditingState = AnchorEditingState.inactive
    private var editor: SceneEditor
    private var assets: [AssetID: SionAsset]
    private var history: DocumentHistory
    private var previewPNG: Data?
    private var pendingTextEdit: PendingTextEdit?
    private var lastDuplicate: DuplicateState?
    private var pendingDuplicateMove: SionVector?
    private var renderContext: SceneRenderContext
    private let imageCache: NSCache<NSString, NSImage>

    private let renderContextBuilder: (SionScene) -> SceneRenderContext
    private let undoManagerProvider: () -> UndoManager?
    private let didChange: (DocumentChange) -> Void
    private var observers: [UUID: () -> Void] = [:]

    init(
      package: SionPackage,
      undoManagerProvider: @escaping () -> UndoManager?,
      didChange: @escaping (DocumentChange) -> Void,
      renderContextBuilder: @escaping (SionScene) -> SceneRenderContext = {
        SceneRenderContext(scene: $0)
      }
    ) throws {
      editor = try SceneEditor(document: package.document)
      assets = package.assets
      history = package.history
      previewPNG = package.previewPNG
      pendingTextEdit = nil
      pendingDuplicateMove = nil
      renderContext = renderContextBuilder(editor.document.scene)
      imageCache = NSCache()
      imageCache.countLimit = EditorDefaults.imageCacheLimit
      imageCache.totalCostLimit = EditorDefaults.imageCacheTotalCostLimit
      self.renderContextBuilder = renderContextBuilder
      self.undoManagerProvider = undoManagerProvider
      self.didChange = didChange

      super.init()
    }

    var document: SionDocument { editor.document }
    var gridVisibility: GridVisibility { editor.document.scene.canvas.grid.visibility }

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
      return try insertPayload(payload, centeredAt: point, undoName: "Paste")
    }

    /// Copies the selection one grid pitch aside; a repeat after moving the
    /// copy re-applies that manual offset (power duplicate).
    @discardableResult
    func duplicateSelection() throws -> [ElementID] {
      guard !selection.isEmpty else { return [] }

      endAnchorEditing()
      let payload = try SceneSelectionPayload(
        package: packageForArchiving(),
        selectedElementIDs: selection
      )
      let center = payload.contentBounds.center
      let delta = duplicateDelta()
      let insertedIDs = try insertPayload(
        payload,
        centeredAt: center + delta,
        undoName: "Duplicate"
      )

      guard !insertedIDs.isEmpty else {
        lastDuplicate = nil
        return []
      }

      lastDuplicate = DuplicateState(
        ids: Set(insertedIDs),
        delta: delta
      )
      return insertedIDs
    }

    func alignSelection(_ edge: SceneAlignmentEdge) throws {
      let targets = arrangeableSelection()
      guard targets.count > 1 else { return }

      endAnchorEditing()
      // Match the visible rotation, stroke, and shadows instead of raw frames.
      let offsets = SceneArrangement.alignedOffsets(
        targets.map { SceneRenderGeometry.paintedBounds(of: $0) },
        edge: edge
      )
      let commands = zip(targets, offsets).map { element, offset in
        SceneCommand.translate(elementIDs: [element.id], by: offset)
      }
      try perform(name: "Align", commands: commands)
    }

    func distributeSelection(_ axis: SceneDistributionAxis) throws {
      let targets = arrangeableSelection()
      guard targets.count > 2 else { return }

      endAnchorEditing()
      let offsets = SceneArrangement.distributedOffsets(
        targets.map { SceneRenderGeometry.paintedBounds(of: $0) },
        axis: axis
      )
      let commands = zip(targets, offsets).map { element, offset in
        SceneCommand.translate(elementIDs: [element.id], by: offset)
      }
      try perform(name: "Distribute", commands: commands)
    }

    /// Reorders eligible elements as one block in retained scene order.
    func moveSelectionInZOrder(_ movement: ZOrderMovement) throws {
      guard let plan = zOrderPlan(for: movement) else { return }

      endAnchorEditing()
      try perform(
        name: movement.actionName,
        command: .reorder(
          elementIDs: plan.orderedIDs,
          destinationIndex: plan.destinationIndex
        )
      )
    }

    func setSelectionLockState(_ lockState: ElementLockState) throws {
      let targets = lockStateTargets(for: lockState)
      guard !targets.isEmpty else { return }

      endAnchorEditing()
      let commands = targets.map { element in
        SceneCommand.setLockState(elementID: element.id, lockState: lockState)
      }
      try perform(name: lockState.undoActionName, commands: commands)
    }

    var canRenameSelection: Bool {
      !selectedElements.isEmpty
        && selectedElements.allSatisfy { $0.lockState == .editable }
    }

    /// One name edit applies atomically across the current selection.
    func renameSelection(_ name: String?) throws {
      guard canRenameSelection else { return }
      let elements = selectedElements

      let commands = elements.compactMap { element -> SceneCommand? in
        guard element.name != name else { return nil }

        return .rename(elementID: element.id, name: name)
      }
      guard !commands.isEmpty else { return }

      let actionName =
        elements.count == 1
        ? EditorActionName.renameElement
        : EditorActionName.renameElements
      try perform(name: actionName, commands: commands)
    }

    func hideSelection() throws {
      let hiddenIDs = hideTargets.map(\.id)
      guard !hiddenIDs.isEmpty else { return }

      endAnchorEditing()
      try perform(
        name: "Hide",
        commands: hiddenIDs.map {
          SceneCommand.setVisibility(elementID: $0, visibility: .hidden)
        }
      )
      selection.subtract(hiddenIDs)
      notifyObservers()
    }

    func revealHiddenElements() throws {
      let hidden = editor.document.scene.elements.filter { $0.visibility == .hidden }
      guard !hidden.isEmpty else { return }

      endAnchorEditing()
      try perform(
        name: "Reveal All",
        commands: hidden.flatMap(revealCommands)
      )
    }

    func toggleGridVisibility() throws {
      var canvas = editor.document.scene.canvas
      let actionName: String

      switch canvas.grid.visibility {
      case .hidden:
        canvas.grid.visibility = .visible
        actionName = EditorActionName.showGrid
      case .visible:
        canvas.grid.visibility = .hidden
        actionName = EditorActionName.hideGrid
      }

      try perform(name: actionName, command: .setCanvas(canvas))
    }

    var canDuplicateSelection: Bool {
      !selection.isEmpty
    }

    var canCopySelection: Bool {
      SceneSelectionPayload.assetsCouldFitEncodedByteBudget(
        package: packageForArchiving(),
        selectedElementIDs: selection,
        maximumByteCount: SionArchiveConstants.maximumEntryByteCount
      )
    }

    var canDeleteSelection: Bool {
      guard !editor.hasPendingGesture, !selection.isEmpty else { return false }

      var removedIDs = selection
      removedIDs.formUnion(editor.document.scene.descendantIDs(of: selection))

      return editor.document.scene.elements.allSatisfy { element in
        !removedIDs.contains(element.id) || element.lockState == .editable
      }
    }

    func canMoveSelectionInZOrder(_ movement: ZOrderMovement) -> Bool {
      zOrderPlan(for: movement) != nil
    }

    func canSetSelectionLockState(_ lockState: ElementLockState) -> Bool {
      !lockStateTargets(for: lockState).isEmpty
    }

    var canHideSelection: Bool {
      !hideTargets.isEmpty
    }

    var canRevealHiddenElements: Bool {
      editor.document.scene.elements.contains { $0.visibility == .hidden }
    }

    /// Group records and their selected subtrees stay untouched until
    /// hierarchy-wide Arrange semantics are defined.
    private var selectedIndependentElements: [SceneElement] {
      let parentByChildID: [ElementID: ElementID] = Dictionary(
        uniqueKeysWithValues: editor.document.scene.elements.compactMap { element in
          guard let parentID = element.parentID else { return nil }

          return (element.id, parentID)
        }
      )

      return selectedElements.filter { element in
        guard !element.content.isGroup else { return false }

        var ancestorID = element.parentID
        while let currentID = ancestorID {
          if selection.contains(currentID) { return false }
          ancestorID = parentByChildID[currentID]
        }

        return true
      }
    }

    private func arrangeableSelection() -> [SceneElement] {
      selectedIndependentElements.filter {
        $0.visibility == .visible && $0.lockState == .editable && $0.content.connector == nil
      }
    }

    var arrangeableSelectionCount: Int {
      arrangeableSelection().count
    }

    private var zOrderTargets: [SceneElement] {
      selectedIndependentElements.filter {
        $0.visibility == .visible && $0.lockState == .editable
      }
    }

    private func lockStateTargets(for lockState: ElementLockState) -> [SceneElement] {
      selectedIndependentElements.filter { $0.lockState != lockState }
    }

    private var hideTargets: [SceneElement] {
      selectedIndependentElements.filter {
        $0.visibility == .visible && $0.lockState == .editable
      }
    }

    /// Locked elements briefly become editable inside one atomic transaction,
    /// then return to their original lock state after becoming visible.
    private func revealCommands(for element: SceneElement) -> [SceneCommand] {
      let reveal = SceneCommand.setVisibility(elementID: element.id, visibility: .visible)
      guard element.lockState == .locked else { return [reveal] }

      return [
        .setLockState(elementID: element.id, lockState: .editable),
        reveal,
        .setLockState(elementID: element.id, lockState: .locked),
      ]
    }

    private func zOrderPlan(for movement: ZOrderMovement) -> ZOrderPlan? {
      let elements = editor.document.scene.elements
      let elementIDs = elements.map(\.id)
      let movedIDSet = Set(zOrderTargets.map(\.id))
      let orderedIDs = elementIDs.filter(movedIDSet.contains)
      guard !orderedIDs.isEmpty else { return nil }

      let retainedIDs = elementIDs.filter { !movedIDSet.contains($0) }
      let destination: Int
      switch movement {
      case .front:
        destination = retainedIDs.endIndex
      case .back:
        destination = retainedIDs.startIndex
      case .forward:
        guard let topmost = elements.lastIndex(where: { movedIDSet.contains($0.id) }) else {
          return nil
        }

        let retainedBelow = elements[..<topmost].count {
          !movedIDSet.contains($0.id)
        }
        destination = min(retainedBelow + 1, retainedIDs.endIndex)
      case .backward:
        guard let bottommost = elements.firstIndex(where: { movedIDSet.contains($0.id) }) else {
          return nil
        }

        let retainedBelow = elements[..<bottommost].count {
          !movedIDSet.contains($0.id)
        }
        destination = max(retainedBelow - 1, retainedIDs.startIndex)
      }

      var reorderedIDs = retainedIDs
      reorderedIDs.insert(contentsOf: orderedIDs, at: destination)
      guard reorderedIDs != elementIDs else { return nil }

      return ZOrderPlan(orderedIDs: orderedIDs, destinationIndex: destination)
    }

    @discardableResult
    private func insertPayload(
      _ payload: SceneSelectionPayload,
      centeredAt point: SionPoint,
      undoName: String
    ) throws -> [ElementID] {
      let occupiedIDs = Set(editor.document.scene.elements.map(\.id))
      let insertion = try payload.insertion(centeredAt: point, excluding: occupiedIDs)
      let insertedAssetIDs = try mergeAssets(insertion.assets)
      let transaction = SceneTransaction(
        name: undoName,
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

    private func duplicateDelta() -> SionVector {
      if let lastDuplicate, selection == lastDuplicate.ids {
        let movement = lastDuplicate.manualTranslation
        // Ignore sub-pixel drift and preserve the established repeat spacing.
        let stayedPut =
          abs(movement.dx) < EditorDefaults.duplicateMoveTolerance
          && abs(movement.dy) < EditorDefaults.duplicateMoveTolerance

        if !stayedPut {
          return movement
        }

        return lastDuplicate.delta
      }

      // Imported files can carry huge grid pitches; keep copies nearby.
      let step = min(
        EditorDefaults.duplicateStepMaximum,
        max(
          EditorDefaults.duplicateStepMinimum,
          editor.document.scene.canvas.grid.spacing
        )
      )
      return SionVector(dx: step, dy: step)
    }

    /// Only explicit translations influence power duplicate; resizes and
    /// rotations may shift bounds without representing user movement.
    private func recordDuplicateMovement(_ offset: SionVector) {
      guard offset != .zero,
        var lastDuplicate,
        selection == lastDuplicate.ids
      else {
        return
      }

      lastDuplicate.manualTranslation = lastDuplicate.manualTranslation + offset
      self.lastDuplicate = lastDuplicate
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

    /// The archive's recovery preview, rendered by the canvas on save.
    var hasPreviewPNG: Bool {
      previewPNG != nil
    }

    func setPreviewPNG(_ data: Data) {
      previewPNG = data
    }

    func load(_ package: SionPackage) throws {
      editor = try SceneEditor(document: package.document)
      assets = package.assets
      history = package.history
      previewPNG = package.previewPNG
      pendingTextEdit = nil
      lastDuplicate = nil
      pendingDuplicateMove = nil
      anchorEditingState = .inactive
      renderContext = renderContextBuilder(editor.document.scene)
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

      // Charge the cache by decoded pixels; compressed bytes understate
      // what a rendition actually retains.
      let decodedCost = image.representations.reduce(asset.data.count) {
        $0 + ($1.pixelsWide * $1.pixelsHigh * 4)
      }
      imageCache.setObject(image, forKey: key, cost: decodedCost)
      return image
    }

    func connectorRoute(for element: SceneElement) -> ConnectorRoute? {
      renderContext.connectorRoute(for: element)
    }

    func elementsForRendering(intersecting bounds: SionRect) -> [SceneElement] {
      renderContext.elements(
        intersecting: bounds,
        including: selection
      ).elements
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

    /// Where a command inserts when no viewport has resolved yet.
    var defaultInsertionCenter: SionPoint {
      editingCanvasBounds(minimumInfiniteSize: SionCanvasDefaults.minimumInfiniteSize).center
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
      SceneRenderGeometry.contentBounds(
        of: editor.document.scene,
        connectorRoutes: { [weak self] element in
          self?.connectorRoute(for: element) ?? nil
        }
      )
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

    /// `.select` is the resting tool and is always sticky. Re-sending the
    /// active tool with a different persistence upgrades it in place, so the
    /// second click of a double click is not swallowed; nothing but the mode
    /// changes then, which keeps an in-progress anchor edit alive.
    func setTool(_ newTool: Tool, persistence: ToolPersistence = .sticky) {
      let resolvedPersistence: ToolPersistence = newTool == .select ? .sticky : persistence
      let changesTool = tool != newTool
      guard changesTool || toolPersistence != resolvedPersistence else { return }

      tool = newTool
      toolPersistence = resolvedPersistence
      if changesTool {
        anchorEditingState = .inactive
      }
      notifyObservers()
    }

    /// A view reports one successful use of `completedTool`; an armed one-shot
    /// tool then hands the canvas back to `.select`. Failed, too-short, and
    /// cancelled creations must not call this.
    @discardableResult
    func toolDidComplete(_ completedTool: Tool) -> Bool {
      guard completedTool == tool, toolPersistence == .oneShot else { return false }

      setTool(.select)
      return true
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

    func select(_ ids: Set<ElementID>, mode: SelectionMode = .replace) {
      let previous = selection
      let existingIDs = Set(editor.document.scene.elements.map(\.id))
      let selectableIDs = ids.intersection(existingIDs)

      switch mode {
      case .replace:
        selection = selectableIDs
      case .extend:
        selection.formUnion(selectableIDs)
      }

      notifySelectionChange(from: previous)
    }

    /// IDs of visible, editable elements touched by a marquee rectangle:
    /// shapes by frame, connectors when their routed path crosses it.
    func elementIDsIntersecting(_ rect: SionRect) -> Set<ElementID> {
      var intersectingIDs = Set<ElementID>()

      for element in editor.document.scene.elements {
        guard element.visibility == .visible, element.lockState == .editable else { continue }

        if element.content.connector == nil {
          if element.geometry.frame.standardized.intersects(rect) {
            intersectingIDs.insert(element.id)
          }
          continue
        }

        guard let route = connectorRoute(for: element) else { continue }

        let crossesRect =
          route.polylinePoints.contains { rect.contains($0) }
          || route.polylineSegments.contains { $0.intersectsInterior(of: rect) }
        if crossesRect {
          intersectingIDs.insert(element.id)
        }
      }

      return intersectingIDs
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
      guard canMoveSelection, offset != .zero else { return }

      try perform(name: "Move", command: .translate(elementIDs: selection, by: offset))
      recordDuplicateMovement(offset)
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
    func insertText(
      _ text: String,
      in frame: SionRect,
      actionName: String = "Add Text"
    ) throws -> ElementID {
      let element = SceneElement.text(frame: frame.standardized, text: text)

      try perform(name: actionName, command: .insert(elements: [element], at: nil))
      select(element.id)
      return element.id
    }

    @discardableResult
    func insertText(
      _ text: String,
      centeredAt point: SionPoint,
      actionName: String = "Add Text"
    ) throws -> ElementID {
      let size = SionCreationDefaults.textSize
      let frame = SionRect(
        x: point.x - (size.width / 2),
        y: point.y - (size.height / 2),
        width: size.width,
        height: size.height
      )

      return try insertText(text, in: frame, actionName: actionName)
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

      // Automatic routing cannot produce a visible same-object route yet.
      if let sourceElementID = source.elementID,
        sourceElementID == target.elementID
      {
        throw ConnectorInsertionError.selfLoopNotSupported(sourceElementID)
      }

      let element = SceneElement.connector(source: source, target: target)

      try perform(name: "Add Connector", command: .insert(elements: [element], at: nil))
      select(element.id)
      return element.id
    }

    func insertMermaid(
      _ source: String,
      at point: SionPoint,
      actionName: String = "Paste Mermaid"
    ) throws -> MermaidInsertionResult {
      let report = MermaidImporter.importReport(from: source, centeredAt: point)
      guard report.omissions.isEmpty, !report.elements.isEmpty else {
        let elementID = try insertText(source, centeredAt: point, actionName: actionName)
        return .sourceText(elementID: elementID, omissions: report.omissions)
      }

      try perform(name: actionName, command: .insert(elements: report.elements, at: nil))
      let elementIDs = report.elements.map(\.id)
      selection = Set(elementIDs)
      notifyObservers()
      return .diagram(elementIDs: elementIDs)
    }

    func beginTextEdit(on id: ElementID) throws {
      guard pendingTextEdit == nil else {
        throw SceneEditingError.gestureAlreadyActive
      }

      try beginPendingTextEdit(on: id)
    }

    func updateTextEdit(_ text: String, on id: ElementID) throws {
      guard var pendingTextEdit, pendingTextEdit.elementID == id else {
        throw SceneEditingError.noActiveGesture
      }

      guard editableText(on: id) != text else { return }

      let result = try editor.updateGesture(with: .setText(elementID: id, text: text))
      guard result == .applied else { return }

      if !pendingTextEdit.didMarkDocumentChanged {
        pendingTextEdit.didMarkDocumentChanged = true
        self.pendingTextEdit = pendingTextEdit
        didChange(.done)
      }

      notifyModelChange(
        notification: .skip,
        renderContextChange: .update([id])
      )
    }

    func endTextEdit() throws {
      guard let pendingTextEdit else { return }

      if try cancelTextEditRestoredToBaseline(pendingTextEdit) {
        return
      }

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

      if try cancelTextEditRestoredToBaseline(pendingTextEdit) {
        try beginPendingTextEdit(on: id)
        return
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

      try beginPendingTextEdit(on: id)
    }

    func cancelTextEdit() {
      guard let pendingTextEdit else { return }

      let result = try? editor.cancelGesture()
      self.pendingTextEdit = nil

      if pendingTextEdit.didMarkDocumentChanged {
        didChange(.undone)
      }
      guard result == .applied else { return }

      notifyModelChange(
        notification: .skip,
        renderContextChange: .update([pendingTextEdit.elementID])
      )
    }

    private func beginPendingTextEdit(on id: ElementID) throws {
      guard let baselineText = editableText(on: id) else {
        throw SceneEditingError.elementDoesNotContainText(id)
      }

      try editor.beginGesture(named: EditorActionName.editText)
      pendingTextEdit = PendingTextEdit(
        elementID: id,
        baselineText: baselineText
      )
    }

    private func cancelTextEditRestoredToBaseline(
      _ pendingTextEdit: PendingTextEdit
    ) throws -> Bool {
      guard editableText(on: pendingTextEdit.elementID) == pendingTextEdit.baselineText else {
        return false
      }

      let result = try editor.cancelGesture()
      self.pendingTextEdit = nil
      if pendingTextEdit.didMarkDocumentChanged {
        didChange(.undone)
      }
      if result == .applied {
        notifyModelChange(
          notification: .skip,
          renderContextChange: .update([pendingTextEdit.elementID])
        )
      }

      return true
    }

    private func editableText(on id: ElementID) -> String? {
      guard let element = editor.document.scene.element(withID: id) else { return nil }

      switch element.content {
      case .shape(let shape):
        return shape.label?.string ?? ""
      case .text(let text):
        return text.string
      case .connector(let connector):
        return connector.label?.string ?? ""
      case .path, .image, .group:
        return nil
      }
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

    func setLockState(_ lockState: ElementLockState, on id: ElementID) throws {
      let actionName = lockState == .locked ? "Lock Element" : "Unlock Element"
      try perform(
        name: actionName,
        command: .setLockState(elementID: id, lockState: lockState)
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

    /// One drop shadow per element, which is what the inspector exposes and
    /// what canvas rendering reads. Content that does not take a shadow can
    /// still have one cleared: a document written elsewhere may carry a shadow
    /// this build would refuse to add, and refusing to remove it too would
    /// leave it on screen with nothing able to reach it.
    func setShadow(_ shadow: ShadowStyle?, on id: ElementID) throws {
      guard var element = editor.document.scene.element(withID: id),
        shadow == nil || element.content.supportsShadow
      else {
        return
      }

      let shadows = shadow.map { [$0] } ?? []
      guard element.style.shadows != shadows else { return }

      element.style.shadows = shadows
      try perform(name: "Change Shadow", command: .setStyle(elementID: id, style: element.style))
    }

    func setShadowEnabled(_ isEnabled: Bool, on id: ElementID) throws {
      guard let element = editor.document.scene.element(withID: id) else { return }

      guard isEnabled else {
        try setShadow(nil, on: id)
        return
      }

      try setShadow(element.style.shadows.first ?? SionShadowDefaults.style, on: id)
    }

    func setShadowColor(_ color: SionColor, on id: ElementID) throws {
      guard let element = editor.document.scene.element(withID: id) else { return }

      var shadow = element.style.shadows.first ?? SionShadowDefaults.style
      shadow.color = color
      try setShadow(shadow, on: id)
    }

    func setShadowBlurRadius(_ radius: Double, on id: ElementID) throws {
      guard radius >= 0, radius.isFinite,
        let element = editor.document.scene.element(withID: id)
      else {
        return
      }

      var shadow = element.style.shadows.first ?? SionShadowDefaults.style
      shadow.blurRadius = radius
      try setShadow(shadow, on: id)
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
      pendingDuplicateMove = nil
      guard canMoveSelection else { return }

      try editor.beginGesture(named: "Move")
      if let lastDuplicate, selection == lastDuplicate.ids {
        pendingDuplicateMove = .zero
      }
    }

    func moveSelection(by offset: SionVector) throws {
      guard !selection.isEmpty, offset != .zero else { return }

      let result = try editor.updateGesture(with: .translate(elementIDs: selection, by: offset))
      guard result == .applied else { return }

      if let movement = pendingDuplicateMove {
        pendingDuplicateMove = movement + offset
      }
      notifyModelChange(
        notification: .skip,
        renderContextChange: .update(translatedElementIDs())
      )
    }

    func endMove() throws {
      let movement = pendingDuplicateMove
      pendingDuplicateMove = nil
      let result = try editor.endGesture()
      guard result == .applied else { return }

      if let movement {
        recordDuplicateMovement(movement)
      }
      registerUndo(actionName: "Move")
      notifyModelChange(notification: .done, renderContextChange: .unchanged)
    }

    func beginResize() throws {
      guard selectedElement != nil else { return }

      try beginTransform(.resize)
    }

    func resize(_ id: ElementID, to frame: SionRect) throws {
      _ = try editor.updateGesture(with: .setFrame(elementID: id, frame: frame))
      notifyModelChange(notification: .skip, renderContextChange: .update([id]))
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
      notifyModelChange(notification: .skip, renderContextChange: .update([id]))
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
      notifyModelChange(notification: .skip, renderContextChange: .update([id]))
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
      notifyModelChange(notification: .done, renderContextChange: .unchanged)
    }

    /// Restores the pre-gesture scene; used when a drag is cancelled.
    func cancelActiveGesture() {
      pendingDuplicateMove = nil
      guard (try? editor.cancelGesture()) == .applied else { return }

      notifyModelChange(
        notification: .skip,
        renderContextChange: .update(translatedElementIDs())
      )
    }

    private func translatedElementIDs() -> Set<ElementID> {
      var ids = selection
      ids.formUnion(editor.document.scene.descendantIDs(of: selection))
      return ids
    }

    /// Mirrors core gesture lifetime for view-state recovery.
    var hasPendingEditorGesture: Bool {
      editor.hasPendingGesture
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

        if ElementHitGeometry.contains(
          point,
          in: element,
          tolerance: EditorDefaults.elementHitSlop
        ) {
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

        return ElementHitGeometry.contains(
          point,
          in: element,
          tolerance: EditorDefaults.elementHitSlop
        )
      }
    }

    @objc func undoSceneEdit() {
      let hadPendingGesture = editor.hasPendingGesture
      guard let actionName = editor.undo() else {
        // An untouched gesture changes no document bytes, but its view still
        // needs to discard the corresponding drag.
        if hadPendingGesture {
          pendingDuplicateMove = nil
          notifyObservers()
        }
        return
      }

      lastDuplicate = nil
      pendingDuplicateMove = nil
      undoManagerProvider()?.registerUndo(withTarget: self) { target in
        Self.performUndo(.redo, on: target)
      }
      undoManagerProvider()?.setActionName(actionName)
      pruneSelection()
      notifyModelChange(notification: .undone)
    }

    @objc func redoSceneEdit() {
      guard let actionName = editor.redo() else { return }

      lastDuplicate = nil
      pendingDuplicateMove = nil
      undoManagerProvider()?.registerUndo(withTarget: self) { target in
        Self.performUndo(.undo, on: target)
      }
      undoManagerProvider()?.setActionName(actionName)
      pruneSelection()
      notifyModelChange(notification: .redone)
    }

    private func perform(name: String, command: SceneCommand) throws {
      try perform(name: name, commands: [command])
    }

    private func perform(name: String, commands: [SceneCommand]) throws {
      let result = try editor.perform(SceneTransaction(name: name, commands: commands))
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

    private func notifyModelChange(
      notification: DocumentChangeNotification,
      renderContextChange: RenderContextChange = .rebuild
    ) {
      // Every notification reaching this funnel mutates the document, so the
      // rendered preview is stale. Selection-only changes bypass this funnel.
      previewPNG = nil

      switch renderContextChange {
      case .rebuild:
        renderContext = renderContextBuilder(editor.document.scene)
      case .update(let changedElementIDs):
        renderContext.update(
          scene: editor.document.scene,
          changedElementIDs: changedElementIDs
        )
      case .unchanged:
        break
      }

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
    static let duplicateStepMinimum = 8.0
    static let duplicateStepMaximum = 64.0
    static let duplicateMoveTolerance = 0.5
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
    static let renameElement = "Rename Element"
    static let renameElements = "Rename Elements"
    static let hideGrid = "Hide Grid"
    static let showGrid = "Show Grid"
  }

  private struct PendingTextEdit {
    let elementID: ElementID
    let baselineText: String
    var didMarkDocumentChanged = false
  }

  private struct DuplicateState {
    let ids: Set<ElementID>
    let delta: SionVector
    var manualTranslation = SionVector.zero
  }

  private struct ZOrderPlan {
    let orderedIDs: [ElementID]
    let destinationIndex: Int
  }

  enum ZOrderMovement {
    case front
    case forward
    case backward
    case back

    var actionName: String {
      switch self {
      case .front: "Bring to Front"
      case .forward: "Bring Forward"
      case .backward: "Send Backward"
      case .back: "Send to Back"
      }
    }
  }

  extension ElementLockState {
    fileprivate var undoActionName: String {
      switch self {
      case .editable: "Unlock"
      case .locked: "Lock"
      }
    }
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
