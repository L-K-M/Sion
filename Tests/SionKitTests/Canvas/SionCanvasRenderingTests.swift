import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasRenderingTests: XCTestCase {
  private let canvasSize = SionSize(width: 320, height: 240)
  private let colorAccuracy = 0.04

  func testElementOpacityMultipliesIntrinsicFillAlpha() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 80, y: 60, width: 160, height: 120),
      kind: .ellipse
    )
    shape.style = ElementStyle(
      fill: .solid(SionColor(red: 1, green: 0, blue: 0, alpha: 0.5)),
      opacity: 0.5
    )

    var equivalent = shape
    equivalent.style.fill = .solid(.init(red: 1, green: 0, blue: 0, alpha: 0.25))
    equivalent.style.opacity = 1

    let actual = try render(elements: [shape])
    let expected = try render(elements: [equivalent])

    assertEqual(
      try pixel(in: actual, at: SionPoint(x: 160, y: 120)),
      try pixel(in: expected, at: SionPoint(x: 160, y: 120))
    )
    assertEqual(
      try pixel(in: actual, at: SionPoint(x: 80, y: 120)),
      try pixel(in: expected, at: SionPoint(x: 80, y: 120))
    )
  }

  func testOpacityCompositesFillAndStrokeOnce() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 80, y: 60, width: 160, height: 120),
      kind: .rectangle
    )
    shape.style = ElementStyle(
      fill: .solid(.black),
      stroke: StrokeStyle(color: .black, width: 20),
      opacity: 0.5
    )

    let image = try render(elements: [shape])
    let fill = try pixel(in: image, at: SionPoint(x: 160, y: 120))
    let overlap = try pixel(in: image, at: SionPoint(x: 85, y: 120))

    XCTAssertEqual(overlap.redComponent, fill.redComponent, accuracy: colorAccuracy)
    XCTAssertEqual(overlap.greenComponent, fill.greenComponent, accuracy: colorAccuracy)
    XCTAssertEqual(overlap.blueComponent, fill.blueComponent, accuracy: colorAccuracy)
  }

  func testOverlayUsesTheOverlayBlendEquation() throws {
    var backdrop = SceneElement.shape(
      frame: SionRect(x: 60, y: 40, width: 200, height: 160),
      kind: .rectangle
    )
    backdrop.style = ElementStyle(
      fill: .solid(SionColor(red: 0.25, green: 0.25, blue: 0.25))
    )

    var overlay = SceneElement.shape(
      frame: SionRect(x: 90, y: 70, width: 140, height: 100),
      kind: .rectangle
    )
    overlay.style = ElementStyle(
      fill: .solid(SionColor(red: 0.8, green: 0.8, blue: 0.8)),
      blendMode: .overlay
    )

    let point = SionPoint(x: 160, y: 120)
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

  func testGroupShadowHasUniformAlphaAcrossFillAndStroke() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 60, y: 70, width: 80, height: 100),
      kind: .rectangle
    )
    shape.style = ElementStyle(
      fill: .solid(.black),
      stroke: StrokeStyle(color: .black, width: 20),
      shadows: [
        ShadowStyle(
          color: SionColor(red: 1, green: 0, blue: 0, alpha: 0.5),
          offset: SionVector(dx: 120, dy: 0),
          blurRadius: 0
        )
      ]
    )

    let image = try render(elements: [shape])
    let strokeOnly = try pixel(in: image, at: SionPoint(x: 175, y: 120))
    let fillAndStroke = try pixel(in: image, at: SionPoint(x: 185, y: 120))

    assertEqual(strokeOnly, fillAndStroke)
  }

  func testRotatedElementShadowUsesBaseSpaceOffset() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 100, y: 80, width: 40, height: 80),
      kind: .rectangle
    )
    shape.geometry.rotationRadians = .pi / 2
    shape.style = ElementStyle(
      fill: .solid(.black),
      shadows: [
        ShadowStyle(
          color: SionColor(red: 1, green: 0, blue: 0),
          offset: SionVector(dx: 80, dy: 0),
          blurRadius: 0
        )
      ]
    )

    let shadow = try pixel(
      in: render(elements: [shape]),
      at: SionPoint(x: 200, y: 120)
    )

    XCTAssertGreaterThan(shadow.redComponent, 0.8)
    XCTAssertGreaterThan(shadow.redComponent - shadow.greenComponent, 0.5)
    XCTAssertGreaterThan(shadow.redComponent - shadow.blueComponent, 0.5)
  }

  func testCanvasCoordinatesGrowDownward() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 80, y: 20, width: 160, height: 50),
      kind: .rectangle
    )
    shape.style = ElementStyle(fill: .solid(.black))

    let image = try render(elements: [shape])
    let upper = try pixel(in: image, at: SionPoint(x: 160, y: 40))
    let lower = try pixel(in: image, at: SionPoint(x: 160, y: 200))

    XCTAssertLessThan(upper.redComponent, 0.2)
    XCTAssertGreaterThan(lower.redComponent, 0.8)
  }

  func testSelectionChromeEscapesElementOpacity() throws {
    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 80, y: 120)),
      target: .free(SionPoint(x: 240, y: 120)),
      routingStyle: .straight
    )
    connector.style.opacity = 0

    let blank = try render(elements: [])
    let selected = try render(elements: [connector], selection: [connector.id])

    XCTAssertNotEqual(try renderedPixels(selected), try renderedPixels(blank))
    XCTAssertNotEqual(
      try pixel(in: selected, at: SionPoint(x: 82, y: 120)),
      try pixel(in: blank, at: SionPoint(x: 82, y: 120))
    )
    assertEqual(
      try pixel(in: selected, at: SionPoint(x: 160, y: 100)),
      try pixel(in: blank, at: SionPoint(x: 160, y: 100))
    )
  }

  func testRouteLessConnectorStillShowsSelectionChrome() throws {
    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 80, y: 80)),
      target: .free(SionPoint(x: 240, y: 160)),
      routingStyle: .straight
    )
    connector.geometry.frame = SionRect(x: 80, y: 80, width: 160, height: 80)
    let unavailableRoute: SceneRenderGeometry.ConnectorRouteProvider = { _ in nil }

    let unselected = try render(
      elements: [connector],
      connectorRouteProvider: unavailableRoute
    )
    let selected = try render(
      elements: [connector],
      selection: [connector.id],
      connectorRouteProvider: unavailableRoute
    )

    XCTAssertNotEqual(
      try renderedPixels(selected),
      try renderedPixels(unselected)
    )
  }

  private func zeroOpacityElements(displayAssetID: AssetID) throws -> [SceneElement] {
    var shape = SceneElement.shape(
      frame: SionRect(x: 80, y: 80, width: 160, height: 80),
      kind: .rectangle,
      text: "Shape"
    )
    shape.style.opacity = 0

    var text = SceneElement.text(
      frame: SionRect(x: 80, y: 80, width: 160, height: 80),
      text: "Text"
    )
    text.style.opacity = 0

    var image = SceneElement.image(
      frame: SionRect(x: 80, y: 70, width: 160, height: 100),
      assetID: displayAssetID,
      displayAssetID: displayAssetID
    )
    image.style.opacity = 0

    var connector = SceneElement.connector(
      source: .free(SionPoint(x: 80, y: 120)),
      target: .free(SionPoint(x: 240, y: 120)),
      routingStyle: .straight
    )
    connector.style.opacity = 0
    connector.content = .connector(
      ConnectorContent(
        source: .free(SionPoint(x: 80, y: 120)),
        target: .free(SionPoint(x: 240, y: 120)),
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
    selection: Set<ElementID> = [],
    connectorRouteProvider: SceneRenderGeometry.ConnectorRouteProvider? = nil
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
    let canvas = SionCanvasView(
      editorController: controller,
      connectorRouteProvider: connectorRouteProvider
    )
    canvas.frame = NSRect(
      origin: .zero,
      size: NSSize(width: canvasSize.width, height: canvasSize.height)
    )
    let graphics = try bitmapContext(
      width: Int(canvasSize.width),
      height: Int(canvasSize.height)
    )
    let context = NSGraphicsContext(cgContext: graphics, flipped: true)
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    graphics.translateBy(x: 0, y: canvasSize.height)
    graphics.scaleBy(x: 1, y: -1)
    canvas.draw(canvas.bounds)
    context.flushGraphics()
    return try bitmapRepresentation(from: graphics)
  }

  private func bitmapContext(width: Int, height: Int) throws -> CGContext {
    let colorSpace = try XCTUnwrap(
      CGColorSpace(name: CGColorSpace.sRGB)
    )
    return try XCTUnwrap(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: TestBitmap.bitsPerComponent,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
  }

  private func bitmapRepresentation(from context: CGContext) throws -> NSBitmapImageRep {
    NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
  }

  private func overlayReferenceColor(at point: SionPoint) throws -> NSColor {
    let graphics = try bitmapContext(
      width: Int(canvasSize.width),
      height: Int(canvasSize.height)
    )
    let bounds = NSRect(
      origin: .zero,
      size: NSSize(width: canvasSize.width, height: canvasSize.height)
    )
    graphics.setFillColor(NSColor.white.cgColor)
    graphics.fill(bounds)
    graphics.setFillColor(
      NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.25, alpha: 1).cgColor
    )
    graphics.fill(bounds)
    graphics.setFillColor(
      NSColor(calibratedRed: 0.8, green: 0.8, blue: 0.8, alpha: 1).cgColor
    )
    graphics.setBlendMode(.overlay)
    graphics.fill(bounds)

    return try pixel(in: bitmapRepresentation(from: graphics), at: point)
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
    XCTAssertEqual(
      actual.alphaComponent,
      expected.alphaComponent,
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
    let graphics = try bitmapContext(width: 1, height: 1)
    graphics.setFillColor(NSColor.red.cgColor)
    graphics.fill(NSRect(x: 0, y: 0, width: 1, height: 1))
    let image = try bitmapRepresentation(from: graphics)
    let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))

    return try SionAsset.safeDisplayPNG(data: data)
  }
}

private enum TestBitmap {
  static let bitsPerComponent = 8
}
