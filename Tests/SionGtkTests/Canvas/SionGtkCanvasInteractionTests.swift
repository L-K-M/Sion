import CGtk
import Foundation
import SionCore
import SionKit
import XCTest

@testable import SionGtk

@MainActor
final class SionGtkCanvasInteractionTests: XCTestCase {
  private var a = ElementID()
  private var b = ElementID()

  private func makeCanvas() throws -> (SionGtkCanvasView, SionUndoManager) {
    try GtkTestSupport.requireDisplay()
    let undoManager = SionUndoManager()
    let first = CanvasFixture.rectangle(x: 100, y: 100, label: "A")
    let second = CanvasFixture.rectangle(x: 400, y: 100)
    a = first.id
    b = second.id
    let canvas = try CanvasFixture.makeCanvas(elements: [first, second], undoManager: undoManager)
    return (canvas, undoManager)
  }

  func testPressSelectsAndDragMovesAsOneUndoStep() throws {
    let (canvas, undoManager) = try makeCanvas()
    let controller = canvas.editorController

    canvas.handlePress(at: SionPoint(x: 180, y: 148), modifiers: [], clickCount: 1)
    XCTAssertEqual(controller.selection, [a])

    canvas.handleMotion(to: SionPoint(x: 200, y: 158), modifiers: [])
    canvas.handleMotion(to: SionPoint(x: 210, y: 168), modifiers: [])
    canvas.handleRelease(at: SionPoint(x: 210, y: 168), modifiers: [])

    let frame = controller.document.scene.element(withID: a)?.geometry.frame
    XCTAssertEqual(frame?.minX ?? 0, 130, accuracy: 0.01)
    XCTAssertEqual(frame?.minY ?? 0, 120, accuracy: 0.01)
    XCTAssertTrue(undoManager.canUndo)
    undoManager.undo()
    XCTAssertEqual(
      controller.document.scene.element(withID: a)?.geometry.frame.minX, 100)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testMarqueeSelectsIntersectingElementsAndShiftExtends() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController

    canvas.handlePress(at: SionPoint(x: 50, y: 50), modifiers: [], clickCount: 1)
    canvas.handleMotion(to: SionPoint(x: 300, y: 250), modifiers: [])
    canvas.handleRelease(at: SionPoint(x: 300, y: 250), modifiers: [])
    XCTAssertEqual(controller.selection, [a])

    canvas.handlePress(at: SionPoint(x: 380, y: 50), modifiers: .shift, clickCount: 1)
    canvas.handleMotion(to: SionPoint(x: 600, y: 250), modifiers: .shift)
    canvas.handleRelease(at: SionPoint(x: 600, y: 250), modifiers: .shift)
    XCTAssertEqual(controller.selection, [a, b])
  }

  func testEscapeCancelsInwards() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController
    controller.select(a)

    canvas.handlePress(at: SionPoint(x: 180, y: 148), modifiers: [], clickCount: 1)
    canvas.handleMotion(to: SionPoint(x: 260, y: 148), modifiers: [])
    XCTAssertTrue(canvas.handleKey(keyval: UInt32(GDK_KEY_Escape), modifiers: []))
    XCTAssertNil(canvas.drag)
    XCTAssertEqual(
      controller.document.scene.element(withID: a)?.geometry.frame.minX, 100)
    XCTAssertEqual(controller.selection, [a])

