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

    let image = try render(elements: [shape])
    let color = try pixel(in: image, at: SionPoint(x: 90, y: 90))

    XCTAssertEqual(color.redComponent, 1, accuracy: colorAccuracy)
    XCTAssertEqual(color.greenComponent, 0.75, accuracy: colorAccuracy)
    XCTAssertEqual(color.blueComponent, 0.75, accuracy: colorAccuracy)
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

    let image = try render(elements: [backdrop, overlay])
    let color = try pixel(in: image, at: SionPoint(x: 90, y: 90))

    XCTAssertEqual(color.redComponent, 0.4, accuracy: colorAccuracy)
    XCTAssertEqual(color.greenComponent, 0.4, accuracy: colorAccuracy)
    XCTAssertEqual(color.blueComponent, 0.4, accuracy: colorAccuracy)
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

      XCTAssertEqual(renderedPixels(rendered), renderedPixels(blank), "\(element.content)")
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

    XCTAssertNotEqual(renderedPixels(selected), renderedPixels(blank))
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
    let representation = try XCTUnwrap(
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
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: representation))
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    canvas.draw(canvas.bounds)
    context.flushGraphics()
    return representation
  }

  private func pixel(in image: NSBitmapImageRep, at point: SionPoint) throws -> NSColor {
    let color = try XCTUnwrap(
      image.colorAt(x: Int(point.x), y: Int(point.y))
    )
    return try XCTUnwrap(color.usingColorSpace(.sRGB))
  }

  private func renderedPixels(_ image: NSBitmapImageRep) -> Data {
    Data(
      bytes: image.bitmapData!,
      count: image.bytesPerRow * image.pixelsHigh
    )
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
