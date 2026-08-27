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
  }

  func testUndoGroupClosureDoesNotDirtySavedDocumentAgain() throws {
    let document = SionDrawingDocument()
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
    let document = SionDrawingDocument()
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
    let document = SionDrawingDocument()
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
}
