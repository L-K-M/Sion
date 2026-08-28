import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionLibraryPaletteTests: XCTestCase {
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
    defer { library.close() }
    library.showPanel()

    let panel = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Library" && $0.isVisible }
    )
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
    XCTAssertGreaterThan(stack.frame.height, scrollView.contentView.bounds.height)

    let lastButton = try XCTUnwrap(buttons.last)
    _ = stack.scrollToVisible(lastButton.frame)

    XCTAssertLessThanOrEqual(stack.visibleRect.minY, lastButton.frame.minY)
    XCTAssertGreaterThanOrEqual(stack.visibleRect.maxY, lastButton.frame.maxY)

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
}

extension NSView {
  fileprivate var libraryTestDescendants: [NSView] {
    subviews + subviews.flatMap(\.libraryTestDescendants)
  }
}
