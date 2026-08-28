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
    let zoomControl = NSSegmentedControl(
      labels: ["Out", "Fit", "In"],
      trackingMode: .selectOne,
      target: nil,
      action: nil
    )
    let temporaryResponder = TestResponderView()
    window.contentView?.addSubview(temporaryResponder)
    XCTAssertTrue(window.makeFirstResponder(temporaryResponder))

    zoomControl.selectedSegment = ZoomTestCommand.zoomInSegment
    XCTAssertTrue(
      NSApp.sendAction(
        ZoomTestCommand.action,
        to: windowController,
        from: zoomControl
      )
    )

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

  func testShowWindowFitsPopulatedDocumentBeforeReturning() throws {
    _ = NSApplication.shared
    let windowController = try makeInitialFitWindowController()
    let window = try XCTUnwrap(windowController.window)
    let autosaveName = isolateFrameAutosave(for: window)
    defer {
      windowController.close()
      NSWindow.removeFrame(usingName: autosaveName)
    }
    let scrollView = try XCTUnwrap(window.contentView as? NSScrollView)
    window.setContentSize(InitialFitTestGeometry.windowContentSize)
    let magnificationBeforeShow = scrollView.magnification

    windowController.showWindow(nil)

    XCTAssertNotEqual(
      scrollView.magnification,
      magnificationBeforeShow,
      accuracy: InitialFitTestGeometry.magnificationAccuracy
    )
  }

  func testInitialFitRetriesAfterVisibleViewportBecomesUsable() throws {
    _ = NSApplication.shared
    let windowController = try makeInitialFitWindowController()
    let window = try XCTUnwrap(windowController.window)
    let autosaveName = isolateFrameAutosave(for: window)
    defer {
      windowController.close()
      NSWindow.removeFrame(usingName: autosaveName)
    }
    let scrollView = try XCTUnwrap(window.contentView as? NSScrollView)
    let magnificationBeforeShow = scrollView.magnification

    window.setContentSize(.zero)
    windowController.showWindow(nil)
    XCTAssertEqual(
      scrollView.magnification,
      magnificationBeforeShow,
      accuracy: InitialFitTestGeometry.magnificationAccuracy
    )

    window.setContentSize(InitialFitTestGeometry.windowContentSize)

    XCTAssertNotEqual(
      scrollView.magnification,
      magnificationBeforeShow,
      accuracy: InitialFitTestGeometry.magnificationAccuracy
    )
  }

  func testInitialFitDoesNotOverrideSubsequentZoomCommand() throws {
    _ = NSApplication.shared
    let windowController = try makeInitialFitWindowController()
    let window = try XCTUnwrap(windowController.window)
    let autosaveName = isolateFrameAutosave(for: window)
    defer {
      windowController.close()
      NSWindow.removeFrame(usingName: autosaveName)
    }
    let scrollView = try XCTUnwrap(window.contentView as? NSScrollView)

    windowController.showWindow(nil)
    windowController.actualSize(nil)

    let queueDrained = expectation(description: "Main queue drained")
    DispatchQueue.main.async {
      queueDrained.fulfill()
    }
    wait(for: [queueDrained], timeout: InitialFitTestGeometry.queueDrainTimeout)

    XCTAssertEqual(
      scrollView.magnification,
      ZoomTestCommand.actualSizeMagnification,
      accuracy: InitialFitTestGeometry.magnificationAccuracy
    )
  }

  func testResizeRetryDoesNotOverrideZoomIssuedWhileViewportUnusable() throws {
    _ = NSApplication.shared
    let windowController = try makeInitialFitWindowController()
    let window = try XCTUnwrap(windowController.window)
    let autosaveName = isolateFrameAutosave(for: window)
    defer {
      windowController.close()
      NSWindow.removeFrame(usingName: autosaveName)
    }
    let scrollView = try XCTUnwrap(window.contentView as? NSScrollView)

    window.setContentSize(.zero)
    windowController.showWindow(nil)
    XCTAssertEqual(scrollView.contentSize, .zero)

    windowController.actualSize(nil)
    window.setContentSize(InitialFitTestGeometry.windowContentSize)
    windowController.windowDidResize(
      Notification(name: NSWindow.didResizeNotification, object: window)
    )

    XCTAssertEqual(
      scrollView.magnification,
      ZoomTestCommand.actualSizeMagnification,
      accuracy: InitialFitTestGeometry.magnificationAccuracy
    )
  }

  func testEmptyInitialShowDoesNotDeferFitUntilLaterContent() throws {
    _ = NSApplication.shared
    let editorController = try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let windowController = SionDocumentWindowController(editorController: editorController)
    let window = try XCTUnwrap(windowController.window)
    let autosaveName = isolateFrameAutosave(for: window)
    defer {
      windowController.close()
      NSWindow.removeFrame(usingName: autosaveName)
    }
    let scrollView = try XCTUnwrap(window.contentView as? NSScrollView)

    windowController.showWindow(nil)
    let magnificationAfterEmptyShow = scrollView.magnification

    _ = try editorController.insertShape(
      in: InitialFitTestGeometry.lateElementFrame,
      kind: .rectangle
    )
    window.setContentSize(InitialFitTestGeometry.resizedWindowContentSize)
    windowController.windowDidResize(
      Notification(name: NSWindow.didResizeNotification, object: window)
    )

    XCTAssertEqual(
      scrollView.magnification,
      magnificationAfterEmptyShow,
      accuracy: InitialFitTestGeometry.magnificationAccuracy
    )
  }

  private func makeInitialFitWindowController() throws -> SionDocumentWindowController {
    let element = SceneElement.shape(frame: InitialFitTestGeometry.elementFrame)
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(InitialFitTestGeometry.canvasSize)),
      elements: [element]
    )
    let editorController = try SionEditorController(
      package: SionPackage(document: SionDocument(scene: scene)),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )

    return SionDocumentWindowController(editorController: editorController)
  }

  private func isolateFrameAutosave(for window: NSWindow) -> NSWindow.FrameAutosaveName {
    let name = NSWindow.FrameAutosaveName(
      "Sion.Tests.InitialFit.\(UUID().uuidString)"
    )
    XCTAssertTrue(window.setFrameAutosaveName(name))
    window.setContentSize(InitialFitTestGeometry.windowContentSize)

    return name
  }
}

private final class TestResponderView: NSView {
  override var acceptsFirstResponder: Bool { true }
}

private enum ZoomTestCommand {
  static let zoomInSegment = 2
  static let action = NSSelectorFromString("performZoomCommand:")
  static let actualSizeMagnification: CGFloat = 1
}

private enum InitialFitTestGeometry {
  static let canvasSize = SionSize(width: 2_400, height: 1_600)
  static let elementFrame = SionRect(x: 80, y: 80, width: 160, height: 90)
  static let lateElementFrame = SionRect(x: 80, y: 80, width: 2_400, height: 1_600)
  static let windowContentSize = NSSize(width: 800, height: 600)
  static let resizedWindowContentSize = NSSize(width: 900, height: 700)
  static let magnificationAccuracy = 0.000_001
  static let queueDrainTimeout = 1.0
}
