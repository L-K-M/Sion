import AppKit
import XCTest

@testable import SionKit

@MainActor
final class PalettePopoverTests: XCTestCase {
  private let paletteContentSize = NSSize(width: 320, height: 240)

  func testContentSizingGivesScrollingContentADefiniteFittingSize() {
    _ = NSApplication.shared
    let content = PaletteScrollingTestContent()

    makeDefinition().applyContentSizing(to: content)

    XCTAssertEqual(content.preferredContentSize, paletteContentSize)
    XCTAssertGreaterThanOrEqual(content.view.fittingSize.width, paletteContentSize.width)
    XCTAssertGreaterThanOrEqual(content.view.fittingSize.height, paletteContentSize.height)
  }

  func testPopoverKeepsTheRequestedSizeWhenTheContentPrefersAnother() {
    _ = NSApplication.shared
    let content = PaletteScrollingTestContent()
    content.preferredContentSize = NSSize(width: 120, height: 90)

    let popover = NSPopover()
    // Attaching the controller re-derives the size, so the request has to be
    // applied after it. Reversing these two lines fails this assertion.
    popover.contentViewController = content
    popover.contentSize = paletteContentSize

    XCTAssertEqual(popover.contentSize, paletteContentSize)
  }

  func testPopoverPresentsScrollingContentAtTheDeclaredContentSize() throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 80, height: 24))
    try XCTUnwrap(window.contentView).addSubview(anchor)
    window.orderFrontRegardless()
    defer { window.close() }

    let palette = Palette(
      definition: makeDefinition(),
      target: { NSObject() },
      makeContent: PaletteScrollingTestContent.init
    )
    defer { drainClose(palette) }

    palette.present(from: anchor)

    let popover = try XCTUnwrap(palette.presentedPopover)

    XCTAssertEqual(popover.contentSize, paletteContentSize)
    XCTAssertEqual(palette.presentation, .popover)

    let contentView = try XCTUnwrap(popover.contentViewController?.view)
    contentView.layoutSubtreeIfNeeded()

    XCTAssertGreaterThanOrEqual(contentView.frame.width, paletteContentSize.width)
    XCTAssertGreaterThanOrEqual(contentView.frame.height, paletteContentSize.height)
  }

  private func makeDefinition() -> PaletteDefinition {
    PaletteDefinition(
      kind: PaletteKind("tests.popover.scrolling"),
      title: "Popover Scrolling Test",
      contentSize: paletteContentSize
    )
  }

  private func drainClose(_ palette: Palette) {
    palette.close()
    let deadline = Date(timeIntervalSinceNow: 1)
    while palette.isPresented || palette.presentedPopover != nil, Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }
}

/// Mirrors a palette body: a scroll view whose document stack is taller than the
/// viewport and supplies no height to the scroll view itself.
@MainActor
private final class PaletteScrollingTestContent: NSViewController, PaletteContent {
  typealias Target = NSObject

  override func loadView() {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    for index in 0..<24 {
      stack.addArrangedSubview(NSTextField(labelWithString: "Row \(index)"))
    }

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.documentView = stack
    stack.translatesAutoresizingMaskIntoConstraints = false
    let clipView = scrollView.contentView
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: clipView.topAnchor),
      stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
      stack.widthAnchor.constraint(equalTo: clipView.widthAnchor),
    ])
    view = scrollView
  }

  func retarget(to target: NSObject?) {}
}
