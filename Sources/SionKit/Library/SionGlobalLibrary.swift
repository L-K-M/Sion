#if canImport(AppKit)
  import AppKit
  import SionCore

  /// The library that outlives any one drawing, kept in Application Support.
  ///
  /// A document's own library travels inside its archive and undoes with the
  /// rest of it. This one belongs to the person rather than the file, so it is
  /// written straight through: there is no document to make it part of, and no
  /// undo stack it could sensibly join.
  @MainActor
  final class SionGlobalLibrary {
    static let shared = SionGlobalLibrary()
    static let didChangeNotification = Notification.Name("SionKitGlobalLibraryDidChange")

    private let fileURL: URL
    private var loadedLibrary: SceneLibrary?
    private var loadFailed = false

    init(fileURL: URL = SionGlobalLibrary.defaultFileURL()) {
      self.fileURL = fileURL
    }

    var items: [SceneLibraryItem] {
      library.items
    }

    /// Whether the stored file can be read, and so whether it can be written
    /// without discarding what is in it.
    var isReadable: Bool {
      _ = library
      return !loadFailed
    }

    @discardableResult
    func add(payload: Data, name: String) throws -> SceneLibraryItem {
      var library = try writableLibrary()
      let item = try library.add(payload: payload, name: name)
      try store(library)
      return item
    }

    func remove(id: String) throws {
      var library = try writableLibrary()
      try library.remove(id: id)
      try store(library)
    }

    func rename(id: String, to name: String) throws {
      var library = try writableLibrary()
      try library.rename(id: id, to: name)
      try store(library)
    }

    func item(id: String) -> SceneLibraryItem? {
      library.item(id: id)
    }

    /// Application Support, under the bundle identifier the way every other
    /// app's own folder is named. A build with no Application Support to write
    /// to keeps the library for the session rather than losing the command.
    static func defaultFileURL() -> URL {
      let container = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory
      let folderName = Bundle.main.bundleIdentifier ?? Storage.fallbackDirectoryName

      return container
        .appendingPathComponent(folderName)
        .appendingPathComponent(Storage.fileName)
    }

    /// Read once per launch. A missing file is an empty library; anything else
    /// is a file with something in it that this build cannot read, which is
    /// remembered so a later write cannot quietly replace it.
    private var library: SceneLibrary {
      if let loadedLibrary { return loadedLibrary }

      let library: SceneLibrary
      do {
        let data = try Data(contentsOf: fileURL)
        library = try SceneLibrary(data: data)
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        library = SceneLibrary()
      } catch {
        loadFailed = true
        library = SceneLibrary()
      }

      loadedLibrary = library
      return library
    }

    private func writableLibrary() throws -> SceneLibrary {
      let library = self.library
      guard !loadFailed else {
        throw SceneLibraryError.malformedStorage
      }

      return library
    }

    private func store(_ library: SceneLibrary) throws {
      let data = try library.dataRepresentation()
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      // Atomic, so a library interrupted mid-write is the previous one rather
      // than half of two.
      try data.write(to: fileURL, options: .atomic)

      loadedLibrary = library
      NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private enum Storage {
      static let fallbackDirectoryName = "Sion"
      static let fileName = "Library.json"
    }
  }
#endif
