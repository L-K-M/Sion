import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class InspectorPaletteTests: XCTestCase {
  func testFloatingInspectorObservesDocumentSelection() throws {
    _ = NSApplication.shared
    var shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    shape.name = "Process"
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let documentController = SionDocumentWindowController(editorController: editor)
    defer { documentController.close() }

    let documentWindow = try XCTUnwrap(documentController.window)
    documentWindow.orderFrontRegardless()
    let inspector = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.inspector.paletteKind)
    )
    defer { inspector.close() }

    inspector.showPanel()

    editor.select(shape.id)

    let panel = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Inspector" && $0.isVisible }
    )
    let labels = try XCTUnwrap(panel.contentView).inspectorTestDescendants.compactMap {
      ($0 as? NSTextField)?.stringValue
    }
    XCTAssertTrue(labels.contains("Process"))
  }

  func testCustomAnchorModeEndsWithDoneOrPanelClose() throws {
    _ = NSApplication.shared
    let shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(shape.id)
    let documentController = SionDocumentWindowController(editorController: editor)
    defer { documentController.close() }

    let documentWindow = try XCTUnwrap(documentController.window)
    documentWindow.orderFrontRegardless()
    let inspector = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.inspector.paletteKind)
    )
    defer { inspector.close() }
    inspector.showPanel()

    let panel = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Inspector" && $0.isVisible }
    )
    let descendants = try XCTUnwrap(panel.contentView).inspectorTestDescendants
    let anchorPopup = try XCTUnwrap(
      descendants.compactMap { $0 as? NSPopUpButton }.first {
        $0.toolTip == "Choose where connectors attach to the selected object."
      }
    )
    anchorPopup.selectItem(withTitle: "Custom points…")
    let action = try XCTUnwrap(anchorPopup.action)

    XCTAssertTrue(NSApp.sendAction(action, to: anchorPopup.target, from: anchorPopup))
    XCTAssertEqual(editor.anchorEditingState, .editing(shape.id))

    let instruction = descendants.compactMap { $0 as? NSTextField }.first {
      $0.stringValue == "Click the object to add an anchor; click an anchor to remove it."
    }
    let done = descendants.compactMap { $0 as? NSButton }.first { $0.title == "Done" }
    XCTAssertFalse(try XCTUnwrap(instruction).isHidden)
    XCTAssertFalse(try XCTUnwrap(done).isHidden)

    done?.performClick(nil)

    XCTAssertEqual(editor.anchorEditingState, .inactive)

    anchorPopup.selectItem(withTitle: "Custom points…")
    XCTAssertTrue(NSApp.sendAction(action, to: anchorPopup.target, from: anchorPopup))
    XCTAssertEqual(editor.anchorEditingState, .editing(shape.id))

    inspector.close()

    XCTAssertEqual(editor.anchorEditingState, .inactive)
  }

  func testCustomAnchorOptionPromotesPopoverToPanel() throws {
    _ = NSApplication.shared
    let shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(shape.id)
    let documentController = SionDocumentWindowController(editorController: editor)
    defer { documentController.close() }

    let documentWindow = try XCTUnwrap(documentController.window)
    let contentView = try XCTUnwrap(documentWindow.contentView)
    let anchor = NSButton(frame: NSRect(x: 20, y: 20, width: 24, height: 24))
    contentView.addSubview(anchor)
    documentWindow.orderFrontRegardless()

    let inspector = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.inspector.paletteKind)
    )
    defer { inspector.close() }
    inspector.present(from: anchor)

    let anchorPopup = try XCTUnwrap(
      NSApp.windows.lazy.filter(\.isVisible).compactMap(\.contentView)
        .flatMap(\.inspectorTestDescendants)
        .compactMap { $0 as? NSPopUpButton }
        .first { $0.toolTip == "Choose where connectors attach to the selected object." }
    )
    anchorPopup.selectItem(withTitle: "Custom points…")
    let action = try XCTUnwrap(anchorPopup.action)

    XCTAssertTrue(NSApp.sendAction(action, to: anchorPopup.target, from: anchorPopup))
    runMainLoop(until: { inspector.isFloating })

    XCTAssertTrue(inspector.isFloating)
    XCTAssertEqual(editor.anchorEditingState, .editing(shape.id))
  }

  private func runMainLoop(until condition: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: TestTiming.presentationTimeout)
    while !condition(), Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: TestTiming.pollInterval))
    }
  }
}

private enum TestTiming {
  static let presentationTimeout = 2.0
  static let pollInterval = 0.01
}

extension NSView {
  fileprivate var inspectorTestDescendants: [NSView] {
    subviews + subviews.flatMap(\.inspectorTestDescendants)
  }
}
