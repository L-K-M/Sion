import Foundation

/// One reusable drawing fragment: a named ``SceneSelectionPayload``.
///
/// The payload is kept encoded rather than decoded. A library outlives the
/// selection it was cut from and may be written by a build that knows element
/// content this one does not, so an entry is carried verbatim and only decoded
/// when something asks to place it.
public struct SceneLibraryItem: Equatable, Sendable {
  public let id: String
  public var name: String
  public let payload: Data

  public init(id: String, name: String, payload: Data) {
    self.id = id
    self.name = name
    self.payload = payload
  }
}

/// An ordered collection of library items, portable enough to live either in a
/// scene's extensions or in a file of its own.
public struct SceneLibrary: Equatable, Sendable {
  /// The reverse-DNS key a document's own library is stored under.
  public static let extensionKey = "ch.lkmc.sion.library"
  public static let formatVersion = 1

  public private(set) var items: [SceneLibraryItem]

  public init(items: [SceneLibraryItem] = []) {
    self.items = items
  }

  /// Reads a library out of a scene extension value. An absent key is an empty
  /// library, which is the same thing a document that never stored one has.
  public init(portableValue: PortableValue?) throws {
    guard let portableValue else {
      self.init()
      return
    }
    guard case .object(let fields) = portableValue else {
      throw SceneLibraryError.malformedStorage
    }
    guard case .string(let format)? = fields["format"], format == Self.formatIdentifier else {
      throw SceneLibraryError.malformedStorage
    }
    guard let version = fields["version"]?.integerValue else {
      throw SceneLibraryError.malformedStorage
    }
    guard version == Self.formatVersion else {
      throw SceneLibraryError.unsupportedVersion(version)
    }
    guard case .array(let encodedItems)? = fields["items"] else {
      throw SceneLibraryError.malformedStorage
    }

    self.init(items: try encodedItems.map(Self.decodedItem))
  }

  public var portableValue: PortableValue {
    .object([
      "format": .string(Self.formatIdentifier),
      "version": .integer(Int64(Self.formatVersion)),
      "items": .array(
        items.map { item in
          PortableValue.object([
            "id": .string(item.id),
            "name": .string(item.name),
            "payload": .string(item.payload.base64EncodedString()),
          ])
        }
      ),
    ])
  }

  /// The same shape as the scene-extension form, as a standalone JSON file.
  ///
  /// A library that has never been written is an absent file, which a caller
  /// can see for itself; empty bytes are a truncated one, and reading those as
  /// an empty library would invite the next write to finish the job.
  public init(data: Data) throws {
    let value = try JSONDecoder().decode(PortableValue.self, from: data)
    try self.init(portableValue: value)
  }

  public func dataRepresentation() throws -> Data {
    try CanonicalJSON.encode(portableValue)
  }

  /// Stores `payload` under `name`, newest first, and hands back the entry.
  ///
  /// The payload is decoded once here so a library never accepts something it
  /// could not place later, and the limits are enforced at the one point where
  /// a library grows: an entry that is already stored stays stored.
  @discardableResult
  public mutating func add(
    payload: Data,
    name: String,
    id: String = UUID().uuidString
  ) throws -> SceneLibraryItem {
    guard payload.count <= SceneLibraryLimits.maximumPayloadByteCount else {
      throw SceneLibraryError.payloadTooLarge(byteCount: payload.count)
    }
    guard items.count < SceneLibraryLimits.maximumItemCount else {
      throw SceneLibraryError.libraryIsFull(itemCount: items.count)
    }
    guard !items.contains(where: { $0.id == id }) else {
      throw SceneLibraryError.duplicateItem(id)
    }

    _ = try SceneSelectionPayload(data: payload)
    let item = SceneLibraryItem(
      id: id,
      name: Self.normalized(name),
      payload: payload
    )
    items.insert(item, at: 0)
    return item
  }

  public mutating func remove(id: String) throws {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      throw SceneLibraryError.itemNotFound(id)
    }

    items.remove(at: index)
  }

  public mutating func rename(id: String, to name: String) throws {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      throw SceneLibraryError.itemNotFound(id)
    }

    items[index].name = Self.normalized(name)
  }

  public func item(id: String) -> SceneLibraryItem? {
    items.first { $0.id == id }
  }

  private static let formatIdentifier = "sion-library"

  /// A name is a label in a list, so it is trimmed, kept to one line, and
  /// bounded. An empty one would leave an unclickable-looking row behind.
  private static func normalized(_ name: String) -> String {
    let singleLine = name.components(separatedBy: .newlines).joined(separator: " ")
    let collapsed = singleLine.trimmingCharacters(in: .whitespaces)
    guard !collapsed.isEmpty else { return SceneLibraryCopy.unnamedItem }

    return String(collapsed.prefix(SceneLibraryLimits.maximumNameLength))
  }

  private static func decodedItem(_ value: PortableValue) throws -> SceneLibraryItem {
    guard case .object(let fields) = value,
      case .string(let id)? = fields["id"],
      case .string(let name)? = fields["name"],
      case .string(let encodedPayload)? = fields["payload"],
      let payload = Data(base64Encoded: encodedPayload)
    else {
      throw SceneLibraryError.malformedStorage
    }
    guard !id.isEmpty else {
      throw SceneLibraryError.malformedStorage
    }

    return SceneLibraryItem(id: id, name: normalized(name), payload: payload)
  }
}

public enum SceneLibraryLimits {
  /// Room for a page of entries without letting a library outweigh the drawing
  /// it is stored beside.
  public static let maximumItemCount = 200
  public static let maximumPayloadByteCount = 512 * 1_024
  public static let maximumNameLength = 120
}

public enum SceneLibraryCopy {
  public static let unnamedItem = "Untitled"
}

public enum SceneLibraryError: Error, Equatable, Sendable {
  case malformedStorage
  case unsupportedVersion(Int)
  case payloadTooLarge(byteCount: Int)
  case libraryIsFull(itemCount: Int)
  case duplicateItem(String)
  case itemNotFound(String)
}

extension PortableValue {
  /// JSON does not distinguish an integer from a whole number, and a decoder
  /// that met `1` as `1.0` must not make the version unreadable.
  fileprivate var integerValue: Int? {
    switch self {
    case .integer(let value):
      return Int(exactly: value)
    case .unsignedInteger(let value):
      return Int(exactly: value)
    case .number(let value):
      return Int(exactly: value)
    default:
      return nil
    }
  }
}
