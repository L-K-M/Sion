import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// Bootstraps the GTK application: one process, one `AdwApplication`, one
/// document controller, and the menu bar every document window shows.
public enum SionGtkApplication {
  public static let applicationID = "ch.lkmc.Sion"

  public static func run(arguments: [String]) -> Int32 {
    guard let application = adw_application_new(applicationID, G_APPLICATION_HANDLES_OPEN) else {
      return 1
    }
    defer { g_object_unref(application) }

    let coordinator = MainActor.assumeIsolated {
      SionGtkApplicationCoordinator(application: application.cast())
    }
    MainActor.assumeIsolated {
      Signals.connect(application.gobject, "startup") { coordinator.startup() }
      Signals.connect(application.gobject, "activate") { coordinator.activate() }
    }
    let open:
      @convention(c) (
        UnsafeMutablePointer<GApplication>?, UnsafeMutablePointer<OpaquePointer?>?, gint,
        UnsafePointer<gchar>?, gpointer?
      ) -> Void = { _, files, count, _, data in
        guard let files, let data else { return }
        let coordinator = Unmanaged<SionGtkApplicationCoordinator>.fromOpaque(data)
          .takeUnretainedValue()
        var urls: [URL] = []
        for index in 0..<Int(count) {
          guard let file = files[index],
            let path = String(takingOwnershipOf: g_file_get_path(file))
          else {
            continue
          }
          urls.append(URL(fileURLWithPath: path))
        }
        MainActor.assumeIsolated { coordinator.open(urls) }
      }
    _ = sion_signal_connect(
      application.gobject, "open", unsafeBitCast(open, to: GCallback.self),
      Unmanaged.passUnretained(coordinator).toOpaque(), nil, 0)

    var cArguments = arguments.map { strdup($0) }
    defer {
      for argument in cArguments {
        free(argument)
      }
    }
    return g_application_run(application.cast(), Int32(cArguments.count), &cArguments)
  }
}

/// The application delegate: menus, application-wide actions, accelerators,
/// and the lifecycle rules `SionApplicationDelegate` implements on macOS.
@MainActor
final class SionGtkApplicationCoordinator {
  let application: UnsafeMutablePointer<GtkApplication>
  let documentController: SionGtkDocumentController

  private var menu: OpaquePointer?
  private var recentSection: OpaquePointer?
  private var windowsSection: OpaquePointer?
  private var undoSection: OpaquePointer?
  private var windowMenuTargets: [String: SionGtkDocument] = [:]

  init(application: UnsafeMutablePointer<GtkApplication>) {
    self.application = application
    documentController = SionGtkDocumentController(application: application)
  }

  func startup() {
    DispatchMainQueueBridge.install()
    buildMenu()
    installActions()
    installAccelerators()

    documentController.menuModel = menu.map { UnsafeMutablePointer<GMenuModel>($0) }
    documentController.updateUndoTitles = { [weak self] undo, redo in
      self?.setUndoTitles(undo: undo, redo: redo)
    }
    documentController.onDocumentsChange = { [weak self] in
      self?.rebuildWindowsSection()
    }
    documentController.recentDocuments.observeChanges { [weak self] in
      self?.rebuildRecentSection()
    }
    SionGtkPaletteCenter.shared.frontHost = { [weak self] in
      self?.documentController.frontWindow
    }
    rebuildRecentSection()
  }

  /// Launching with nothing to open shows an untitled drawing.
  func activate() {
    if documentController.documents.isEmpty {
      documentController.newDocument()
    } else {
      documentController.frontWindow?.present()
    }
  }

  func open(_ urls: [URL]) {
    for url in urls {
      if url.pathExtension.lowercased() == SionGtkDocument.filenameExtension {
        documentController.openDocument(at: url)
      } else if SionMermaidFile.fileExtensions.contains(url.pathExtension.lowercased()) {
        documentController.openMermaidDocument(at: url)
      } else {
        documentController.openDocument(at: url)
      }
    }
    if documentController.documents.isEmpty {
      documentController.newDocument()
    }
  }

