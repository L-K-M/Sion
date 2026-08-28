import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasGestureLifecycleTests: XCTestCase {
  func testEveryDragRecoversFromEveryLifecycleLoss() {
    _ = NSApplication.shared

    for loss in GestureLoss.allCases {
      for dragKind in GestureDragKind.allCases {
        XCTContext.runActivity(named: "\(dragKind.rawValue) / \(loss.rawValue)") { _ in
          do {
            try assertRecovery(of: dragKind, after: loss)
          } catch {
            XCTFail("Gesture fixture failed: \(error)")
          }
        }
      }
    }
  }

  func testEscapeRestoresCursorAfterUntouchedMove() throws {
    _ = NSApplication.shared
    let fixture = try makeFixture(for: .move, hostedInDocumentWindow: false)
    let previousCursor = NSCursor.current
    defer { previousCursor.set() }

    fixture.canvas.mouseDown(
      with: try mouseEvent(.leftMouseDown, fixture: fixture, at: fixture.start)
    )
    XCTAssertEqual(NSCursor.current, .closedHand)

    fixture.canvas.keyDown(with: try escapeEvent(for: fixture))

    XCTAssertEqual(NSCursor.current, .arrow)
    XCTAssertFalse(fixture.controller.hasPendingEditorGesture)
    XCTAssertEqual(fixture.controller.document, fixture.documentBeforeDrag)
  }

  func testCancelOperationStepsFromTextToAnchorsToSelection() throws {
    _ = NSApplication.shared
    let fixture = try makeFixture(for: .move, hostedInDocumentWindow: false)
    fixture.controller.select(fixture.targetID)

    fixture.canvas.beginTextEditing(fixture.targetID)
    try fixture.controller.updateTextEdit("Changed", on: fixture.targetID)
    fixture.canvas.cancelOperation(nil)

    let editedElement = try XCTUnwrap(
      fixture.controller.document.scene.element(withID: fixture.targetID)
    )
    guard case .shape(let shape) = editedElement.content else {
      return XCTFail("Expected the text fixture to remain a shape")
    }

    XCTAssertEqual(shape.label?.string, GestureTestGeometry.targetText)
    XCTAssertEqual(fixture.controller.selection, [fixture.targetID])

    fixture.controller.beginAnchorEditing(on: fixture.targetID)
    fixture.canvas.cancelOperation(nil)

    XCTAssertEqual(fixture.controller.anchorEditingState, .inactive)
    XCTAssertEqual(fixture.controller.selection, [fixture.targetID])

    fixture.canvas.cancelOperation(nil)

    XCTAssertTrue(fixture.controller.selection.isEmpty)
  }

  private func assertRecovery(
    of dragKind: GestureDragKind,
    after loss: GestureLoss
  ) throws {
    let fixture = try makeFixture(
      for: dragKind,
      hostedInDocumentWindow: loss.requiresDocumentWindow
    )
    defer { fixture.windowController?.close() }

    try beginDrag(fixture)
    let selectionDuringDrag = fixture.controller.selection
    let documentDuringDrag = fixture.controller.document

    XCTAssertEqual(
      fixture.controller.hasPendingEditorGesture,
      dragKind.usesEditorGesture
    )
    guard try apply(loss, to: fixture) else { return }

    let expectedDocument = expectedDocument(after: loss, for: fixture)
    let expectedSelection = Set(
      selectionDuringDrag.filter {
        expectedDocument.scene.element(withID: $0) != nil
      }
    )

    XCTAssertEqual(fixture.controller.document, expectedDocument)
    XCTAssertEqual(fixture.controller.selection, expectedSelection)
    XCTAssertFalse(fixture.controller.hasPendingEditorGesture)
    XCTAssertTrue(
      try backingPixels(of: fixture.canvas)
        == referencePixels(
          for: expectedDocument,
          selection: expectedSelection,
          tool: fixture.controller.tool
        )
    )

    try assertNoStaleDrag(
      fixture,
      kind: dragKind,
      expectedDocument: expectedDocument,
      expectedSelection: expectedSelection
    )
    assertUndoState(
      after: loss,
      fixture: fixture,
      kind: dragKind,
      documentDuringDrag: documentDuringDrag
    )
  }

  private func apply(_ loss: GestureLoss, to fixture: GestureFixture) throws -> Bool {
    switch loss {
    case .escape:
      fixture.canvas.keyDown(with: try escapeEvent(for: fixture))
    case .externalUndo:
      fixture.controller.undoSceneEdit()
    case .responderChange:
      let window = try XCTUnwrap(fixture.windowController?.window)
      let responder = GestureTestResponder(frame: .zero)
      window.contentView?.addSubview(responder)
      XCTAssertTrue(window.makeFirstResponder(responder))
    case .windowResign:
      let window = try XCTUnwrap(fixture.windowController?.window)
      guard let delegate = window.delegate else {
        XCTFail("Document window has no delegate")
        return false
      }

      delegate.windowDidResignKey?(
        Notification(name: NSWindow.didResignKeyNotification, object: window)
      )
    case .missingMouseUp:
      fixture.canvas.mouseMoved(
        with: try mouseEvent(.mouseMoved, fixture: fixture, at: fixture.end)
      )
    }

    return true
  }

  private func expectedDocument(
    after loss: GestureLoss,
    for fixture: GestureFixture
  ) -> SionDocument {
    guard loss == .externalUndo, !fixture.kind.usesEditorGesture else {
      return fixture.documentBeforeDrag
    }

    return fixture.documentBeforeSeed
  }

  private func assertNoStaleDrag(
    _ fixture: GestureFixture,
    kind: GestureDragKind,
    expectedDocument: SionDocument,
    expectedSelection: Set<ElementID>
  ) throws {
    if kind.usesEditorGesture {
      fixture.canvas.cancelOperation(nil)
      XCTAssertTrue(fixture.controller.selection.isEmpty)
      return
    }

    fixture.canvas.mouseUp(
      with: try mouseEvent(.leftMouseUp, fixture: fixture, at: fixture.end)
    )
    XCTAssertEqual(fixture.controller.document, expectedDocument)
    XCTAssertEqual(fixture.controller.selection, expectedSelection)
  }

  private func assertUndoState(
    after loss: GestureLoss,
    fixture: GestureFixture,
    kind: GestureDragKind,
    documentDuringDrag: SionDocument
  ) {
    guard loss == .externalUndo else {
      fixture.controller.undoSceneEdit()
      XCTAssertEqual(fixture.controller.document, fixture.documentBeforeSeed)
      fixture.controller.redoSceneEdit()
      XCTAssertEqual(fixture.controller.document, fixture.documentBeforeDrag)
      return
    }

    fixture.controller.redoSceneEdit()
    if kind.usesEditorGesture {
      XCTAssertEqual(fixture.controller.document, documentDuringDrag)
      fixture.controller.undoSceneEdit()
      XCTAssertEqual(fixture.controller.document, fixture.documentBeforeDrag)
      fixture.controller.undoSceneEdit()
      XCTAssertEqual(fixture.controller.document, fixture.documentBeforeSeed)
      return
    }

    XCTAssertEqual(fixture.controller.document, fixture.documentBeforeDrag)
  }

  private func makeFixture(
    for kind: GestureDragKind,
    hostedInDocumentWindow: Bool
  ) throws -> GestureFixture {
    let target = SceneElement.shape(
      frame: GestureTestGeometry.targetFrame,
      kind: .roundedRectangle(radius: GestureTestGeometry.cornerRadius),
      text: GestureTestGeometry.targetText
    )
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(GestureTestGeometry.canvasSize)),
      elements: [target]
    )
    let documentBeforeSeed = SionDocument(scene: scene)
    let controller = try SionEditorController(
      package: SionPackage(document: documentBeforeSeed),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    _ = try controller.insertShape(in: GestureTestGeometry.seedFrame, kind: .ellipse)
    configure(controller, for: kind, targetID: target.id)

    let documentBeforeDrag = controller.document
    let points = kind.points(in: target.geometry.frame)
    let windowController: SionDocumentWindowController?
    let canvas: SionCanvasView
    if hostedInDocumentWindow {
      let host = SionDocumentWindowController(editorController: controller)
      let scrollView = try XCTUnwrap(host.window?.contentView as? NSScrollView)
      canvas = try XCTUnwrap(scrollView.documentView as? SionCanvasView)
      windowController = host
    } else {
      canvas = SionCanvasView(
        editorController: controller,
        creationFailureFeedback: {}
      )
      windowController = nil
    }

    return GestureFixture(
      kind: kind,
      targetID: target.id,
      controller: controller,
      canvas: canvas,
      windowController: windowController,
      documentBeforeSeed: documentBeforeSeed,
      documentBeforeDrag: documentBeforeDrag,
      start: points.start,
      end: points.end
    )
  }

  private func configure(
    _ controller: SionEditorController,
    for kind: GestureDragKind,
    targetID: ElementID
  ) {
    switch kind {
    case .move, .resize, .rotate, .cornerRadius:
      controller.setTool(.select)
      controller.select(targetID)
    case .create:
      controller.setTool(.rectangle)
    case .connector:
      controller.setTool(.connector)
    case .marquee:
      controller.setTool(.select)
      controller.select(nil)
    }
  }

  private func beginDrag(_ fixture: GestureFixture) throws {
    fixture.canvas.mouseDown(
      with: try mouseEvent(.leftMouseDown, fixture: fixture, at: fixture.start)
    )
    fixture.canvas.mouseDragged(
      with: try mouseEvent(.leftMouseDragged, fixture: fixture, at: fixture.end)
    )
  }

  private func referencePixels(
    for document: SionDocument,
    selection: Set<ElementID>,
    tool: SionEditorController.Tool
  ) throws -> Data {
    let controller = try SionEditorController(
      package: SionPackage(document: document),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    controller.setTool(tool)
    if let selectedID = selection.first {
      controller.select(selectedID)
    }

    return try backingPixels(
      of: SionCanvasView(
        editorController: controller,
        creationFailureFeedback: {}
      )
    )
  }

  private func backingPixels(of canvas: SionCanvasView) throws -> Data {
    let representation = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.bounds.width),
        pixelsHigh: Int(canvas.bounds.height),
        bitsPerSample: GestureTestBitmap.bitsPerSample,
        samplesPerPixel: GestureTestBitmap.samplesPerPixel,
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

  private func mouseEvent(
    _ type: NSEvent.EventType,
    fixture: GestureFixture,
    at point: SionPoint
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type,
        location: fixture.canvas.convert(fixture.canvas.viewPoint(for: point), to: nil),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: fixture.windowController?.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )
    )
  }

  private func escapeEvent(for fixture: GestureFixture) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: fixture.windowController?.window?.windowNumber ?? 0,
        context: nil,
        characters: GestureTestKey.escapeCharacter,
        charactersIgnoringModifiers: GestureTestKey.escapeCharacter,
        isARepeat: false,
        keyCode: GestureTestKey.escapeCode
      )
    )
  }
}

