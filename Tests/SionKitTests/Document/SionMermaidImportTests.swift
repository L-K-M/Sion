import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionMermaidImportTests: XCTestCase {
  func testMermaidFileReadsUTF8SourceAndRejectsUnreadableFiles() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let readable = directory.appendingPathComponent("flow.mmd")
    try Data(MermaidFixture.diagram.utf8).write(to: readable)

    XCTAssertEqual(try SionMermaidFile.source(at: readable), MermaidFixture.diagram)

    let invalid = directory.appendingPathComponent("invalid.mmd")
    try Data([0xFF, 0xFE, 0xFF]).write(to: invalid)

    XCTAssertThrowsError(try SionMermaidFile.source(at: invalid)) { error in
      XCTAssertEqual(error as? SionMermaidFileError, .notUTF8(invalid))
    }

    let oversized = directory.appendingPathComponent("huge.mmd")
    try Data(repeating: 0x41, count: SionMermaidFile.maximumByteCount + 1).write(to: oversized)

    XCTAssertThrowsError(try SionMermaidFile.source(at: oversized)) { error in
      XCTAssertEqual(error as? SionMermaidFileError, .tooLarge(oversized))
    }
  }

  func testMermaidFileAcceptsPlainTextContentTypes() {
    let identifiers = SionMermaidFile.contentTypes.map(\.identifier)

    XCTAssertTrue(identifiers.contains("public.plain-text"))
    XCTAssertTrue(identifiers.contains("public.text"))
  }

  func testImportingAMermaidFileInsertsOneUndoableDiagram() throws {
    let document = makeDocument()
    let undoManager = try XCTUnwrap(document.undoManager)
    undoManager.groupsByEvent = false
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("flow.mmd")
    try Data(MermaidFixture.diagram.utf8).write(to: url)

    undoManager.beginUndoGrouping()
    let result = try XCTUnwrap(document.importMermaid(contentsOf: url))
    undoManager.endUndoGrouping()

    guard case .diagram(let elementIDs) = result else {
      return XCTFail("Expected a diagram insertion")
    }

    XCTAssertEqual(elementIDs.count, 3)
    XCTAssertEqual(document.editingController.document.scene.elements.count, 3)
    XCTAssertEqual(undoManager.undoActionName, "Import Mermaid")

    undoManager.undo()

    XCTAssertTrue(document.editingController.document.scene.elements.isEmpty)
  }

  func testLossyMermaidImportKeepsTheSourceAsText() throws {
    let document = makeDocument()

    let result = try XCTUnwrap(document.insertMermaid(MermaidFixture.lossyDiagram))

    guard case .sourceText(let elementID, let omissions) = result else {
      return XCTFail("Expected the source-text fallback")
    }

    let element = try XCTUnwrap(
      document.editingController.document.scene.element(withID: elementID)
    )
    guard case .text(let text) = element.content else {
      return XCTFail("Expected preserved source text")
    }

    XCTAssertEqual(text.string, MermaidFixture.lossyDiagram)
    XCTAssertFalse(omissions.isEmpty)
  }

  func testImportingAnUnreadableFileLeavesTheDocumentUnchanged() throws {
    let document = makeDocument()
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // The read throws to its caller; only the panel command shows an alert.
    XCTAssertThrowsError(
      try document.importMermaid(contentsOf: directory.appendingPathComponent("gone.mmd"))
    )
    XCTAssertTrue(document.editingController.document.scene.elements.isEmpty)
  }

  func testNewDocumentFromMermaidStartsFromTheImportedDiagram() throws {
    _ = NSApplication.shared
    let controller = SionDocumentController()
    let document = try XCTUnwrap(
      controller.makeMermaidDocument(source: MermaidFixture.diagram, display: false)
    )
    defer { document.close() }

    XCTAssertEqual(document.editingController.document.scene.elements.count, 3)
    XCTAssertTrue(document.isDocumentEdited)
  }

  private func makeDocument() -> SionDrawingDocument {
    SionDrawingDocument(archiveGenerator: MermaidFixture.generator)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}

private enum MermaidFixture {
  static let generator = SionArchiveGenerator(name: "SionKitTests", version: "2.0.0")

  static let diagram = """
    flowchart LR
      A --> B
    """

  static let lossyDiagram = """
    flowchart LR
      A --> B
      style A fill:#fff
    """
}
