import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasInteractionTests: XCTestCase {
  func testInlineEditorSuppressesBackingTextForEveryEditableKind() throws {
    _ = NSApplication.shared
    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 40, y: 180)),
      target: .free(SionPoint(x: 280, y: 180)),
      routingStyle: .straight
    )
    connector.content = .connector(
      ConnectorContent(
        source: .free(SionPoint(x: 40, y: 180)),
        target: .free(SionPoint(x: 280, y: 180)),
        routingStyle: .straight,
        label: TextContent(string: "Flow")
      )
    )
    let elements = [
      SceneElement.shape(
        frame: SionRect(x: 40, y: 40, width: 180, height: 80),
        text: "Shape"
      ),
      SceneElement.text(
        frame: SionRect(x: 40, y: 40, width: 180, height: 80),
        text: "Standalone"
      ),
      connector,
    ]

    for element in elements {
      let controller = try makeController(elements: [element])
      let canvas = makeCanvas(controller: controller)
      let paintedPixels = try backingPixels(of: canvas)

      canvas.beginTextEditing(element.id)
      let editingPixels = try backingPixels(of: canvas)
      canvas.discardPendingEdits()

      let referenceController = try makeController(
        elements: [removingEditableText(from: element)]
      )
      let referencePixels = try backingPixels(
        of: makeCanvas(controller: referenceController)
      )

      XCTAssertFalse(paintedPixels == referencePixels)
      XCTAssertTrue(editingPixels == referencePixels)
    }
  }

  func testCanvasCreationSelectsEachNewElement() throws {
    let controller = try makeController()
    let canvas = makeCanvas(controller: controller)
    defer { canvas.commitPendingEdits() }

    controller.setTool(.rectangle)
    try click(canvas: canvas, at: SionPoint(x: 80, y: 70))
    let shape = try XCTUnwrap(controller.document.scene.elements.last)
    XCTAssertEqual(controller.selection, [shape.id])

    controller.setTool(.text)
    try click(canvas: canvas, at: SionPoint(x: 300, y: 200))
    let text = try XCTUnwrap(controller.document.scene.elements.last)
    XCTAssertEqual(controller.selection, [text.id])
  }

  func testCanvasCreationBeepsWhenInsertionFails() throws {
    let controller = try makeController()
    var feedbackCount = 0
    let canvas = makeCanvas(
      controller: controller,
      creationFailureFeedback: { feedbackCount += 1 }
    )
    controller.setTool(.rectangle)

    try click(
      canvas: canvas,
      at: SionPoint(x: SceneLimits.maximumCoordinateMagnitude + 100, y: 40)
    )

    XCTAssertEqual(feedbackCount, 1)
    XCTAssertTrue(controller.document.scene.elements.isEmpty)
  }

  func testMarqueeUsesMouseUpPointForNegativeDrag() throws {
    let element = SceneElement.shape(
      frame: SionRect(x: 100, y: 100, width: 60, height: 40),
      kind: .rectangle
    )
    let controller = try makeController(elements: [element])
    let canvas = makeCanvas(controller: controller)

    canvas.mouseDown(
      with: try mouseEvent(
        .leftMouseDown,
        canvas: canvas,
        at: SionPoint(x: 220, y: 180)
      )
    )
    canvas.mouseDragged(
      with: try mouseEvent(
        .leftMouseDragged,
        canvas: canvas,
        at: SionPoint(x: 210, y: 170)
      )
    )
    canvas.mouseUp(
      with: try mouseEvent(
        .leftMouseUp,
        canvas: canvas,
        at: SionPoint(x: 80, y: 80)
      )
    )

    XCTAssertEqual(controller.selection, [element.id])
  }

  func testShiftMarqueeExtendsSelection() throws {
    let first = SceneElement.shape(
      frame: SionRect(x: 20, y: 20, width: 40, height: 40),
      kind: .rectangle
    )
    let second = SceneElement.shape(
      frame: SionRect(x: 140, y: 140, width: 40, height: 40),
      kind: .rectangle
    )
    let controller = try makeController(elements: [first, second])
    let canvas = makeCanvas(controller: controller)
    controller.select(first.id)

    try drag(
      canvas: canvas,
      from: SionPoint(x: 220, y: 220),
      to: SionPoint(x: 120, y: 120),
      modifierFlags: .shift
    )

    XCTAssertEqual(controller.selection, [first.id, second.id])
  }

  func testEscapeCancelsRotation() throws {
    let frame = SionRect(x: 100, y: 100, width: 100, height: 60)
    let element = SceneElement.shape(frame: frame, kind: .rectangle)
    let controller = try makeController(elements: [element])
    let canvas = makeCanvas(controller: controller)
    controller.select(element.id)

    let handle = InteractionGeometry.rotationHandlePoint(
      in: frame,
      offset: TestMetrics.rotationHandleOffset
    )
    canvas.mouseDown(
      with: try mouseEvent(.leftMouseDown, canvas: canvas, at: handle)
    )
    canvas.mouseDragged(
      with: try mouseEvent(
        .leftMouseDragged,
        canvas: canvas,
        at: SionPoint(x: frame.maxX + TestMetrics.rotationHandleOffset, y: frame.center.y)
      )
    )

    let changedRotation = try XCTUnwrap(
      controller.document.scene.element(withID: element.id)?.geometry.rotationRadians
    )
    XCTAssertNotEqual(changedRotation, 0)

    canvas.cancelOperation(nil)

    let restoredRotation = try XCTUnwrap(
      controller.document.scene.element(withID: element.id)?.geometry.rotationRadians
    )
    XCTAssertEqual(restoredRotation, 0)
  }

  func testEscapeCancelsCreation() throws {
    let controller = try makeController()
    let canvas = makeCanvas(controller: controller)
    let start = SionPoint(x: 40, y: 40)
    let end = SionPoint(x: 180, y: 120)
    controller.setTool(.rectangle)

    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, canvas: canvas, at: start))
    canvas.mouseDragged(with: try mouseEvent(.leftMouseDragged, canvas: canvas, at: end))
    canvas.cancelOperation(nil)
    canvas.mouseUp(with: try mouseEvent(.leftMouseUp, canvas: canvas, at: end))

    XCTAssertTrue(controller.document.scene.elements.isEmpty)
  }

  func testMarqueeThresholdUsesScreenDistance() throws {
    let selected = SceneElement.shape(
      frame: SionRect(x: 20, y: 20, width: 40, height: 40),
      kind: .rectangle
    )
    let touched = SceneElement.shape(
      frame: SionRect(x: 100, y: 100, width: 40, height: 40),
      kind: .rectangle
    )
    let controller = try makeController(elements: [selected, touched])
    let canvas = makeCanvas(controller: controller)
    let scrollView = NSScrollView(frame: canvas.frame)
    scrollView.allowsMagnification = true
    scrollView.maxMagnification = 4
    scrollView.documentView = canvas
    scrollView.magnification = 4
    controller.select(selected.id)

    try drag(
      canvas: canvas,
      from: SionPoint(x: 99.5, y: 99.5),
      to: SionPoint(x: 100.5, y: 100.5),
      modifierFlags: .shift
    )

    XCTAssertEqual(controller.selection, [selected.id, touched.id])
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

  private func makeCanvas(
    controller: SionEditorController,
    creationFailureFeedback: @escaping @MainActor () -> Void = {}
  ) -> SionCanvasView {
    SionCanvasView(
      editorController: controller,
      creationFailureFeedback: creationFailureFeedback
    )
  }

  private func backingPixels(of canvas: SionCanvasView) throws -> Data {
    let representation = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.bounds.width),
        pixelsHigh: Int(canvas.bounds.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: representation))
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    canvas.draw(canvas.bounds)
    context.flushGraphics()
    let bytes = try XCTUnwrap(representation.bitmapData)
    return Data(
      bytes: bytes,
      count: representation.bytesPerRow * representation.pixelsHigh
    )
  }

  private func removingEditableText(from element: SceneElement) -> SceneElement {
    var element = element
    switch element.content {
    case .shape(var shape):
      shape.label = nil
      element.content = .shape(shape)
    case .text(var text):
      text.string = ""
      element.content = .text(text)
    case .connector(var connector):
      connector.label = nil
      element.content = .connector(connector)
    case .path, .image, .group:
      break
    }

    return element
  }

  private func click(canvas: SionCanvasView, at point: SionPoint) throws {
    canvas.mouseDown(with: try mouseEvent(.leftMouseDown, canvas: canvas, at: point))
    canvas.mouseUp(with: try mouseEvent(.leftMouseUp, canvas: canvas, at: point))
  }

  private func drag(
    canvas: SionCanvasView,
    from start: SionPoint,
    to end: SionPoint,
    modifierFlags: NSEvent.ModifierFlags = []
  ) throws {
    canvas.mouseDown(
      with: try mouseEvent(
        .leftMouseDown,
        canvas: canvas,
        at: start,
        modifierFlags: modifierFlags
      )
    )
    canvas.mouseDragged(
      with: try mouseEvent(
        .leftMouseDragged,
        canvas: canvas,
        at: end,
        modifierFlags: modifierFlags
      )
    )
    canvas.mouseUp(
      with: try mouseEvent(
        .leftMouseUp,
        canvas: canvas,
        at: end,
        modifierFlags: modifierFlags
      )
    )
  }

  private func mouseEvent(
    _ type: NSEvent.EventType,
    canvas: SionCanvasView,
    at point: SionPoint,
    modifierFlags: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    return try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type,
        location: canvas.convert(canvas.viewPoint(for: point), to: nil),
        modifierFlags: modifierFlags,
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

private enum TestMetrics {
  static let rotationHandleOffset = 28.0
}
