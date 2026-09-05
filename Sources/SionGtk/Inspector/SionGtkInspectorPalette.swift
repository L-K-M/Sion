import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// The Inspector: name, lock, fill, stroke, shadow, connector route, and
/// connector anchors of the selection, mirroring `InspectorPaletteController`.
/// Every control shows model state and sends one semantic command.
@MainActor
final class SionGtkInspectorPalette: SionGtkPaletteContent {
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

  let widget: UnsafeMutablePointer<GtkWidget>

  private weak var target: SionEditorController?
  private var observerID: UUID?
  private var presentation: SionGtkPalettePresentation?
  private var nameFieldPresentation = NameFieldPresentation.noSelection
  private var nameEditState = NameEditState.unchanged
  private var isRefreshing = false
  private let showAsPanel: @MainActor () -> Void

  private let stack = paletteStack()
  let selectionLabel = gtk_label_new("No selection")!
  let nameField = gtk_entry_new()!
  let lockButton = gtk_check_button_new_with_label("Locked")!
  let fillColorWell: UnsafeMutablePointer<GtkWidget>
  private let strokeColorWell: UnsafeMutablePointer<GtkWidget>
  let strokeWidthSlider: UnsafeMutablePointer<GtkWidget>
  private let shadowButton = gtk_check_button_new_with_label("Drop Shadow")!
  private let shadowColorWell: UnsafeMutablePointer<GtkWidget>
  private let shadowBlurSlider: UnsafeMutablePointer<GtkWidget>
  private let routePopup: UnsafeMutablePointer<GtkWidget>
  let magnetPopup: UnsafeMutablePointer<GtkWidget>
  let anchorEditingControls = gtk_box_new(
    GTK_ORIENTATION_VERTICAL, InspectorMetrics.spacing)!
  private let anchorEditingDoneButton = gtk_button_new_with_label(AnchorEditingCopy.doneTitle)!
  private var strokeSliderIsDragging = false
  private var blurSliderIsDragging = false

