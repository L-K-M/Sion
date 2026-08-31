import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionGlobalLibraryTests: XCTestCase {
  func testStoredItemsOutliveTheInstanceThatWroteThem() throws {
    let fileURL = try makeStoreURL()
    let library = SionGlobalLibrary(fileURL: fileURL)
    let payload = try payloadData()

    let item = try library.add(payload: payload, name: "Node")
    try library.rename(id: item.id, to: "Renamed Node")

    // A second instance reads the file rather than the first one's memory,
    // which is what the next launch does.
    let reopened = SionGlobalLibrary(fileURL: fileURL)

    XCTAssertEqual(reopened.items.map(\.name), ["Renamed Node"])
    XCTAssertEqual(reopened.item(id: item.id)?.payload, payload)

    try library.remove(id: item.id)

    XCTAssertTrue(SionGlobalLibrary(fileURL: fileURL).items.isEmpty)
  }

  func testAMissingFileIsAnEmptyLibraryRatherThanAFailure() throws {
    let library = SionGlobalLibrary(fileURL: try makeStoreURL())

    XCTAssertTrue(library.items.isEmpty)
    XCTAssertTrue(library.isReadable)
    XCTAssertNoThrow(try library.add(payload: try payloadData(), name: "Node"))
  }

  func testAFileThisBuildCannotReadIsNeverOverwritten() throws {
    let fileURL = try makeStoreURL()
    let foreign = Data("{\"format\":\"something-else\"}\n".utf8)
    try foreign.write(to: fileURL)

    let library = SionGlobalLibrary(fileURL: fileURL)

    XCTAssertFalse(library.isReadable)
    XCTAssertThrowsError(try library.add(payload: try payloadData(), name: "Node"))
    XCTAssertEqual(try Data(contentsOf: fileURL), foreign)
  }

  func testEveryChangeAnnouncesItselfSoOpenPalettesCatchUp() throws {
    let library = SionGlobalLibrary(fileURL: try makeStoreURL())
    var changeCount = 0
    let observer = NotificationCenter.default.addObserver(
      forName: SionGlobalLibrary.didChangeNotification,
      object: library,
      queue: nil
    ) { _ in
      changeCount += 1
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    let item = try library.add(payload: try payloadData(), name: "Node")
    try library.rename(id: item.id, to: "Renamed")
    try library.remove(id: item.id)

    XCTAssertEqual(changeCount, 3)
  }

  /// A directory that does not exist yet, so the store has to create its own.
  private func makeStoreURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SionGlobalLibraryTests-\(UUID().uuidString)")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("Library.json")
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
