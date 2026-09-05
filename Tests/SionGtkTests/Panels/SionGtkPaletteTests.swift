import CGtk
import Foundation
import SionCore
import SionKit
import XCTest

@testable import SionGtk

@MainActor
private final class FakePaletteHost: SionGtkPaletteHost {
  let controller: SionEditorController
  var feedback: [SionEditorFeedbackRequest] = []
  var textEditingStarted: [ElementID] = []
  var commits = 0

  init(controller: SionEditorController) {
    self.controller = controller
  }

  var paletteEditorController: SionEditorController { controller }
  var canvasVisibleCenter: SionPoint { SionPoint(x: 500, y: 400) }
  var toplevel: UnsafeMutablePointer<GtkWindow>? { nil }

  func presentEditorFeedback(_ request: SionEditorFeedbackRequest) {
    feedback.append(request)
  }

  func beginTextEditing(_ id: ElementID) {
    textEditingStarted.append(id)
  }

  func commitPendingEdits() {
    commits += 1
  }
}

@MainActor
final class SionGtkPaletteTests: XCTestCase {
  func testInspectorFollowsSelectionAndCommitsEdits() throws {
    try GtkTestSupport.requireDisplay()
    let shape = CanvasFixture.rectangle(x: 10, y: 10)
    let controller = try CanvasFixture.makeController(elements: [shape])
    let host = FakePaletteHost(controller: controller)
    let inspector = SionGtkInspectorPalette(showAsPanel: {})
    inspector.retarget(to: host)

    XCTAssertEqual(inspector.selectionText, "No selection")
    XCTAssertFalse(inspector.isLockEnabled)

    controller.select(shape.id)
    XCTAssertEqual(inspector.selectionText, shape.displayName)
    XCTAssertTrue(inspector.isLockEnabled)
    XCTAssertTrue(inspector.isFillEnabled)

    inspector.setStrokeWidthForTesting(4)
    XCTAssertEqual(controller.document.scene.element(withID: shape.id)?.style.stroke?.width, 4)

    inspector.setNameForTesting("Box")
    XCTAssertEqual(controller.document.scene.element(withID: shape.id)?.name, "Box")
    XCTAssertEqual(inspector.selectionText, "Box")

    inspector.setLockedForTesting(true)
    XCTAssertEqual(controller.document.scene.element(withID: shape.id)?.lockState, .locked)
    XCTAssertEqual(inspector.selectionText, "Box • Locked")
    XCTAssertFalse(inspector.isFillEnabled)
  }

  func testInspectorCustomMagnetsBeginAnchorEditingAndShowThePanel() throws {
    try GtkTestSupport.requireDisplay()
    let shape = CanvasFixture.rectangle(x: 10, y: 10)
    let controller = try CanvasFixture.makeController(elements: [shape])
    let host = FakePaletteHost(controller: controller)
    var shownAsPanel = 0
    let inspector = SionGtkInspectorPalette(showAsPanel: { shownAsPanel += 1 })
    inspector.retarget(to: host)
    controller.select(shape.id)

    inspector.selectMagnetOptionForTesting(.custom)

    XCTAssertEqual(controller.anchorEditingState, .editing(shape.id))
    XCTAssertEqual(shownAsPanel, 1)
    XCTAssertTrue(inspector.isAnchorEditingVisible)

    // Closing the floating palette ends anchor editing; a popover does not.
    inspector.paletteDidPresent(.panel)
    inspector.paletteDidDismiss(.panel)
    XCTAssertEqual(controller.anchorEditingState, .inactive)
  }

  func testHistoryListsRevisionsAndRestores() throws {
    try GtkTestSupport.requireDisplay()
    let shape = CanvasFixture.rectangle(x: 10, y: 10)
    let controller = try CanvasFixture.makeController(elements: [shape])
    let archive = try SionArchive.encode(
      package: controller.packageForArchiving(), intent: .manual,
      generator: SionArchiveGenerator(name: "Sion", version: "test"))
    let saved = try SionArchive.decode(archive.data)
    let restored = try SionEditorController(
      package: saved, undoManagerProvider: { nil }, didChange: { _ in })
    let host = FakePaletteHost(controller: restored)
    let history = SionGtkHistoryPalette()

    history.retarget(to: nil)
    XCTAssertEqual(history.revisionButtonCount, 0)
    history.retarget(to: host)
    XCTAssertEqual(history.revisionButtonCount, restored.historyRevisions.count)
    XCTAssertGreaterThan(restored.historyRevisions.count, 0)

    history.restoreRevision(restored.historyRevisions[0].identifier)
    XCTAssertEqual(host.commits, 1)
  }