  init(showAsPanel: @escaping @MainActor () -> Void) {
    self.showAsPanel = showAsPanel
    fillColorWell = Self.makeColorWell(label: "Fill color")
    strokeColorWell = Self.makeColorWell(label: "Stroke color")
    strokeWidthSlider = gtk_scale_new_with_range(
      GTK_ORIENTATION_HORIZONTAL, InspectorMetrics.minimumStrokeWidth,
      InspectorMetrics.maximumStrokeWidth, 0.5)!
    shadowColorWell = Self.makeColorWell(label: "Drop shadow color")
    shadowBlurSlider = gtk_scale_new_with_range(
      GTK_ORIENTATION_HORIZONTAL, SionShadowDefaults.minimumBlurRadius,
      SionShadowDefaults.maximumBlurRadius, 1)!
    routePopup = Self.makeDropDown(
      ConnectorRoutingStyle.allCases.map(\.displayName), label: "Connector route")
    magnetPopup = Self.makeDropDown(MagnetOption.allCases.map(\.title), label: "Connector anchors")
    widget = scrollingPaletteBody(stack)

    configureControls()
    gtk_box_append(stack.cast(), selectionLabel)
    gtk_box_append(stack.cast(), paletteRow(label: "Name", control: nameField))
    gtk_box_append(stack.cast(), lockButton)
    gtk_box_append(stack.cast(), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
    gtk_box_append(stack.cast(), paletteRow(label: "Fill", control: fillColorWell))
    gtk_box_append(stack.cast(), paletteRow(label: "Stroke", control: strokeColorWell))
    gtk_box_append(stack.cast(), paletteRow(label: "Width", control: strokeWidthSlider))
    gtk_box_append(stack.cast(), shadowButton)
    gtk_box_append(stack.cast(), paletteRow(label: "Shadow", control: shadowColorWell))
    gtk_box_append(stack.cast(), paletteRow(label: "Blur", control: shadowBlurSlider))
    gtk_box_append(stack.cast(), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
    gtk_box_append(stack.cast(), paletteRow(label: "Route", control: routePopup))
    gtk_box_append(stack.cast(), paletteRow(label: "Connector anchors", control: magnetPopup))
    gtk_box_append(stack.cast(), anchorEditingControls)
    refresh()
  }

  func retarget(to host: SionGtkPaletteHost?) {
    let target = host?.paletteEditorController
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

  func paletteDidPresent(_ presentation: SionGtkPalettePresentation) {
    self.presentation = presentation
  }

  func paletteDidDismiss(_ presentation: SionGtkPalettePresentation) {
    if presentation == .panel {
      target?.endAnchorEditing()
    }

    if self.presentation == presentation {
      self.presentation = nil
    }
  }

  // MARK: Controls

  private func configureControls() {
    gtk_widget_add_css_class(selectionLabel, "heading")
    gtk_label_set_xalign(selectionLabel.opaque, 0)
    gtk_label_set_ellipsize(selectionLabel.opaque, PANGO_ELLIPSIZE_END)
    gtk_label_set_wrap(selectionLabel.opaque, 1)
    gtk_label_set_lines(selectionLabel.opaque, 2)

    sion_accessible_set_label(nameField.opaque, "Element name")
    Signals.connect(nameField.gobject, "activate") { [weak self] in
      self?.commitNameIfNeeded()
    }
    Signals.connect(nameField.gobject, "changed") { [weak self] in
      guard let self, !self.isRefreshing else { return }
      self.nameEditState = .changed
    }
    let nameFocus = gtk_event_controller_focus_new()!
    Signals.connect(nameFocus.gobject, "leave") { [weak self] in
      self?.commitNameIfNeeded()
    }
    gtk_widget_add_controller(nameField, nameFocus)
    let nameKeys = gtk_event_controller_key_new()!
    Signals.connectKey(nameKeys.gobject, "key-pressed") { [weak self] keyval, _, _ in
      // Escape reverts the field; dropping the pending edit keeps the cancel
      // from being committed when editing ends.
      guard let self, keyval == UInt32(GDK_KEY_Escape) else { return false }
      self.nameEditState = .unchanged
      self.presentNameField(self.nameFieldPresentation)
      return true
    }
    gtk_widget_add_controller(nameField, nameKeys)

    sion_accessible_set_label(lockButton.opaque, "Element lock")
    Signals.connect(lockButton.gobject, "toggled") { [weak self] in
      self?.changeLock()
    }

    Signals.connect(fillColorWell.gobject, "notify::rgba") { [weak self] _ in
      self?.changeFill()
    }
    Signals.connect(strokeColorWell.gobject, "notify::rgba") { [weak self] _ in
      self?.changeStrokeColor()
    }
    configureSlider(
      strokeWidthSlider, label: "Stroke width", marks: InspectorMetrics.strokeWidthTickCount,
      dragging: { [weak self] in self?.strokeSliderIsDragging ?? false },
      setDragging: { [weak self] in self?.strokeSliderIsDragging = $0 },
      commit: { [weak self] in self?.changeStrokeWidth() })

    gtk_widget_set_tooltip_text(shadowButton, "Cast a drop shadow behind this object.")
    sion_accessible_set_label(shadowButton.opaque, "Drop shadow")
    Signals.connect(shadowButton.gobject, "toggled") { [weak self] in
      self?.changeShadowEnabled()
    }
    Signals.connect(shadowColorWell.gobject, "notify::rgba") { [weak self] _ in
      self?.changeShadowColor()
    }
    configureSlider(
      shadowBlurSlider, label: "Drop shadow blur", marks: 0,
      dragging: { [weak self] in self?.blurSliderIsDragging ?? false },
      setDragging: { [weak self] in self?.blurSliderIsDragging = $0 },
      commit: { [weak self] in self?.changeShadowBlur() })

    Signals.connect(routePopup.gobject, "notify::selected") { [weak self] _ in
      self?.changeRoute()
    }
    gtk_widget_set_tooltip_text(
      magnetPopup, "Choose where connectors attach to the selected object.")
    Signals.connect(magnetPopup.gobject, "notify::selected") { [weak self] _ in
      self?.changeMagnets()
    }

    let instruction = gtk_label_new(AnchorEditingCopy.instruction)!
    gtk_widget_add_css_class(instruction, "dim-label")
    gtk_label_set_wrap(instruction.opaque, 1)
    gtk_label_set_xalign(instruction.opaque, 0)
    gtk_label_set_max_width_chars(instruction.opaque, 34)
    sion_accessible_set_label(anchorEditingDoneButton.opaque, "Finish editing connector anchors")
    gtk_widget_set_halign(anchorEditingDoneButton, GTK_ALIGN_START)
    Signals.connect(anchorEditingDoneButton.gobject, "clicked") { [weak self] in
      self?.target?.endAnchorEditing()
    }
    gtk_box_append(anchorEditingControls.cast(), instruction)
    gtk_box_append(anchorEditingControls.cast(), anchorEditingDoneButton)
    gtk_widget_set_visible(anchorEditingControls, 0)
  }

  /// Sliders commit once, on release, like a non-continuous `NSSlider`;
  /// keyboard changes commit at once.
  private func configureSlider(
    _ slider: UnsafeMutablePointer<GtkWidget>, label: String, marks: Int,
    dragging: @escaping @MainActor () -> Bool,
    setDragging: @escaping @MainActor (Bool) -> Void,
    commit: @escaping @MainActor () -> Void
  ) {
    sion_accessible_set_label(slider.opaque, label)
    gtk_scale_set_draw_value(slider.cast(), 0)
    gtk_widget_set_hexpand(slider, 1)
    if marks > 1 {
      var lower = 0.0
      var upper = 0.0
      let adjustment = gtk_range_get_adjustment(slider.cast())
      lower = gtk_adjustment_get_lower(adjustment)
      upper = gtk_adjustment_get_upper(adjustment)
      for index in 0..<marks {
        let value = lower + (upper - lower) * Double(index) / Double(marks - 1)
        gtk_scale_add_mark(slider.cast(), value, GTK_POS_BOTTOM, nil)
      }
    }
    let press = gtk_gesture_click_new()!
    gtk_event_controller_set_propagation_phase(press, GTK_PHASE_CAPTURE)
    Signals.connect(press.gobject, "pressed") { _, _, _ in setDragging(true) }
    Signals.connect(press.gobject, "released") { _, _, _ in
      setDragging(false)
      commit()
    }
    gtk_widget_add_controller(slider, press)
    Signals.connect(slider.gobject, "value-changed") { [weak self] in
      guard let self, !self.isRefreshing, !dragging() else { return }
      commit()
    }
  }

  private static func makeColorWell(label: String) -> UnsafeMutablePointer<GtkWidget> {
    let dialog = gtk_color_dialog_new()
    gtk_color_dialog_set_with_alpha(dialog, 1)
    let button = gtk_color_dialog_button_new(dialog)!
    sion_accessible_set_label(button.opaque, label)
    return button
  }

  private static func makeDropDown(_ titles: [String], label: String) -> UnsafeMutablePointer<
    GtkWidget
  > {
    var cTitles: [UnsafePointer<CChar>?] = titles.map { UnsafePointer(strdup($0)) } + [nil]
    defer {
      for title in cTitles {
        free(UnsafeMutablePointer(mutating: title))
      }
    }
    let list = cTitles.withUnsafeMutableBufferPointer { gtk_string_list_new($0.baseAddress) }
    let dropDown = gtk_drop_down_new(list, nil)!
    sion_accessible_set_label(dropDown.opaque, label)
    return dropDown
  }

  // MARK: Refresh

  private func refresh() {
    isRefreshing = true
    defer { isRefreshing = false }

    let selectedElements = target?.selectedElements ?? []
    refreshNameField(for: selectedElements)

    guard let element = target?.selectedElement else {
      let hasMultipleSelection = target?.selection.isEmpty == false
      gtk_label_set_text(
        selectionLabel.opaque, hasMultipleSelection ? "Multiple elements" : "No selection")
      gtk_check_button_set_inconsistent(lockButton.cast(), hasMultipleSelection ? 1 : 0)
      gtk_check_button_set_active(lockButton.cast(), 0)
      gtk_widget_set_sensitive(lockButton, 0)
      gtk_widget_set_tooltip_text(
        lockButton,
        hasMultipleSelection ? "Lock state cannot be changed for a mixed selection." : nil)
      gtk_widget_set_sensitive(routePopup, 0)
      gtk_widget_set_sensitive(magnetPopup, 0)
      gtk_widget_set_visible(anchorEditingControls, 0)
      gtk_widget_set_sensitive(fillColorWell, 0)
      gtk_widget_set_sensitive(strokeColorWell, 0)
      gtk_widget_set_sensitive(strokeWidthSlider, 0)
      clearShadowControls()
      return
    }

    let isEditable = element.lockState == .editable
    let name = element.name ?? element.displayName
    gtk_label_set_text(selectionLabel.opaque, isEditable ? name : "\(name) • Locked")
    gtk_check_button_set_inconsistent(lockButton.cast(), 0)
    gtk_check_button_set_active(lockButton.cast(), isEditable ? 0 : 1)
    gtk_widget_set_sensitive(lockButton, 1)
    gtk_widget_set_tooltip_text(
      lockButton,
      isEditable ? "Prevent changes to this element." : "Unlock this element to edit it.")
    gtk_widget_set_sensitive(fillColorWell, element.content.supportsFill && isEditable ? 1 : 0)
    gtk_widget_set_sensitive(strokeColorWell, element.content.supportsStroke && isEditable ? 1 : 0)
    gtk_widget_set_sensitive(
      strokeWidthSlider, element.content.supportsStroke && isEditable ? 1 : 0)
    setColor(fillColorWell, element.style.fill.solidColor ?? .clear)
    setColor(strokeColorWell, element.style.stroke?.color ?? .primaryInk)
    gtk_range_set_value(strokeWidthSlider.cast(), element.style.stroke?.width ?? 0)
    refreshShadowControls(for: element, isEditable: isEditable)

    let editsAnchors = target?.anchorEditingState == .editing(element.id) && isEditable
    gtk_widget_set_sensitive(
      magnetPopup, element.content.connector == nil && !editsAnchors && isEditable ? 1 : 0)
    gtk_widget_set_visible(anchorEditingControls, editsAnchors ? 1 : 0)
    if editsAnchors {
      gtk_drop_down_set_selected(magnetPopup.opaque, UInt32(MagnetOption.custom.rawValue))
    } else {
      selectMagnetOption(for: element.magnetConfiguration)
    }

    guard let connector = element.content.connector else {
      gtk_widget_set_sensitive(routePopup, 0)
      return
    }

    gtk_widget_set_sensitive(routePopup, isEditable ? 1 : 0)
    if let index = ConnectorRoutingStyle.allCases.firstIndex(of: connector.routingStyle) {
      gtk_drop_down_set_selected(routePopup.opaque, UInt32(index))
    }
  }

  private func refreshNameField(for elements: [SceneElement]) {
    gtk_widget_set_sensitive(nameField, target?.canRenameSelection == true ? 1 : 0)

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
    let wasRefreshing = isRefreshing
    isRefreshing = true
    defer { isRefreshing = wasRefreshing }
    nameFieldPresentation = presentation
    nameEditState = .unchanged

    switch presentation {
    case .noSelection:
      gtk_editable_set_text(nameField.opaque, "")
      gtk_entry_set_placeholder_text(nameField.cast(), nil)
    case .value(let name):
      gtk_editable_set_text(nameField.opaque, name)
      gtk_entry_set_placeholder_text(nameField.cast(), nil)
    case .mixed:
      gtk_editable_set_text(nameField.opaque, "")
      gtk_entry_set_placeholder_text(nameField.cast(), InspectorCopy.mixedValue)
    }
  }

  /// The colour and blur controls only mean something once a shadow exists.
  /// Content that does not take a shadow but arrived carrying one keeps a
  /// live checkbox so the shadow can be switched off.
  private func refreshShadowControls(for element: SceneElement, isEditable: Bool) {
    let supportsShadow = element.content.supportsShadow && isEditable
    let shadow = element.style.shadows.first
    gtk_widget_set_sensitive(shadowButton, supportsShadow || (isEditable && shadow != nil) ? 1 : 0)
    gtk_check_button_set_active(shadowButton.cast(), shadow == nil ? 0 : 1)
    gtk_widget_set_sensitive(shadowColorWell, supportsShadow && shadow != nil ? 1 : 0)
    gtk_widget_set_sensitive(shadowBlurSlider, supportsShadow && shadow != nil ? 1 : 0)
    setColor(shadowColorWell, shadow?.color ?? SionShadowDefaults.style.color)
    // A document can carry a blur the inspector's range does not reach;
    // clamping it here would silently shrink it on the first drag.
    let blurRadius = shadow?.blurRadius ?? SionShadowDefaults.style.blurRadius
    gtk_range_set_range(
      shadowBlurSlider.cast(), SionShadowDefaults.minimumBlurRadius,
      max(SionShadowDefaults.maximumBlurRadius, blurRadius))
    gtk_range_set_value(shadowBlurSlider.cast(), blurRadius)
  }

  private func clearShadowControls() {
    gtk_widget_set_sensitive(shadowButton, 0)
    gtk_check_button_set_active(shadowButton.cast(), 0)
    gtk_widget_set_sensitive(shadowColorWell, 0)
    gtk_widget_set_sensitive(shadowBlurSlider, 0)
  }

  private func setColor(_ well: UnsafeMutablePointer<GtkWidget>, _ color: SionColor) {
    var rgba = SionGtkColorBridge.rgba(color)
    gtk_color_dialog_button_set_rgba(well.opaque, &rgba)
  }

  private func color(of well: UnsafeMutablePointer<GtkWidget>) -> SionColor {
    guard let rgba = gtk_color_dialog_button_get_rgba(well.opaque) else { return .black }
    return SionGtkColorBridge.modelColor(rgba.pointee)
  }

  // MARK: Commands

  private func changeShadowEnabled() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }

    let enabled = gtk_check_button_get_active(shadowButton.cast()) != 0
    attemptEdit { try target.setShadowEnabled(enabled, on: id) }
  }

  private func changeShadowColor() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }

