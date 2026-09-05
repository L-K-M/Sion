import CGtk
import Foundation
import SionCore
import SionKit
import XCTest

@testable import SionGtk

@MainActor
final class SionGtkDocumentTests: XCTestCase {
  private let generator = SionArchiveGenerator(name: "Sion", version: "test")

  private func temporaryURL(_ name: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("sion-doc-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(name)
  }

  private func writeArchive(elements: [SceneElement], to url: URL) throws {
    let document = SionDocument(scene: SionScene(elements: elements))
    let archive = try SionArchive.encode(
      package: SionPackage(document: document), intent: .manual, generator: generator)
    try archive.data.write(to: url)
  }

  func testReadingAnArchiveLoadsTheSceneAndNamesTheDocument() throws {
    let url = temporaryURL("Plan.sion")
    try writeArchive(elements: [CanvasFixture.rectangle(x: 10, y: 10)], to: url)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let document = SionGtkDocument(archiveGenerator: generator)
    try document.read(from: url)

    XCTAssertEqual(document.editingController.document.scene.elements.count, 1)
    XCTAssertEqual(document.displayName, "Plan")
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertFalse(document.canRevert)
  }

  func testEditsMarkTheDocumentAndUndoClearsIt() throws {
    let document = SionGtkDocument(archiveGenerator: generator)
    XCTAssertEqual(document.displayName, "Untitled")
    document.untitledNumber = 3
    XCTAssertEqual(document.displayName, "Untitled 3")

    _ = try document.editingController.insertShape(at: SionPoint(x: 10, y: 10))
    XCTAssertTrue(document.isDocumentEdited)
    document.undoManager.undo()
    XCTAssertFalse(document.isDocumentEdited)
  }

  func testEachEventIsItsOwnUndoStep() throws {
    try GtkTestSupport.requireDisplay()
    let document = SionGtkDocument(archiveGenerator: generator)
    let controller = document.editingController

    _ = try controller.insertShape(at: SionPoint(x: 10, y: 10))
    GtkTestSupport.drainMainLoop()
    _ = try controller.insertShape(at: SionPoint(x: 300, y: 10))
    GtkTestSupport.drainMainLoop()
    XCTAssertEqual(controller.document.scene.elements.count, 2)

    document.undoManager.undo()
    XCTAssertEqual(controller.document.scene.elements.count, 1)
    XCTAssertTrue(document.isDocumentEdited)
    document.undoManager.undo()
    XCTAssertTrue(controller.document.scene.elements.isEmpty)
    XCTAssertFalse(document.isDocumentEdited)
    document.undoManager.redo()
    XCTAssertEqual(controller.document.scene.elements.count, 1)
  }

  func testClosingAnEditedFileDocumentAutosavesInPlace() throws {
    let url = temporaryURL("Auto.sion")
    try writeArchive(elements: [], to: url)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let document = SionGtkDocument(archiveGenerator: generator)
    try document.read(from: url)
    _ = try document.editingController.insertShape(at: SionPoint(x: 10, y: 10))
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertTrue(document.canRevert)

    var allowed: Bool?
    document.canClose { allowed = $0 }

    XCTAssertEqual(allowed, true)
    XCTAssertFalse(document.isDocumentEdited)
    let reread = try SionArchive.decode(Data(contentsOf: url))
    XCTAssertEqual(reread.document.scene.elements.count, 1)
    XCTAssertEqual(reread.document.title, "Auto")
  }

  func testAnUntitledEditedDocumentAsksBeforeClosing() throws {
    try GtkTestSupport.requireDisplay()
    let document = SionGtkDocument(archiveGenerator: generator)
    _ = try document.editingController.insertShape(at: SionPoint(x: 10, y: 10))

    var answered = false
    // Without a window the question cannot be asked; the close waits.
    document.canClose { _ in answered = true }
    GtkTestSupport.drainMainLoop()

    XCTAssertFalse(answered)
  }

  func testMermaidInsertionAndExports() throws {
    try GtkTestSupport.requireDisplay()
    let document = SionGtkDocument(archiveGenerator: generator)

    let result = document.insertMermaid("graph TD\n  A --> B")
    XCTAssertNotNil(result)
    XCTAssertGreaterThanOrEqual(document.editingController.document.scene.elements.count, 3)

    let png = try document.imageExportData(options: SionImageExportOptions())
    XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    let mermaid = MermaidExporter.export(document: document.editingController.document)
    XCTAssertTrue(mermaid.source.contains("-->"))
  }

  func testWindowRoutesCommandsToCanvasAndDocument() throws {
    try GtkTestSupport.requireDisplay()
    let application = gtk_application_new("ch.lkmc.Sion.tests", G_APPLICATION_NON_UNIQUE)!
    defer { g_object_unref(application.gobject) }
    // Windows may only join an application that has started up; registering
    // emits GApplication::startup.
    g_application_register(application.cast(), nil, nil)
    let document = SionGtkDocument(archiveGenerator: generator)
    let window = SionGtkDocumentWindow(document: document, application: application, menuModel: nil)

    XCTAssertFalse(window.isEnabled(.undo))
    XCTAssertFalse(window.isEnabled(.copy))
    XCTAssertTrue(window.isEnabled(.save))
    XCTAssertFalse(window.isEnabled(.revertToSaved))

    window.perform(.zoomIn)
    XCTAssertEqual(window.canvasView.magnification, SionGtkCanvasView.zoomStep, accuracy: 0.0001)

    window.selectTool(.circle, clickCount: 1)
    XCTAssertEqual(document.editingController.tool, .circle)
    XCTAssertEqual(document.editingController.toolPersistence, .oneShot)
    XCTAssertEqual(window.toolAccessibilityValue, "Circle. Reverts to Select after one use")
    window.selectTool(.circle, clickCount: 2)
    XCTAssertEqual(document.editingController.toolPersistence, .sticky)

    _ = try document.editingController.insertShape(at: SionPoint(x: 10, y: 10))
    document.editingController.selectAll()
    XCTAssertTrue(window.isEnabled(.copy))
    XCTAssertTrue(window.isEnabled(.undo))
    window.perform(.undo)
    XCTAssertTrue(document.editingController.document.scene.elements.isEmpty)
  }

  func testMenuTreeCoversEveryCommandOnce() {
    var seen: [SionGtkCommand] = []
    func walk(_ entries: [SionGtkMenuEntry]) {
      for entry in entries {
        switch entry {
        case .command(let command): seen.append(command)
        case .submenu(_, let children): walk(children)
        case .separator, .dynamicSection: break
        }
      }
    }
    walk(SionGtkMenuTree.menuBar)

    XCTAssertEqual(Set(seen).count, seen.count, "a command appears twice in the menu bar")
    XCTAssertEqual(Set(seen), Set(SionGtkCommand.allCases))
    for command in SionGtkCommand.allCases where command.scope == .window {
      XCTAssertTrue(command.actionName.hasPrefix("win."), command.rawValue)
    }
    let contextCommands = Set(
      SionGtkMenuTree.canvasContextMenu.compactMap { entry -> SionGtkCommand? in
        if case .command(let command) = entry { return command }
        return nil
      })
    XCTAssertTrue(contextCommands.allSatisfy(\.isCanvasCommand))
  }
}
