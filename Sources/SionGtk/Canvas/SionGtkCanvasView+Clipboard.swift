import CGtk
import CSionGtkShim
import Foundation
import SionCore
import SionKit

/// Copy, cut, paste, and drop, with the same paste precedence as macOS: the
/// selection payload, image files, PDF/SVG/TIFF data, SVG text, bitmaps,
/// Mermaid text, plain text.
extension SionGtkCanvasView {
  func copy() {
    guard editorController.canCopySelection else { return }

    _ = copySelection()
  }

  func cut() {
    guard editorController.canCopySelection, editorController.canDeleteSelection else { return }
    guard copySelection() else { return }

    try? editorController.deleteSelection()
  }

  private func copySelection() -> Bool {
    guard let data = try? editorController.selectionPayloadData(),
      data.count <= SionArchiveConstants.maximumEntryByteCount
    else {
      return false
    }

    let text = editorController.selectedElements.compactMap(\.editableText).joined(separator: "\n")
    return clipboard.write(selection: data, text: text.isEmpty ? nil : text)
  }

  func paste() {
    let point = visibleCanvasCenter()
    clipboard.readPasteContent { [weak self] content in
      self?.insert(content, at: point)
    }
  }

  /// Inserts what the clipboard or a drop delivered.
  func insert(_ content: SionGtkPasteContent?, at point: SionPoint) {
    guard let content else { return }

    switch content {
    case .selection(let data):
      _ = try? editorController.insertSelectionPayload(data, at: point)
    case .image(let data, let type, let filename):
      _ = insertPastedImage(data: data, type: type, filename: filename, at: point)
    case .text(let text):
      guard !text.isEmpty else { return }
      if MermaidImporter.looksLikeMermaid(text) {
        SionMermaidInsertion.insert(
          text, at: point, origin: .paste, using: editorController, feedback: editorFeedback)
        return
      }
      _ = try? editorController.insertText(text, centeredAt: point)
    }
  }

  @discardableResult
  func insertPastedImage(data: Data, type: ImagePasteType, filename: String?, at point: SionPoint)
    -> Bool
  {
    guard !data.isEmpty, data.count <= SionArchiveConstants.maximumEntryByteCount else {
      return false
    }

    let taskID = UUID()
    let service = imageRenditionService
    let task = Task { @MainActor [weak self] in
      let display = await service.make(from: data)
      guard let self else { return }

      self.imagePasteTasks.removeValue(forKey: taskID)
      guard !Task.isCancelled else { return }
      guard let display else {
        self.creationFailureFeedback()
        return
      }

      do {
        try self.editorController.insertImage(
          originalData: data,
          mediaType: type.mediaType,
          fileExtension: type.fileExtension,
          filename: filename,
          pixelSize: display.sourcePixelSize,
          displayPNGData: display.data,
          displayPixelSize: display.pixelSize,
          at: point
        )
      } catch {
        self.creationFailureFeedback()
      }
    }
    imagePasteTasks[taskID] = task

    return true
  }

  // MARK: Drop

  func installDropTarget() {
    let target = gtk_drop_target_new(0, GDK_ACTION_COPY)!
    var types: [GType] = [GTypes.fileList, GTypes.file, GTypes.texture, GTypes.string]
    types.withUnsafeMutableBufferPointer { buffer in
      gtk_drop_target_set_gtypes(target, buffer.baseAddress, gsize(buffer.count))
    }
    Signals.connectDrop(target.gobject) { [weak self] value, x, y in
      guard let self, let value else { return false }
      return self.performDrop(value, atWidgetX: x, y: y)
    }
    gtk_widget_add_controller(drawingArea, target)
  }

  /// A dropped image lands where it was dropped, not at the viewport centre.
  func performDrop(_ value: UnsafeMutablePointer<GValue>, atWidgetX x: Double, y: Double) -> Bool {
    commitTextEditing()
    guard let content = SionGtkCanvasClipboard.pasteContent(from: value) else { return false }

    insert(content, at: modelPoint(fromWidgetX: x, y: y))
    return true
  }
}

/// What a paste or drop delivered, already reduced to what the canvas inserts.
enum SionGtkPasteContent: Equatable {
  case selection(Data)
  case image(Data, type: ImagePasteType, filename: String?)
  case text(String)
}

enum ImagePasteType: Equatable {
  case png
  case jpeg
  case gif
  case webp
  case pdf
  case svg
  case tiff

