#if canImport(AppKit)
  import AppKit
  import SionCore

  /// The library that outlives any one drawing, kept in Application Support.
  ///
  /// A document's own library travels inside its archive and undoes with the
  /// rest of it. This one belongs to the person rather than the file, so it is
  /// written straight through: there is no document to make it part of, and no
  /// undo stack it could sensibly join.
  ///
  /// The index and the payloads are separate files. A rename touches the index
  /// alone, and listing the library reads the index alone — an entry's bytes
  /// are fetched when something asks to place it. Kept in one file, a library
  /// of image-heavy selections would be re-encoded in full on every rename and
  /// held in memory from launch.
  @MainActor
  final class SionGlobalLibrary {
    static let shared = SionGlobalLibrary()
    static let didChangeNotification = Notification.Name("SionKitGlobalLibraryDidChange")

    private let directoryURL: URL
    private var loadedIndex: GlobalLibraryIndex?
    private var loadFailure: Error?

    init(directoryURL: URL = SionGlobalLibrary.defaultDirectoryURL()) {
      self.directoryURL = directoryURL
    }

    var entries: [SceneLibraryEntry] {
      index.rows.map { SceneLibraryEntry(id: $0.id, name: $0.name) }
    }

    /// Whether the stored index can be read, and so whether it can be written
    /// without discarding what is in it.
    var isReadable: Bool {
      _ = index
      return loadFailure == nil
    }

    func entry(id: String) -> SceneLibraryEntry? {
      guard let row = index.rows.first(where: { $0.id == id }) else { return nil }

      return SceneLibraryEntry(id: row.id, name: row.name)
    }

    /// An entry's bytes, read now rather than held since launch.
    ///
    /// The size is checked before the read: a payload file is bounded when it
    /// is written, but nothing stops it being replaced afterwards, and this is
    /// the point where it would be pulled into memory.
    func payload(id: String) throws -> Data {
      guard let row = index.rows.first(where: { $0.id == id }) else {
        throw SceneLibraryError.itemNotFound(id)
      }

      let url = try payloadURL(named: row.payloadFileName)
      let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard byteCount <= SceneLibraryLimits.maximumPayloadByteCount else {
        throw SceneLibraryError.payloadTooLarge(byteCount: byteCount)
      }

      return try Data(contentsOf: url)
    }

    @discardableResult
    func add(payload: Data, name: String) throws -> SceneLibraryEntry {
      var index = try writableIndex()
      try SceneLibraryLimits.validateAddition(
        payloadByteCount: payload.count,
        itemCount: index.rows.count
      )

      // Never store what could not be placed again.
      _ = try SceneSelectionPayload(data: payload)

      let id = UUID().uuidString
      let row = GlobalLibraryIndex.Row(
        id: id,
        name: SceneLibraryNaming.normalized(name),
        payloadFileName: "\(id).json"
      )

      // The payload lands first, so the index never names a file that is not
      // there yet; a write that fails between the two leaves an inert file.
      let url = try payloadURL(named: row.payloadFileName)
      try write(payload, to: url)
      index.rows.insert(row, at: 0)
      try store(index)
      return SceneLibraryEntry(id: row.id, name: row.name)
    }

    func remove(id: String) throws {
      var index = try writableIndex()
      guard let position = index.rows.firstIndex(where: { $0.id == id }) else {
        throw SceneLibraryError.itemNotFound(id)
      }

      let row = index.rows.remove(at: position)
      // The index goes first here, for the same reason it goes last above.
      try store(index)

      if let url = try? payloadURL(named: row.payloadFileName) {
        try? FileManager.default.removeItem(at: url)
      }
    }

    /// The write the split layout exists for: the index alone.
    func rename(id: String, to name: String) throws {
      var index = try writableIndex()
      guard let position = index.rows.firstIndex(where: { $0.id == id }) else {
        throw SceneLibraryError.itemNotFound(id)
      }

      index.rows[position].name = SceneLibraryNaming.normalized(name)
      try store(index)
    }

    /// Application Support, under the bundle identifier the way every other
    /// app's own folder is named. A build with no Application Support to write
    /// to keeps the library for the session rather than losing the command.
    ///
    /// Nonisolated because it reads nothing but the file system's layout, and
    /// the default argument it serves is evaluated wherever the caller is.
    nonisolated static func defaultDirectoryURL() -> URL {
      let manager = FileManager.default
      let domains = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      let container = domains.first ?? manager.temporaryDirectory
      let folder = Bundle.main.bundleIdentifier ?? GlobalLibraryStorage.fallbackDirectoryName

      let appFolder = container.appendingPathComponent(folder)

      return appFolder.appendingPathComponent(GlobalLibraryStorage.directoryName)
    }

    private var indexFileURL: URL {
      directoryURL.appendingPathComponent(GlobalLibraryStorage.indexFileName)
    }

    /// The single file earlier builds wrote, beside this library's folder.
    private var legacyFileURL: URL {
      let container = directoryURL.deletingLastPathComponent()

      return container.appendingPathComponent(GlobalLibraryStorage.legacyFileName)
    }

    /// Every payload path is built here, so this is where a name that would
    /// reach outside the library is stopped. The index rejects one on the way
    /// in as well; a rule this cheap is worth holding at the funnel too, since
    /// what comes out of it is passed to `removeItem`.
    private func payloadURL(named fileName: String) throws -> URL {
      guard GlobalLibraryIndex.isSafePayloadFileName(fileName) else {
        throw SceneLibraryError.malformedStorage
      }

      let payloads = directoryURL.appendingPathComponent(
        GlobalLibraryStorage.payloadDirectoryName
      )

      return payloads.appendingPathComponent(fileName)
    }

    /// Read once per launch. A missing index is an empty library, or a file an
    /// earlier build left to be taken over; anything else is an index with
    /// something in it that this build cannot read, which is remembered so a
    /// later write cannot quietly replace it.
    private var index: GlobalLibraryIndex {
      if let loadedIndex { return loadedIndex }

      let loaded = loadFromDisk()
      loadedIndex = loaded.index
      loadFailure = loaded.failure
      return loaded.index
    }

    private func loadFromDisk() -> (index: GlobalLibraryIndex, failure: Error?) {
      do {
        let data = try Data(contentsOf: indexFileURL)
        return (try GlobalLibraryIndex(data: data), nil)
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return adoptedLegacyLibrary()
      } catch {
        // Kept, not flattened: a file held open or unreadable by permission is
        // not malformed, and the banner reads whatever comes back out.
        return (GlobalLibraryIndex(), error)
      }
    }

    /// Takes over the one-file library earlier builds wrote, splitting it into
    /// this layout. Writing during a read is what a migration is; the legacy
    /// file is removed only once its contents are stored, and a legacy file
    /// that cannot be read is left exactly where it is.
    ///
    /// Payload names are generated rather than taken from the item IDs, which
    /// that file never had to keep usable as file names.
    private func adoptedLegacyLibrary() -> (index: GlobalLibraryIndex, failure: Error?) {
      let data: Data
      do {
        data = try Data(contentsOf: legacyFileURL)
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return (GlobalLibraryIndex(), nil)
      } catch {
        // A legacy file that is there but unreadable is not an absent one.
        // Reading it as absent would leave the store writable, and the first
        // write would put an index beside it that stops the migration from
        // ever being tried again.
        return (GlobalLibraryIndex(), error)
      }

      var written = [URL]()
      do {
        let library = try SceneLibrary(data: data)
        var index = GlobalLibraryIndex()

        for item in library.items {
          let row = GlobalLibraryIndex.Row(
            id: item.id,
            name: item.name,
            payloadFileName: "\(UUID().uuidString).json"
          )
          let url = try payloadURL(named: row.payloadFileName)
          try write(item.payload, to: url)
          written.append(url)
          index.rows.append(row)
        }

        try store(index, announcing: false)
        try? FileManager.default.removeItem(at: legacyFileURL)
        return (index, nil)
      } catch {
        // Names are generated per attempt, so what a failed one wrote would
        // otherwise be left behind again on every launch.
        for url in written {
          try? FileManager.default.removeItem(at: url)
        }

        return (GlobalLibraryIndex(), error)
      }
    }

    private func writableIndex() throws -> GlobalLibraryIndex {
      let index = self.index
      if let loadFailure {
        throw loadFailure
      }

      return index
    }

    private func store(_ index: GlobalLibraryIndex, announcing: Bool = true) throws {
      try write(index.dataRepresentation(), to: indexFileURL)
      loadedIndex = index

      guard announcing else { return }

      NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func write(_ data: Data, to url: URL) throws {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      // Atomic, so a file interrupted mid-write is the previous one rather
      // than half of two.
      try data.write(to: url, options: .atomic)
    }
  }

  /// The index beside the payloads: which entries there are, what they are
  /// called, and which file holds each one's bytes.
  struct GlobalLibraryIndex: Equatable {
    struct Row: Equatable {
      let id: String
      var name: String
      let payloadFileName: String
    }

    static let formatIdentifier = "sion-library-index"
    static let formatVersion = 1

    var rows: [Row]

    init(rows: [Row] = []) {
      self.rows = rows
    }

    init(data: Data) throws {
      let value = try JSONDecoder().decode(PortableValue.self, from: data)
      guard case .object(let fields) = value,
        case .string(let format)? = fields["format"],
        format == Self.formatIdentifier,
        case .integer(let version)? = fields["version"],
        case .array(let encodedRows)? = fields["items"]
      else {
        throw SceneLibraryError.malformedStorage
      }
      guard version == Int64(Self.formatVersion) else {
        throw SceneLibraryError.unsupportedVersion(Int(version))
      }

      var rows = [Row]()
      var ids = Set<String>()
      var fileNames = Set<String>()

      for encodedRow in encodedRows {
        let row = try Self.row(encodedRow)
        // Two rows over one file would have a removal take the bytes another
        // row still names; two rows under one id would leave one of them
        // unreachable and the other only half removable.
        guard ids.insert(row.id).inserted, fileNames.insert(row.payloadFileName).inserted
        else {
          throw SceneLibraryError.malformedStorage
        }

        rows.append(row)
      }

      self.init(rows: rows)
    }

    func dataRepresentation() throws -> Data {
      try CanonicalJSON.encode(
        PortableValue.object([
          "format": .string(Self.formatIdentifier),
          "version": .integer(Int64(Self.formatVersion)),
          "items": .array(
            rows.map { row in
              PortableValue.object([
                "id": .string(row.id),
                "name": .string(row.name),
                "payload": .string(row.payloadFileName),
              ])
            }
          ),
        ])
      )
    }

    /// A payload name is joined onto a folder path, so it has to be one plain
    /// component. An index that has been edited by hand must not be able to
    /// name a file outside the library.
    static func isSafePayloadFileName(_ name: String) -> Bool {
      guard !name.isEmpty, name != ".", name != ".." else { return false }

      let separators: Set<Character> = ["/", "\\", ":", "\0"]

      return !name.contains(where: separators.contains)
    }

    private static func row(_ value: PortableValue) throws -> Row {
      guard case .object(let fields) = value,
        case .string(let id)? = fields["id"],
        case .string(let name)? = fields["name"],
        case .string(let payloadFileName)? = fields["payload"],
        !id.isEmpty,
        isSafePayloadFileName(payloadFileName)
      else {
        throw SceneLibraryError.malformedStorage
      }

      return Row(
        id: id,
        name: SceneLibraryNaming.normalized(name),
        payloadFileName: payloadFileName
      )
    }
  }

  /// Outside the class, which is main-actor isolated: `defaultDirectoryURL()`
  /// is not, and a type nested in an isolated one would be.
  private enum GlobalLibraryStorage {
    static let fallbackDirectoryName = "Sion"
    static let directoryName = "Library"
    static let payloadDirectoryName = "payloads"
    static let indexFileName = "index.json"
    static let legacyFileName = "Library.json"
  }
#endif
