import CGtk
import Foundation

/// Turns the shared menu tree into `GMenu` models. Separators become sections,
/// which is how `GMenu` draws them; dynamic sections are handed back so their
/// owner can fill them at display time.
@MainActor
enum SionGtkMenuBuilder {
  struct Result {
    let menu: OpaquePointer
    var dynamicSections: [SionGtkDynamicMenuSection: OpaquePointer] = [:]
    /// The section whose first item is Undo, so its titles can follow the
    /// front document.
    var undoSection: OpaquePointer?

    var model: UnsafeMutablePointer<GMenuModel> {
      UnsafeMutablePointer<GMenuModel>(menu)
    }
  }

  static func build(_ entries: [SionGtkMenuEntry]) -> Result {
    var result = Result(menu: g_menu_new()!)
    append(entries, to: result.menu, result: &result)
    return result
  }

  private static func append(
    _ entries: [SionGtkMenuEntry], to menu: OpaquePointer, result: inout Result
  ) {
    var section = g_menu_new()!
    var sectionStartsWithUndo = false

    func flush(_ result: inout Result) {
      if g_menu_model_get_n_items(UnsafeMutablePointer<GMenuModel>(section)) > 0 {
        g_menu_append_section(menu, nil, UnsafeMutablePointer<GMenuModel>(section))
        if sectionStartsWithUndo {
          result.undoSection = section
        }
      }
      g_object_unref(section.gobject)
      section = g_menu_new()!
      sectionStartsWithUndo = false
    }

    for entry in entries {
      switch entry {
      case .separator:
        flush(&result)
      case .command(let command):
        if command == .undo,
          g_menu_model_get_n_items(UnsafeMutablePointer<GMenuModel>(section)) == 0
        {
          sectionStartsWithUndo = true
        }
        g_menu_append(section, command.title, command.actionName)
      case .submenu(let title, let children):
        let submenu = g_menu_new()!
        append(children, to: submenu, result: &result)
        g_menu_append_submenu(section, title, UnsafeMutablePointer<GMenuModel>(submenu))
        g_object_unref(submenu.gobject)
      case .dynamicSection(let dynamic):
        let dynamicMenu = g_menu_new()!
        g_menu_append_section(section, nil, UnsafeMutablePointer<GMenuModel>(dynamicMenu))
        result.dynamicSections[dynamic] = dynamicMenu
      }
    }
    flush(&result)
    g_object_unref(section.gobject)
  }
}
