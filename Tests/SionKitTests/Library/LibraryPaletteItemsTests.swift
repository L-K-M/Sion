import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class LibraryPaletteItemsTests: XCTestCase {
  func testAStoredSelectionBecomesARowThatPlacesItBack() throws {
    _ = NSApplication.shared
    let fixture = try makeFixture()
    defer { fixture.windowController.close() }

    XCTAssertTrue(fixture.itemButtons.isEmpty)
    XCTAssertEqual(fixture.builtInButtons.count, LibraryLayout.builtInRowCount)

    fixture.editor.select(fixture.elementID)
    let stored = try fixture.editor.addSelectionToDocumentLibrary(named: "Node")

    // The palette watches the document, so storing an item is enough.
    let row = try XCTUnwrap(fixture.itemButtons.first)
    XCTAssertEqual(fixture.itemButtons.count, 1)
    XCTAssertEqual(row.title, "Node")
    XCTAssertEqual(row.identifier?.rawValue, stored.id)
    XCTAssertEqual(fixture.sectionTitles, ["This Document"])

    let insertionCenter = fixture.windowController.canvasVisibleCenter
    row.performClick(nil)

    XCTAssertEqual(fixture.editor.document.scene.elements.count, 2)
    XCTAssertEqual(
      fixture.editor.document.scene.elements.last?.geometry.frame.center,
      insertionCenter
    )
  }

  func testEachLibraryKeepsItsOwnSectionAndItsOwnRemoval() throws {
    _ = NSApplication.shared
    let fixture = try makeFixture()
    defer { fixture.windowController.close() }

    fixture.editor.select(fixture.elementID)
    let documentItem = try fixture.editor.addSelectionToDocumentLibrary(named: "In Document")
    let globalItem = try fixture.globalLibrary.add(
      payload: try fixture.editor.selectionPayloadData(),
      name: "Everywhere"
    )

    XCTAssertEqual(fixture.sectionTitles, ["This Document", "All Documents"])
    XCTAssertEqual(fixture.itemButtons.map(\.title), ["In Document", "Everywhere"])

    fixture.controller.remove(.init(scope: .document, id: documentItem.id))

    XCTAssertEqual(fixture.sectionTitles, ["All Documents"])
    XCTAssertEqual(fixture.itemButtons.map(\.title), ["Everywhere"])
    XCTAssertTrue(fixture.editor.documentLibrary.items.isEmpty)

    fixture.controller.rename(.init(scope: .global, id: globalItem.id), to: "Renamed")

    XCTAssertEqual(fixture.itemButtons.map(\.title), ["Renamed"])

    fixture.controller.remove(.init(scope: .global, id: globalItem.id))

    XCTAssertTrue(fixture.sectionTitles.isEmpty)
    XCTAssertTrue(fixture.itemButtons.isEmpty)
    XCTAssertEqual(fixture.builtInButtons.count, LibraryLayout.builtInRowCount)
  }

  func testEveryRowOffersTheSameTwoCommandsOnASecondaryClick() throws {
    _ = NSApplication.shared
    let fixture = try makeFixture()
    defer { fixture.windowController.close() }

    fixture.editor.select(fixture.elementID)
    _ = try fixture.editor.addSelectionToDocumentLibrary(named: "Node")

    let row = try XCTUnwrap(fixture.itemButtons.first)
    let menu = try XCTUnwrap(row.menu)

    XCTAssertEqual(menu.items.map(\.title), ["Rename…", "Remove from Library"])
    XCTAssertTrue(
      menu.items.allSatisfy {
        $0.representedObject is LibraryPaletteController.ItemReference
      }
    )
  }

  @MainActor
  private struct Fixture {
    let editor: SionEditorController
    let windowController: SionDocumentWindowController
    let globalLibrary: SionGlobalLibrary
    let controller: LibraryPaletteController
    let elementID: ElementID

    var stack: NSStackView {
      (controller.view as? NSScrollView)?.documentView as? NSStackView ?? NSStackView()
    }

    var builtInButtons: [NSButton] {
      buttons.filter { $0.identifier == LibraryPaletteController.builtInItemIdentifier }
    }

    var itemButtons: [NSButton] {
      buttons.filter { $0.identifier != LibraryPaletteController.builtInItemIdentifier }
    }

    var sectionTitles: [String] {
      stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }
    }

    private var buttons: [NSButton] {
      stack.arrangedSubviews.compactMap { $0 as? NSButton }
    }
  }

  private func makeFixture() throws -> Fixture {
    let element = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 80, height: 60))
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [element]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let windowController = SionDocumentWindowController(editorController: editor)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LibraryPaletteItemsTests-\(UUID().uuidString)")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }

    // One store, shared by the palette and the test: a second instance over
    // the same file would keep its own cache and never see these writes.
    let globalLibrary = SionGlobalLibrary(
      fileURL: directory.appendingPathComponent("Library.json")
    )
    let controller = LibraryPaletteController(globalLibrary: globalLibrary)
    controller.retarget(to: windowController)

    return Fixture(
      editor: editor,
      windowController: windowController,
      globalLibrary: globalLibrary,
      controller: controller,
      elementID: element.id
    )
  }
}

private enum LibraryLayout {
  /// Eight shapes and Text.
  static let builtInRowCount = 9
}