  // MARK: Actions

  private func installActions() {
    let map = OpaquePointer(application)
    for command in SionGtkCommand.allCases where command.scope == .application {
      guard let action = g_simple_action_new(command.rawValue, nil) else { continue }
      Signals.connect(action.gobject, "activate") { [weak self] _ in
        self?.perform(command)
      }
      g_action_map_add_action(map, action)
    }

    let stringType = g_variant_type_new("s")
    defer { g_variant_type_free(stringType) }
    if let openRecent = g_simple_action_new("openRecent", stringType) {
      Signals.connect(openRecent.gobject, "activate") { [weak self] parameter in
        guard let parameter,
          let path = String(gtkString: g_variant_get_string(OpaquePointer(parameter), nil))
        else {
          return
        }
        self?.documentController.openRecentDocument(at: URL(fileURLWithPath: path))
      }
      g_action_map_add_action(map, openRecent)
    }
    if let activateWindow = g_simple_action_new("activateWindow", stringType) {
      Signals.connect(activateWindow.gobject, "activate") { [weak self] parameter in
        guard let self, let parameter,
          let key = String(gtkString: g_variant_get_string(OpaquePointer(parameter), nil)),
          let document = self.windowMenuTargets[key]
        else {
          return
        }
        self.documentController.window(for: document)?.present()
      }
      g_action_map_add_action(map, activateWindow)
    }
  }

  private func perform(_ command: SionGtkCommand) {
    switch command {
    case .newDocument:
      documentController.newDocument()
    case .newDocumentFromMermaid:
      SionGtkDialogs.open(
        title: MermaidFileCopy.message,
        acceptLabel: MermaidFileCopy.prompt,
        filters: [SionGtkDocument.mermaidFilter],
        parent: documentController.frontWindow?.toplevel
      ) { [weak self] url in
        guard let url else { return }
        self?.documentController.openMermaidDocument(at: url)
      }
    case .open:
      SionGtkDialogs.open(
        title: "Open",
        filters: [SionGtkDocument.fileFilter],
        parent: documentController.frontWindow?.toplevel
      ) { [weak self] url in
        guard let url else { return }
        self?.documentController.openDocument(at: url)
      }
    case .clearRecentDocuments:
      documentController.clearRecentDocuments()
    case .about:
      presentAbout()
    case .help:
      gtk_show_uri(
        documentController.frontWindow?.toplevel, SionGtkResources.helpIndexURL.absoluteString, 0)
    case .quit:
      documentController.terminate { [weak self] allowed in
        guard allowed, let self else { return }
        g_application_quit(self.application.cast())
      }
    default:
      break
    }
  }

  private func installAccelerators() {
    for command in SionGtkCommand.allCases {
      let accelerators = command.accelerators
      guard !accelerators.isEmpty else { continue }
      sion_application_set_accels(
        application, command.actionName, accelerators[0],
        accelerators.count > 1 ? accelerators[1] : nil,
        accelerators.count > 2 ? accelerators[2] : nil)
    }
  }

  private func presentAbout() {
    let dialog = adw_about_dialog_new()!
    adw_about_dialog_set_application_name(dialog.opaque, "Sion")
    adw_about_dialog_set_application_icon(dialog.opaque, SionGtkApplication.applicationID)
    adw_about_dialog_set_version(dialog.opaque, SionGtkResources.versionString)
    adw_about_dialog_set_developer_name(dialog.opaque, "L-K-M")
    adw_about_dialog_set_comments(dialog.opaque, "Native diagramming and digital illustration")
    adw_about_dialog_set_website(dialog.opaque, "https://github.com/L-K-M/Sion")
    adw_about_dialog_set_issue_url(dialog.opaque, "https://github.com/L-K-M/Sion/issues")
    adw_about_dialog_set_license_type(dialog.opaque, GTK_LICENSE_CUSTOM)
    adw_about_dialog_set_license(
      dialog.opaque,
      "Sion is free and unencumbered software released into the public domain under the "
        + "Unlicense. See https://unlicense.org.")
    adw_dialog_present(dialog.cast(), documentController.frontWindow?.window)
  }