    attemptEdit { try target.setShadowColor(color(of: shadowColorWell), on: id) }
  }

  private func changeShadowBlur() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }

    attemptEdit {
      try target.setShadowBlurRadius(gtk_range_get_value(shadowBlurSlider.cast()), on: id)
    }
  }

  private func changeLock() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }

    let lockState =
      gtk_check_button_get_active(lockButton.cast()) != 0 ? ElementLockState.locked : .editable
    if lockState == .locked {
      target.endAnchorEditing()
    }

    attemptEdit { try target.setLockState(lockState, on: id) }
  }

  func commitNameIfNeeded() {
    guard let target else { return }
    let value = String(gtkString: gtk_editable_get_text(nameField.opaque)) ?? ""
    guard nameEditState == .changed || !nameFieldPresentation.matches(value) else { return }

    // Blank means unnamed; surrounding whitespace never becomes a name.
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = trimmed.isEmpty ? nil : trimmed
    nameEditState = .unchanged
    attemptEdit { try target.renameSelection(name) }

    // Model state wins after rejected, duplicate, or observer-driven edits.
    refreshNameField(for: target.selectedElements)
  }

  private func changeRoute() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }
    let index = Int(gtk_drop_down_get_selected(routePopup.opaque))
    guard ConnectorRoutingStyle.allCases.indices.contains(index) else { return }

    attemptEdit { try target.setRoutingStyle(ConnectorRoutingStyle.allCases[index], on: id) }
  }

  private func changeFill() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }

    attemptEdit { try target.setFillColor(color(of: fillColorWell), on: id) }
  }

  private func changeStrokeColor() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }

    attemptEdit { try target.setStrokeColor(color(of: strokeColorWell), on: id) }
  }

  private func changeStrokeWidth() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id else { return }

    attemptEdit { try target.setStrokeWidth(gtk_range_get_value(strokeWidthSlider.cast()), on: id) }
  }

  private func changeMagnets() {
    guard !isRefreshing, let target, let id = target.selectedElement?.id,
      let option = MagnetOption(rawValue: Int(gtk_drop_down_get_selected(magnetPopup.opaque)))
    else {
      return
    }

    if option == .custom {
      target.beginAnchorEditing(on: id)
      showAsPanel()
      return
    }

    guard let preset = option.preset else { return }

    target.endAnchorEditing()
    attemptEdit { try target.setMagnetConfiguration(.preset(preset), on: id) }
  }

  private func selectMagnetOption(for configuration: MagnetConfiguration) {
    if case .custom = configuration {
      gtk_drop_down_set_selected(magnetPopup.opaque, UInt32(MagnetOption.custom.rawValue))
      return
    }

    guard case .preset(let preset) = configuration, let option = MagnetOption(preset: preset) else {
      gtk_drop_down_set_selected(magnetPopup.opaque, GTK_INVALID_LIST_POSITION)
      return
    }

    gtk_drop_down_set_selected(magnetPopup.opaque, UInt32(option.rawValue))
  }

  /// Rejected semantic edits must leave every control showing model state.
  private func attemptEdit(_ action: () throws -> Void) {
    do {
      try action()
    } catch {
      gdk_display_beep(gdk_display_get_default())
      refresh()
    }
  }
}

