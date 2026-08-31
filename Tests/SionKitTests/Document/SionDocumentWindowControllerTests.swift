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

  func testZoomToolbarShowsCurrentPercentage() throws {
    _ = NSApplication.shared
    let windowController = try makeZoomWindowController()
    defer { windowController.close() }

    let item = try zoomToolbarItem(
      from: windowController,
      placement: .installed
    )
    let label = try zoomPercentageLabel(in: item)

    XCTAssertEqual(label.stringValue, "100%")
    XCTAssertEqual(label.accessibilityLabel(), "Zoom level")
  }

  func testZoomPercentageTracksInstalledToolbarItem() throws {
    _ = NSApplication.shared
    let windowController = try makeZoomWindowController()
    defer { windowController.close() }
    let scrollView = try XCTUnwrap(windowController.window?.contentView as? NSScrollView)
    let installedItem = try zoomToolbarItem(
      from: windowController,
      placement: .installed
    )
    let installedLabel = try zoomPercentageLabel(in: installedItem)

    windowController.zoomIn(nil)
    XCTAssertEqual(installedLabel.stringValue, "120%")

    // A customization preview must not replace the installed item's live state.
    _ = try zoomToolbarItem(
      from: windowController,
      placement: .customizationPalette
    )
    scrollView.magnification = ZoomPercentageTestValue.directMagnification

    XCTAssertEqual(installedLabel.stringValue, "125%")
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

  func testSingleClickArmsAToolAndASecondClickKeepsItActive() throws {
    _ = NSApplication.shared
    let editorController = try makeEditorController()
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    windowController.selectTool(.rectangle, clickCount: 1)

    XCTAssertEqual(editorController.tool, .rectangle)
    XCTAssertEqual(editorController.toolPersistence, .oneShot)

    windowController.selectTool(.rectangle, clickCount: 2)

    XCTAssertEqual(editorController.tool, .rectangle)
    XCTAssertEqual(editorController.toolPersistence, .sticky)
  }

  func testToolSegmentsDescribeTheirPersistence() throws {
    _ = NSApplication.shared
    let editorController = try makeEditorController()
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    let control = try toolsSegmentedControl(in: windowController)
    windowController.selectTool(.rectangle, clickCount: 1)

    XCTAssertEqual(control.selectedSegment, SionEditorController.Tool.rectangle.rawValue)
    XCTAssertEqual(
      control.toolTip(forSegment: SionEditorController.Tool.rectangle.rawValue),
      "\(SionEditorController.Tool.rectangle.help). Reverts to Select after one use"
    )
    XCTAssertEqual(
      control.toolTip(forSegment: SionEditorController.Tool.circle.rawValue),
      "\(SionEditorController.Tool.circle.help). Double-click to keep the tool active"
    )
    XCTAssertEqual(
      control.toolTip(forSegment: SionEditorController.Tool.select.rawValue),
      SionEditorController.Tool.select.help
    )
    XCTAssertEqual(
      windowController.toolAccessibilityValue,
      "Rounded Rectangle. Reverts to Select after one use"
    )
  }

  func testChoosingAnArmedToolAgainKeepsItActiveWithoutAClickCount() throws {
    _ = NSApplication.shared
    let editorController = try makeEditorController()
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    // A keyboard or accessibility press reports no click count at all.
    windowController.selectTool(.rectangle, clickCount: 1)
    XCTAssertEqual(editorController.toolPersistence, .oneShot)

    windowController.selectTool(.rectangle, clickCount: 1)

    XCTAssertEqual(editorController.tool, .rectangle)
    XCTAssertEqual(editorController.toolPersistence, .sticky)
  }

  func testChoosingAToolAgainAfterItWasSpentArmsAnotherSingleUse() throws {
    _ = NSApplication.shared
    let editorController = try makeEditorController()
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    windowController.selectTool(.rectangle, clickCount: 1)
    editorController.toolDidComplete(.rectangle)
    XCTAssertEqual(editorController.tool, .select)

    // Two quick single uses are not a double click.
    windowController.selectTool(.rectangle, clickCount: 1)

    XCTAssertEqual(editorController.toolPersistence, .oneShot)
  }

  func testToolClickCountIgnoresEventsWithoutAClickCount() throws {
    let key = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: " ",
        charactersIgnoringModifiers: " ",
        isARepeat: false,
        keyCode: 49
      )
    )
    let doubleClick = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 2,
        pressure: 1
      )
    )

    XCTAssertEqual(SionDocumentWindowController.toolClickCount(for: nil), 1)
    XCTAssertEqual(SionDocumentWindowController.toolClickCount(for: key), 1)
    XCTAssertEqual(SionDocumentWindowController.toolClickCount(for: doubleClick), 2)
  }

  func testCustomizationPaletteToolsCopyDoesNotStealSynchronization() throws {
    _ = NSApplication.shared
    let editorController = try makeEditorController()
    let windowController = SionDocumentWindowController(editorController: editorController)
    defer { windowController.close() }

    let installed = try toolsSegmentedControl(in: windowController, willBeInserted: true)
    _ = try toolsSegmentedControl(in: windowController, willBeInserted: false)

    windowController.selectTool(.circle, clickCount: 2)

    XCTAssertEqual(installed.selectedSegment, SionEditorController.Tool.circle.rawValue)
    XCTAssertEqual(
      installed.toolTip(forSegment: SionEditorController.Tool.circle.rawValue),
      "\(SionEditorController.Tool.circle.help). Stays active until another tool is chosen"
    )
  }

  private func toolsSegmentedControl(
    in windowController: SionDocumentWindowController,
    willBeInserted: Bool = true
  ) throws -> NSSegmentedControl {
    let toolbar = NSToolbar(identifier: "Sion.Tests.Tools")
    let item = try XCTUnwrap(
      windowController.toolbar(
        toolbar,
        itemForItemIdentifier: NSToolbarItem.Identifier("Sion.Tools"),
        willBeInsertedIntoToolbar: willBeInserted
      )
    )

    return try XCTUnwrap(item.view as? NSSegmentedControl)
  }

  private func makeEditorController() throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func makeZoomWindowController() throws -> SionDocumentWindowController {
    let editorController = try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )

    return SionDocumentWindowController(editorController: editorController)
  }

  private func zoomToolbarItem(
    from windowController: SionDocumentWindowController,
    placement: ZoomToolbarTestPlacement
  ) throws -> NSToolbarItem {
    let toolbar = NSToolbar(identifier: "Sion.Tests.ZoomPercentage")

    return try XCTUnwrap(
      windowController.toolbar(
        toolbar,
        itemForItemIdentifier: NSToolbarItem.Identifier("Sion.Zoom"),
        willBeInsertedIntoToolbar: placement.willBeInserted
      )
    )
  }

  private func zoomPercentageLabel(in item: NSToolbarItem) throws -> NSTextField {
    let stack = try XCTUnwrap(item.view as? NSStackView)

    return try XCTUnwrap(
      stack.arrangedSubviews.compactMap { $0 as? NSTextField }.first
    )
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

private enum ZoomToolbarTestPlacement {
  case installed
  case customizationPalette

  var willBeInserted: Bool {
    switch self {
    case .installed: true
    case .customizationPalette: false
    }
  }
}

private enum ZoomPercentageTestValue {
  static let directMagnification: CGFloat = 1.25
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
