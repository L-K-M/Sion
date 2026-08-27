import AppKit
import ObjectiveC.runtime
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasInteractionTests: XCTestCase {
  func testCanvasCreationSelectsEachNewElement() throws {
    let controller = try makeController()
    let fixture = makeCanvas(controller: controller)
    defer {
      fixture.canvas.commitPendingEdits()
      fixture.window.close()
    }

    controller.setTool(.rectangle)
    try click(canvas: fixture.canvas, at: SionPoint(x: 80, y: 70))
    let shape = try XCTUnwrap(controller.document.scene.elements.last)
    XCTAssertEqual(controller.selection, [shape.id])

    controller.setTool(.text)
    try click(canvas: fixture.canvas, at: SionPoint(x: 300, y: 200))
    let text = try XCTUnwrap(controller.document.scene.elements.last)
    XCTAssertEqual(controller.selection, [text.id])
  }

  func testCanvasCreationBeepsWhenInsertionFails() throws {
    let controller = try makeController()
    let fixture = makeCanvas(controller: controller)
    defer { fixture.window.close() }
    controller.setTool(.rectangle)

    let original = try XCTUnwrap(
      class_getClassMethod(NSSound.self, #selector(NSSound.beep))
    )
    let recorder = try XCTUnwrap(
      class_getClassMethod(NSSound.self, #selector(NSSound.sionRecordBeep))
    )
    BeepRecorder.count = 0
    method_exchangeImplementations(original, recorder)
    defer { method_exchangeImplementations(recorder, original) }

    try click(
      canvas: fixture.canvas,
      at: SionPoint(x: SceneLimits.maximumCoordinateMagnitude + 100, y: 40)
    )

    XCTAssertEqual(BeepRecorder.count, 1)
    XCTAssertTrue(controller.document.scene.elements.isEmpty)
  }

  private func makeController(elements: [SceneElement] = []) throws -> SionEditorController {
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(SionSize(width: 640, height: 480))),
      elements: elements
    )
    return try SionEditorController(
      package: SionPackage(document: SionDocument(scene: scene)),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func makeCanvas(controller: SionEditorController) -> CanvasFixture {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let canvas = SionCanvasView(editorController: controller)
    window.contentView = canvas

    return CanvasFixture(canvas: canvas, window: window)
  }

  private func click(canvas: SionCanvasView, at point: SionPoint) throws {
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, canvas: canvas, at: point))
    canvas.mouseUp(with: try mouseEvent(.leftMouseUp, canvas: canvas, at: point))
  }

  private func mouseEvent(
    _ type: NSEvent.EventType,
    canvas: SionCanvasView,
    at point: SionPoint
  ) throws -> NSEvent {
    let viewPoint = canvas.viewPoint(for: point)
    let windowPoint = canvas.convert(viewPoint, to: nil)

    return try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: canvas.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )
    )
  }
}

private struct CanvasFixture {
  let canvas: SionCanvasView
  let window: NSWindow
}

private enum BeepRecorder {
  nonisolated(unsafe) static var count = 0
}

extension NSSound {
  @objc fileprivate class func sionRecordBeep() {
    BeepRecorder.count += 1
  }
}
