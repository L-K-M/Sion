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
          contentSize: NSSize(width: 280, height: 250),
          sizing: .resizable(minimumContentSize: NSSize(width: 240, height: 180))
        ),
        target: Self.frontWindowController,
        makeContent: { LibraryPaletteController(globalLibrary: .shared) }
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
  private final class InspectorPaletteController: NSViewController, NSTextFieldDelegate,
    PaletteContent
  {
    typealias Target = SionEditorController

    private enum NameFieldPresentation {
      case noSelection
      case value(String)
      case mixed

      func matches(_ value: String) -> Bool {
        switch self {
        case .noSelection, .mixed:
          value.isEmpty
        case .value(let displayedValue):
          value == displayedValue
        }
      }
    }

    private enum NameEditState {
      case unchanged
      case changed
    }

    private weak var target: SionEditorController?
    private var observerID: UUID?
    private var presentation: PalettePresentation?
    private var nameFieldPresentation = NameFieldPresentation.noSelection
    private var nameEditState = NameEditState.unchanged
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
    private let shadowButton = NSButton(
      checkboxWithTitle: "Drop Shadow",
      target: nil,
      action: nil
    )
    private let shadowColorWell = NSColorWell()
    private let shadowBlurSlider = NSSlider()
    private let routePopup = NSPopUpButton()
    private let magnetPopup = NSPopUpButton()
    private let stack = NSStackView()
    private let anchorEditingControls = NSStackView()
    private let anchorEditingInstruction = NSTextField(
      wrappingLabelWithString: AnchorEditingCopy.instruction
    )
    private let anchorEditingDoneButton = NSButton()

    override func loadView() {
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
      configureShadowControls()
      configureLockButton()
      configureNameField()
      stack.addArrangedSubview(selectionLabel)
      stack.addArrangedSubview(row(label: "Name", control: nameField))
      stack.addArrangedSubview(lockButton)
      stack.addArrangedSubview(separator())
      stack.addArrangedSubview(row(label: "Fill", control: fillColorWell))
      stack.addArrangedSubview(row(label: "Stroke", control: strokeColorWell))
      stack.addArrangedSubview(row(label: "Width", control: strokeWidthSlider))
      stack.addArrangedSubview(shadowButton)
      stack.addArrangedSubview(row(label: "Shadow", control: shadowColorWell))
      stack.addArrangedSubview(row(label: "Blur", control: shadowBlurSlider))
      stack.addArrangedSubview(separator())
      stack.addArrangedSubview(row(label: "Route", control: routePopup))
      stack.addArrangedSubview(row(label: "Connector anchors", control: magnetPopup))
      stack.addArrangedSubview(anchorEditingControls)
      stack.addArrangedSubview(NSView())
      // Anchor editing reveals extra rows, so the body has to be able to
      // scroll rather than clip inside the palette's declared size.
      view = scrollingPaletteBody(stack)
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

    private func configureShadowControls() {
      shadowButton.target = self
      shadowButton.action = #selector(changeShadowEnabled(_:))
      shadowButton.toolTip = "Cast a drop shadow behind this object."
      shadowButton.setAccessibilityLabel("Drop shadow")

      shadowColorWell.target = self
      shadowColorWell.action = #selector(changeShadowColor(_:))
      shadowColorWell.setAccessibilityLabel("Drop shadow color")

      shadowBlurSlider.minValue = SionShadowDefaults.minimumBlurRadius
      shadowBlurSlider.maxValue = SionShadowDefaults.maximumBlurRadius
      shadowBlurSlider.allowsTickMarkValuesOnly = false
      shadowBlurSlider.isContinuous = false
      shadowBlurSlider.target = self
      shadowBlurSlider.action = #selector(changeShadowBlur(_:))
      shadowBlurSlider.setAccessibilityLabel("Drop shadow blur")
    }

    private func configureLockButton() {
      lockButton.allowsMixedState = true
      lockButton.target = self
      lockButton.action = #selector(changeLock(_:))
      lockButton.setAccessibilityLabel("Element lock")
    }

    private func configureNameField() {
      nameField.delegate = self
      nameField.target = self
      nameField.action = #selector(changeName(_:))
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
        clearShadowControls()
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
      fillColorWell.isEnabled = element.content.supportsFill && isEditable
      strokeColorWell.isEnabled = element.content.supportsStroke && isEditable
      strokeWidthSlider.isEnabled = strokeColorWell.isEnabled
      fillColorWell.color = nsColor(element.style.fill.solidColor ?? .clear)
      strokeColorWell.color = nsColor(element.style.stroke?.color ?? .primaryInk)
      strokeWidthSlider.doubleValue = element.style.stroke?.width ?? 0
      refreshShadowControls(for: element, isEditable: isEditable)
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
        presentNameField(.noSelection)
        return
      }

      let names = Set(elements.map(\.name))
      guard names.count == 1 else {
        presentNameField(.mixed)
        return
      }

      presentNameField(.value(names.first.flatMap { $0 } ?? ""))
    }

    private func presentNameField(_ presentation: NameFieldPresentation) {
      nameFieldPresentation = presentation
      nameEditState = .unchanged

      switch presentation {
      case .noSelection:
        nameField.stringValue = ""
        nameField.placeholderString = nil
      case .value(let name):
        nameField.stringValue = name
        nameField.placeholderString = nil
      case .mixed:
        nameField.stringValue = ""
        nameField.placeholderString = InspectorCopy.mixedValue
      }
    }

    /// The color and blur controls only mean something once a shadow exists.
    /// Content that does not take a shadow but arrived carrying one keeps a
    /// live checkbox so the shadow can be switched off; the controls that would
    /// restyle it stay dark, since the command refuses to set one there.
    private func refreshShadowControls(for element: SceneElement, isEditable: Bool) {
      let supportsShadow = element.content.supportsShadow && isEditable
      let shadow = element.style.shadows.first
      shadowButton.isEnabled = supportsShadow || (isEditable && shadow != nil)
      shadowButton.state = shadow == nil ? .off : .on
      shadowColorWell.isEnabled = supportsShadow && shadow != nil
      shadowBlurSlider.isEnabled = shadowColorWell.isEnabled
      shadowColorWell.color = nsColor(shadow?.color ?? SionShadowDefaults.style.color)
      // A document can carry a blur the inspector's range does not reach;
      // clamping it here would silently shrink it on the first drag.
      let blurRadius = shadow?.blurRadius ?? SionShadowDefaults.style.blurRadius
      shadowBlurSlider.maxValue = max(SionShadowDefaults.maximumBlurRadius, blurRadius)
      shadowBlurSlider.doubleValue = blurRadius
    }

    private func clearShadowControls() {
      shadowButton.isEnabled = false
      shadowButton.state = .off
      shadowColorWell.isEnabled = false
      shadowBlurSlider.isEnabled = false
    }

    @objc private func changeShadowEnabled(_ sender: NSButton) {
      guard let target, let id = target.selectedElement?.id else { return }

      attemptEdit { try target.setShadowEnabled(sender.state == .on, on: id) }
    }

    @objc private func changeShadowColor(_ sender: NSColorWell) {
      guard let target, let id = target.selectedElement?.id else { return }

      attemptEdit { try target.setShadowColor(sionColor(sender.color), on: id) }
    }

    @objc private func changeShadowBlur(_ sender: NSSlider) {
      guard let target, let id = target.selectedElement?.id else { return }

      attemptEdit { try target.setShadowBlurRadius(sender.doubleValue, on: id) }
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
      commitNameIfNeeded(sender)
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField, field === nameField else { return }

      nameEditState = .changed
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      // Escape reverts the field; dropping the pending edit keeps the cancel
      // from being committed when editing ends.
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        nameEditState = .unchanged
      }
      return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      guard let field = notification.object as? NSTextField, field === nameField else { return }

      commitNameIfNeeded(field)
    }

    private func commitNameIfNeeded(_ sender: NSTextField) {
      guard let target else { return }
      guard nameEditState == .changed || !nameFieldPresentation.matches(sender.stringValue) else {
        return
      }

      // Blank means unnamed; surrounding whitespace never becomes a name.
      let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = trimmed.isEmpty ? nil : trimmed
      nameEditState = .unchanged
      attemptEdit { try target.renameSelection(name) }

      // Model state wins after rejected, duplicate, or observer-driven edits.
      refreshNameField(for: target.selectedElements)
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

      view = scrollingPaletteBody(stack)
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

  /// Wraps a palette's document stack in a vertically scrolling body, which
  /// keeps every labeled entry reachable inside a fixed-size palette.
  ///
  /// The stack matches the clip view's width so it only scrolls vertically; its
  /// height stays intrinsic, which is what lets it grow past the viewport. The
  /// scroll view contributes no height of its own, so a palette's declared
  /// content size is what has to size the container — see
  /// ``PaletteDefinition/applyContentSizing(to:)``.
  @MainActor
  func scrollingPaletteBody(_ stack: NSStackView) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    // The popover and the panel supply their own backing; a second opaque
    // rectangle inside them only fights their material.
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.documentView = stack

    stack.translatesAutoresizingMaskIntoConstraints = false
    let clipView = scrollView.contentView
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: clipView.topAnchor),
      stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
      stack.widthAnchor.constraint(equalTo: clipView.widthAnchor),
    ])

    return scrollView
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

  enum InspectorMetrics {
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

  extension ElementContent {
    fileprivate var supportsFill: Bool {
      switch self {
      case .shape, .path: true
      case .text, .image, .group, .connector: false
      }
    }

    /// An image takes a border even though it takes no fill.
    fileprivate var supportsStroke: Bool {
      switch self {
      case .shape, .path, .image, .connector: true
      case .text, .group: false
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
    var subviewsRecursive: [NSView] {
      subviews + subviews.flatMap(\.subviewsRecursive)
    }
  }
#endif
