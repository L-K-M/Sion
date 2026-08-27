import Foundation
import XCTest

@testable import SionCore

final class FormatSchemaTests: XCTestCase {
  func testSchemasAreStrictJSONWithResolvableLocalReferences() throws {
    for filename in schemaFilenames {
      let data = try Data(contentsOf: schemaDirectory.appendingPathComponent(filename))

      // Strict decoding catches duplicate members that JSONSerialization accepts.
      _ = try CanonicalJSON.decodeStrict(PortableValue.self, from: data)

      let root = try XCTUnwrap(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
      )
      let definitions = try XCTUnwrap(root[definitionsKey] as? [String: Any])

      for reference in localReferences(in: root) {
        XCTAssertTrue(reference.hasPrefix(definitionReferencePrefix))

        let name = String(reference.dropFirst(definitionReferencePrefix.count))
        XCTAssertNotNil(definitions[name], "Missing schema definition: \(reference)")
      }
    }
  }

  private func localReferences(in value: Any) -> [String] {
    if let object = value as? [String: Any] {
      return object.flatMap { key, member in
        if key == referenceKey, let reference = member as? String {
          return [reference]
        }

        return localReferences(in: member)
      }
    }

    guard let array = value as? [Any] else {
      return []
    }

    return array.flatMap(localReferences)
  }

  private var schemaDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("docs/schema")
  }

  private let schemaFilenames = [
    "manifest-v1.schema.json",
    "scene-v1.schema.json",
  ]
  private let definitionsKey = "$defs"
  private let referenceKey = "$ref"
  private let definitionReferencePrefix = "#/$defs/"
}