enum MagnetOption: Int, CaseIterable {
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

private enum InspectorCopy {
  static let mixedValue = "Mixed"
}

enum AnchorEditingCopy {
  static let customOptionTitle = "Custom points…"
  static let instruction = "Click the object to add an anchor; click an anchor to remove it."
  static let doneTitle = "Done"
}

extension ConnectorRoutingStyle {
  var displayName: String {
    switch self {
    case .straight: "Straight"
    case .curved: "Curved"
    case .orthogonal: "Orthogonal"
    case .bezier: "Bézier"
    }
  }
}

extension ElementContent {
  var supportsFill: Bool {
    switch self {
    case .shape, .path: true
    case .text, .image, .group, .connector: false
    }
  }

  /// An image takes a border even though it takes no fill.
  var supportsStroke: Bool {
    switch self {
    case .shape, .path, .image, .connector: true
    case .text, .group: false
    }
  }
}

extension FillStyle {
  var solidColor: SionColor? {
    guard case .solid(let color) = self else { return nil }

    return color
  }
}

/// Seams the tests drive the controls through.
extension SionGtkInspectorPalette {
  var selectionText: String {
    String(gtkString: gtk_label_get_text(selectionLabel.opaque)) ?? ""
  }

  var isLockEnabled: Bool { gtk_widget_get_sensitive(lockButton) != 0 }
  var isFillEnabled: Bool { gtk_widget_get_sensitive(fillColorWell) != 0 }
  var isAnchorEditingVisible: Bool { gtk_widget_get_visible(anchorEditingControls) != 0 }

  func setStrokeWidthForTesting(_ width: Double) {
    gtk_range_set_value(strokeWidthSlider.cast(), width)
  }

  func setLockedForTesting(_ locked: Bool) {
    gtk_check_button_set_active(lockButton.cast(), locked ? 1 : 0)
  }

  func setNameForTesting(_ name: String) {
    gtk_editable_set_text(nameField.opaque, name)
    commitNameIfNeeded()
  }

  func selectMagnetOptionForTesting(_ option: MagnetOption) {
    gtk_drop_down_set_selected(magnetPopup.opaque, UInt32(option.rawValue))
  }
}
