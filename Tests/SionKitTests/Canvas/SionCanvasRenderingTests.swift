import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasRenderingTests: XCTestCase {
  private let canvasSize = SionSize(width: 320, height: 240)
  private let colorAccuracy: CGFloat = 0.04
  private let sRGBColorAccuracy: CGFloat = 2.0 / 255.0

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

  func testGradientHonorsAuthoredStartAndEndPoints() throws {
    let frame = SionRect(x: 80, y: 60, width: 160, height: 120)
    let start = SionPoint(x: 0.25, y: 0.5)
    let end = SionPoint(x: 0.75, y: 0.5)
    let beforeStart = SionPoint(x: 0.1, y: 0.5)
    let afterEnd = SionPoint(x: 0.9, y: 0.5)
    var shape = SceneElement.shape(frame: frame, kind: .rectangle)
    shape.style = ElementStyle(
      fill: .linearGradient(
        LinearGradientFill(
          stops: [
            GradientStop(color: SionColor(red: 1, green: 0, blue: 0), location: 0),
            GradientStop(color: SionColor(red: 0, green: 0, blue: 1), location: 1),
          ],
          start: start,
          end: end
        )
      )
    )

    let image = try render(elements: [shape])

    assertEqual(
      try pixel(in: image, at: frame.point(atNormalized: beforeStart)),
      NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    )
    assertEqual(
      try pixel(in: image, at: frame.point(atNormalized: afterEnd)),
      NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    )
  }

  func testShortTransparentGradientExtendsItsEndpointColors() throws {
    let frame = SionRect(x: 80, y: 60, width: 160, height: 120)
    var shape = SceneElement.shape(frame: frame, kind: .rectangle)
    shape.style = ElementStyle(
      fill: .linearGradient(
        LinearGradientFill(
          stops: [
            GradientStop(
              color: SionColor(red: 1, green: 0, blue: 0, alpha: 0),
              location: 0
            ),
            GradientStop(color: SionColor(red: 1, green: 0, blue: 0), location: 1),
          ],
          start: SionPoint(x: 0.4, y: 0.5),
          end: SionPoint(x: 0.6, y: 0.5)
        )
      )
    )

    let image = try render(elements: [shape])

    assertEqual(
      try pixel(
        in: image,
        at: frame.point(atNormalized: SionPoint(x: 0.25, y: 0.5))
      ),
      NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    )
    assertEqual(
      try pixel(
        in: image,
        at: frame.point(atNormalized: SionPoint(x: 0.75, y: 0.5))
      ),
      NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    )
  }

  func testRotatedVectorPathKeepsGradientInLocalGeometry() throws {
    let frame = SionRect(x: 80, y: 60, width: 160, height: 120)
    let rotation = Double.pi / 2
    let start = SionPoint(x: 0.25, y: 0.5)
    let end = SionPoint(x: 0.75, y: 0.5)
    let beforeStart = SionPoint(x: 0.1, y: 0.5)
    let afterEnd = SionPoint(x: 0.9, y: 0.5)
    let pathMinimum = SionPoint(x: 0.2, y: 0.2)
    let pathMaximum = SionPoint(x: 0.8, y: 0.8)
    let pathBounds = SionRect(
      x: frame.minX + (frame.width * pathMinimum.x),
      y: frame.minY + (frame.height * pathMinimum.y),
      width: frame.width * (pathMaximum.x - pathMinimum.x),
      height: frame.height * (pathMaximum.y - pathMinimum.y)
    )
    let path = VectorPath(commands: [
      .move(to: pathMinimum),
      .line(to: SionPoint(x: pathMaximum.x, y: pathMinimum.y)),
      .line(to: pathMaximum),
      .line(to: SionPoint(x: pathMinimum.x, y: pathMaximum.y)),
      .close,
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.geometry.rotationRadians = rotation
    element.style = ElementStyle(
      fill: .linearGradient(
        LinearGradientFill(
          stops: [
            GradientStop(color: SionColor(red: 1, green: 0, blue: 0), location: 0),
            GradientStop(color: SionColor(red: 0, green: 0, blue: 1), location: 1),
          ],
          start: start,
          end: end
        )
      )
    )

    let image = try render(elements: [element])
    let rotatedBeforeStart = InteractionGeometry.rotated(
      pathBounds.point(atNormalized: beforeStart),
      around: frame.center,
      by: rotation
    )
    let rotatedAfterEnd = InteractionGeometry.rotated(
      pathBounds.point(atNormalized: afterEnd),
      around: frame.center,
      by: rotation
    )

    assertEqual(
      try pixel(in: image, at: rotatedBeforeStart),
      NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    )
    assertEqual(
      try pixel(in: image, at: rotatedAfterEnd),
      NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    )
  }

  func testColorsRemainSRGBInDisplayP3Context() throws {
    let authored = SionColor(red: 0.25, green: 0.5, blue: 0.75)
    let expected = NSColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 1)
    let solidFrame = SionRect(x: 20, y: 60, width: 100, height: 120)
    var solid = SceneElement.shape(frame: solidFrame, kind: .rectangle)
    solid.style = ElementStyle(fill: .solid(authored))

    let gradientFrame = SionRect(x: 180, y: 60, width: 100, height: 120)
    let gradientStart = SionPoint(x: 0.25, y: 0.5)
    var gradient = SceneElement.shape(frame: gradientFrame, kind: .rectangle)
    gradient.style = ElementStyle(
      fill: .linearGradient(
        LinearGradientFill(
          stops: [
            GradientStop(color: authored, location: 0),
            GradientStop(color: .white, location: 1),
          ],
          start: gradientStart,
          end: SionPoint(x: 0.75, y: 0.5)
        )
      )
    )
    let displayP3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))

    let image = try render(
      elements: [solid, gradient],
      colorSpace: displayP3
    )

    assertEqual(
      try pixel(in: image, at: solidFrame.center),
      expected,
      accuracy: sRGBColorAccuracy
    )
    assertEqual(
      try pixel(
        in: image,
        at: gradientFrame.point(atNormalized: gradientStart)
      ),
      expected,
      accuracy: sRGBColorAccuracy
    )
  }

  func testColorBridgeConvertsDisplayP3InputToStoredSRGB() throws {
    let source = NSColor(displayP3Red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8)
    let expected = try XCTUnwrap(source.usingColorSpace(.sRGB))

    let model = SionColorBridge.modelColor(source)
    let bridged = SionColorBridge.appKitColor(model)

    XCTAssertEqual(
      model.red,
      Double(expected.redComponent),
      accuracy: Double(sRGBColorAccuracy)
    )
    XCTAssertEqual(
      model.green,
      Double(expected.greenComponent),
      accuracy: Double(sRGBColorAccuracy)
    )
    XCTAssertEqual(
      model.blue,
      Double(expected.blueComponent),
      accuracy: Double(sRGBColorAccuracy)
    )
    XCTAssertEqual(
      model.alpha,
      Double(expected.alphaComponent),
      accuracy: Double(sRGBColorAccuracy)
    )
    XCTAssertEqual(bridged.colorSpace, .sRGB)
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
    let empty = try render(
      elements: [],
      connectorRouteProvider: unavailableRoute
    )
    let unselectedPixels = try renderedPixels(unselected)
    let selectedPixels = try renderedPixels(selected)
    let emptyPixels = try renderedPixels(empty)

    XCTAssertNotEqual(selectedPixels, unselectedPixels)
    XCTAssertEqual(
      unselectedPixels,
      emptyPixels,
      "An unselected route-less connector must paint nothing"
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
    connectorRouteProvider: SceneRenderGeometry.ConnectorRouteProvider? = nil,
    colorSpace: CGColorSpace? = nil
  ) throws -> CGImage {
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
      height: Int(canvasSize.height),
      colorSpace: colorSpace
    )
    let context = NSGraphicsContext(cgContext: graphics, flipped: true)
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    graphics.translateBy(x: 0, y: canvasSize.height)
    graphics.scaleBy(x: 1, y: -1)
    canvas.draw(canvas.bounds)
    context.flushGraphics()
    return try XCTUnwrap(graphics.makeImage())
  }

  private func bitmapContext(
    width: Int,
    height: Int,
    colorSpace: CGColorSpace? = nil
  ) throws -> CGContext {
    let renderedColorSpace =
      try colorSpace
      ?? XCTUnwrap(
        CGColorSpace(name: CGColorSpace.sRGB)
      )
    return try XCTUnwrap(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: TestBitmap.bitsPerComponent,
        bytesPerRow: 0,
        space: renderedColorSpace,
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
      NSColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1).cgColor
    )
    graphics.fill(bounds)
    graphics.setFillColor(
      NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1).cgColor
    )
    graphics.setBlendMode(.overlay)
    graphics.fill(bounds)

    return try pixel(in: XCTUnwrap(graphics.makeImage()), at: point)
  }

  private func pixel(in image: CGImage, at point: SionPoint) throws -> NSColor {
    let pixelX = min(max(0, Int(point.x)), image.width - 1)
    let pixelY = min(max(0, Int(point.y)), image.height - 1)
    let sourceY = image.height - pixelY - 1
    let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    var components = [UInt8](repeating: 0, count: TestBitmap.componentsPerPixel)

    return try components.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(
        CGContext(
          data: bytes.baseAddress,
          width: 1,
          height: 1,
          bitsPerComponent: TestBitmap.bitsPerComponent,
          bytesPerRow: TestBitmap.componentsPerPixel,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      )
      context.interpolationQuality = .none
      context.setBlendMode(.copy)
      context.translateBy(x: CGFloat(-pixelX), y: CGFloat(-sourceY))
      context.draw(
        image,
        in: CGRect(
          x: 0,
          y: 0,
          width: CGFloat(image.width),
          height: CGFloat(image.height)
        )
      )

      let values = bytes.bindMemory(to: UInt8.self)
      let alpha = CGFloat(values[3]) / 255
      guard alpha > 0 else {
        return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
      }

      return NSColor(
        srgbRed: (CGFloat(values[0]) / 255) / alpha,
        green: (CGFloat(values[1]) / 255) / alpha,
        blue: (CGFloat(values[2]) / 255) / alpha,
        alpha: alpha
      )
    }
  }

  private func assertEqual(
    _ actual: NSColor,
    _ expected: NSColor,
    accuracy: CGFloat? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let accuracy = accuracy ?? colorAccuracy

    XCTAssertEqual(
      actual.redComponent,
      expected.redComponent,
      accuracy: accuracy,
      file: file,
      line: line
    )
    XCTAssertEqual(
      actual.greenComponent,
      expected.greenComponent,
      accuracy: accuracy,
      file: file,
      line: line
    )
    XCTAssertEqual(
      actual.blueComponent,
      expected.blueComponent,
      accuracy: accuracy,
      file: file,
      line: line
    )
    XCTAssertEqual(
      actual.alphaComponent,
      expected.alphaComponent,
      accuracy: accuracy,
      file: file,
      line: line
    )
  }

  private func renderedPixels(_ image: CGImage) throws -> Data {
    let context = try bitmapContext(width: image.width, height: image.height)
    context.setBlendMode(.copy)
    context.draw(
      image,
      in: CGRect(
        x: 0,
        y: 0,
        width: CGFloat(image.width),
        height: CGFloat(image.height)
      )
    )

    let bytes = try XCTUnwrap(context.data)
      .assumingMemoryBound(to: UInt8.self)
    let visibleBytesPerRow = image.width * TestBitmap.componentsPerPixel
    var pixels = Data(capacity: visibleBytesPerRow * image.height)

    for row in 0..<image.height {
      pixels.append(
        bytes.advanced(by: row * context.bytesPerRow),
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
  static let componentsPerPixel = 4
}
