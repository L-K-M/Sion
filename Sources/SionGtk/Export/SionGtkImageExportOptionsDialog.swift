import CGtk
import CSionGtkShim
import Foundation

/// Format, scale, and background controls for "Export Image…". GTK's file
/// dialog takes no accessory view, so the options are asked first and the
/// file chooser follows with the matching type and suggested name.
@MainActor
package enum SionGtkImageExportOptionsDialog {
  /// Presents the options; `completion` receives nil when cancelled.
  package static func present(
    initial options: SionImageExportOptions,
    parent: UnsafeMutablePointer<GtkWidget>?,
    completion: @escaping @MainActor (SionImageExportOptions?) -> Void
  ) {
    let controls = SionGtkImageExportOptionsView(options: options)
    let dialog = adw_alert_dialog_new("Export Image", nil)!
    adw_alert_dialog_set_extra_child(dialog.cast(), controls.widget)
    adw_alert_dialog_add_response(dialog.cast(), "cancel", "Cancel")
    adw_alert_dialog_add_response(dialog.cast(), "export", "Export…")
    adw_alert_dialog_set_response_appearance(dialog.cast(), "export", ADW_RESPONSE_SUGGESTED)
    adw_alert_dialog_set_default_response(dialog.cast(), "export")
    adw_alert_dialog_set_close_response(dialog.cast(), "cancel")
    Signals.connect(dialog.gobject, "response") { response in
      let id = response.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
      completion(id == "export" ? controls.options : nil)
    }
    adw_dialog_present(dialog, parent)
  }
}

/// The controls themselves, mirroring `SionImageExportAccessoryView`: the
/// dialog owns presentation; this view only reports chosen options.
@MainActor
package final class SionGtkImageExportOptionsView {
  package let widget: UnsafeMutablePointer<GtkWidget>
  package var onChange: (@MainActor (SionImageExportOptions) -> Void)?
  package private(set) var options: SionImageExportOptions

  private let formatDropDown: UnsafeMutablePointer<GtkWidget>
  private let scaleDropDown: UnsafeMutablePointer<GtkWidget>
  private let transparencyButton: UnsafeMutablePointer<GtkWidget>
  private var isSynchronizing = false

  package init(options: SionImageExportOptions) {
    self.options = options
    formatDropDown = Self.makeDropDown(
      SionImageExportFormat.allCases.map(\.title), selected: options.format.rawValue,
      label: "Export format")
    scaleDropDown = Self.makeDropDown(
      SionImageExportScale.allCases.map(\.title), selected: options.scale.rawValue,
      label: "Export scale")
    transparencyButton = gtk_check_button_new_with_label("Transparent Background")!
    gtk_check_button_set_active(transparencyButton.cast(), options.hasTransparentBackground ? 1 : 0)
    sion_accessible_set_label(transparencyButton.opaque, "Transparent background")

    let grid = gtk_grid_new()!
    gtk_grid_set_row_spacing(grid.cast(), 8)
    gtk_grid_set_column_spacing(grid.cast(), 8)
    gtk_grid_attach(grid.cast(), Self.makeLabel("Format:"), 0, 0, 1, 1)
    gtk_grid_attach(grid.cast(), formatDropDown, 1, 0, 1, 1)
    gtk_grid_attach(grid.cast(), Self.makeLabel("Scale:"), 0, 1, 1, 1)
    gtk_grid_attach(grid.cast(), scaleDropDown, 1, 1, 1, 1)
    gtk_grid_attach(grid.cast(), transparencyButton, 0, 2, 2, 1)
    gtk_widget_set_margin_top(grid, 8)
    widget = grid

    Signals.connect(formatDropDown.gobject, "notify::selected") { [weak self] _ in
      self?.controlChanged()
    }
    Signals.connect(scaleDropDown.gobject, "notify::selected") { [weak self] _ in
      self?.controlChanged()
    }
    Signals.connect(transparencyButton.gobject, "toggled") { [weak self] in
      self?.controlChanged()
    }
    synchronizeEnabledState()
  }

  /// Applies a control change and reports the resulting options.
  package func controlChanged() {
    guard !isSynchronizing else { return }
    options.format =
      SionImageExportFormat(rawValue: Int(gtk_drop_down_get_selected(formatDropDown.opaque)))
      ?? options.format
    options.scale =
      SionImageExportScale(rawValue: Int(gtk_drop_down_get_selected(scaleDropDown.opaque)))
      ?? options.scale
    options.hasTransparentBackground = gtk_check_button_get_active(transparencyButton.cast()) != 0
    synchronizeEnabledState()
    onChange?(options)
  }

  /// Programmatic selection, for tests and for restoring a previous choice.
  package func select(
    format: SionImageExportFormat? = nil, scale: SionImageExportScale? = nil,
    transparent: Bool? = nil
  ) {
    isSynchronizing = true
    if let format {
      gtk_drop_down_set_selected(formatDropDown.opaque, UInt32(format.rawValue))
    }
    if let scale {
      gtk_drop_down_set_selected(scaleDropDown.opaque, UInt32(scale.rawValue))
    }
    if let transparent {
      gtk_check_button_set_active(transparencyButton.cast(), transparent ? 1 : 0)
    }
    isSynchronizing = false
    controlChanged()
  }

  package var isScaleEnabled: Bool { gtk_widget_get_sensitive(scaleDropDown) != 0 }
  package var isTransparencyEnabled: Bool { gtk_widget_get_sensitive(transparencyButton) != 0 }

  /// Vector output ignores scale, and a format without alpha stays opaque.
  private func synchronizeEnabledState() {
    gtk_widget_set_sensitive(scaleDropDown, options.format.supportsScale ? 1 : 0)
    gtk_widget_set_sensitive(transparencyButton, options.format.supportsTransparency ? 1 : 0)
  }

  private static func makeDropDown(_ titles: [String], selected: Int, label: String)
    -> UnsafeMutablePointer<GtkWidget>
  {
    var cTitles: [UnsafePointer<CChar>?] = titles.map { UnsafePointer(strdup($0)) } + [nil]
    defer {
      for title in cTitles {
        free(UnsafeMutablePointer(mutating: title))
      }
    }
    let list = cTitles.withUnsafeMutableBufferPointer { gtk_string_list_new($0.baseAddress) }
    let dropDown = gtk_drop_down_new(list, nil)!
    gtk_drop_down_set_selected(dropDown.opaque, UInt32(selected))
    sion_accessible_set_label(dropDown.opaque, label)
    return dropDown
  }

  private static func makeLabel(_ title: String) -> UnsafeMutablePointer<GtkWidget> {
    let label = gtk_label_new(title)!
    gtk_label_set_xalign(label.opaque, 1)
    gtk_widget_add_css_class(label, "dim-label")
    return label
  }
}
