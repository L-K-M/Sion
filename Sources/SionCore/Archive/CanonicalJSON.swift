import Foundation

public enum CanonicalJSON {
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    var data = try encoder.encode(value)
    data.append(0x0A)
    return data
  }

  public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
  }

  /// Rejects members that Codable would otherwise discard silently.
  public static func decodeStrict<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
    let value = try decode(type, from: data)
    var duplicateKeyDetector = JSONDuplicateKeyDetector(data: data)
    try duplicateKeyDetector.validate()

    let canonical = try encode(value)
    let inputObject = try JSONSerialization.jsonObject(with: data)
    let canonicalObject = try JSONSerialization.jsonObject(with: canonical)

    try rejectUnknownMembers(in: inputObject, comparedWith: canonicalObject, path: "$")
    return value
  }

  private static func rejectUnknownMembers(
    in input: Any,
    comparedWith canonical: Any,
    path: String
  ) throws {
    if let inputObject = input as? [String: Any],
      let canonicalObject = canonical as? [String: Any]
    {
      for (key, value) in inputObject {
        guard let canonicalValue = canonicalObject[key] else {
          throw CanonicalJSONError.unknownMember("\(path).\(key)")
        }

        try rejectUnknownMembers(
          in: value,
          comparedWith: canonicalValue,
          path: "\(path).\(key)"
        )
      }

      return
    }

    guard let inputArray = input as? [Any],
      let canonicalArray = canonical as? [Any]
    else {
      return
    }

    for index in inputArray.indices where canonicalArray.indices.contains(index) {
      try rejectUnknownMembers(
        in: inputArray[index],
        comparedWith: canonicalArray[index],
        path: "\(path)[\(index)]"
      )
    }
  }
}

public enum CanonicalJSONError: Error, Equatable {
  case duplicateMember(String)
  case unknownMember(String)
}

private struct JSONDuplicateKeyDetector {
  private let bytes: [UInt8]
  private var index = 0

  init(data: Data) {
    bytes = Array(data)
  }

  mutating func validate() throws {
    skipWhitespace()
    try parseValue(path: "$")
  }

  private mutating func parseValue(path: String) throws {
    skipWhitespace()
    guard let byte = current else {
      return
    }

    switch byte {
    case CharacterByte.objectStart:
      try parseObject(path: path)
    case CharacterByte.arrayStart:
      try parseArray(path: path)
    case CharacterByte.quote:
      _ = try parseString()
    default:
      parsePrimitive()
    }
  }

  private mutating func parseObject(path: String) throws {
    index += 1
    skipWhitespace()
    guard current != CharacterByte.objectEnd else {
      index += 1
      return
    }

    var keys = Set<String>()
    while current != nil {
      let key = try parseString()
      let memberPath = "\(path).\(key)"
      guard keys.insert(key).inserted else {
        throw CanonicalJSONError.duplicateMember(memberPath)
      }

      skipWhitespace()
      guard current == CharacterByte.colon else {
        return
      }
      index += 1
      try parseValue(path: memberPath)
      skipWhitespace()

      guard current == CharacterByte.comma else {
        if current == CharacterByte.objectEnd {
          index += 1
        }
        return
      }
      index += 1
      skipWhitespace()
    }
  }

  private mutating func parseArray(path: String) throws {
    index += 1
    skipWhitespace()
    guard current != CharacterByte.arrayEnd else {
      index += 1
      return
    }

    var elementIndex = 0
    while current != nil {
      try parseValue(path: "\(path)[\(elementIndex)]")
      elementIndex += 1
      skipWhitespace()

      guard current == CharacterByte.comma else {
        if current == CharacterByte.arrayEnd {
          index += 1
        }
        return
      }
      index += 1
      skipWhitespace()
    }
  }

  private mutating func parseString() throws -> String {
    let start = index
    guard current == CharacterByte.quote else {
      return ""
    }
    index += 1

    var escaped = false
    while let byte = current {
      index += 1
      if escaped {
        escaped = false
        continue
      }
      if byte == CharacterByte.escape {
        escaped = true
        continue
      }
      if byte == CharacterByte.quote {
        break
      }
    }

    let stringData = Data(bytes[start..<index])
    return try JSONSerialization.jsonObject(
      with: stringData,
      options: [.fragmentsAllowed]
    ) as? String ?? ""
  }

  private mutating func parsePrimitive() {
    while let byte = current, !CharacterByte.valueTerminators.contains(byte) {
      index += 1
    }
  }

  private mutating func skipWhitespace() {
    while let byte = current, CharacterByte.whitespace.contains(byte) {
      index += 1
    }
  }

  private var current: UInt8? {
    bytes.indices.contains(index) ? bytes[index] : nil
  }
}

private enum CharacterByte {
  static let objectStart = UInt8(ascii: "{")
  static let objectEnd = UInt8(ascii: "}")
  static let arrayStart = UInt8(ascii: "[")
  static let arrayEnd = UInt8(ascii: "]")
  static let quote = UInt8(ascii: "\"")
  static let escape = UInt8(ascii: "\\")
  static let colon = UInt8(ascii: ":")
  static let comma = UInt8(ascii: ",")
  static let whitespace: Set<UInt8> = [
    UInt8(ascii: " "),
    UInt8(ascii: "\t"),
    UInt8(ascii: "\r"),
    UInt8(ascii: "\n"),
  ]
  static let valueTerminators = whitespace.union([comma, objectEnd, arrayEnd])
}
