import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionLibraryPaletteTests: XCTestCase {
  private let libraryViewportHeight: CGFloat = 250

  func testLibraryInsertsEveryBuiltInShapeAtTheViewportCenter() throws {
    _ = NSApplication.shared
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let editor = try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { undoManager },
      didChange: { _ in }
    )
    let documentController = SionDocumentWindowController(editorController: editor)
    defer { documentController.close() }

    let documentWindow = try XCTUnwrap(documentController.window)
    documentWindow.orderFrontRegardless()
    let library = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.library.paletteKind)
    )
    defer { drainClose(library) }
    library.showPanel()

    let libraryPanels = NSApp.windows.filter { $0.title == "Library" && $0.isVisible }
    XCTAssertEqual(libraryPanels.count, 1)
    let panel = try XCTUnwrap(libraryPanels.first)
    let descendants = try XCTUnwrap(panel.contentView).libraryTestDescendants
    let scrollView = try XCTUnwrap(
      descendants.compactMap { $0 as? NSScrollView }.first
    )
    let stack = try XCTUnwrap(scrollView.documentView as? NSStackView)
    let buttons = stack.arrangedSubviews.compactMap { $0 as? NSButton }
    let expectedShapes: [(title: String, kind: ShapeKind, size: SionSize)] = [
      ("Rectangle", .rectangle, SionSize(width: 160, height: 96)),
      (
        "Rounded Rectangle",
        .roundedRectangle(radius: SceneElementDefaults.cornerRadius),
        SionSize(width: 160, height: 96)
      ),
      ("Ellipse", .ellipse, SionSize(width: 120, height: 120)),
      ("Diamond", .diamond, SionSize(width: 160, height: 96)),
      ("Triangle", .triangle, SionSize(width: 160, height: 96)),
      ("Hexagon", .hexagon, SionSize(width: 160, height: 96)),
      ("Capsule", .capsule, SionSize(width: 160, height: 96)),
      ("Cylinder", .cylinder, SionSize(width: 160, height: 96)),
    ]

    XCTAssertEqual(buttons.map(\.title), expectedShapes.map(\.title) + ["Text"])
    XCTAssertTrue(scrollView.hasVerticalScroller)

    panel.contentView?.layoutSubtreeIfNeeded()

    XCTAssertTrue(buttons.allSatisfy { !$0.frame.isEmpty })
    XCTAssertGreaterThan(stack.fittingSize.height, libraryViewportHeight)

    for expected in expectedShapes {
      let button = try XCTUnwrap(buttons.first { $0.title == expected.title })
      let insertionCenter = documentController.canvasVisibleCenter

      undoManager.beginUndoGrouping()
      button.performClick(nil)
      undoManager.endUndoGrouping()

      let element = try XCTUnwrap(editor.document.scene.elements.last)
      guard case .shape(let shape) = element.content else {
        return XCTFail("Expected \(expected.title) to insert a shape")
      }

      XCTAssertEqual(shape.kind, expected.kind)
      XCTAssertEqual(element.geometry.frame.center, insertionCenter)
      XCTAssertEqual(element.geometry.frame.size, expected.size)
      XCTAssertEqual(editor.selection, [element.id])
    }

    XCTAssertEqual(editor.document.scene.elements.count, expectedShapes.count)
    XCTAssertEqual(undoManager.undoActionName, "Add Shape")

    undoManager.undo()

    XCTAssertEqual(editor.document.scene.elements.count, expectedShapes.count - 1)
  }

  func testLibraryPopoverPresentsEveryEntryAtTheDeclaredContentSize() throws {
    _ = NSApplication.shared
    SionPalettes.shared.registerIfNeeded()

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

    let library = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.library.paletteKind)
    )
    // A palette is app global, so any earlier presentation has to be gone first.
    drainClose(library)
    defer { drainClose(library) }

    library.present(from: anchor)

    let popover = try XCTUnwrap(library.presentedPopover)

    // Asserting against the registered definition keeps the test honest when
    // the palette is re-declared at another size.
    XCTAssertEqual(popover.contentSize, library.definitionContentSize)

    let scrollView = try XCTUnwrap(popover.contentViewController?.view as? NSScrollView)
    scrollView.layoutSubtreeIfNeeded()

    let stack = try XCTUnwrap(scrollView.documentView as? NSStackView)
    let buttons = stack.arrangedSubviews.compactMap { $0 as? NSButton }

    XCTAssertEqual(buttons.count, 9)
    XCTAssertGreaterThanOrEqual(scrollView.frame.width, library.definitionContentSize.width)
    XCTAssertGreaterThanOrEqual(scrollView.frame.height, library.definitionContentSize.height)
    XCTAssertGreaterThan(stack.fittingSize.height, libraryViewportHeight)
    XCTAssertTrue(buttons.allSatisfy { !$0.frame.isEmpty })
  }

  func testHistoryPopoverScrollsWithoutItsOwnBackingOrBorder() throws {
    _ = NSApplication.shared
    SionPalettes.shared.registerIfNeeded()

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

    let history = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.history.paletteKind)
    )
    drainClose(history)
    defer { drainClose(history) }

    history.present(from: anchor)

    let popover = try XCTUnwrap(history.presentedPopover)
    let scrollView = try XCTUnwrap(popover.contentViewController?.view as? NSScrollView)

    XCTAssertEqual(popover.contentSize, history.definitionContentSize)
    XCTAssertTrue(scrollView.hasVerticalScroller)
    XCTAssertFalse(scrollView.drawsBackground)
    XCTAssertEqual(scrollView.borderType, .noBorder)
  }

  private func drainClose(_ palette: Palette) {
    palette.close()
    let deadline = Date(timeIntervalSinceNow: 1)
    while palette.isPresented || palette.presentedPopover != nil, Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
  }
}

extension NSView {
  fileprivate var libraryTestDescendants: [NSView] {
    subviews + subviews.flatMap(\.libraryTestDescendants)
  }
}
