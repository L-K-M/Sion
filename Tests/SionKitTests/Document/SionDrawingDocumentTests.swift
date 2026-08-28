import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionDrawingDocumentTests: XCTestCase {
  func testMermaidExportWarningsMatchCoverage() {
    XCTAssertNil(MermaidExportWarning(coverage: .complete))
    XCTAssertEqual(MermaidExportWarning(coverage: .partial), .partial)
    XCTAssertEqual(MermaidExportWarning(coverage: .none), .nothingRepresentable)
  }

  func testMermaidExportWarningsDescribeOmissions() throws {
    let omissions = [
      MermaidOmission(kind: .image, count: 1),
      MermaidOmission(kind: .path, count: 2),
    ]
    let partial = try XCTUnwrap(MermaidExportWarning(coverage: .partial))
    let none = try XCTUnwrap(MermaidExportWarning(coverage: .none))

    XCTAssertEqual(
      partial.informativeText(for: omissions),
      "Unsupported visible content will be omitted: 1 image, 2 paths."
    )
    XCTAssertEqual(
      none.informativeText(for: omissions),
      "The file will contain omission comments only: 1 image, 2 paths."
    )
    XCTAssertEqual(
      partial.informativeText(for: []),
      "Unsupported visible content will be omitted: unspecified content."
    )
  }

  func testUndoGroupClosureDoesNotDirtySavedDocumentAgain() throws {
    let document = makeDocument()
    let undoManager = try XCTUnwrap(document.undoManager)
    undoManager.groupsByEvent = false
    undoManager.beginUndoGrouping()

    _ = try document.editingController.insertShape(at: SionPoint(x: 100, y: 100))
    XCTAssertTrue(document.isDocumentEdited)

    // Model a save completing before AppKit closes the current event's undo group.
    document.updateChangeCount(.changeCleared)
    XCTAssertFalse(document.isDocumentEdited)

    undoManager.endUndoGrouping()
    XCTAssertFalse(document.isDocumentEdited)
  }

  func testOneUndoReturnsDocumentToCleanState() throws {
    let document = makeDocument()
    let undoManager = try XCTUnwrap(document.undoManager)
    undoManager.groupsByEvent = false
    undoManager.beginUndoGrouping()

    _ = try document.editingController.insertShape(at: SionPoint(x: 100, y: 100))
    undoManager.endUndoGrouping()

    XCTAssertTrue(document.isDocumentEdited)

    undoManager.undo()

    XCTAssertFalse(document.isDocumentEdited)
  }

  func testSerializationKeepsInlineTextEditorActive() throws {
    let document = makeDocument()
    let id = try document.editingController.insertText("Draft", at: SionPoint(x: 100, y: 100))
    document.makeWindowControllers()
    let windowController = try XCTUnwrap(
      document.windowControllers.first as? SionDocumentWindowController
    )
    windowController.beginTextEditing(id)
    let responder = try XCTUnwrap(windowController.window?.firstResponder)

    _ = try document.data(ofType: SionDrawingDocument.typeIdentifier)

    XCTAssertTrue(windowController.window?.firstResponder === responder)
    windowController.close()
  }

  func testSerializationPersistsPNGPreview() throws {
    let document = makeDocument()
    _ = try document.editingController.insertShape(at: SionPoint(x: 100, y: 100))
    document.makeWindowControllers()
    let windowController = try XCTUnwrap(
      document.windowControllers.first as? SionDocumentWindowController
    )
    // LIFO runs responder cleanup before closing the window.
    defer { windowController.close() }

    let data = try document.data(ofType: SionDrawingDocument.typeIdentifier)
    let package = try SionArchive.decode(data)
    let preview = try XCTUnwrap(package.previewPNG)

    XCTAssertEqual(
      Array(preview.prefix(DocumentPreview.pngSignature.count)),
      DocumentPreview.pngSignature
    )
  }

  func testSerializationWritesInjectedGenerator() throws {
    let document = SionDrawingDocument(
      archiveGenerator: DocumentArchiveFixture.generator
    )

    let data = try document.data(ofType: SionDrawingDocument.typeIdentifier)
    let entries = Dictionary(
      uniqueKeysWithValues: try StoredZIPArchive.decode(data).map { ($0.path, $0.data) }
    )
    let manifestData = try XCTUnwrap(entries[SionArchiveConstants.manifestPath])
    let manifest = try CanonicalJSON.decodeStrict(
      SionManifest.self,
      from: manifestData
    )

    XCTAssertEqual(
      manifest.generator,
      GeneratorDescriptor(
        name: DocumentArchiveFixture.generator.name,
        version: DocumentArchiveFixture.generator.version
      )
    )
  }

  func testSaveAsUpdatesWindowAndArchiveTitles() async throws {
    let document = makeDocument()
    document.makeWindowControllers()
    let windowController = try XCTUnwrap(
      document.windowControllers.first as? SionDocumentWindowController
    )
    defer { windowController.close() }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let savedTitle = "Renamed Diagram"
    let savedFilename = "\(savedTitle).sion"
    let url = directory.appendingPathComponent(savedFilename)
    let saveError: Error? = await withCheckedContinuation { continuation in
      document.save(
        to: url,
        ofType: SionDrawingDocument.typeIdentifier,
        for: .saveAsOperation
      ) { error in
        continuation.resume(returning: error)
      }
    }

    XCTAssertNil(saveError)
    XCTAssertEqual(document.fileURL, url)
    XCTAssertEqual(document.displayName, savedTitle)
    XCTAssertEqual(windowController.window?.title, savedTitle)

    let package = try SionArchive.decode(Data(contentsOf: url))
    XCTAssertEqual(package.document.title, savedTitle)
  }

  func testAutosaveElsewhereKeepsAuthoredTitle() throws {
    let document = makeDocument()
    let authoredTitle = "Recovery Source"
    try document.editingController.load(
      SionPackage(document: SionDocument(title: authoredTitle))
    )

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let recoveryURL = directory.appendingPathComponent("Autosave Recovery.sion")
    try document.write(
      to: recoveryURL,
      ofType: SionDrawingDocument.typeIdentifier,
      for: .autosaveElsewhereOperation,
      originalContentsURL: nil
    )

    let package = try SionArchive.decode(Data(contentsOf: recoveryURL))
    XCTAssertEqual(package.document.title, authoredTitle)
  }

  @MainActor
  func testReadForRevertRestoresSavedContentAndCanvasFocus() throws {
    let savedElement = SceneElement.text(
      frame: SionRect(x: 40, y: 40, width: 180, height: 80),
      text: RevertFixture.savedText
    )
    let savedPackage = SionPackage(
      document: SionDocument(scene: SionScene(elements: [savedElement]))
    )
    let savedArchive = try SionArchive.encode(
      package: savedPackage,
      intent: .manual,
      generator: DocumentArchiveFixture.generator
    )
    let document = makeDocument()
    try document.editingController.load(savedPackage)
    document.makeWindowControllers()
    let windowController = try XCTUnwrap(
      document.windowControllers.first as? SionDocumentWindowController
    )
    defer { windowController.close() }

    let window = try XCTUnwrap(windowController.window)
    let scrollView = try XCTUnwrap(window.contentView as? NSScrollView)
    let canvas = try XCTUnwrap(scrollView.documentView as? SionCanvasView)
    defer {
      // Do not let a stale responder turn this assertion into a test hang.
      window.makeFirstResponder(canvas)
    }

    windowController.beginTextEditing(savedElement.id)
    let textView = try XCTUnwrap(window.firstResponder as? NSTextView)
    textView.string = RevertFixture.unsavedText
    textView.didChangeText()

    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertEqual(
      document.editingController.document.scene.element(withID: savedElement.id)?.textContent,
      RevertFixture.unsavedText
    )

    try document.read(
      from: savedArchive.data,
      ofType: SionDrawingDocument.typeIdentifier
    )

    XCTAssertEqual(
      document.editingController.document.scene.element(withID: savedElement.id)?.textContent,
      RevertFixture.savedText
    )
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertFalse(document.undoManager?.canUndo ?? true)
    XCTAssertNil(textView.window)
    XCTAssertTrue(window.firstResponder === canvas)
  }

  private func makeDocument() -> SionDrawingDocument {
    SionDrawingDocument(archiveGenerator: DocumentArchiveFixture.generator)
  }
}

private enum DocumentPreview {
  static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
}

private enum DocumentArchiveFixture {
  static let generator = SionArchiveGenerator(
    name: "SionKitTests",
    version: "2.0.0"
  )
}

private enum RevertFixture {
  static let savedText = "Saved"
  static let unsavedText = "Unsaved"
}

extension SceneElement {
  fileprivate var textContent: String? {
    guard case .text(let text) = content else { return nil }

    return text.string
  }
}
