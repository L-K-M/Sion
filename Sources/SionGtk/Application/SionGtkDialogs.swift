import CGtk
import CSionGtkShim
import Foundation

/// Alerts and file choosers shared by the application and its documents.
@MainActor
package enum SionGtkDialogs {
  /// A response the caller identifies by its position in `responses`.
  package struct Response {
    package enum Appearance {
      case `default`
      case suggested
      case destructive
    }

    package let label: String
    package let appearance: Appearance

    package init(_ label: String, appearance: Appearance = .default) {
      self.label = label
      self.appearance = appearance
    }
  }

  /// Presents a modal alert and reports the index of the chosen response.
  /// Closing the dialog reports `closeResponse`.
  package static func alert(
    heading: String,
    body: String?,
    responses: [Response],
    defaultResponse: Int? = nil,
    closeResponse: Int = 0,
    parent: UnsafeMutablePointer<GtkWidget>?,
    completion: @escaping @MainActor (Int) -> Void
  ) {
    let dialog = adw_alert_dialog_new(heading, body)!
    for (index, response) in responses.enumerated() {
      let id = "response-\(index)"
      adw_alert_dialog_add_response(dialog.cast(), id, response.label)
      switch response.appearance {
      case .default:
        break
      case .suggested:
        adw_alert_dialog_set_response_appearance(dialog.cast(), id, ADW_RESPONSE_SUGGESTED)
      case .destructive:
        adw_alert_dialog_set_response_appearance(dialog.cast(), id, ADW_RESPONSE_DESTRUCTIVE)
      }
    }
    if let defaultResponse, responses.indices.contains(defaultResponse) {
      adw_alert_dialog_set_default_response(dialog.cast(), "response-\(defaultResponse)")
    }
    if responses.indices.contains(closeResponse) {
      adw_alert_dialog_set_close_response(dialog.cast(), "response-\(closeResponse)")
    }
    Signals.connect(dialog.gobject, "response") { response in
      let id = response.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
      let index = Int(id.dropFirst("response-".count)) ?? closeResponse
      completion(index)
    }
    adw_dialog_present(dialog, parent)
  }

  /// Presents an error the way `NSDocument.presentError` does: the description
  /// as the heading and the recovery suggestion as the body.
  package static func presentError(_ error: Error, parent: UnsafeMutablePointer<GtkWidget>?) {
    let localized = error as? LocalizedError
    let heading = localized?.errorDescription ?? error.localizedDescription
    let body = localized?.recoverySuggestion
    alert(
      heading: heading,
      body: body,
      responses: [Response("OK", appearance: .suggested)],
      defaultResponse: 0,
      parent: parent
    ) { _ in }
  }

  /// A file type the open and save dialogs offer.
  package struct FileFilter {
    package let name: String
    package let mimeTypes: [String]
    package let suffixes: [String]

    package init(name: String, mimeTypes: [String], suffixes: [String]) {
      self.name = name
      self.mimeTypes = mimeTypes
      self.suffixes = suffixes
    }
  }

  private static func filterList(_ filters: [FileFilter]) -> OpaquePointer? {
    guard !filters.isEmpty else { return nil }
    guard let store = g_list_store_new(gtk_file_filter_get_type()) else { return nil }
    for filter in filters {
      let gtkFilter = gtk_file_filter_new()
      gtk_file_filter_set_name(gtkFilter, filter.name)
      for mimeType in filter.mimeTypes {
        gtk_file_filter_add_mime_type(gtkFilter, mimeType)
      }
      for suffix in filter.suffixes {
        gtk_file_filter_add_suffix(gtkFilter, suffix)
      }
      g_list_store_append(store, gtkFilter?.gobject)
      g_object_unref(gtkFilter?.gobject)
    }
    return store
  }

  /// Runs a file-open dialog; `completion` receives nil when it was dismissed.
  package static func open(
    title: String,
    acceptLabel: String? = nil,
    filters: [FileFilter] = [],
    parent: UnsafeMutablePointer<GtkWindow>?,
    completion: @escaping @MainActor (URL?) -> Void
  ) {
    let dialog = gtk_file_dialog_new()
    gtk_file_dialog_set_title(dialog, title)
    gtk_file_dialog_set_modal(dialog, 1)
    if let acceptLabel {
      gtk_file_dialog_set_accept_label(dialog, acceptLabel)
    }
    if let list = filterList(filters) {
      gtk_file_dialog_set_filters(dialog, list)
      g_object_unref(list.gobject)
    }
    let (callback, data) = GAsync.callback { source, result in
      defer { g_object_unref(dialog?.gobject) }
      let file = try? GLibError.check { error in
        gtk_file_dialog_open_finish(OpaquePointer(source), result, error)
      }
      completion(url(from: file))
    }
    gtk_file_dialog_open(dialog, parent, nil, callback, data)
  }

  /// Runs a file-save dialog with a suggested name.
  package static func save(
    title: String,
    suggestedName: String,
    initialFolder: URL? = nil,
    filters: [FileFilter] = [],
    parent: UnsafeMutablePointer<GtkWindow>?,
    completion: @escaping @MainActor (URL?) -> Void
  ) {
    let dialog = gtk_file_dialog_new()
    gtk_file_dialog_set_title(dialog, title)
    gtk_file_dialog_set_modal(dialog, 1)
    gtk_file_dialog_set_initial_name(dialog, suggestedName)
    if let initialFolder {
      let folder = g_file_new_for_path(initialFolder.path)
      gtk_file_dialog_set_initial_folder(dialog, folder)
      g_object_unref(folder?.gobject)
    }
    if let list = filterList(filters) {
      gtk_file_dialog_set_filters(dialog, list)
      g_object_unref(list.gobject)
    }
    let (callback, data) = GAsync.callback { source, result in
      defer { g_object_unref(dialog?.gobject) }
      let file = try? GLibError.check { error in
        gtk_file_dialog_save_finish(OpaquePointer(source), result, error)
      }
      completion(url(from: file))
    }
    gtk_file_dialog_save(dialog, parent, nil, callback, data)
  }

  /// Copies a `GFile`'s path and drops the reference the dialog handed over.
  package static func url(from file: OpaquePointer?) -> URL? {
    guard let file else { return nil }
    defer { g_object_unref(file.gobject) }
    guard let path = String(takingOwnershipOf: g_file_get_path(file)) else { return nil }
    return URL(fileURLWithPath: path)
  }
}
