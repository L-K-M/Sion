import Foundation

public struct DocumentID: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public init() {
    self.init(rawValue: UUID())
  }

  public init?(_ description: String) {
    guard let value = UUID(uuidString: description) else {
      return nil
    }

    self.init(rawValue: value)
  }

  public var description: String {
    rawValue.uuidString.lowercased()
  }
}

extension DocumentID: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)

    guard let identifier = DocumentID(value) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Document ID must be a UUID."
      )
    }

    self = identifier
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

public struct ElementID: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }

  public init() {
    self.init(rawValue: UUID())
  }

  public init?(_ description: String) {
    guard let value = UUID(uuidString: description) else {
      return nil
    }

    self.init(rawValue: value)
  }

  public var description: String {
    rawValue.uuidString.lowercased()
  }
}

extension ElementID: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)

    guard let identifier = ElementID(value) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Element ID must be a UUID."
      )
    }

    self = identifier
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

/// A content-addressed asset key, normally `sha256:<lowercase hex>`.
public struct AssetID: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String {
    rawValue
  }
}

extension AssetID: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
