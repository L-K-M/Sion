#if canImport(AppKit)
  import AppKit
  import SionCore

  @MainActor
  final class SionDocumentWindowController: NSWindowController, NSWindowDelegate,
    NSToolbarDelegate
  {
    private let editorController: SionEditorController
    private let canvasView: SionCanvasView
    private let scrollView = NSScrollView()
    private var toolControl: NSSegmentedControl?
    private var observerID: UUID?
    private var isInitialZoomPending = true

    var paletteEditorController: SionEditorController { editorController }
    var canvasVisibleCenter: SionPoint { canvasView.visibleCenter }

    func commitPendingEdits() {
      canvasView.commitPendingEdits()
    }

    func checkpointPendingEdits() {
      canvasView.checkpointPendingEdits()
    }

    func discardPendingEdits() {
      canvasView.discardPendingEdits()
    }

    func beginTextEditing(_ id: ElementID) {
      canvasView.beginTextEditing(id)
    }

    func renderPreviewPNG() -> Data? {
      canvasView.renderPreviewPNG()
    }

    init(editorController: SionEditorController) {
      self.editorController = editorController
      canvasView = SionCanvasView(editorController: editorController)

      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: WindowMetrics.initialSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.title = editorController.document.title
      window.titlebarAppearsTransparent = true
      window.tabbingMode = .preferred
      window.isRestorable = true
      window.setFrameAutosaveName("SionDocumentWindow")

      super.init(window: window)

      window.delegate = self
      configureContent()
      configureToolbar()
      registerPalettes()
      observerID = editorController.observeChanges { [weak self] in
        self?.synchronizeUI()
      }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is unavailable")
    }

    override func windowDidLoad() {
      super.windowDidLoad()

      window?.makeFirstResponder(canvasView)
    }

    func windowDidResignKey(_ notification: Notification) {
      canvasView.cancelActiveDrag()
    }

    func windowDidResize(_ notification: Notification) {
      guard window?.isVisible == true else { return }

      // A zero-sized restored viewport can become usable after its first show.
      applyInitialZoomIfNeeded()
    }

    override func showWindow(_ sender: Any?) {
      super.showWindow(sender)
      window?.makeFirstResponder(canvasView)

      applyInitialZoomIfNeeded()
    }

    override func close() {
      if let observerID {
        editorController.removeObserver(observerID)
        self.observerID = nil
      }
      canvasView.invalidate()
      super.close()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [.tools, .zoom, .flexibleSpace, .inspector, .library, .history]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [.tools, .zoom, .flexibleSpace, .inspector, .library]
    }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      switch itemIdentifier {
      case .tools:
        return toolsItem()
      case .zoom:
        return zoomItem()
      case .inspector:
        return buttonItem(
          identifier: .inspector,
          label: "Inspector",
          symbolName: "slider.horizontal.3",
          action: #selector(showInspector(_:))
        )
      case .library:
        return buttonItem(
          identifier: .library,
          label: "Library",
          symbolName: "square.grid.2x2",
          action: #selector(showLibrary(_:))
        )
      case .history:
        return buttonItem(
          identifier: .history,
          label: "History",
          symbolName: "clock.arrow.circlepath",
          action: #selector(showHistory(_:))
        )
      default:
        return nil
      }
    }

    @objc func zoomIn(_ sender: Any?) {
      resolveInitialZoom()
      setMagnification(scrollView.magnification * WindowMetrics.zoomStep)
    }

    @objc func zoomOut(_ sender: Any?) {
      resolveInitialZoom()
      setMagnification(scrollView.magnification / WindowMetrics.zoomStep)
    }

    @objc func actualSize(_ sender: Any?) {
      setMagnification(1)
    }

    @objc func zoomToFit(_ sender: Any?) {
      resolveInitialZoom()
      let bounds = editorController.contentBounds()
      let available = scrollView.contentSize
      guard bounds.width > 0, bounds.height > 0 else { return }

      let scale =
        min(
          available.width / bounds.width,
          available.height / bounds.height
        ) * WindowMetrics.fitInsetFactor
      setMagnification(scale)
      let visible = scrollView.contentView.bounds.size
      let center = canvasView.viewPoint(for: bounds.center)
      let origin = NSPoint(
        x: max(0, center.x - (visible.width / 2)),
        y: max(0, center.y - (visible.height / 2))
      )
      scrollView.contentView.scroll(to: origin)
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc func showInspector(_ sender: Any?) {
      presentPalette(.inspector, sender: sender)
    }

    @objc func showLibrary(_ sender: Any?) {
      presentPalette(.library, sender: sender)
    }

    @objc func showHistory(_ sender: Any?) {
      presentPalette(.history, sender: sender)
    }

    private func configureContent() {
      scrollView.documentView = canvasView
      scrollView.hasHorizontalScroller = true
      scrollView.hasVerticalScroller = true
      scrollView.allowsMagnification = true
      scrollView.minMagnification = WindowMetrics.minimumMagnification
      scrollView.maxMagnification = WindowMetrics.maximumMagnification
      scrollView.backgroundColor = .windowBackgroundColor
      scrollView.drawsBackground = true
      window?.contentView = scrollView
    }

    private func configureToolbar() {
      // A new identifier bypasses saved v1 layouts that cannot contain Zoom.
      let toolbar = NSToolbar(identifier: ToolbarIdentifier.document)
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      toolbar.allowsUserCustomization = true
      toolbar.autosavesConfiguration = true
      toolbar.centeredItemIdentifier = .tools
      window?.toolbar = toolbar
      window?.toolbarStyle = .unified
    }

    private func registerPalettes() {
      SionPalettes.shared.registerIfNeeded()
    }

    private func toolsItem() -> NSToolbarItem {
      let images = SionEditorController.Tool.allCases.map {
        NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.title) ?? NSImage()
      }
      let control = NSSegmentedControl(
        images: images,
        trackingMode: .selectOne,
        target: self,
        action: #selector(selectTool(_:))
      )
      control.selectedSegment = editorController.tool.rawValue
      control.segmentStyle = .texturedRounded
      control.setAccessibilityLabel("Editing tool")
      for tool in SionEditorController.Tool.allCases {
        control.setToolTip(tool.help, forSegment: tool.rawValue)
      }
      toolControl = control

      let item = NSToolbarItem(itemIdentifier: .tools)
      item.label = "Tools"
      item.paletteLabel = "Editing Tools"
      item.view = control
      return item
    }

    private func zoomItem() -> NSToolbarItem {
      let commands = ZoomCommand.allCases
      let control = NSSegmentedControl(
        labels: commands.map(\.label),
        trackingMode: .momentary,
        target: self,
        action: #selector(performZoomCommand(_:))
      )
      control.segmentStyle = .texturedRounded
      control.setAccessibilityLabel("Canvas zoom")
      for command in commands {
        control.setToolTip(command.title, forSegment: command.rawValue)
      }

      let item = NSToolbarItem(itemIdentifier: .zoom)
      item.label = "Zoom"
      item.paletteLabel = "Zoom Controls"
      item.toolTip = "Zoom the canvas"
      item.view = control
      return item
    }

    private func buttonItem(
      identifier: NSToolbarItem.Identifier,
      label: String,
      symbolName: String,
      action: Selector
    ) -> NSToolbarItem {
      let item = NSToolbarItem(itemIdentifier: identifier)
      let button = NSButton(
        image: NSImage(systemSymbolName: symbolName, accessibilityDescription: label) ?? NSImage(),
        target: self,
        action: action
      )
      button.bezelStyle = .texturedRounded
      button.isBordered = false
      button.toolTip = label
      button.setAccessibilityLabel(label)

      item.label = label
      item.paletteLabel = label
      item.toolTip = label
      item.view = button
      return item
    }

    @objc private func selectTool(_ sender: NSSegmentedControl) {
      guard let tool = SionEditorController.Tool(rawValue: sender.selectedSegment) else { return }

      editorController.setTool(tool)
      window?.makeFirstResponder(canvasView)
    }

    @objc private func performZoomCommand(_ sender: NSSegmentedControl) {
      guard let command = ZoomCommand(rawValue: sender.selectedSegment) else { return }

      switch command {
      case .zoomOut:
        zoomOut(sender)
      case .fit:
        zoomToFit(sender)
      case .zoomIn:
        zoomIn(sender)
      }

      window?.makeFirstResponder(canvasView)
    }

    private func synchronizeUI() {
      toolControl?.selectedSegment = editorController.tool.rawValue
    }

    private func applyInitialZoomIfNeeded() {
      guard isInitialZoomPending else { return }
      guard !editorController.document.scene.elements.isEmpty else { return }

      // Fit only after AppKit exposes a usable viewport; a later show can retry.
      window?.contentView?.layoutSubtreeIfNeeded()
      let available = scrollView.contentSize
      guard available.width > 0, available.height > 0 else { return }

      zoomToFit(nil)
    }

    private func resolveInitialZoom() {
      // A later resize must not replace an automatic or explicit zoom choice.
      isInitialZoomPending = false
    }

    private func setMagnification(_ requested: CGFloat) {
      let magnification = min(
        scrollView.maxMagnification,
        max(scrollView.minMagnification, requested)
      )
      let center = NSPoint(
        x: scrollView.documentVisibleRect.midX, y: scrollView.documentVisibleRect.midY)
      scrollView.setMagnification(magnification, centeredAt: center)
    }

    private func presentPalette(_ kind: SionPaletteKind, sender: Any?) {
      guard let palette = PaletteCenter.shared.registeredPalette(for: kind.paletteKind) else {
        return
      }

      guard let anchor = sender as? NSView else {
        palette.showPanel()
        return
      }

      palette.present(from: anchor)
    }
  }

  extension NSToolbarItem.Identifier {
    fileprivate static let tools = NSToolbarItem.Identifier("Sion.Tools")
    fileprivate static let zoom = NSToolbarItem.Identifier("Sion.Zoom")
    fileprivate static let inspector = NSToolbarItem.Identifier("Sion.Inspector")
    fileprivate static let library = NSToolbarItem.Identifier("Sion.Library")
    fileprivate static let history = NSToolbarItem.Identifier("Sion.History")
  }

  private enum WindowMetrics {
    static let initialSize = NSSize(width: 1_180, height: 780)
    static let minimumMagnification = 0.1
    static let maximumMagnification = 8.0
    static let zoomStep = 1.2
    static let fitInsetFactor = 0.88
  }

  private enum ToolbarIdentifier {
    static let document = NSToolbar.Identifier("SionDocumentToolbar.v2")
  }

  private enum ZoomCommand: Int, CaseIterable {
    case zoomOut
    case fit
    case zoomIn

    var label: String {
      switch self {
      case .zoomOut: "−"
      case .fit: "Fit"
      case .zoomIn: "+"
      }
    }

    var title: String {
      switch self {
      case .zoomOut: "Zoom Out"
      case .fit: "Zoom to Fit"
      case .zoomIn: "Zoom In"
      }
    }
  }
#endif
