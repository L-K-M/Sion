import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasRenderingTests: XCTestCase {
  private let canvasSize = SionSize(width: 180, height: 180)
  private let colorAccuracy = 0.04

  func testElementOpacityMultipliesIntrinsicFillAlpha() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 30, y: 30, width: 120, height: 120),
      kind: .rectangle
    )
    shape.style = ElementStyle(
      fill: .solid(SionColor(red: 1, green: 0, blue: 0, alpha: 0.5)),
      opacity: 0.5
    )

    var equivalent = shape
    equivalent.style.fill = .solid(.init(red: 1, green: 0, blue: 0))
    equivalent.style.opacity = 0.25

    let point = SionPoint(x: 90, y: 90)
    let actual = try pixel(in: render(elements: [shape]), at: point)
    let expected = try pixel(in: render(elements: [equivalent]), at: point)

    assertEqual(actual, expected)
  }

  func testOpacityCompositesFillAndStrokeOnce() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 30, y: 30, width: 120, height: 120),
      kind: .rectangle
    )
    shape.style = ElementStyle(
      fill: .solid(.black),
      stroke: StrokeStyle(color: .black, width: 20),
      opacity: 0.5
    )

    let image = try render(elements: [shape])
    let fill = try pixel(in: image, at: SionPoint(x: 90, y: 90))
    let overlap = try pixel(in: image, at: SionPoint(x: 35, y: 90))

    XCTAssertEqual(overlap.redComponent, fill.redComponent, accuracy: colorAccuracy)
    XCTAssertEqual(overlap.greenComponent, fill.greenComponent, accuracy: colorAccuracy)
    XCTAssertEqual(overlap.blueComponent, fill.blueComponent, accuracy: colorAccuracy)
  }

  func testOverlayUsesTheOverlayBlendEquation() throws {
    var backdrop = SceneElement.shape(
      frame: SionRect(x: 20, y: 20, width: 140, height: 140),
      kind: .rectangle
    )
    backdrop.style = ElementStyle(
      fill: .solid(SionColor(red: 0.25, green: 0.25, blue: 0.25))
    )

    var overlay = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 100, height: 100),
      kind: .rectangle
    )
    overlay.style = ElementStyle(
      fill: .solid(SionColor(red: 0.8, green: 0.8, blue: 0.8)),
      blendMode: .overlay
    )

    let point = SionPoint(x: 90, y: 90)
    let actual = try pixel(in: render(elements: [backdrop, overlay]), at: point)
    let expected = try overlayReferenceColor(at: point)

    assertEqual(actual, expected)
  }

  func testZeroOpacitySuppressesEveryArtworkKind() throws {
    let asset = try redDisplayAsset()
    let elements = try zeroOpacityElements(displayAssetID: asset.id)
    let blank = try render(elements: [])

    for element in elements {
      let rendered = try render(
        elements: [element],
        assets: [asset.id: asset]
      )

      XCTAssertEqual(
        try renderedPixels(rendered),
        try renderedPixels(blank),
        "\(element.content)"
      )
    }
  }

  func testSelectionChromeEscapesElementOpacity() throws {
    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 30, y: 90)),
      target: .free(SionPoint(x: 150, y: 90)),
      routingStyle: .straight
    )
    connector.style.opacity = 0

    let blank = try render(elements: [])
    let selected = try render(elements: [connector], selection: [connector.id])

    XCTAssertNotEqual(try renderedPixels(selected), try renderedPixels(blank))
  }

  private func zeroOpacityElements(displayAssetID: AssetID) throws -> [SceneElement] {
    var shape = SceneElement.shape(
      frame: SionRect(x: 30, y: 50, width: 120, height: 80),
      kind: .rectangle,
      text: "Shape"
    )
    shape.style.opacity = 0

    var text = SceneElement.text(
      frame: SionRect(x: 30, y: 50, width: 120, height: 80),
      text: "Text"
    )
    text.style.opacity = 0

    var image = SceneElement.image(
      frame: SionRect(x: 30, y: 30, width: 120, height: 120),
      assetID: displayAssetID,
      displayAssetID: displayAssetID
    )
    image.style.opacity = 0

    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 30, y: 90)),
      target: .free(SionPoint(x: 150, y: 90)),
      routingStyle: .straight
    )
    connector.style.opacity = 0
    connector.content = .connector(
      ConnectorContent(
        source: .free(SionPoint(x: 30, y: 90)),
        target: .free(SionPoint(x: 150, y: 90)),
        routingStyle: .straight,
        sourceDecoration: .circle,
        targetDecoration: .filledArrow,
        label: TextContent(string: "Flow")
      )
    )

    return [shape, text, image, connector]
  }

  private func render(
    elements: [SceneElement],
    assets: [AssetID: SionAsset] = [:],
    selection: Set<ElementID> = []
  ) throws -> NSBitmapImageRep {
    _ = NSApplication.shared
    let scene = SionScene(
      canvas: SionCanvas(
        extent: .fixed(canvasSize),
        background: .white
      ),
      elements: elements
    )
    let controller = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: scene),
        assets: assets
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    controller.select(selection)
    let canvas = SionCanvasView(editorController: controller)
    let representation = try bitmapRepresentation()
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: representation))
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    canvas.draw(canvas.bounds)
    context.flushGraphics()
    return representation
  }

  private func bitmapRepresentation() throws -> NSBitmapImageRep {
    try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
  }

  private func overlayReferenceColor(at point: SionPoint) throws -> NSColor {
    let representation = try bitmapRepresentation()
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: representation))
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    let bounds = NSRect(
      origin: .zero,
      size: NSSize(width: canvasSize.width, height: canvasSize.height)
    )
    NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1).setFill()
    bounds.fill()
    NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.25, alpha: 1).setFill()
    bounds.fill()
    context.cgContext.setBlendMode(.overlay)
    NSColor(calibratedRed: 0.8, green: 0.8, blue: 0.8, alpha: 1).setFill()
    bounds.fill()
    context.flushGraphics()

    return try pixel(in: representation, at: point)
  }

  private func pixel(in image: NSBitmapImageRep, at point: SionPoint) throws -> NSColor {
    let color = try XCTUnwrap(
      image.colorAt(x: Int(point.x), y: Int(point.y))
    )
    return try XCTUnwrap(color.usingColorSpace(.sRGB))
  }

  private func assertEqual(
    _ actual: NSColor,
    _ expected: NSColor,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      actual.redComponent,
      expected.redComponent,
      accuracy: colorAccuracy,
      file: file,
      line: line
    )
    XCTAssertEqual(
      actual.greenComponent,
      expected.greenComponent,
      accuracy: colorAccuracy,
      file: file,
      line: line
    )
    XCTAssertEqual(
      actual.blueComponent,
      expected.blueComponent,
      accuracy: colorAccuracy,
      file: file,
      line: line
    )
  }

  private func renderedPixels(_ image: NSBitmapImageRep) throws -> Data {
    let bytes = try XCTUnwrap(image.bitmapData)
    let visibleBytesPerRow = image.pixelsWide * image.samplesPerPixel
    var pixels = Data(capacity: visibleBytesPerRow * image.pixelsHigh)

    // NSBitmapImageRep leaves row-padding bytes uninitialized.
    for row in 0..<image.pixelsHigh {
      pixels.append(
        bytes.advanced(by: row * image.bytesPerRow),
        count: visibleBytesPerRow
      )
    }

    return pixels
  }

  private func redDisplayAsset() throws -> SionAsset {
    let image = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1,
        pixelsHigh: 1,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    image.setColor(.red, atX: 0, y: 0)
    let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))

    return try SionAsset.safeDisplayPNG(data: data)
  }
}
