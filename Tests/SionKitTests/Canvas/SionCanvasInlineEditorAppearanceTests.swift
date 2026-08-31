import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasInlineEditorAppearanceTests: XCTestCase {
  private let colorAccuracy = 2.0 / 255.0

  func testInlineTextEditorStaysLightUnderDarkSystemAppearance() throws {
    let application = NSApplication.shared
    let previousAppearance = application.appearance
    application.appearance = NSAppearance(named: .darkAqua)
    defer { application.appearance = previousAppearance }

    let element = SceneElement.text(
      frame: SionRect(x: 40, y: 40, width: 180, height: 80),
      text: "Test"
    )
    let controller = try makeController(elements: [element])
    let canvas = SionCanvasView(editorController: controller)
    canvas.beginTextEditing(element.id)
    defer { canvas.discardPendingEdits() }

    let scrollView = try inlineEditor(in: canvas)
    let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)

    XCTAssertEqual(
      scrollView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
      .aqua
    )
    XCTAssertEqual(
      textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
      .aqua
    )
    // The pin must not leak to the canvas that hosts the editor.
    XCTAssertNil(canvas.appearance)

    XCTAssertTrue(scrollView.drawsBackground)
    XCTAssertFalse(textView.drawsBackground)
    assertColor(scrollView.backgroundColor, matches: .canvas)

    let ink = try XCTUnwrap(textView.textColor)
    assertColor(ink, matches: .primaryInk)
    assertColor(textView.insertionPointColor, matches: .primaryInk)
    XCTAssertEqual(Array(textView.selectedTextAttributes.keys), [.backgroundColor])

    // The pin is load bearing: the dynamic highlight has to resolve light.
    let highlight = try XCTUnwrap(
      textView.selectedTextAttributes[.backgroundColor] as? NSColor
    )
    var resolvedHighlight: NSColor?
    textView.effectiveAppearance.performAsCurrentDrawingAppearance {
      resolvedHighlight = highlight.usingColorSpace(.sRGB)
    }
    XCTAssertGreaterThan(brightness(of: try XCTUnwrap(resolvedHighlight)), 0.5)
  }

  func testShapeLabelEditorMirrorsAReadableFillAndReplacesAnUnreadableOne() throws {
    var lightShape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 160, height: 90),
      text: "Shape"
    )
    lightShape.style.fill = .solid(SionColor(red: 0.9, green: 0.95, blue: 1))

    var darkShape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 160, height: 90),
      text: "Shape"
    )
    darkShape.style.fill = .solid(.black)

    let lightController = try makeController(elements: [lightShape])
    let lightCanvas = SionCanvasView(editorController: lightController)
    lightCanvas.beginTextEditing(lightShape.id)
    defer { lightCanvas.discardPendingEdits() }

    assertColor(
      try inlineEditor(in: lightCanvas).backgroundColor,
      matches: SionColor(red: 0.9, green: 0.95, blue: 1)
    )

    let darkController = try makeController(elements: [darkShape])
    let darkCanvas = SionCanvasView(editorController: darkController)
    darkCanvas.beginTextEditing(darkShape.id)
    defer { darkCanvas.discardPendingEdits() }

    // Dark fill under the default dark label ink: the paper is replaced.
    assertColor(try inlineEditor(in: darkCanvas).backgroundColor, matches: .white)
  }

  func testInlineTextEditorFallsBackToWhiteForDarkSceneBackground() throws {
    let application = NSApplication.shared
    let previousAppearance = application.appearance
    application.appearance = NSAppearance(named: .darkAqua)
    defer { application.appearance = previousAppearance }

    let element = SceneElement.text(
      frame: SionRect(x: 40, y: 40, width: 180, height: 80),
      text: "Test"
    )
    let controller = try makeController(
      elements: [element],
      canvas: SionCanvas(background: .black)
    )
    let canvas = SionCanvasView(editorController: controller)
    canvas.beginTextEditing(element.id)
    defer { canvas.discardPendingEdits() }

    let scrollView = try inlineEditor(in: canvas)
    let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)

    assertColor(scrollView.backgroundColor, matches: .white)
    assertColor(try XCTUnwrap(textView.textColor), matches: .primaryInk)
    // The editor reads the scene; it never rewrites it.
    XCTAssertEqual(controller.document.scene.canvas.background, .black)
  }

  func testPaperColorFlattensAlphaAndKeepsInkReadable() {
    assertColor(SionColorBridge.paperColor(.canvas, ink: .primaryInk), matches: .canvas)
    // A fully transparent backdrop is the page it sits on: white.
    assertColor(
      SionColorBridge.paperColor(
        SionColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0),
        ink: .primaryInk
      ),
      matches: .white
    )
    // Dark ink on a dark backdrop is unreadable, so the paper is replaced.
    assertColor(
      SionColorBridge.paperColor(SionColor(red: 0.1, green: 0.1, blue: 0.1), ink: .primaryInk),
      matches: .white
    )
    // Light ink on a light backdrop is unreadable the other way around.
    assertColor(SionColorBridge.paperColor(.canvas, ink: .white), matches: .primaryInk)
    // Light ink on its own dark backdrop already reads; keep the backdrop.
    assertColor(SionColorBridge.paperColor(.black, ink: .white), matches: .black)
    XCTAssertEqual(
      Double(SionColorBridge.paperColor(.canvas, ink: .primaryInk).alphaComponent),
      1,
      accuracy: colorAccuracy
    )
  }

  private func makeController(
    elements: [SceneElement],
    canvas: SionCanvas = SionCanvas()
  ) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(canvas: canvas, elements: elements))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func inlineEditor(in canvas: SionCanvasView) throws -> NSScrollView {
    try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSScrollView }.first)
  }

  private func brightness(of color: NSColor) -> Double {
    (0.299 * Double(color.redComponent))
      + (0.587 * Double(color.greenComponent))
      + (0.114 * Double(color.blueComponent))
  }

  private func assertColor(
    _ color: NSColor,
    matches expected: SionColor,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard let sRGB = color.usingColorSpace(.sRGB) else {
      return XCTFail("Expected an sRGB-convertible color.", file: file, line: line)
    }

    XCTAssertEqual(
      Double(sRGB.redComponent),
      expected.red,
      accuracy: colorAccuracy,
      file: file,
      line: line
    )
    XCTAssertEqual(
      Double(sRGB.greenComponent),
      expected.green,
      accuracy: colorAccuracy,
      file: file,
      line: line
    )
    XCTAssertEqual(
      Double(sRGB.blueComponent),
      expected.blue,
      accuracy: colorAccuracy,
      file: file,
      line: line
    )
  }
}