  func testLibraryInsertsShapesAndListsStoredItems() throws {
    try GtkTestSupport.requireDisplay()
    let shape = CanvasFixture.rectangle(x: 10, y: 10)
    let controller = try CanvasFixture.makeController(elements: [shape])
    let host = FakePaletteHost(controller: controller)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("sion-library-\(UUID().uuidString)")
    let library = SionGtkLibraryPalette(globalLibrary: SionGlobalLibrary(directoryURL: directory))
    defer { try? FileManager.default.removeItem(at: directory) }
    library.retarget(to: host)

    XCTAssertEqual(library.displayedItemCount, 0)
    library.addShape(.diamond)
    XCTAssertEqual(controller.document.scene.elements.count, 2)
    XCTAssertEqual(controller.selectedElement?.geometry.frame.center, SionPoint(x: 500, y: 400))

    library.addText()
    XCTAssertEqual(host.textEditingStarted.count, 1)

    controller.select(shape.id)
    _ = try controller.addSelectionToDocumentLibrary(named: "Kept")
    XCTAssertEqual(library.displayedItemCount, 1)

    let reference = SionGtkLibraryPalette.ItemReference(
      scope: .document, id: controller.documentLibrary.entries[0].id)
    library.rename(reference, to: "Renamed")
    XCTAssertEqual(controller.documentLibrary.entries[0].name, "Renamed")
    library.insert(reference)
    XCTAssertEqual(controller.document.scene.elements.count, 4)
    library.remove(reference)
    XCTAssertEqual(library.displayedItemCount, 0)
  }

  func testFeedbackPresenterShowsAndClearsByContext() throws {
    try GtkTestSupport.requireDisplay()
    var announced: [String] = []
    let presenter = SionGtkEditorFeedbackPresenter(announcementHandler: { announced.append($0) })
    let overlay = gtk_overlay_new()!
    gtk_overlay_set_child(overlay.opaque, gtk_label_new("canvas"))

    presenter.handle(.show(.libraryCommandFailed(.full)))
    XCTAssertNil(presenter.presentedMessage)
    presenter.attach(to: overlay)
    XCTAssertEqual(presenter.presentedMessage, "The library is full. Remove an item and try again.")
    XCTAssertEqual(announced.count, 1)

    presenter.handle(.clear(.mermaidSource))
    XCTAssertNotNil(presenter.presentedMessage)
    presenter.handle(.clear(.library))
    XCTAssertNil(presenter.presentedMessage)

    presenter.handle(.show(.commandFailed(.pasteMermaid)))
    XCTAssertEqual(presenter.presentedContext, .mermaidSource)
    presenter.dismissFeedback()
    XCTAssertNil(presenter.presentedContext)
  }

  func testPaletteCenterFloatsWithoutAnAnchorAndCloses() throws {
    try GtkTestSupport.requireDisplay()
    let palette = SionGtkPaletteCenter.shared.palette(for: .history)

    palette.present(relativeTo: nil)
    XCTAssertTrue(palette.isFloating)
    GtkTestSupport.drainMainLoop()

    palette.close()
    GtkTestSupport.drainMainLoop()
    XCTAssertFalse(palette.isPresented)
  }

  func testDefaultShapeShadowIsPainted() throws {
    try GtkTestSupport.requireDisplay()
    var shape = SceneElement.shape(frame: SionRect(x: 100, y: 100, width: 160, height: 96))
    shape.style.shadows = [
      ShadowStyle(
        color: SionColor(red: 0, green: 0, blue: 0), offset: SionVector(dx: 30, dy: 0),
        blurRadius: 0)
    ]
    let canvas = try CanvasFixture.makeCanvas(elements: [shape])
    let bounds = SionRect(x: 0, y: 0, width: 400, height: 300)

    let shadowed = try CanvasFixture.renderedPixel(
      canvas, at: SionPoint(x: 280, y: 148), bounds: bounds)
    let clear = try CanvasFixture.renderedPixel(
      canvas, at: SionPoint(x: 350, y: 148), bounds: bounds)

    XCTAssertGreaterThan(shadowed.alpha, 200)
    XCTAssertEqual(clear.alpha, 0)
  }
}
