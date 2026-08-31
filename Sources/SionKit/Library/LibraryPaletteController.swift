#if canImport(AppKit)
  import AppKit
  import SionCore

  /// The Library palette: the built-in shapes first, then whatever the document
  /// and the person have put by for reuse.
  @MainActor
  final class LibraryPaletteController: NSViewController, PaletteContent {
    typealias Target = SionDocumentWindowController

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

    /// Marks the rows that are always there. A stored item carries its own id
    /// instead, which is how a click knows which one it came from.
    static let builtInItemIdentifier = NSUserInterfaceItemIdentifier("sion.library.builtIn")

    private enum LibraryShape: Int, CaseIterable {
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

      var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .roundedRectangle: "rectangle.rounded"
        case .ellipse: "circle"
        case .diamond: "diamond"
        case .triangle: "triangle"
        case .hexagon: "hexagon"
        case .capsule: "capsule"
        case .cylinder: "cylinder"
        }
      }

      var kind: ShapeKind {
        switch self {
        case .rectangle: .rectangle
        case .roundedRectangle:
          .roundedRectangle(radius: SceneElementDefaults.cornerRadius)
        case .ellipse: .ellipse
        case .diamond: .diamond
        case .triangle: .triangle
        case .hexagon: .hexagon
        case .capsule: .capsule
        case .cylinder: .cylinder
        }
      }
    }

    private let globalLibrary: SionGlobalLibrary
    private let stack = NSStackView()
    private weak var target: SionDocumentWindowController?
    private var observerID: UUID?
    private var builtInViewCount = 0
    private var displayedDocumentStorage: PortableValue?
    private var hasRenderedItems = false

    init(globalLibrary: SionGlobalLibrary) {
      self.globalLibrary = globalLibrary

      super.init(nibName: nil, bundle: nil)

      // The target form unregisters itself when this controller goes away.
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(globalLibraryDidChange),
        name: SionGlobalLibrary.didChangeNotification,
        object: nil
      )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = InspectorMetrics.spacing
      stack.edgeInsets = InspectorMetrics.insets

      for shape in LibraryShape.allCases {
        stack.addArrangedSubview(libraryButton(for: shape))
      }

      stack.addArrangedSubview(
        builtInButton("Text", symbol: "textformat", action: #selector(addText)))

      // Everything after this point is rebuilt whenever a library changes.
      builtInViewCount = stack.arrangedSubviews.count
      view = scrollingPaletteBody(stack)
    }

    func retarget(to target: SionDocumentWindowController?) {
      if let observerID {
        self.target?.paletteEditorController.removeObserver(observerID)
      }

      self.target = target
      observerID = target?.paletteEditorController.observeChanges { [weak self] in
        self?.refreshItems()
      }
      refreshItems(force: true)
    }

    /// Places a stored item at the middle of what the document is showing.
    func insert(_ reference: ItemReference) {
      guard let target else { return }
      guard let item = item(for: reference) else {
        report(.itemUnavailable)
        return
      }

      do {
        _ = try target.paletteEditorController.insertSelectionPayload(
          item.payload,
          at: target.canvasVisibleCenter,
          undoName: LibraryCopy.insertUndoName
        )
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

    func item(for reference: ItemReference) -> SceneLibraryItem? {
      switch reference.scope {
      case .document:
        target?.paletteEditorController.documentLibrary.item(id: reference.id)
      case .global:
        globalLibrary.item(id: reference.id)
      }
    }

    @objc private func addShape(_ sender: NSButton) {
      guard let target, let shape = LibraryShape(rawValue: sender.tag) else { return }

      _ = try? target.paletteEditorController.insertShape(
        centeredAt: target.canvasVisibleCenter,
        kind: shape.kind
      )
    }

    @objc private func addText() {
      guard let target else { return }

      guard
        let id = try? target.paletteEditorController.insertText(
          "Text",
          centeredAt: target.canvasVisibleCenter
        )
      else {
        return
      }

      target.beginTextEditing(id)
    }

    @objc private func insertLibraryItem(_ sender: NSButton) {
      guard let reference = Self.reference(from: sender) else { return }

      insert(reference)
    }

    @objc private func renameLibraryItem(_ sender: NSMenuItem) {
      guard let reference = sender.representedObject as? ItemReference,
        let item = item(for: reference),
        let name = Self.promptForName(current: item.name)
      else {
        return
      }

      rename(reference, to: name)
    }

    @objc private func removeLibraryItem(_ sender: NSMenuItem) {
      guard let reference = sender.representedObject as? ItemReference else { return }

      remove(reference)
    }

    @objc private func globalLibraryDidChange() {
      // The notification only fires on a real change, and the guard below
      // watches the document's storage rather than this one's.
      refreshItems(force: true)
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
          guard let editor = target?.paletteEditorController else { return }

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

    /// Rebuilt only when a library actually changed, because the document's
    /// own one is re-read on every edit the drawing sees. The stored value is
    /// compared before it is decoded: a drag posts a change per mouse event,
    /// and decoding a library's payloads that often would be all this palette
    /// ever did.
    private func refreshItems(force: Bool = false) {
      // The rows go below the built-in ones, so those have to exist first.
      // `loadViewIfNeeded()` would say this outright but is macOS 14; reading
      // the view is what it does.
      if !isViewLoaded {
        _ = view
      }

      let storage = target.flatMap { $0.paletteEditorController.documentLibraryStorage }
      guard force || !hasRenderedItems || storage != displayedDocumentStorage else { return }

      displayedDocumentStorage = storage
      hasRenderedItems = true
      let items = currentItems()

      for view in stack.arrangedSubviews.dropFirst(builtInViewCount) {
        stack.removeArrangedSubview(view)
        view.removeFromSuperview()
      }

      for scope in Scope.allCases {
        let scoped = items.filter { $0.reference.scope == scope }
        guard !scoped.isEmpty else { continue }

        stack.addArrangedSubview(sectionHeader(scope.sectionTitle))
        for item in scoped {
          stack.addArrangedSubview(itemButton(item))
        }
      }

      updateEnabledState()
    }

    private func currentItems() -> [ItemDescription] {
      let documentItems = target?.paletteEditorController.documentLibrary.items ?? []

      return documentItems.map { ItemDescription(scope: .document, item: $0) }
        + globalLibrary.items.map { ItemDescription(scope: .global, item: $0) }
    }

    /// A stored item shown in the list: no payload, because the list is
    /// rebuilt from it and the bytes are only needed once something is placed.
    private struct ItemDescription: Equatable {
      let reference: ItemReference
      let name: String

      init(scope: Scope, item: SceneLibraryItem) {
        reference = ItemReference(scope: scope, id: item.id)
        name = item.name
      }
    }

    /// Every row puts something into a drawing, so with no front document
    /// there is nothing any of them could do.
    private func updateEnabledState() {
      for case let button as NSButton in view.subviewsRecursive {
        button.isEnabled = target != nil
      }
    }

    private func report(_ failure: SionEditorFeedback.LibraryFailure) {
      guard let target else {
        NSSound.beep()
        return
      }

      target.presentEditorFeedback(.show(.libraryCommandFailed(failure)))
    }

    private func sectionHeader(_ title: String) -> NSTextField {
      let label = NSTextField(labelWithString: title)
      label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
      label.textColor = .secondaryLabelColor
      return label
    }

    private func itemButton(_ description: ItemDescription) -> NSButton {
      let button = libraryButton(
        description.name,
        symbol: LibraryCopy.itemSymbolName,
        action: #selector(insertLibraryItem(_:))
      )
      button.identifier = NSUserInterfaceItemIdentifier(description.reference.id)
      button.tag = description.reference.scope.rawValue
      button.toolTip = "\(description.name) — \(description.reference.scope.sectionTitle)"
      button.lineBreakMode = .byTruncatingTail
      button.menu = itemMenu(for: description.reference)
      return button
    }

    private func itemMenu(for reference: ItemReference) -> NSMenu {
      let menu = NSMenu()

      for entry in [
        (title: LibraryCopy.renameTitle, action: #selector(renameLibraryItem(_:))),
        (title: LibraryCopy.removeTitle, action: #selector(removeLibraryItem(_:))),
      ] {
        let menuItem = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = reference
        menu.addItem(menuItem)
      }

      return menu
    }

    private func libraryButton(for shape: LibraryShape) -> NSButton {
      let button = builtInButton(
        shape.title,
        symbol: shape.symbolName,
        action: #selector(addShape(_:))
      )
      button.tag = shape.rawValue
      return button
    }

    private func builtInButton(_ title: String, symbol: String, action: Selector) -> NSButton {
      let button = libraryButton(title, symbol: symbol, action: action)
      button.identifier = Self.builtInItemIdentifier
      return button
    }

    private func libraryButton(_ title: String, symbol: String, action: Selector) -> NSButton {
      let button = NSButton(title: title, target: self, action: action)
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      button.imagePosition = .imageLeading
      button.alignment = .left
      button.bezelStyle = .recessed
      return button
    }

    private static func reference(from button: NSButton) -> ItemReference? {
      guard let id = button.identifier?.rawValue,
        id != Self.builtInItemIdentifier.rawValue,
        let scope = Scope(rawValue: button.tag)
      else {
        return nil
      }

      return ItemReference(scope: scope, id: id)
    }

    /// A one-field sheet-less prompt; the palette it is asked from may be a
    /// floating panel with no window of its own to attach a sheet to.
    private static func promptForName(current: String) -> String? {
      let alert = NSAlert()
      alert.messageText = LibraryCopy.renamePrompt
      alert.addButton(withTitle: LibraryCopy.renameConfirmTitle)
      alert.addButton(withTitle: LibraryCopy.cancelTitle)

      let field = NSTextField(string: current)
      field.frame = NSRect(origin: .zero, size: LibraryCopy.renameFieldSize)
      alert.accessoryView = field
      alert.window.initialFirstResponder = field

      guard alert.runModal() == .alertFirstButtonReturn else { return nil }

      return field.stringValue
    }
  }

  private enum LibraryCopy {
    static let itemSymbolName = "square.on.square"
    static let insertUndoName = "Place Library Item"
    static let renameTitle = "Rename…"
    static let removeTitle = "Remove from Library"
    static let renamePrompt = "Rename Library Item"
    static let renameConfirmTitle = "Rename"
    static let cancelTitle = "Cancel"
    static let renameFieldSize = NSSize(width: 240, height: 24)
  }
#endif
