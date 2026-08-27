import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionDocumentWindowControllerTests: XCTestCase {
  func testToolbarUsesVersionedConfigurationIdentifier() throws {
    _ = NSApplication.shared
    let editorController = try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    XCTAssertEqual(
      windowController.window?.toolbar?.identifier,
      NSToolbar.Identifier("SionDocumentToolbar.v2")
    )
  }

  func testDefaultToolbarIncludesZoomControl() throws {
    _ = NSApplication.shared
    let editorController = try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    let toolbar = NSToolbar(identifier: "Sion.Tests.Toolbar")
    let identifiers = windowController.toolbarDefaultItemIdentifiers(toolbar)

    XCTAssertTrue(identifiers.contains(NSToolbarItem.Identifier("Sion.Zoom")))
  }

  func testZoomToolbarActionReturnsFocusToCanvas() throws {
    _ = NSApplication.shared
    let editorController = try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    let window = try XCTUnwrap(windowController.window)
    let toolbar = try XCTUnwrap(window.toolbar)
    let zoomItem = try XCTUnwrap(
      windowController.toolbar(
        toolbar,
        itemForItemIdentifier: NSToolbarItem.Identifier("Sion.Zoom"),
        willBeInsertedIntoToolbar: false
      )
    )
    let zoomControl = try XCTUnwrap(zoomItem.view as? NSSegmentedControl)
    let temporaryResponder = NSTextField()
    window.contentView?.addSubview(temporaryResponder)
    XCTAssertTrue(window.makeFirstResponder(temporaryResponder))

    zoomControl.selectedSegment = 2
    let action = try XCTUnwrap(zoomControl.action)
    XCTAssertTrue(NSApp.sendAction(action, to: zoomControl.target, from: zoomControl))

    XCTAssertTrue(window.firstResponder is SionCanvasView)
  }

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
    defer { windowController.close() }

    let scrollView = try XCTUnwrap(windowController.window?.contentView as? NSScrollView)

    windowController.zoomToFit(nil)
    let firstFit = scrollView.magnification
    windowController.zoomIn(nil)
    XCTAssertNotEqual(scrollView.magnification, firstFit)

    windowController.zoomToFit(nil)

    XCTAssertEqual(scrollView.magnification, firstFit, accuracy: 0.000_001)
  }
}