  init?(fileExtension: String) {
    switch fileExtension.lowercased() {
    case "png": self = .png
    case "jpg", "jpeg": self = .jpeg
    case "gif": self = .gif
    case "webp": self = .webp
    case "pdf": self = .pdf
    case "svg": self = .svg
    case "tif", "tiff": self = .tiff
    default: return nil
    }
  }

  init?(mimeType: String) {
    switch mimeType {
    case "image/png": self = .png
    case "image/jpeg": self = .jpeg
    case "image/gif": self = .gif
    case "image/webp": self = .webp
    case "application/pdf": self = .pdf
    case "image/svg+xml": self = .svg
    case "image/tiff": self = .tiff
    default: return nil
    }
  }

  var mediaType: String {
    switch self {
    case .png: "image/png"
    case .jpeg: "image/jpeg"
    case .gif: "image/gif"
    case .webp: "image/webp"
    case .pdf: "application/pdf"
    case .svg: "image/svg+xml"
    case .tiff: "image/tiff"
    }
  }

  var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .gif: "gif"
    case .webp: "webp"
    case .pdf: "pdf"
    case .svg: "svg"
    case .tiff: "tiff"
    }
  }
}

/// The desktop clipboard behind copy and paste. Without a display (headless
/// tests) it holds nothing and accepts nothing.
@MainActor
package final class SionGtkCanvasClipboard {
  package static let selectionMimeType = "application/vnd.lkmc.sion.selection"

  /// The binary types paste accepts as-is, in precedence order.
  static let preservedMimeTypes: [(String, ImagePasteType)] = [
    ("application/pdf", .pdf), ("image/svg+xml", .svg), ("image/tiff", .tiff),
  ]
  static let textMimeTypes = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING"]
  static let uriListMimeType = "text/uri-list"

  private let clipboard: OpaquePointer?

  package init() {
    clipboard = gdk_display_get_default().flatMap { gdk_display_get_clipboard($0) }
  }

  /// Puts the selection payload and its text on the clipboard.
  func write(selection: Data, text: String?) -> Bool {
    guard let clipboard else { return false }

    var providers: [UnsafeMutablePointer<GdkContentProvider>?] = []
    let bytes = selection.withUnsafeBytes { buffer in
      g_bytes_new(buffer.baseAddress, gsize(buffer.count))
    }
    providers.append(gdk_content_provider_new_for_bytes(Self.selectionMimeType, bytes))
    g_bytes_unref(bytes)
    if let text {
      var value = GValue.string(text)
      providers.append(gdk_content_provider_new_for_value(&value))
      g_value_unset(&value)
    }
    let union = providers.withUnsafeMutableBufferPointer { buffer in
      gdk_content_provider_new_union(buffer.baseAddress, gsize(buffer.count))
    }
    let result = gdk_clipboard_set_content(clipboard, union) != 0
    g_object_unref(union?.gobject)
    return result
  }

  /// Mirrors `validateMenuItem` for Paste from the advertised formats alone;
  /// the bytes are read only when pasting.
  var hasPasteableContent: Bool {
    guard let clipboard else { return false }
    let available = availableMimeTypes(gdk_clipboard_get_formats(clipboard))
    if available.contains(Self.selectionMimeType) || available.contains(Self.uriListMimeType) {
      return true
    }
    if Self.preservedMimeTypes.contains(where: { available.contains($0.0) }) {
      return true
    }
    if available.contains(where: { $0.hasPrefix("image/") }) {
      return true
    }
    if let formats = gdk_clipboard_get_formats(clipboard),
      gdk_content_formats_contain_gtype(formats, GTypes.texture) != 0
        || gdk_content_formats_contain_gtype(formats, GTypes.string) != 0
    {
      return true
    }
    return Self.textMimeTypes.contains(where: { available.contains($0) })
  }

  private func availableMimeTypes(_ formats: OpaquePointer?) -> Set<String> {
    guard let formats else { return [] }
    var count = 0
    guard let types = gdk_content_formats_get_mime_types(formats, &count) else { return [] }
    var result = Set<String>()
    for index in 0..<count {
      if let type = String(gtkString: types[index]) {
        result.insert(type)
      }
    }
    return result
  }

  /// Reads the clipboard in paste precedence, one format at a time, and
  /// reports what the canvas should insert (nil when nothing applies).
  func readPasteContent(_ completion: @escaping @MainActor (SionGtkPasteContent?) -> Void) {
    guard let clipboard else {
      completion(nil)
      return
    }
    let available = availableMimeTypes(gdk_clipboard_get_formats(clipboard))
    let formats = gdk_clipboard_get_formats(clipboard)
    let hasTexture =
      formats.map { gdk_content_formats_contain_gtype($0, GTypes.texture) != 0 } ?? false
    let hasString =
      formats.map { gdk_content_formats_contain_gtype($0, GTypes.string) != 0 } ?? false

    var attempts: [(@MainActor (@escaping @MainActor (SionGtkPasteContent?) -> Void) -> Void)] = []

    if available.contains(Self.selectionMimeType) {
      attempts.append { [self] next in
        self.readBytes(clipboard, mimeType: Self.selectionMimeType) { data in
          guard let data, !data.isEmpty, data.count <= SionArchiveConstants.maximumEntryByteCount
          else {
            return next(nil)
          }
          next(.selection(data))
        }
      }
    }
    if available.contains(Self.uriListMimeType) {
      attempts.append { [self] next in
        self.readBytes(clipboard, mimeType: Self.uriListMimeType) { data in
          guard let data, let list = String(data: data, encoding: .utf8) else { return next(nil) }
          next(Self.imageFileContent(fromURIList: list))
        }
      }
    }
    for (mimeType, type) in Self.preservedMimeTypes where available.contains(mimeType) {
      attempts.append { [self] next in
        self.readBytes(clipboard, mimeType: mimeType) { data in
          guard let data, !data.isEmpty, data.count <= SionArchiveConstants.maximumEntryByteCount
          else {
            return next(nil)
          }
          next(.image(data, type: type, filename: nil))
        }
      }
    }
    // SVG text is artwork; every other string is text. Read it once.
    let hasText = hasString || Self.textMimeTypes.contains(where: { available.contains($0) })
    if hasText {
      attempts.append { [self] next in
        self.readText(clipboard) { text in
          guard let text, !text.isEmpty else { return next(nil) }
          if text.contains("<svg"), text.utf8.count <= SionArchiveConstants.maximumEntryByteCount {
            return next(.image(Data(text.utf8), type: .svg, filename: nil))
          }
          next(.text(text))
        }
      }
    }
    if available.contains("image/png") {
      attempts.append { [self] next in
        self.readBytes(clipboard, mimeType: "image/png") { data in
          guard let data, !data.isEmpty, data.count <= SionArchiveConstants.maximumEntryByteCount
          else {
            return next(nil)
          }
          next(.image(data, type: .png, filename: nil))
        }
      }
    } else if hasTexture || available.contains(where: { $0.hasPrefix("image/") }) {
      attempts.append { [self] next in
        self.readTexturePNG(clipboard) { data in
          guard let data, !data.isEmpty, data.count <= SionArchiveConstants.maximumEntryByteCount
          else {
            return next(nil)
          }
          next(.image(data, type: .png, filename: nil))
        }
      }
    }

    // Plain text after an SVG-only read failed is handled above; an image
    // paste that yields text falls back to text last, as on macOS.
    func run(_ index: Int) {
      guard index < attempts.count else {
        completion(nil)
        return
      }
      attempts[index]({ content in
        if let content {
          // Text wins only after every image attempt; defer it if one remains.
          if case .text = content, index < attempts.count - 1 {
            run(index + 1)
            self.deferredText = content
            return
          }
          completion(content)
        } else if index == attempts.count - 1, let deferredText = self.deferredText {
          self.deferredText = nil
          completion(deferredText)
        } else {
          run(index + 1)
        }
      })
    }
    deferredText = nil
    run(0)
  }

  private var deferredText: SionGtkPasteContent?

  /// A dropped or copied file list: the first supported image file, if any.
  static func imageFileContent(fromURIList list: String) -> SionGtkPasteContent? {
    for line in list.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.hasPrefix("#"), let url = URL(string: trimmed), url.isFileURL else { continue }
      return imageFileContent(from: url)
    }
    return nil
  }

  static func imageFileContent(from url: URL) -> SionGtkPasteContent? {
    guard let type = ImagePasteType(fileExtension: url.pathExtension),
      let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
      let size = values.fileSize, size > 0, size <= SionArchiveConstants.maximumEntryByteCount,
      let data = try? Data(contentsOf: url)
    else {
      return nil
    }
    return .image(data, type: type, filename: url.lastPathComponent)
  }

  /// What a drop target's value holds: files, a texture, or a string.
  static func pasteContent(from value: UnsafeMutablePointer<GValue>) -> SionGtkPasteContent? {
    if sion_value_holds(value, GTypes.fileList) != 0, let list = sion_value_get_boxed(value) {
      guard let files = gdk_file_list_get_files(OpaquePointer(list)) else { return nil }
      defer { g_slist_free(files) }
      for file in files.elements {
        if let path = String(takingOwnershipOf: g_file_get_path(OpaquePointer(file))),
          let content = imageFileContent(from: URL(fileURLWithPath: path))
        {
          return content
        }
      }
      return nil
    }
    if sion_value_holds(value, GTypes.file) != 0, let file = sion_value_get_object(value),
      let path = String(takingOwnershipOf: g_file_get_path(OpaquePointer(file)))
    {
      return imageFileContent(from: URL(fileURLWithPath: path))
    }
    if sion_value_holds(value, GTypes.texture) != 0, let texture = sion_value_get_object(value) {
      guard let bytes = gdk_texture_save_to_png_bytes(OpaquePointer(texture)) else { return nil }
      defer { g_bytes_unref(bytes) }
      let data = Data(gbytes: bytes)
      guard data.count <= SionArchiveConstants.maximumEntryByteCount else { return nil }
      return .image(data, type: .png, filename: nil)
    }
    if sion_value_holds(value, GTypes.string) != 0, let text = value.pointee.stringValue {
      guard text.contains("<svg"), text.utf8.count <= SionArchiveConstants.maximumEntryByteCount
      else {
        return nil
      }
      return .image(Data(text.utf8), type: .svg, filename: nil)
    }
    return nil
  }

  // MARK: Asynchronous reads

  private func readBytes(
    _ clipboard: OpaquePointer, mimeType: String, completion: @escaping @MainActor (Data?) -> Void
  ) {
    var types: [UnsafePointer<CChar>?] = [UnsafePointer(strdup(mimeType)), nil]
    let (callback, data) = GAsync.callback { source, result in
      defer {
        for type in types {
          free(UnsafeMutablePointer(mutating: type))
        }
      }
      var outType: UnsafePointer<gchar>?
      let stream = try? GLibError.check { error in
        gdk_clipboard_read_finish(OpaquePointer(source), result, &outType, error)
      }
      guard let stream else { return completion(nil) }
      defer { g_object_unref(stream.gobject) }
      completion(Self.readAll(stream))
    }
    types.withUnsafeMutableBufferPointer { buffer in
      gdk_clipboard_read_async(
        clipboard, buffer.baseAddress, G_PRIORITY_DEFAULT, nil, callback, data)
    }
  }

  private func readText(
    _ clipboard: OpaquePointer, completion: @escaping @MainActor (String?) -> Void
  ) {
    let (callback, data) = GAsync.callback { source, result in
      let text = try? GLibError.check { error in
        gdk_clipboard_read_text_finish(OpaquePointer(source), result, error)
      }
      completion(String(takingOwnershipOf: text ?? nil))
    }
    gdk_clipboard_read_text_async(clipboard, nil, callback, data)
  }

  private func readTexturePNG(
    _ clipboard: OpaquePointer, completion: @escaping @MainActor (Data?) -> Void
  ) {
    let (callback, data) = GAsync.callback { source, result in
      let texture = try? GLibError.check { error in
        gdk_clipboard_read_texture_finish(OpaquePointer(source), result, error)
      }
      guard let texture = texture ?? nil else { return completion(nil) }
      defer { g_object_unref(texture.gobject) }
      guard let bytes = gdk_texture_save_to_png_bytes(texture) else { return completion(nil) }
      defer { g_bytes_unref(bytes) }
      completion(Data(gbytes: bytes))
    }
    gdk_clipboard_read_texture_async(clipboard, nil, callback, data)
  }

  private static func readAll(_ stream: UnsafeMutablePointer<GInputStream>) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let read = buffer.withUnsafeMutableBytes { raw in
        g_input_stream_read(stream, raw.baseAddress, gsize(raw.count), nil, nil)
      }
      guard read > 0 else { break }
      data.append(buffer, count: Int(read))
      if data.count > SionArchiveConstants.maximumEntryByteCount { break }
    }
    return data
  }
}

extension Data {
  /// Copies a `GBytes` buffer.
  init(gbytes: OpaquePointer) {
    var size = 0
    guard let pointer = g_bytes_get_data(gbytes, &size), size > 0 else {
      self.init()
      return
    }
    self.init(bytes: pointer, count: size)
  }
}
