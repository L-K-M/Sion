import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasContextMenuTests: XCTestCase {
  func testASecondaryClickSelectsWhatItLandsOn() throws {
    _ = NSApplication.shared
    let first = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 100, height: 80))
    let second = SceneElement.shape(frame: SionRect(x: 200, y: 0, width: 100, height: 80))
    let controller = try makeController(elements: [first, second])
    let canvas = makeCanvas(controller)

    XCTAssertNotNil(canvas.menu(for: try event(canvas, at: SionPoint(x: 50, y: 40))))
    XCTAssertEqual(controller.selection, [first.id])

    // An element already inside the selection keeps the whole selection, so a
    // command chosen from the menu still applies to everything it describes.
    controller.select([first.id, second.id])
    _ = canvas.menu(for: try event(canvas, at: SionPoint(x: 250, y: 40)))

    XCTAssertEqual(controller.selection, [first.id, second.id])

    // One outside it replaces it.
    controller.select(second.id)
    _ = canvas.menu(for: try event(canvas, at: SionPoint(x: 50, y: 40)))

    XCTAssertEqual(controller.selection, [first.id])

    _ = canvas.menu(for: try event(canvas, at: SionPoint(x: 400, y: 260)))

    XCTAssertTrue(controller.selection.isEmpty)
  }

  func testEveryContextCommandReachesAResponderThatImplementsIt() throws {
    _ = NSApplication.shared
    let controller = try makeController(elements: [])
    let windowController = SionDocumentWindowController(editorController: controller)
    defer { windowController.close() }

    let canvas = makeCanvas(controller)
    let actions = Self.commandActions(in: SionCanvasContextMenu.entries)

    XCTAssertFalse(actions.isEmpty)

    // The selectors are resolved by name, so a typo would otherwise show up as
    // a permanently greyed-out row rather than a build failure.
    for action in actions {
      XCTAssertTrue(
        canvas.responds(to: action) || windowController.responds(to: action),
        "Nothing implements \(action)"
      )
    }
  }

  func testTheMenuOffersTheDocumentCommandsAndValidatesThemAgainstTheSelection() throws {
    _ = NSApplication.shared
    let element = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 100, height: 80))
    let controller = try makeController(elements: [element])
    let canvas = makeCanvas(controller)
    let menu = try XCTUnwrap(canvas.menu(for: try event(canvas, at: SionPoint(x: 400, y: 260))))

    XCTAssertEqual(
      menu.items.filter { !$0.isSeparatorItem }.map(\.title),
      [
        "Cut", "Copy", "Paste", "Duplicate", "Delete",
        "Add to Library", "Arrange",
        "Lock", "Unlock", "Hide Selection", "Reveal All Hidden",
        "Select All", "Show Grid", "Snap to Objects", "Zoom to Fit",
      ]
    )
    XCTAssertEqual(
      menu.item(withTitle: "Add to Library")?.submenu?.items.map(\.title),
      ["This Document", "All Documents"]
    )

    let copyItem = try XCTUnwrap(menu.item(withTitle: "Copy"))
    let addToLibrary = try XCTUnwrap(
      menu.item(withTitle: "Add to Library")?.submenu?.item(withTitle: "This Document")
    )

    // The click above landed on empty canvas, so it cleared the selection.
    XCTAssertFalse(canvas.validateMenuItem(copyItem))
    XCTAssertFalse(canvas.validateMenuItem(addToLibrary))

    controller.select(element.id)

    XCTAssertTrue(canvas.validateMenuItem(copyItem))
    XCTAssertTrue(canvas.validateMenuItem(addToLibrary))
  }

  func testAddingToTheDocumentLibraryStoresTheSelectionUnderItsOwnName() throws {
    _ = NSApplication.shared
    let element = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 100, height: 80))
    let controller = try makeController(elements: [element])
    let canvas = makeCanvas(controller)
    controller.select(element.id)

    canvas.addSelectionToDocumentLibrary(nil)

    XCTAssertEqual(controller.documentLibrary.items.map(\.name), ["Shape"])

    try controller.renameSelection("Decision")
    canvas.addSelectionToDocumentLibrary(nil)

    XCTAssertEqual(controller.documentLibrary.items.map(\.name), ["Decision", "Shape"])
  }

  private static func commandActions(in entries: [SionCanvasContextMenu.Entry]) -> [Selector] {
    entries.flatMap { entry -> [Selector] in
      switch entry {
      case .command(_, let action, _, _):
        [action]
      case .separator:
        []
      case .submenu(_, let entries):
        commandActions(in: entries)
      }
    }
  }

  private func makeController(elements: [SceneElement]) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(
          scene: SionScene(
            canvas: SionCanvas(extent: .fixed(SionSize(width: 640, height: 480))),
            elements: elements
          )
        )
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func makeCanvas(_ controller: SionEditorController) -> SionCanvasView {
    let canvas = SionCanvasView(editorController: controller)
    canvas.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    return canvas
  }

  private func event(_ canvas: SionCanvasView, at point: SionPoint) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .rightMouseDown,
        location: canvas.convert(canvas.viewPoint(for: point), to: nil),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )
    )
  }
}