    XCTAssertTrue(canvas.handleKey(keyval: UInt32(GDK_KEY_Escape), modifiers: []))
    XCTAssertTrue(controller.selection.isEmpty)
  }

  func testArrowKeysNudgeAndTabTraverses() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController

    XCTAssertFalse(canvas.handleKey(keyval: UInt32(GDK_KEY_Right), modifiers: []))
    XCTAssertTrue(canvas.handleKey(keyval: UInt32(GDK_KEY_Tab), modifiers: []))
    XCTAssertEqual(controller.selection.count, 1)
    let selected = controller.selectedElement!
    let before = selected.geometry.frame.minX

    XCTAssertTrue(canvas.handleKey(keyval: UInt32(GDK_KEY_Right), modifiers: .shift))
    XCTAssertEqual(
      controller.document.scene.element(withID: selected.id)?.geometry.frame.minX,
      before + CanvasMetrics.largeNudgeDistance)
    XCTAssertTrue(canvas.handleKey(keyval: UInt32(GDK_KEY_Up), modifiers: []))
    XCTAssertEqual(
      controller.document.scene.element(withID: selected.id)?.geometry.frame.minY,
      100 - CanvasMetrics.nudgeDistance)
  }

  func testDeleteKeyRemovesTheSelection() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController
    controller.select(b)

    XCTAssertTrue(canvas.handleKey(keyval: UInt32(GDK_KEY_Delete), modifiers: []))

    XCTAssertEqual(controller.document.scene.elements.count, 1)
  }

  func testCreationToolInsertsAtDefaultSizeAndOneShotReverts() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController
    controller.setTool(.rectangle, persistence: .oneShot)

    canvas.handlePress(at: SionPoint(x: 700, y: 400), modifiers: [], clickCount: 1)
    canvas.handleRelease(at: SionPoint(x: 700, y: 400), modifiers: [])

    let inserted = try XCTUnwrap(controller.selectedElement)
    XCTAssertEqual(inserted.geometry.frame.origin, SionPoint(x: 700, y: 400))
    XCTAssertEqual(inserted.geometry.frame.size, SionCreationDefaults.rectangleSize)
    XCTAssertEqual(controller.tool, .select)
  }

  func testCircleDragStaysCircular() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController
    controller.setTool(.circle, persistence: .sticky)

    canvas.handlePress(at: SionPoint(x: 700, y: 400), modifiers: [], clickCount: 1)
    canvas.handleMotion(to: SionPoint(x: 780, y: 440), modifiers: [])
    canvas.handleRelease(at: SionPoint(x: 780, y: 440), modifiers: [])

    let inserted = try XCTUnwrap(controller.selectedElement)
    XCTAssertEqual(inserted.geometry.frame.size, SionSize(width: 80, height: 80))
    XCTAssertEqual(controller.tool, .circle)
  }

  func testConnectorToolLinksTwoShapes() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController
    controller.setTool(.connector)

    canvas.handlePress(at: SionPoint(x: 180, y: 148), modifiers: [], clickCount: 1)
    canvas.handleMotion(to: SionPoint(x: 480, y: 148), modifiers: [])
    canvas.handleRelease(at: SionPoint(x: 480, y: 148), modifiers: [])

    let connector = controller.document.scene.elements.first { $0.content.connector != nil }
    XCTAssertNotNil(connector)
    XCTAssertEqual(connector?.content.connector?.source.elementID, a)
    XCTAssertEqual(connector?.content.connector?.target.elementID, b)
  }

  func testResizeHandleDragChangesTheFrame() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController
    controller.select(a)

    // The south-east handle sits on the frame's corner.
    canvas.handlePress(at: SionPoint(x: 260, y: 196), modifiers: [], clickCount: 1)
    XCTAssertNotNil(canvas.drag)
    canvas.handleMotion(to: SionPoint(x: 300, y: 216), modifiers: [])
    canvas.handleRelease(at: SionPoint(x: 300, y: 216), modifiers: [])

    let frame = controller.document.scene.element(withID: a)?.geometry.frame
    XCTAssertEqual(frame?.width ?? 0, 200, accuracy: 0.01)
    XCTAssertEqual(frame?.height ?? 0, 116, accuracy: 0.01)
  }

  func testCommandValidationFollowsTheSelection() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController

    XCTAssertFalse(canvas.canPerform(.copy))
    XCTAssertFalse(canvas.canPerform(.delete))
    XCTAssertTrue(canvas.canPerform(.selectAll))
    XCTAssertTrue(canvas.canPerform(.toggleGridVisibility))
    XCTAssertEqual(canvas.isChecked(.toggleObjectSnapping), true)

    controller.selectAll()
    XCTAssertTrue(canvas.canPerform(.copy))
    XCTAssertTrue(canvas.canPerform(.alignLeading))
    XCTAssertFalse(canvas.canPerform(.distributeHorizontally))

    canvas.perform(.toggleObjectSnapping)
    XCTAssertEqual(canvas.isChecked(.toggleObjectSnapping), false)
    canvas.perform(.delete)
    XCTAssertTrue(controller.document.scene.elements.isEmpty)
  }

  func testZoomStepsAndClamps() throws {
    let (canvas, _) = try makeCanvas()
    var reported: [Double] = []
    canvas.onMagnificationChange = { reported.append($0) }

    canvas.zoomIn()
    XCTAssertEqual(canvas.magnification, SionGtkCanvasView.zoomStep, accuracy: 0.0001)
    canvas.actualSize()
    XCTAssertEqual(canvas.magnification, 1)
    for _ in 0..<40 {
      canvas.zoomOut()
    }
    XCTAssertEqual(canvas.magnification, SionGtkCanvasView.minimumMagnification)
    for _ in 0..<40 {
      canvas.zoomIn()
    }
    XCTAssertEqual(canvas.magnification, SionGtkCanvasView.maximumMagnification)
    XCTAssertFalse(reported.isEmpty)
  }

  func testTextEditingCommitsThroughTheController() throws {
    let (canvas, undoManager) = try makeCanvas()
    let controller = canvas.editorController

    canvas.beginTextEditing(a)
    let editor = try XCTUnwrap(canvas.textEditor)
    XCTAssertEqual(editor.text, "A")
    gtk_text_buffer_set_text(gtk_text_view_get_buffer(editorTextView(editor)), "Renamed", -1)
    GtkTestSupport.drainMainLoop()
    canvas.commitPendingEdits()

    XCTAssertNil(canvas.textEditor)
    XCTAssertEqual(
      controller.document.scene.element(withID: a)?.editableText, "Renamed")
    XCTAssertTrue(undoManager.canUndo)
  }

  func testDiscardingTextEditingRestoresTheText() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController

    canvas.beginTextEditing(a)
    let editor = try XCTUnwrap(canvas.textEditor)
    gtk_text_buffer_set_text(gtk_text_view_get_buffer(editorTextView(editor)), "Changed", -1)
    GtkTestSupport.drainMainLoop()
    canvas.discardPendingEdits()

    XCTAssertEqual(
      controller.document.scene.element(withID: a)?.editableText, "A")
  }

  func testPasteContentParsingFromURIListAndSVGText() throws {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appendingPathComponent("sion-test-\(UUID().uuidString).svg")
    let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'></svg>"
    try Data(svg.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let content = SionGtkCanvasClipboard.imageFileContent(
      fromURIList: "# comment\n\(url.absoluteString)\n")
    guard case .image(let data, let type, let filename) = content else {
      return XCTFail("expected an image")
    }
    XCTAssertEqual(type, .svg)
    XCTAssertEqual(filename, url.lastPathComponent)
    XCTAssertEqual(data, Data(svg.utf8))
    XCTAssertNil(SionGtkCanvasClipboard.imageFileContent(fromURIList: "file:///nowhere/x.txt"))
  }

  func testInsertingPastedTextChoosesMermaidOrText() throws {
    let (canvas, _) = try makeCanvas()
    let controller = canvas.editorController
    let count = controller.document.scene.elements.count

    canvas.insert(.text("Hello"), at: SionPoint(x: 600, y: 600))
    XCTAssertEqual(controller.document.scene.elements.count, count + 1)
    XCTAssertEqual(controller.selectedElement?.editableText, "Hello")

    canvas.insert(.text("graph TD\n  X --> Y"), at: SionPoint(x: 800, y: 800))
    XCTAssertGreaterThan(controller.document.scene.elements.count, count + 1)
  }

  private func editorTextView(_ editor: SionGtkInlineTextEditor) -> UnsafeMutablePointer<
    GtkTextView
  > {
    let scrolled = editor.widget
    return gtk_scrolled_window_get_child(scrolled.opaque)!.cast()
  }
}
