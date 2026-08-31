import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionGlobalLibraryTests: XCTestCase {
  func testStoredItemsOutliveTheInstanceThatWroteThem() throws {
    let directory = makeStoreDirectory()
    let library = SionGlobalLibrary(directoryURL: directory)
    let payload = try payloadData()

    let entry = try library.add(payload: payload, name: "Node")
    try library.rename(id: entry.id, to: "Renamed Node")

    // A second instance reads the files rather than the first one's memory,
    // which is what the next launch does.
    let reopened = SionGlobalLibrary(directoryURL: directory)

    XCTAssertEqual(reopened.entries.map(\.name), ["Renamed Node"])
    XCTAssertEqual(try reopened.payload(id: entry.id), payload)

    try library.remove(id: entry.id)

    XCTAssertTrue(SionGlobalLibrary(directoryURL: directory).entries.isEmpty)
  }

  func testARenameRewritesTheIndexAndLeavesThePayloadAlone() throws {
    let directory = makeStoreDirectory()
    let library = SionGlobalLibrary(directoryURL: directory)
    let entry = try library.add(payload: try payloadData(), name: "Node")

    // Marking the stored file is what makes a rewrite visible: a rename that
    // re-encoded the whole library would put the payload back over this.
    let payloadURL = try onlyPayloadURL(in: directory)
    let sentinel = Data("sentinel".utf8)
    try sentinel.write(to: payloadURL)

    try library.rename(id: entry.id, to: "Renamed")

    XCTAssertEqual(library.entries.map(\.name), ["Renamed"])
    XCTAssertEqual(try Data(contentsOf: payloadURL), sentinel)
  }

  func testARowIsListedWithoutReadingItsBytes() throws {
    let directory = makeStoreDirectory()
    let library = SionGlobalLibrary(directoryURL: directory)
    let entry = try library.add(payload: try payloadData(), name: "Node")
    try FileManager.default.removeItem(at: try onlyPayloadURL(in: directory))

    // A fresh instance has nothing cached, so listing it has to come from the
    // index alone — a library of large entries is not read in to draw rows.
    let reopened = SionGlobalLibrary(directoryURL: directory)

    // One missing payload degrades that one entry, not the whole store: the
    // library stays writable rather than freezing over a single damaged file.
    XCTAssertTrue(reopened.isReadable)
    XCTAssertEqual(reopened.entries.map(\.name), ["Node"])
    XCTAssertThrowsError(try reopened.payload(id: entry.id))
  }

  func testRemovingAnEntryTakesItsPayloadWithIt() throws {
    let directory = makeStoreDirectory()
    let library = SionGlobalLibrary(directoryURL: directory)
    let entry = try library.add(payload: try payloadData(), name: "Node")
    let payloadURL = try onlyPayloadURL(in: directory)

    try library.remove(id: entry.id)

    XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    XCTAssertThrowsError(try library.payload(id: entry.id)) { error in
      XCTAssertEqual(error as? SceneLibraryError, .itemNotFound(entry.id))
    }
  }

  func testTheOneFileLibraryOfAnEarlierBuildIsTakenOver() throws {
    let directory = makeStoreDirectory()
    let payload = try payloadData()
    var legacy = SceneLibrary()
    let item = try legacy.add(payload: payload, name: "Stored Earlier", id: "legacy")
    let legacyURL = directory.deletingLastPathComponent()
      .appendingPathComponent("Library.json")
    try FileManager.default.createDirectory(
      at: legacyURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try legacy.dataRepresentation().write(to: legacyURL)

    let library = SionGlobalLibrary(directoryURL: directory)

    XCTAssertEqual(library.entries, [SceneLibraryEntry(id: "legacy", name: item.name)])
    XCTAssertEqual(try library.payload(id: "legacy"), payload)
    // Removed only once its contents are stored in the new layout.
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    XCTAssertEqual(SionGlobalLibrary(directoryURL: directory).entries.count, 1)
  }

  func testAMissingIndexAndItsMissingFolderAreAnEmptyLibrary() throws {
    let directory = makeStoreDirectory()
    let library = SionGlobalLibrary(directoryURL: directory)

    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    XCTAssertTrue(library.entries.isEmpty)
    XCTAssertTrue(library.isReadable)

    // The store makes the folders it was pointed at, so a first launch stores.
    XCTAssertNoThrow(try library.add(payload: try payloadData(), name: "Node"))
    XCTAssertEqual(SionGlobalLibrary(directoryURL: directory).entries.map(\.name), ["Node"])
  }

  func testAnIndexThisBuildCannotReadIsNeverOverwritten() throws {
    let directory = makeStoreDirectory()
    let indexURL = directory.appendingPathComponent("index.json")
    let foreign = Data("{\"format\":\"something-else\"}\n".utf8)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try foreign.write(to: indexURL)

    let library = SionGlobalLibrary(directoryURL: directory)

    XCTAssertFalse(library.isReadable)
    XCTAssertThrowsError(try library.add(payload: try payloadData(), name: "Node"))
    XCTAssertEqual(try Data(contentsOf: indexURL), foreign)
  }

  func testAnIndexMayNotNameAPayloadOutsideTheLibrary() {
    for name in ["", ".", "..", "../escape.json", "sub/escape.json", "colon:escape"] {
      XCTAssertFalse(GlobalLibraryIndex.isSafePayloadFileName(name), name)
    }

    XCTAssertTrue(GlobalLibraryIndex.isSafePayloadFileName("A0BE-1234.json"))

    // The positive control: the same document with a safe name decodes, so
    // the refusal below can only come from the name and not from some other
    // mismatch in the fixture.
    let safe = Data(
      """
      {"format":"sion-library-index","version":1,\
      "items":[{"id":"a","name":"A","payload":"A0BE-1234.json"}]}
      """.utf8
    )

    XCTAssertEqual(try GlobalLibraryIndex(data: safe).rows.map(\.id), ["a"])

    let escaping = Data(
      """
      {"format":"sion-library-index","version":1,\
      "items":[{"id":"a","name":"A","payload":"../../secrets.json"}]}
      """.utf8
    )

    XCTAssertThrowsError(try GlobalLibraryIndex(data: escaping)) { error in
      XCTAssertEqual(error as? SceneLibraryError, .malformedStorage)
    }
  }

  func testAnIndexMayNotRepeatAnIdOrShareAPayloadFile() {
    let repeatedID = Data(
      """
      {"format":"sion-library-index","version":1,"items":[\
      {"id":"a","name":"A","payload":"one.json"},\
      {"id":"a","name":"B","payload":"two.json"}]}
      """.utf8
    )
    // Sharing a file would have a removal take bytes another row still names.
    let sharedPayload = Data(
      """
      {"format":"sion-library-index","version":1,"items":[\
      {"id":"a","name":"A","payload":"one.json"},\
      {"id":"b","name":"B","payload":"one.json"}]}
      """.utf8
    )

    for index in [repeatedID, sharedPayload] {
      XCTAssertThrowsError(try GlobalLibraryIndex(data: index)) { error in
        XCTAssertEqual(error as? SceneLibraryError, .malformedStorage)
      }
    }
  }

  func testALegacyFileThatCannotBeReadIsNotTakenAsAnAbsentOne() throws {
    let directory = makeStoreDirectory()
    let legacyURL = directory.deletingLastPathComponent()
      .appendingPathComponent("Library.json")
    try FileManager.default.createDirectory(
      at: legacyURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    // A directory where the file should be. Reading one as data fails for
    // anyone, so this does not depend on who is running the tests the way a
    // permission bit would.
    try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)

    let library = SionGlobalLibrary(directoryURL: directory)

    // Reading it as absent would leave the store writable, and the first write
    // would put an index beside it that stops the migration ever running.
    XCTAssertFalse(library.isReadable)
    XCTAssertThrowsError(try library.add(payload: try payloadData(), name: "Node"))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path)
    )
  }

  func testEveryChangeAnnouncesItselfSoOpenPalettesCatchUp() throws {
    let library = SionGlobalLibrary(directoryURL: makeStoreDirectory())
    var changeCount = 0
    let observer = NotificationCenter.default.addObserver(
      forName: SionGlobalLibrary.didChangeNotification,
      object: library,
      queue: nil
    ) { _ in
      changeCount += 1
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let entry = try library.add(payload: try payloadData(), name: "Node")
    try library.rename(id: entry.id, to: "Renamed")
    try library.remove(id: entry.id)

    XCTAssertEqual(changeCount, 3)
  }

  /// A library folder that does not exist yet, so the store has to make its
  /// own, inside a container the legacy file could also sit in.
  private func makeStoreDirectory() -> URL {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent("SionGlobalLibraryTests-\(UUID().uuidString)")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: container)
    }

    return container.appendingPathComponent("Library")
  }

  private func onlyPayloadURL(in directory: URL) throws -> URL {
    let payloads = try FileManager.default.contentsOfDirectory(
      at: directory.appendingPathComponent("payloads"),
      includingPropertiesForKeys: nil
    )

    XCTAssertEqual(payloads.count, 1)
    return try XCTUnwrap(payloads.first)
  }

  private func payloadData() throws -> Data {
    let element = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 40, height: 30))
    let package = SionPackage(
      document: SionDocument(scene: SionScene(elements: [element]))
    )
    return try SceneSelectionPayload(
      package: package,
      selectedElementIDs: [element.id]
    ).dataRepresentation()
  }
}
