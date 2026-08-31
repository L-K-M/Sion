import Foundation
import XCTest

@testable import SionCore

final class SceneLibraryTests: XCTestCase {
  func testStoredItemsSurviveBothEncodedForms() throws {
    var library = SceneLibrary()
    let first = try library.add(payload: try payloadData(), name: "Node")
    let second = try library.add(payload: try payloadData(width: 60), name: "Wide Node")

    // Newest first, which is the order the palette lists them in.
    XCTAssertEqual(library.items.map(\.id), [second.id, first.id])

    XCTAssertEqual(try SceneLibrary(portableValue: library.portableValue), library)
    XCTAssertEqual(try SceneLibrary(data: library.dataRepresentation()), library)
    XCTAssertEqual(library.item(id: first.id), first)
  }

  func testAnAbsentStoreReadsAsAnEmptyLibraryAndAnEmptyOneDoesNot() throws {
    // A document that never stored a library has no key, which is the same
    // thing as an empty library. A file of zero bytes is a truncated one, and
    // reading it as empty would let the next write finish destroying it.
    XCTAssertEqual(try SceneLibrary(portableValue: nil), SceneLibrary())
    XCTAssertThrowsError(try SceneLibrary(data: Data()))
  }

  func testStorageWrittenBySomethingElseIsRefusedRatherThanRead() throws {
    // Each of these is a document another writer could have left behind under
    // the same key. Reading one as an empty library would invite overwriting
    // it; refusing is what keeps the round-trip promise the format makes.
    let rejected: [PortableValue] = [
      .string("not a library"),
      .object([:]),
      .object(["format": .string("something-else"), "version": .integer(1), "items": .array([])]),
      .object(["format": .string("sion-library"), "version": .integer(1)]),
    ]

    for value in rejected {
      XCTAssertThrowsError(try SceneLibrary(portableValue: value)) { error in
        XCTAssertEqual(error as? SceneLibraryError, .malformedStorage)
      }
    }

    XCTAssertThrowsError(
      try SceneLibrary(
        portableValue: .object([
          "format": .string("sion-library"),
          "version": .integer(2),
          "items": .array([]),
        ])
      )
    ) { error in
      XCTAssertEqual(error as? SceneLibraryError, .unsupportedVersion(2))
    }
  }

  func testAVersionThatSurvivedAJSONRoundTripAsANumberStillReads() throws {
    let library = try SceneLibrary(
      portableValue: .object([
        "format": .string("sion-library"),
        "version": .number(1),
        "items": .array([]),
      ])
    )

    XCTAssertEqual(library, SceneLibrary())
  }

  func testOnlyPlaceablePayloadsAreAccepted() throws {
    var library = SceneLibrary()

    XCTAssertThrowsError(try library.add(payload: Data("{}".utf8), name: "Broken"))
    XCTAssertTrue(library.items.isEmpty)
  }

  func testTheLimitsHoldAtThePointALibraryGrows() throws {
    var library = SceneLibrary()

    XCTAssertThrowsError(
      try library.add(
        payload: Data(count: SceneLibraryLimits.maximumPayloadByteCount + 1),
        name: "Huge"
      )
    ) { error in
      XCTAssertEqual(
        error as? SceneLibraryError,
        .payloadTooLarge(byteCount: SceneLibraryLimits.maximumPayloadByteCount + 1)
      )
    }

    let payload = try payloadData()
    var full = SceneLibrary(
      items: (0..<SceneLibraryLimits.maximumItemCount).map {
        SceneLibraryItem(id: "item-\($0)", name: "Item \($0)", payload: payload)
      }
    )

    XCTAssertThrowsError(try full.add(payload: payload, name: "One More")) { error in
      XCTAssertEqual(
        error as? SceneLibraryError,
        .libraryIsFull(itemCount: SceneLibraryLimits.maximumItemCount)
      )
    }

    _ = try library.add(payload: payload, name: "A", id: "shared")
    XCTAssertThrowsError(try library.add(payload: payload, name: "B", id: "shared")) { error in
      XCTAssertEqual(error as? SceneLibraryError, .duplicateItem("shared"))
    }
  }

