import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionDocumentWindowControllerTests: XCTestCase {
  func testZoomToFitIsIndependentOfCurrentMagnification() throws {
    _ = NSApplication.shared
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(SionSize(width: 1_000, height: 800)))
    )
    let editorController = try SionEditorController(
      package: SionPackage(document: SionDocument(scene: scene)),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let windowController = SionDocumentWindowController(editorController: editorController)
    let scrollView = try XCTUnwrap(windowController.window?.contentView as? NSScrollView)

    windowController.zoomToFit(nil)
    let firstFit = scrollView.magnification
    windowController.zoomIn(nil)
    XCTAssertNotEqual(scrollView.magnification, firstFit)

    windowController.zoomToFit(nil)

    XCTAssertEqual(scrollView.magnification, firstFit, accuracy: 0.000_001)
    windowController.close()
  }
}
