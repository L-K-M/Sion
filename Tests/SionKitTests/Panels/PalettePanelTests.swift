import AppKit
import XCTest

@testable import SionKit

@MainActor
final class PalettePanelTests: XCTestCase {
  func testHeaderProvidesWindowDragRegion() throws {
    _ = NSApplication.shared
    let panel = makePanel()
    let contentView = try XCTUnwrap(panel.contentView)
    let header = try XCTUnwrap(
      contentView.descendants.first { $0 is NSVisualEffectView }
    )

    XCTAssertTrue(panel.isMovable)
    XCTAssertTrue(header.acceptsFirstMouse(for: nil))
    XCTAssertTrue(header.mouseDownCanMoveWindow)
  }

  func testPanelSizesItsChromeAndContentFromTheDefinition() throws {
    _ = NSApplication.shared
    let panel = makePanel()
    let content = PaletteTestContent()
    panel.embed(content)
    let chrome = try XCTUnwrap(panel.contentView)

    // The palette's own 320 points plus the panel's 24pt header. The palette
    // bodies scroll and so fit to nothing on their own: without a size stated
    // here the chrome fits its header alone and the panel opens as a bare pill.
    XCTAssertEqual(chrome.fittingSize.width, PalettePanelTestGeometry.contentSize.width)
    XCTAssertEqual(
      chrome.fittingSize.height,
      PalettePanelTestGeometry.contentSize.height + PalettePanelTestGeometry.headerHeight
    )

    chrome.setFrameSize(chrome.fittingSize)
    chrome.layoutSubtreeIfNeeded()

    XCTAssertEqual(content.view.frame.size, PalettePanelTestGeometry.contentSize)
  }

  func testHeaderHitTestingReachesTheCloseButtonAndTheDragRegion() throws {
    _ = NSApplication.shared
    let panel = makePanel()
    let chrome = try XCTUnwrap(panel.contentView)
    chrome.setFrameSize(chrome.fittingSize)
    chrome.layoutSubtreeIfNeeded()

    let header = try XCTUnwrap(chrome.descendants.first { $0 is NSVisualEffectView })
    let closeButton = try XCTUnwrap(chrome.descendants.compactMap { $0 as? NSButton }.first)

    // `hitTest` takes points in the header's superview, which is the chrome.
    // The header sits at the top of an unflipped chrome, so a header that only
    // looks at its own bounds misses every click that lands on it.
    let onCloseButton = chrome.convert(
      NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
      from: closeButton
    )
    let onDragRegion = chrome.convert(
      NSPoint(x: header.bounds.maxX - 4, y: header.bounds.midY),
      from: header
    )

    XCTAssertIdentical(header.hitTest(onCloseButton), closeButton)
    XCTAssertIdentical(header.hitTest(onDragRegion), header)
    XCTAssertNil(header.hitTest(NSPoint(x: chrome.bounds.midX, y: chrome.bounds.midY)))
  }

  func testCloseButtonClosesPanel() throws {
    _ = NSApplication.shared
    let panel = makePanel()
    panel.setCloseHandler { [weak panel] in
      panel?.close()
    }
    panel.orderFrontRegardless()

    let contentView = try XCTUnwrap(panel.contentView)
    let closeButton = try XCTUnwrap(
      contentView.descendants.compactMap { $0 as? NSButton }.first {
        $0.toolTip == "Close \(PalettePanelTestCopy.title) Palette"
      }
    )

    XCTAssertTrue(panel.styleMask.contains(.closable))
    XCTAssertTrue(closeButton.acceptsFirstMouse(for: nil))
    closeButton.performClick(nil)

    XCTAssertFalse(panel.isVisible)
  }

  func testPaletteCloseClosesFloatingPanel() throws {
    _ = NSApplication.shared
    let palette = Palette(
      definition: PaletteDefinition(
        kind: PaletteKind("tests.close"),
        title: "Palette Close Test",
        contentSize: NSSize(width: 300, height: 320)
      ),
      target: { NSObject() },
      makeContent: PaletteTestContent.init
    )
    defer { palette.close() }

    palette.showPanel()
    let panel = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Palette Close Test" && $0.isVisible }
    )

    palette.close()

    XCTAssertFalse(panel.isVisible)
  }

  private func makePanel() -> PalettePanel {
    PalettePanel(
      definition: PaletteDefinition(
        kind: PaletteKind("tests.inspector"),
        title: PalettePanelTestCopy.title,
        contentSize: PalettePanelTestGeometry.contentSize
      )
    )
  }
}

private enum PalettePanelTestCopy {
  static let title = "Palette Panel Test"
}

private enum PalettePanelTestGeometry {
  static let contentSize = NSSize(width: 300, height: 320)
  static let headerHeight: CGFloat = 24
}

@MainActor
private final class PaletteTestContent: NSViewController, PaletteContent {
  typealias Target = NSObject

  override func loadView() {
    view = NSView()
  }

  func retarget(to target: NSObject?) {}
}

extension NSView {
  fileprivate var descendants: [NSView] {
    subviews + subviews.flatMap(\.descendants)
  }
}