  func testNamesAreReducedToSomethingThatFitsOnARow() throws {
    var library = SceneLibrary()
    let payload = try payloadData()
    let blank = try library.add(payload: payload, name: "   ", id: "blank")
    let wrapped = try library.add(payload: payload, name: " two\nlines ", id: "wrapped")
    let long = try library.add(
      payload: payload,
      name: String(repeating: "x", count: SceneLibraryLimits.maximumNameLength + 40),
      id: "long"
    )

    XCTAssertEqual(blank.name, SceneLibraryCopy.unnamedItem)
    XCTAssertEqual(wrapped.name, "two lines")
    XCTAssertEqual(long.name.count, SceneLibraryLimits.maximumNameLength)

    try library.rename(id: "blank", to: "Renamed")
    XCTAssertEqual(library.item(id: "blank")?.name, "Renamed")

    try library.remove(id: "blank")
    XCTAssertNil(library.item(id: "blank"))
    XCTAssertThrowsError(try library.remove(id: "blank")) { error in
      XCTAssertEqual(error as? SceneLibraryError, .itemNotFound("blank"))
    }
    XCTAssertThrowsError(try library.rename(id: "blank", to: "Nope"))
  }

  func testASceneKeepsItsLibraryThroughAnUndoableTransaction() throws {
    let element = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 40, height: 30))
    var editor = try SceneEditor(document: SionDocument(scene: SionScene(elements: [element])))
    var library = SceneLibrary()
    try library.add(payload: try payloadData(), name: "Node", id: "stored")

    try editor.perform(
      SceneTransaction(
        name: "Add to Library",
        command: .setSceneExtension(key: SceneLibrary.extensionKey, value: library.portableValue)
      )
    )

    XCTAssertEqual(
      try SceneLibrary(
        portableValue: editor.document.scene.extensions[SceneLibrary.extensionKey]
      ),
      library
    )

    // Removing the last item clears the key rather than leaving an empty one
    // behind for the next reader to decode.
    try editor.perform(
      SceneTransaction(
        name: "Remove from Library",
        command: .setSceneExtension(key: SceneLibrary.extensionKey, value: nil)
      )
    )

    XCTAssertNil(editor.document.scene.extensions[SceneLibrary.extensionKey])
    XCTAssertEqual(editor.undo(), "Remove from Library")
    XCTAssertEqual(
      try SceneLibrary(
        portableValue: editor.document.scene.extensions[SceneLibrary.extensionKey]
      ),
      library
    )
    XCTAssertEqual(editor.undo(), "Add to Library")
    XCTAssertNil(editor.document.scene.extensions[SceneLibrary.extensionKey])
  }

  func testADocumentCarriesItsLibraryThroughTheArchive() throws {
    let element = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 40, height: 30))
    var library = SceneLibrary()
    let item = try library.add(payload: try payloadData(), name: "Node", id: "stored")
    let package = SionPackage(
      document: SionDocument(
        scene: SionScene(
          elements: [element],
          extensions: [SceneLibrary.extensionKey: library.portableValue]
        )
      )
    )

    // The library rides in a scene extension, so nothing about the archive had
    // to change to carry it — this is the check that it really does.
    let encoded = try SionArchive.encode(
      package: package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522),
      generator: testArchiveGenerator
    )
    let decoded = try SionArchive.decode(encoded.data)
    let restored = try SceneLibrary(
      portableValue: decoded.document.scene.extensions[SceneLibrary.extensionKey]
    )

    XCTAssertEqual(restored, library)
    XCTAssertEqual(restored.item(id: "stored")?.payload, item.payload)
  }

  private func payloadData(width: Double = 40) throws -> Data {
    let element = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: width, height: 30)
    )
    let package = SionPackage(
      document: SionDocument(scene: SionScene(elements: [element]))
    )
    let payload = try SceneSelectionPayload(
      package: package,
      selectedElementIDs: [element.id]
    )
    return try payload.dataRepresentation()
  }
}
