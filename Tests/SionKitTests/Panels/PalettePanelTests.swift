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
        $0.toolTip == "Close Inspector Palette"
      }
    )

    XCTAssertTrue(panel.styleMask.contains(.closable))
    XCTAssertTrue(closeButton.acceptsFirstMouse(for: nil))
    closeButton.performClick(nil)

    XCTAssertFalse(panel.isVisible)
  }

  func testClosePrioritizesVisibleDetachedPanel() throws {
    _ = NSApplication.shared
    let host = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    let anchor = NSView(frame: host.contentView?.bounds ?? .zero)
    host.contentView = anchor
    host.orderFrontRegardless()

    let palette = Palette(
      definition: PaletteDefinition(
        kind: PaletteKind("tests.detachment"),
        title: "Inspector",
        contentSize: NSSize(width: 300, height: 320)
      ),
      target: { NSObject() },
      makeContent: PaletteTestContent.init
    )
    defer {
      palette.close()
      host.close()
    }

    palette.present(from: anchor)
    let detachedPanel = try XCTUnwrap(palette.detachableWindow(for: NSPopover()))
    detachedPanel.orderFrontRegardless()

    palette.close()

    XCTAssertFalse(detachedPanel.isVisible)
  }

  private func makePanel() -> PalettePanel {
    PalettePanel(
      definition: PaletteDefinition(
        kind: PaletteKind("tests.inspector"),
        title: "Inspector",
        contentSize: NSSize(width: 300, height: 320)
      )
    )
  }
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
