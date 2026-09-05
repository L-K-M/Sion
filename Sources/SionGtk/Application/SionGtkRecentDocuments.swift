import CGtk
import CSionGtkShim
import Foundation

/// The Open Recent list, backed by the desktop's shared recent-files store so
/// files opened here also appear in the file manager's history.
@MainActor
package final class SionGtkRecentDocuments {
  private static let applicationName = "sion"
  private static let maximumCount = 10

  private let manager: UnsafeMutablePointer<GtkRecentManager>
  private var changeHandlers: [UUID: @MainActor () -> Void] = [:]

  package init() {
    manager = gtk_recent_manager_get_default()!
    Signals.connect(manager.gobject, "changed") { [weak self] in
      guard let self else { return }
      for handler in self.changeHandlers.values {
        handler()
      }
    }
  }

  /// The most recent Sion drawings first, limited like the macOS menu.
  package var urls: [URL] {
    guard let list = gtk_recent_manager_get_items(manager) else { return [] }
    defer { g_list_free(list) }

    var entries: [(url: URL, modified: Int)] = []
    for item in list.elements {
      let info = OpaquePointer(item)
      defer { gtk_recent_info_unref(info) }
      guard gtk_recent_info_has_application(info, Self.applicationName) != 0,
        gtk_recent_info_exists(info) != 0,
        let uri = String(gtkString: gtk_recent_info_get_uri(info)),
        let url = URL(string: uri), url.isFileURL
      else {
        continue
      }
      let modified = g_date_time_to_unix(gtk_recent_info_get_modified(info))
      entries.append((url, modified))
    }
    return entries.sorted { $0.modified > $1.modified }.prefix(Self.maximumCount).map(\.url)
  }

  package func noteOpened(_ url: URL) {
    var data = GtkRecentData()
    let displayName = strdup(url.lastPathComponent)
    let mimeType = strdup(SionGtkDocument.mimeType)
    let appName = strdup(Self.applicationName)
    let appExec = strdup("sion %u")
    defer {
      free(displayName)
      free(mimeType)
      free(appName)
      free(appExec)
    }
    data.display_name = displayName
    data.mime_type = mimeType
    data.app_name = appName
    data.app_exec = appExec
    data.is_private = 0
    gtk_recent_manager_add_full(manager, url.absoluteString, &data)
  }

  /// Forgets Sion's own entries; other applications' history is untouched.
  package func clear() {
    for url in urls {
      gtk_recent_manager_remove_item(manager, url.absoluteString, nil)
    }
  }

  @discardableResult
  package func observeChanges(_ handler: @escaping @MainActor () -> Void) -> UUID {
    let id = UUID()
    changeHandlers[id] = handler
    return id
  }

  package func removeObserver(_ id: UUID) {
    changeHandlers[id] = nil
  }
}