  // MARK: Menus

  private func buildMenu() {
    let root = g_menu_new()!
    for entry in SionGtkMenuTree.menuBar {
      append(entry, to: root)
    }
    menu = root
  }

  /// Separators become sections, which is how `GMenu` draws them.
  private func append(_ entries: [SionGtkMenuEntry], to menu: OpaquePointer) {
    var section = g_menu_new()!
    var sectionStartsWithUndo = false
    func flush() {
      if g_menu_model_get_n_items(UnsafeMutablePointer<GMenuModel>(section)) > 0 {
        g_menu_append_section(menu, nil, UnsafeMutablePointer<GMenuModel>(section))
        if sectionStartsWithUndo {
          undoSection = section
        }
      } else {
        g_object_unref(section.gobject)
      }
      section = g_menu_new()!
      sectionStartsWithUndo = false
    }
    for entry in entries {
      switch entry {
      case .separator:
        flush()
      case .command(let command):
        if g_menu_model_get_n_items(UnsafeMutablePointer<GMenuModel>(section)) == 0,
          command == .undo
        {
          sectionStartsWithUndo = true
        }
        append(entry, to: section)
      case .submenu, .dynamicSection:
        append(entry, to: section)
      }
    }
    flush()
    g_object_unref(section.gobject)
  }

  private func append(_ entry: SionGtkMenuEntry, to menu: OpaquePointer) {
    switch entry {
    case .separator:
      break
    case .command(let command):
      g_menu_append(menu, command.title, command.actionName)
    case .submenu(let title, let entries):
      let submenu = g_menu_new()!
      append(entries, to: submenu)
      g_menu_append_submenu(menu, title, UnsafeMutablePointer<GMenuModel>(submenu))
      g_object_unref(submenu.gobject)
    case .dynamicSection(let dynamic):
      let section = g_menu_new()!
      g_menu_append_section(menu, nil, UnsafeMutablePointer<GMenuModel>(section))
      switch dynamic {
      case .recentDocuments: recentSection = section
      case .windows: windowsSection = section
      }
    }
  }

  private func rebuildRecentSection() {
    guard let recentSection else { return }
    g_menu_remove_all(recentSection)
    for url in documentController.recentDocumentURLs {
      let item = g_menu_item_new(url.lastPathComponent, nil)
      g_menu_item_set_action_and_target_value(
        item, "app.openRecent", g_variant_new_string(url.path))
      g_menu_append_item(recentSection, item)
      g_object_unref(item?.gobject)
    }
    if let action = g_action_map_lookup_action(OpaquePointer(application), "clearRecentDocuments") {
      g_simple_action_set_enabled(
        action, documentController.recentDocumentURLs.isEmpty ? 0 : 1)
    }
  }

  private func rebuildWindowsSection() {
    guard let windowsSection else { return }
    g_menu_remove_all(windowsSection)
    windowMenuTargets.removeAll()
    for (index, document) in documentController.documents.enumerated() {
      let key = "window-\(index)"
      windowMenuTargets[key] = document
      let item = g_menu_item_new(document.displayName, nil)
      g_menu_item_set_action_and_target_value(item, "app.activateWindow", g_variant_new_string(key))
      g_menu_append_item(windowsSection, item)
      g_object_unref(item?.gobject)
    }
  }

  private func setUndoTitles(undo: String, redo: String) {
    guard let undoSection else { return }
    g_menu_remove_all(undoSection)
    g_menu_append(undoSection, undo, SionGtkCommand.undo.actionName)
    g_menu_append(undoSection, redo, SionGtkCommand.redo.actionName)
  }
}