private enum GestureDragKind: String, CaseIterable {
  case move
  case resize
  case rotate
  case cornerRadius
  case create
  case connector
  case marquee

  var usesEditorGesture: Bool {
    switch self {
    case .move, .resize, .rotate, .cornerRadius:
      true
    case .create, .connector, .marquee:
      false
    }
  }

  func points(in frame: SionRect) -> (start: SionPoint, end: SionPoint) {
    switch self {
    case .move:
      (frame.center, frame.center + SionVector(dx: 40, dy: 24))
    case .resize:
      (
        InteractionGeometry.resizeHandlePoint(.southEast, in: frame),
        SionPoint(x: frame.maxX + 40, y: frame.maxY + 24)
      )
    case .rotate:
      (
        InteractionGeometry.rotationHandlePoint(
          in: frame,
          offset: GestureTestGeometry.rotationHandleOffset
        ),
        SionPoint(x: frame.maxX + 40, y: frame.center.y)
      )
    case .cornerRadius:
      (
        InteractionGeometry.roundedRectangleCornerRadiusHandle(
          in: frame,
          radius: GestureTestGeometry.cornerRadius
        ),
        SionPoint(x: frame.minX + 44, y: frame.minY + 44)
      )
    case .create:
      (SionPoint(x: 300, y: 260), SionPoint(x: 440, y: 340))
    case .connector:
      (SionPoint(x: 300, y: 80), SionPoint(x: 480, y: 220))
    case .marquee:
      (SionPoint(x: 80, y: 80), SionPoint(x: 240, y: 200))
    }
  }
}

