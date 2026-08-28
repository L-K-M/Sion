#if canImport(AppKit)
  import AppKit
  import SionCore

  enum SionPaletteKind {
    case inspector
    case library
    case history

    var paletteKind: PaletteKind {
      switch self {
      case .inspector: PaletteKind("sion.inspector")
      case .library: PaletteKind("sion.library")
      case .history: PaletteKind("sion.history")
      }
    }
  }

  /// Resolves document targets while a floating palette owns focus.
  @MainActor
  private enum SionPaletteTargetResolver {
    static func frontWindowController(
      mainWindow: NSWindow?,
      keyWindow: NSWindow?,
      orderedWindows: [NSWindow]
    ) -> SionDocumentWindowController? {
      let windows = [mainWindow, keyWindow].compactMap { $0 } + orderedWindows

      for window in windows {
        guard window.isVisible else { continue }
        guard let controller = window.windowController as? SionDocumentWindowController else {
          continue
        }

        return controller
      }

      return nil
    }

    static func frontWindowController() -> SionDocumentWindowController? {
      frontWindowController(
        mainWindow: NSApp.mainWindow,
        keyWindow: NSApp.keyWindow,
        orderedWindows: NSApp.orderedWindows
      )
    }
  }

  @MainActor
  final class SionPalettes {
    static let shared = SionPalettes()

    private var isRegistered = false

    private init() {}

    func registerIfNeeded() {
      guard !isRegistered else { return }
      isRegistered = true

      PaletteCenter.shared.palette(
        for: PaletteDefinition(
          kind: SionPaletteKind.inspector.paletteKind,
          title: "Inspector",
          contentSize: NSSize(width: 300, height: 320),
          sizing: .resizable(minimumContentSize: NSSize(width: 260, height: 240))
        ),
        target: Self.frontEditorController,
        makeContent: InspectorPaletteController.init
      )
      PaletteCenter.shared.palette(
        for: PaletteDefinition(
          kind: SionPaletteKind.library.paletteKind,
          title: "Library",
          contentSize: NSSize(width: 280, height: 250)
        ),
        target: Self.frontWindowController,
        makeContent: LibraryPaletteController.init
      )
      PaletteCenter.shared.palette(
        for: PaletteDefinition(
          kind: SionPaletteKind.history.paletteKind,
          title: "History",
          contentSize: NSSize(width: 320, height: 360),
          sizing: .resizable(minimumContentSize: NSSize(width: 260, height: 220))
        ),
        target: Self.frontWindowController,
        makeContent: HistoryPaletteController.init
      )
    }

    private static func frontEditorController() -> SionEditorController? {
      frontWindowController()?.paletteEditorController
    }

    private static func frontWindowController() -> SionDocumentWindowController? {
      SionPaletteTargetResolver.frontWindowController()
    }
  }

  @MainActor
  private final class InspectorPaletteController: NSViewController, PaletteContent {
    typealias Target = SionEditorController

    private weak var target: SionEditorController?
    private var observerID: UUID?
    private var presentation: PalettePresentation?
    private let selectionLabel = NSTextField(labelWithString: "No selection")
    private let nameField = NSTextField()
    private let lockButton = NSButton(
      checkboxWithTitle: "Locked",
      target: nil,
      action: nil
    )
    private let fillColorWell = NSColorWell()
    private let strokeColorWell = NSColorWell()
    private let strokeWidthSlider = NSSlider()
    private let routePopup = NSPopUpButton()
    private let magnetPopup = NSPopUpButton()
    private let anchorEditingControls = NSStackView()
    private let anchorEditingInstruction = NSTextField(
      wrappingLabelWithString: AnchorEditingCopy.instruction
    )
    private let anchorEditingDoneButton = NSButton()

    override func loadView() {
      let stack = NSStackView()
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = InspectorMetrics.spacing
      stack.edgeInsets = InspectorMetrics.insets

      selectionLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
      selectionLabel.lineBreakMode = .byTruncatingTail
      selectionLabel.maximumNumberOfLines = 2

      configureRoutePopup()
      configureMagnetPopup()
      configureAnchorEditingControls()
      configureAppearanceControls()
      configureLockButton()
      configureNameField()
      stack.addArrangedSubview(selectionLabel)
      stack.addArrangedSubview(row(label: "Name", control: nameField))
      stack.addArrangedSubview(lockButton)
      stack.addArrangedSubview(separator())
      stack.addArrangedSubview(row(label: "Fill", control: fillColorWell))
      stack.addArrangedSubview(row(label: "Stroke", control: strokeColorWell))
      stack.addArrangedSubview(row(label: "Width", control: strokeWidthSlider))
      stack.addArrangedSubview(separator())
      stack.addArrangedSubview(row(label: "Route", control: routePopup))
      stack.addArrangedSubview(row(label: "Connector anchors", control: magnetPopup))
      stack.addArrangedSubview(anchorEditingControls)
      stack.addArrangedSubview(NSView())
      view = stack
    }

    var paletteInitialFirstResponder: NSView? { routePopup }

    func retarget(to target: SionEditorController?) {
      if let currentTarget = self.target,
        target.map({ $0 !== currentTarget }) ?? (presentation == .panel)
      {
        currentTarget.endAnchorEditing()
      }

      if let observerID {
        self.target?.removeObserver(observerID)
      }

      self.target = target
      observerID = target?.observeChanges { [weak self] in
        self?.refresh()
      }
      refresh()
    }

    func paletteDidPresent(_ presentation: PalettePresentation) {
      self.presentation = presentation
    }

    func paletteDidDismiss(_ presentation: PalettePresentation) {
      if presentation == .panel {
        target?.endAnchorEditing()
      }

      if self.presentation == presentation {
        self.presentation = nil
      }
    }

    private func configureRoutePopup() {
      for style in ConnectorRoutingStyle.allCases {
        routePopup.addItem(withTitle: style.displayName)
        routePopup.lastItem?.representedObject = style.rawValue
      }
      routePopup.target = self
      routePopup.action = #selector(changeRoute(_:))
      routePopup.setAccessibilityLabel("Connector route")
    }

    private func configureAppearanceControls() {
      fillColorWell.target = self
      fillColorWell.action = #selector(changeFill(_:))
      fillColorWell.setAccessibilityLabel("Fill color")

      strokeColorWell.target = self
      strokeColorWell.action = #selector(changeStrokeColor(_:))
      strokeColorWell.setAccessibilityLabel("Stroke color")

      strokeWidthSlider.minValue = InspectorMetrics.minimumStrokeWidth
      strokeWidthSlider.maxValue = InspectorMetrics.maximumStrokeWidth
      strokeWidthSlider.numberOfTickMarks = InspectorMetrics.strokeWidthTickCount
      strokeWidthSlider.allowsTickMarkValuesOnly = false
      strokeWidthSlider.isContinuous = false
      strokeWidthSlider.target = self
      strokeWidthSlider.action = #selector(changeStrokeWidth(_:))
      strokeWidthSlider.setAccessibilityLabel("Stroke width")
    }

    private func configureLockButton() {
      lockButton.allowsMixedState = true
      lockButton.target = self
      lockButton.action = #selector(changeLock(_:))
      lockButton.setAccessibilityLabel("Element lock")
    }

    private func configureNameField() {
      nameField.target = self
      nameField.action = #selector(changeName(_:))
      (nameField.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
      nameField.setAccessibilityLabel("Element name")
    }

    private func configureMagnetPopup() {
      for option in MagnetOption.allCases {
        magnetPopup.addItem(withTitle: option.title)
        magnetPopup.lastItem?.tag = option.rawValue
      }
      magnetPopup.target = self
      magnetPopup.action = #selector(changeMagnets(_:))
      magnetPopup.toolTip = "Choose where connectors attach to the selected object."
      magnetPopup.setAccessibilityLabel("Connector anchors")
    }

    private func configureAnchorEditingControls() {
      anchorEditingInstruction.textColor = .secondaryLabelColor
      anchorEditingInstruction.maximumNumberOfLines = 0
      anchorEditingInstruction.preferredMaxLayoutWidth = InspectorMetrics.anchorInstructionWidth

      anchorEditingDoneButton.title = AnchorEditingCopy.doneTitle
      anchorEditingDoneButton.bezelStyle = .rounded
      anchorEditingDoneButton.target = self
      anchorEditingDoneButton.action = #selector(endAnchorEditing)
      anchorEditingDoneButton.setAccessibilityLabel("Finish editing connector anchors")

      anchorEditingControls.orientation = .vertical
      anchorEditingControls.alignment = .leading
      anchorEditingControls.spacing = InspectorMetrics.spacing
      anchorEditingControls.addArrangedSubview(anchorEditingInstruction)
      anchorEditingControls.addArrangedSubview(anchorEditingDoneButton)
      anchorEditingControls.isHidden = true
    }

    private func refresh() {
      let selectedElements = target?.selectedElements ?? []
      refreshNameField(for: selectedElements)

      guard let element = target?.selectedElement else {
        let hasMultipleSelection = target?.selection.isEmpty == false
        selectionLabel.stringValue =
          hasMultipleSelection
          ? "Multiple elements"
          : "No selection"
        lockButton.state = hasMultipleSelection ? .mixed : .off
        lockButton.isEnabled = false
        lockButton.toolTip =
          hasMultipleSelection
          ? "Lock state cannot be changed for a mixed selection."
          : nil
        routePopup.isEnabled = false
        magnetPopup.isEnabled = false
        anchorEditingControls.isHidden = true
        fillColorWell.isEnabled = false
        strokeColorWell.isEnabled = false
        strokeWidthSlider.isEnabled = false
        return
      }

      let isEditable = element.lockState == .editable
      let name = element.name ?? element.displayName
      selectionLabel.stringValue = isEditable ? name : "\(name) • Locked"
      lockButton.state = isEditable ? .off : .on
      lockButton.isEnabled = true
      lockButton.toolTip =
        isEditable
        ? "Prevent changes to this element."
        : "Unlock this element to edit it."
      let supportsFill = element.content.supportsFill
      fillColorWell.isEnabled = supportsFill && isEditable
      strokeColorWell.isEnabled =
        (element.content.connector != nil || supportsFill) && isEditable
      strokeWidthSlider.isEnabled = strokeColorWell.isEnabled
      fillColorWell.color = nsColor(element.style.fill.solidColor ?? .clear)
      strokeColorWell.color = nsColor(element.style.stroke?.color ?? .primaryInk)
      strokeWidthSlider.doubleValue = element.style.stroke?.width ?? 0
      let editsAnchors =
        target?.anchorEditingState == .editing(element.id) && isEditable
      magnetPopup.isEnabled =
        element.content.connector == nil && !editsAnchors && isEditable
      anchorEditingControls.isHidden = !editsAnchors
      if editsAnchors {
        magnetPopup.selectItem(withTag: MagnetOption.custom.rawValue)
      } else {
        selectMagnetOption(for: element.magnetConfiguration)
      }

      guard let connector = element.content.connector else {
        routePopup.isEnabled = false
        return
      }

      routePopup.isEnabled = isEditable
      routePopup.selectItem(withTitle: connector.routingStyle.displayName)
    }

    private func refreshNameField(for elements: [SceneElement]) {
      nameField.isEnabled = target?.canRenameSelection == true
      guard !elements.isEmpty else {
        nameField.stringValue = ""
        nameField.placeholderString = nil
        return
      }

      let names = Set(elements.map(\.name))
      guard names.count == 1 else {
        nameField.stringValue = ""
        nameField.placeholderString = InspectorCopy.mixedValue
        return
      }

      nameField.stringValue = names.first.flatMap { $0 } ?? ""
      nameField.placeholderString = nil
    }

    @objc private func changeLock(_ sender: NSButton) {
      guard let target, let id = target.selectedElement?.id else { return }

      let lockState = sender.state == .on ? ElementLockState.locked : .editable
      if lockState == .locked {
        target.endAnchorEditing()
      }

      attemptEdit { try target.setLockState(lockState, on: id) }
    }

    @objc private func changeName(_ sender: NSTextField) {
      guard let target else { return }

      let name = sender.stringValue.isEmpty ? nil : sender.stringValue
      attemptEdit { try target.renameSelection(name) }
    }

    @objc private func changeRoute(_ sender: NSPopUpButton) {
      guard let target,
        let id = target.selectedElement?.id,
        let rawValue = sender.selectedItem?.representedObject as? String,
        let style = ConnectorRoutingStyle(rawValue: rawValue)
      else {
        return
      }

      attemptEdit { try target.setRoutingStyle(style, on: id) }
    }

    @objc private func changeFill(_ sender: NSColorWell) {
      guard let target, let id = target.selectedElement?.id else { return }

      attemptEdit { try target.setFillColor(sionColor(sender.color), on: id) }
    }

    @objc private func changeStrokeColor(_ sender: NSColorWell) {
      guard let target, let id = target.selectedElement?.id else { return }

      attemptEdit { try target.setStrokeColor(sionColor(sender.color), on: id) }
    }

    @objc private func changeStrokeWidth(_ sender: NSSlider) {
      guard let target, let id = target.selectedElement?.id else { return }

      attemptEdit { try target.setStrokeWidth(sender.doubleValue, on: id) }
    }

    @objc private func changeMagnets(_ sender: NSPopUpButton) {
      guard let target,
        let id = target.selectedElement?.id,
        let tag = sender.selectedItem?.tag,
        let option = MagnetOption(rawValue: tag)
      else {
        return
      }

      if option == .custom {
        target.beginAnchorEditing(on: id)
        PaletteCenter.shared.registeredPalette(
          for: SionPaletteKind.inspector.paletteKind
        )?.showPanel()
        return
      }

      guard let preset = option.preset else { return }

      target.endAnchorEditing()
      attemptEdit { try target.setMagnetConfiguration(.preset(preset), on: id) }
    }

    @objc private func endAnchorEditing() {
      target?.endAnchorEditing()
    }

    private func selectMagnetOption(for configuration: MagnetConfiguration) {
      if case .custom = configuration {
        magnetPopup.selectItem(withTag: MagnetOption.custom.rawValue)
        return
      }

      guard case .preset(let preset) = configuration,
        let option = MagnetOption(preset: preset)
      else {
        magnetPopup.select(nil)
        return
      }

      magnetPopup.selectItem(withTag: option.rawValue)
    }

    /// Rejected semantic edits must leave every control showing model state.
    private func attemptEdit(_ action: () throws -> Void) {
      do {
        try action()
      } catch {
        NSSound.beep()
        refresh()
      }
    }

    private func row(label: String, control: NSView) -> NSView {
      let labelView = NSTextField(labelWithString: label)
      labelView.textColor = .secondaryLabelColor
      labelView.setContentHuggingPriority(.required, for: .horizontal)

      let row = NSStackView(views: [labelView, control])
      row.orientation = .horizontal
      row.alignment = .centerY
      row.distribution = .fill
      row.spacing = InspectorMetrics.spacing
      return row
    }

    private func separator() -> NSView {
      let separator = NSBox()
      separator.boxType = .separator
      return separator
    }
  }

  @MainActor
  private final class LibraryPaletteController: NSViewController, PaletteContent {
    typealias Target = SionDocumentWindowController

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

    private weak var target: SionDocumentWindowController?

    override func loadView() {
      let stack = NSStackView()
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = InspectorMetrics.spacing
      stack.edgeInsets = InspectorMetrics.insets

      for shape in LibraryShape.allCases {
        stack.addArrangedSubview(libraryButton(for: shape))
      }

      stack.addArrangedSubview(
        libraryButton("Text", symbol: "textformat", action: #selector(addText)))

      // The fixed-height palette keeps every labeled entry keyboard reachable.
      let scrollView = NSScrollView()
      scrollView.hasVerticalScroller = true
      scrollView.documentView = stack
      stack.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
      ])
      view = scrollView
    }

    func retarget(to target: SionDocumentWindowController?) {
      self.target = target
      for case let button as NSButton in view.subviewsRecursive {
        button.isEnabled = target != nil
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

    private func libraryButton(for shape: LibraryShape) -> NSButton {
      let button = libraryButton(
        shape.title,
        symbol: shape.symbolName,
        action: #selector(addShape(_:))
      )
      button.tag = shape.rawValue
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
  }

  @MainActor
  private final class HistoryPaletteController: NSViewController, PaletteContent {
    typealias Target = SionDocumentWindowController

    private weak var target: SionDocumentWindowController?
    private var observerID: UUID?
    private var displayedRevisionIDs: [String]?
    private let stack = NSStackView()

    override func loadView() {
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = InspectorMetrics.spacing
      stack.edgeInsets = InspectorMetrics.insets

      let scrollView = NSScrollView()
      scrollView.hasVerticalScroller = true
      scrollView.documentView = stack
      stack.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
      ])
      view = scrollView
    }

    func retarget(to target: SionDocumentWindowController?) {
      if let observerID {
        self.target?.paletteEditorController.removeObserver(observerID)
      }

      self.target = target
      observerID = target?.paletteEditorController.observeChanges { [weak self] in
        self?.refresh()
      }
      refresh()
    }

    private func refresh() {
      let revisions = target?.paletteEditorController.historyRevisions ?? []
      let revisionIDs = revisions.map(\.identifier)
      guard revisionIDs != displayedRevisionIDs else { return }
      displayedRevisionIDs = revisionIDs

      for child in stack.arrangedSubviews {
        stack.removeArrangedSubview(child)
        child.removeFromSuperview()
      }

      guard !revisions.isEmpty else {
        stack.addArrangedSubview(NSTextField(labelWithString: "No saved revisions"))
        return
      }

      for revision in revisions {
        let title =
          "\(revision.intent.displayName) · \(HistoryDateFormatter.shared.string(from: revision.savedAt))"
        let button = NSButton(
          title: title,
          target: self,
          action: #selector(restoreRevision(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(revision.identifier)
        button.bezelStyle = .recessed
        button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.toolTip = "Restore this revision. Undo restores the current drawing."
        stack.addArrangedSubview(button)
      }
    }

    @objc private func restoreRevision(_ sender: NSButton) {
      guard let target, let identifier = sender.identifier?.rawValue else { return }

      target.commitPendingEdits()
      try? target.paletteEditorController.restoreRevision(identifier: identifier)
    }
  }

  private enum MagnetOption: Int, CaseIterable {
    case none
    case cardinalFour
    case northSouth
    case eastWest
    case diagonalFour
    case eight
    case vertices
    case onePerSide
    case twoPerSide
    case threePerSide
    case fourPerSide
    case fivePerSide
    case custom

    init?(preset: MagnetPreset) {
      switch preset {
      case .none: self = .none
      case .cardinalFour: self = .cardinalFour
      case .northSouth: self = .northSouth
      case .eastWest: self = .eastWest
      case .diagonalFour: self = .diagonalFour
      case .eight: self = .eight
      case .vertices: self = .vertices
      case .perSegment(1): self = .onePerSide
      case .perSegment(2): self = .twoPerSide
      case .perSegment(3): self = .threePerSide
      case .perSegment(4): self = .fourPerSide
      case .perSegment(5): self = .fivePerSide
      case .perSegment: return nil
      }
    }

    var title: String {
      switch self {
      case .none: "No fixed points"
      case .cardinalFour: "N, S, E, W"
      case .northSouth: "N, S"
      case .eastWest: "E, W"
      case .diagonalFour: "NE, NW, SE, SW"
      case .eight: "8 magnets"
      case .vertices: "Each vertex"
      case .onePerSide: "1 per side"
      case .twoPerSide: "2 per side"
      case .threePerSide: "3 per side"
      case .fourPerSide: "4 per side"
      case .fivePerSide: "5 per side"
      case .custom: AnchorEditingCopy.customOptionTitle
      }
    }

    var preset: MagnetPreset? {
      switch self {
      case .none: MagnetPreset.none
      case .cardinalFour: .cardinalFour
      case .northSouth: .northSouth
      case .eastWest: .eastWest
      case .diagonalFour: .diagonalFour
      case .eight: .eight
      case .vertices: .vertices
      case .onePerSide: .perSegment(1)
      case .twoPerSide: .perSegment(2)
      case .threePerSide: .perSegment(3)
      case .fourPerSide: .perSegment(4)
      case .fivePerSide: .perSegment(5)
      case .custom: nil
      }
    }
  }

  private enum InspectorMetrics {
    static let spacing = 10.0
    static let insets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    static let anchorInstructionWidth: CGFloat = 244
    static let minimumStrokeWidth = 0.0
    static let maximumStrokeWidth = 12.0
    static let strokeWidthTickCount = 13
  }

  private enum InspectorCopy {
    static let mixedValue = "Mixed"
  }

  private enum AnchorEditingCopy {
    static let customOptionTitle = "Custom points…"
    static let instruction = "Click the object to add an anchor; click an anchor to remove it."
    static let doneTitle = "Done"
  }

  private enum HistoryDateFormatter {
    static let shared: DateFormatter = {
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .short
      return formatter
    }()
  }

  extension ConnectorRoutingStyle {
    fileprivate var displayName: String {
      switch self {
      case .straight: "Straight"
      case .curved: "Curved"
      case .orthogonal: "Orthogonal"
      case .bezier: "Bézier"
      }
    }
  }

  extension SaveIntent {
    fileprivate var displayName: String {
      switch self {
      case .manual: "Saved"
      case .autosave: "Autosaved"
      case .saveAs: "Saved As"
      }
    }
  }

  extension SceneElement {
    fileprivate var displayName: String {
      switch content {
      case .shape: "Shape"
      case .path: "Path"
      case .text: "Text"
      case .image: "Image"
      case .group: "Group"
      case .connector: "Connector"
      }
    }
  }

  extension ElementContent {
    fileprivate var supportsFill: Bool {
      switch self {
      case .shape, .path: true
      case .text, .image, .group, .connector: false
      }
    }
  }

  extension FillStyle {
    fileprivate var solidColor: SionColor? {
      guard case .solid(let color) = self else { return nil }

      return color
    }
  }

  private func nsColor(_ color: SionColor) -> NSColor {
    SionColorBridge.appKitColor(color)
  }

  private func sionColor(_ color: NSColor) -> SionColor {
    SionColorBridge.modelColor(color)
  }

  extension NSView {
    fileprivate var subviewsRecursive: [NSView] {
      subviews + subviews.flatMap(\.subviewsRecursive)
    }
  }
#endif
