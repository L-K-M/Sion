import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionDocumentExportTests: XCTestCase {
  func testImageExportWorksWithoutAWindow() throws {
    let document = makeDocument()
    _ = try document.editingController.insertShape(
      in: SionRect(x: 0, y: 0, width: 120, height: 80),
      kind: .rectangle
    )
    XCTAssertTrue(document.windowControllers.isEmpty)

    var options = SionImageExportOptions()
    options.scale = .twoX
    let data = try document.imageExportData(options: options)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
    let content = document.editingController.contentBounds()

    XCTAssertEqual(bitmap.pixelsWide, Int((content.width * 2).rounded()))
    XCTAssertEqual(bitmap.pixelsHigh, Int((content.height * 2).rounded()))
  }

  func testPDFExportWorksWithoutAWindow() throws {
    let document = makeDocument()
    _ = try document.editingController.insertShape(
      in: SionRect(x: 0, y: 0, width: 120, height: 80),
      kind: .rectangle
    )

    var options = SionImageExportOptions()
    options.format = .pdf
    let data = try document.imageExportData(options: options)

    XCTAssertEqual(Array(data.prefix(4)), Array("%PDF".utf8))
  }

  func testPrintOperationPrintsTheDrawingOnOnePage() throws {
    _ = NSApplication.shared
    let document = makeDocument()
    _ = try document.editingController.insertShape(
      in: SionRect(x: 0, y: 0, width: 120, height: 80),
      kind: .rectangle
    )

    let operation = try document.printOperation(withSettings: [:])
    let printView = try XCTUnwrap(operation.view as? SionScenePrintView)
    var range = NSRange(location: 0, length: 0)

    XCTAssertEqual(operation.jobTitle, document.displayName)
    XCTAssertTrue(printView.knowsPageRange(&range))
    XCTAssertEqual(range, NSRange(location: 1, length: 1))
    XCTAssertEqual(operation.printInfo.horizontalPagination, .clip)
    XCTAssertEqual(operation.printInfo.verticalPagination, .clip)
    XCTAssertEqual(
      printView.bounds.size,
      SionScenePrintView.printableSize(for: operation.printInfo)
    )
  }

  private func makeDocument() -> SionDrawingDocument {
    SionDrawingDocument(archiveGenerator: ExportFixture.generator)
  }
}

private enum ExportFixture {
  static let generator = SionArchiveGenerator(name: "SionKitTests", version: "2.0.0")
}