private enum GestureLoss: String, CaseIterable {
  case escape
  case externalUndo
  case responderChange
  case windowResign
  case missingMouseUp

  var requiresDocumentWindow: Bool {
    switch self {
    case .responderChange, .windowResign:
      true
    case .escape, .externalUndo, .missingMouseUp:
      false
    }
  }
}

private struct GestureFixture {
  let kind: GestureDragKind
  let targetID: ElementID
  let controller: SionEditorController
  let canvas: SionCanvasView
  let windowController: SionDocumentWindowController?
  let documentBeforeSeed: SionDocument
  let documentBeforeDrag: SionDocument
  let start: SionPoint
  let end: SionPoint
}

private final class GestureTestResponder: NSView {
  override var acceptsFirstResponder: Bool { true }
}

private enum GestureTestGeometry {
  static let canvasSize = SionSize(width: 640, height: 480)
  static let targetFrame = SionRect(x: 100, y: 100, width: 120, height: 80)
  static let seedFrame = SionRect(x: 520, y: 400, width: 40, height: 40)
  static let cornerRadius = 20.0
  static let rotationHandleOffset = 28.0
  static let targetText = "Target"
}

private enum GestureTestBitmap {
  static let bitsPerSample = 8
  static let samplesPerPixel = 4
}

private enum GestureTestKey {
  static let escapeCode: UInt16 = 53
  static let escapeCharacter = "\u{1B}"
}
