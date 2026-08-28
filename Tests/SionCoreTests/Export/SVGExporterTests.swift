import XCTest

@testable import SionCore

final class SVGExporterTests: XCTestCase {
  private let pointAccuracy = 1e-12

  func testImageExportNeverEmbedsAnActiveOriginal() throws {
    let originalData = Data("<svg><script>alert('unsafe')</script></svg>".utf8)
    let original = try SionAsset(
      data: originalData,
      mediaType: "image/svg+xml",
      fileExtension: "svg"
    )
    let display = try SionAsset.safeDisplayPNG(data: testPNGData())
    let image = SceneElement.image(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      assetID: original.id,
      displayAssetID: display.id
    )
    let document = SionDocument(scene: SionScene(elements: [image]))

    let svg = try SVGExporter.export(
      document: document,
      assets: [original.id: original, display.id: display]
    )

    XCTAssertTrue(svg.contains("href=\"data:image/png;base64,"))
    XCTAssertTrue(svg.contains(display.data.base64EncodedString()))
    XCTAssertFalse(svg.contains(originalData.base64EncodedString()))
  }

  func testImageExportRejectsSpoofedDisplayPNG() throws {
    let spoofed = try SionAsset(
      data: Data("<svg><script>alert('unsafe')</script></svg>".utf8),
      mediaType: "image/png",
      fileExtension: "png"
    )
    let image = SceneElement.image(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      assetID: spoofed.id,
      displayAssetID: spoofed.id
    )
    let document = SionDocument(scene: SionScene(elements: [image]))

    XCTAssertThrowsError(
      try SVGExporter.export(document: document, assets: [spoofed.id: spoofed])
    ) { error in
      XCTAssertEqual(error as? SVGExportError, .invalidDisplayAsset(spoofed.id))
    }
  }

  func testImageExportEmbedsEachDisplayAssetOnce() throws {
    let display = try SionAsset.safeDisplayPNG(data: testPNGData())
    let first = SceneElement.image(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      assetID: display.id,
      displayAssetID: display.id
    )
    let second = SceneElement.image(
      frame: SionRect(x: 120, y: 0, width: 100, height: 100),
      assetID: display.id,
      displayAssetID: display.id
    )
    let document = SionDocument(scene: SionScene(elements: [first, second]))

    let svg = try SVGExporter.export(document: document, assets: [display.id: display])
    let payload = display.data.base64EncodedString()

    XCTAssertEqual(svg.components(separatedBy: payload).count - 1, 1)
  }

  func testConnectorResolvesVertexMagnetOnDiamondOutline() throws {
    var diamond = SceneElement.shape(
      frame: SionRect(x: 100, y: 200, width: 200, height: 100),
      kind: .diamond
    )
    diamond.magnetConfiguration = .preset(.vertices)
    let connector = SceneElement.connector(
      source: .element(
        diamond.id,
        attachment: .magnet("vertex-0"),
        fallbackPoint: .zero
      ),
      target: .free(SionPoint(x: 400, y: 200)),
      routingStyle: .straight
    )

    let route = try XCTUnwrap(
      SceneRenderGeometry.connectorRoute(
        for: connector,
        in: SionScene(elements: [diamond, connector])
      )
    )

    XCTAssertEqual(route.start, SionPoint(x: 200, y: 200))
  }

  func testShadowFilterUsesPaintedUserSpaceBounds() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      kind: .rectangle
    )
    let shadow = ShadowStyle(
      color: .primaryInk,
      offset: SionVector(dx: 300, dy: 200),
      blurRadius: 40
    )
    shape.style.shadows = [shadow]

    let svg = try SVGExporter.export(
      document: SionDocument(scene: SionScene(elements: [shape])),
      assets: [:]
    )

    XCTAssertTrue(svg.contains("filterUnits=\"userSpaceOnUse\""))
    XCTAssertFalse(svg.contains("x=\"-50%\""))
    XCTAssertFalse(svg.contains("width=\"200%\""))

    let filterStart = try XCTUnwrap(svg.range(of: "<filter "))
    let filterSuffix = svg[filterStart.lowerBound...]
    let filterEnd = try XCTUnwrap(filterSuffix.firstIndex(of: ">"))
    let filterTag = filterSuffix[...filterEnd]
    let x = try XCTUnwrap(numberAttribute("x", in: filterTag))
    let y = try XCTUnwrap(numberAttribute("y", in: filterTag))
    let width = try XCTUnwrap(numberAttribute("width", in: filterTag))
    let height = try XCTUnwrap(numberAttribute("height", in: filterTag))

    XCTAssertLessThanOrEqual(x, shape.geometry.frame.minX)
    XCTAssertLessThanOrEqual(y, shape.geometry.frame.minY)
    XCTAssertGreaterThanOrEqual(
      x + width,
      shape.geometry.frame.maxX + shadow.offset.dx + shadow.blurRadius
    )
    XCTAssertGreaterThanOrEqual(
      y + height,
      shape.geometry.frame.maxY + shadow.offset.dy + shadow.blurRadius
    )
  }

  func testConnectorResolutionUsesRotatedMagnets() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 100, y: 200, width: 200, height: 100)
    )
    shape.geometry.rotationRadians = .pi / 2
    shape.magnetConfiguration = .preset(.northSouth)

    let target = SionPoint(x: 400, y: 250)
    let explicit = SceneElement.connector(
      source: .element(
        shape.id,
        attachment: .magnet("north"),
        fallbackPoint: .zero
      ),
      target: .free(target),
      routingStyle: .straight
    )
    let automatic = SceneElement.connector(
      source: .element(
        shape.id,
        attachment: .automatic,
        fallbackPoint: .zero
      ),
      target: .free(target),
      routingStyle: .straight
    )
    let scene = SionScene(elements: [shape, explicit, automatic])

    let explicitRoute = try XCTUnwrap(
      SceneRenderGeometry.connectorRoute(for: explicit, in: scene)
    )
    let automaticRoute = try XCTUnwrap(
      SceneRenderGeometry.connectorRoute(for: automatic, in: scene)
    )

    XCTAssertEqual(explicitRoute.start.x, 250, accuracy: pointAccuracy)
    XCTAssertEqual(explicitRoute.start.y, 250, accuracy: pointAccuracy)
    XCTAssertEqual(automaticRoute.start.x, 250, accuracy: pointAccuracy)
    XCTAssertEqual(automaticRoute.start.y, 250, accuracy: pointAccuracy)
  }

  func testInvalidXMLScalarsAreReplaced() throws {
    let text = SceneElement.text(
      frame: SionRect(x: 0, y: 0, width: 160, height: 80),
      text: "before\u{0000}after\u{000C}"
    )
    let document = SionDocument(
      title: "title\u{0001}",
      scene: SionScene(elements: [text])
    )

    let svg = try SVGExporter.export(document: document, assets: [:])

    XCTAssertFalse(svg.unicodeScalars.contains { $0.value == 0 || $0.value == 12 })
    XCTAssertTrue(svg.contains("before�after�"))
    XCTAssertTrue(svg.contains("title�"))
  }

  func testShapeEffectsWrapGeometryAndLabel() throws {
    let id = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000001"))
    var shape = SceneElement.shape(
      id: id,
      frame: SionRect(x: 20, y: 20, width: 120, height: 80),
      kind: .rectangle,
      text: "Label"
    )
    shape.style = ElementStyle(
      fill: .solid(SionColor(red: 1, green: 0, blue: 0, alpha: 0.5)),
      stroke: StrokeStyle(
        color: SionColor(red: 0, green: 0, blue: 1, alpha: 0.25),
        width: 4
      ),
      shadows: [
        ShadowStyle(
          color: SionColor(red: 0, green: 0, blue: 0, alpha: 0.3),
          offset: SionVector(dx: 3, dy: 4),
          blurRadius: 6
        )
      ],
      opacity: 0.4,
      blendMode: .overlay
    )
    let svg = try export([shape])

    let group = try openingTag(startingWith: "<g id=\"element-\(id)\"", in: svg)
    let groupMarkup = try elementGroup(id: id, in: svg)
    let path = try openingTag(startingWith: "<path d=", in: String(groupMarkup))

    XCTAssertTrue(group.text.contains("opacity=\"0.4\""))
    XCTAssertTrue(group.text.contains("mix-blend-mode:overlay"))
    XCTAssertTrue(group.text.contains("filter=\"url(#shadow-\(id))\""))
    XCTAssertTrue(svg.contains("id=\"shadow-\(id)\""))
    XCTAssertFalse(path.text.contains("opacity="))
    XCTAssertFalse(path.text.contains("mix-blend-mode:"))
    XCTAssertFalse(path.text.contains("filter="))
    XCTAssertTrue(path.text.contains("fill=\"#ff000080\""))
    XCTAssertTrue(path.text.contains("stroke=\"#0000ff40\""))
    XCTAssertTrue(groupMarkup.contains("<text "))
  }

  func testLinearGradientPreservesAuthoredSRGBDefinition() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 20, width: 120, height: 80),
      kind: .rectangle
    )
    shape.style = ElementStyle(
      fill: .linearGradient(
        LinearGradientFill(
          stops: [
            GradientStop(
              color: SionColor(red: 0.25, green: 0.5, blue: 0.75),
              location: 0
            ),
            GradientStop(color: SionColor(red: 1, green: 1, blue: 1), location: 1),
          ],
          start: SionPoint(x: 0.25, y: 0.4),
          end: SionPoint(x: 0.75, y: 0.6)
        )
      )
    )

    let svg = try export([shape])

    XCTAssertTrue(
      svg.contains(
        "<linearGradient id=\"gradient-\(shape.id)\" x1=\"25%\" y1=\"40%\" x2=\"75%\" y2=\"60%\">"
      )
    )
    XCTAssertTrue(svg.contains("stop-color=\"#4080bfff\""))
    XCTAssertTrue(svg.contains("stop-color=\"#ffffffff\""))
  }

  func testConnectorEffectsWrapRouteMarkersAndLabel() throws {
    let id = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000002"))
    var connector = SceneElement.connector(
      id: id,
      source: .free(SionPoint(x: 20, y: 40)),
      target: .free(SionPoint(x: 220, y: 40)),
      routingStyle: .straight
    )
    connector.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: SionColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5),
        width: 3
      ),
      opacity: 0.25,
      blendMode: .multiply
    )
    connector.content = .connector(
      ConnectorContent(
        source: .free(SionPoint(x: 20, y: 40)),
        target: .free(SionPoint(x: 220, y: 40)),
        routingStyle: .straight,
        sourceDecoration: .circle,
        targetDecoration: .filledArrow,
        label: TextContent(string: "Flow")
      )
    )
    let svg = try export([connector])

    let group = try openingTag(startingWith: "<g id=\"element-\(id)\"", in: svg)
    let groupMarkup = try elementGroup(id: id, in: svg)

    XCTAssertTrue(group.text.contains("opacity=\"0.25\""))
    XCTAssertTrue(group.text.contains("mix-blend-mode:multiply"))
    XCTAssertTrue(groupMarkup.contains("marker-start=\"url(#marker-circle)\""))
    XCTAssertTrue(groupMarkup.contains("marker-end=\"url(#marker-filledArrow)\""))
    XCTAssertTrue(groupMarkup.contains("<text "))
    XCTAssertEqual(svg.components(separatedBy: "opacity=\"0.25\"").count - 1, 1)
  }

  func testConnectorRouteIgnoresElementRotation() throws {
    let id = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000005"))
    var connector = SceneElement.connector(
      id: id,
      source: .free(SionPoint(x: 20, y: 40)),
      target: .free(SionPoint(x: 220, y: 40)),
      routingStyle: .straight
    )
    connector.geometry.rotationRadians = .pi / 2

    let svg = try export([connector])
    let group = try openingTag(startingWith: "<g id=\"element-\(id)\"", in: svg)
    let groupMarkup = try elementGroup(id: id, in: svg)

    XCTAssertFalse(group.text.contains("transform="))
    XCTAssertTrue(groupMarkup.contains(#"d="M20 40L220 40""#))
  }

  func testShadowFilterContainsLongShapeLabel() throws {
    let id = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000006"))
    let label = String(repeating: "W", count: 20)
    var shape = SceneElement.shape(
      id: id,
      frame: SionRect(x: 100, y: 100, width: 20, height: 40),
      kind: .rectangle,
      text: label
    )
    var labelStyle = TextStyle.shapeLabelDefault
    labelStyle.font.size = 20
    shape.content = .shape(
      ShapeContent(
        kind: .rectangle,
        label: TextContent(string: label, style: labelStyle)
      )
    )
    shape.style.shadows = [
      ShadowStyle(color: .black, offset: .zero, blurRadius: 0)
    ]

    let svg = try export([shape])
    let filter = try openingTag(startingWith: "<filter id=\"shadow-\(id)\"", in: svg)
    let minimumTextWidth = Double(label.count) * 20
    let filterX = try XCTUnwrap(numberAttribute("x", in: filter.text))
    let filterWidth = try XCTUnwrap(numberAttribute("width", in: filter.text))

    XCTAssertLessThanOrEqual(filterX, shape.geometry.frame.center.x - minimumTextWidth / 2)
    XCTAssertGreaterThanOrEqual(
      filterX + filterWidth,
      shape.geometry.frame.center.x + minimumTextWidth / 2
    )
  }

  func testShadowFilterContainsLongConnectorLabel() throws {
    let id = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000007"))
    let label = String(repeating: "W", count: 20)
    var connector = SceneElement.connector(
      id: id,
      source: .free(SionPoint(x: 100, y: 120)),
      target: .free(SionPoint(x: 120, y: 120)),
      routingStyle: .straight
    )
    var labelStyle = TextStyle.shapeLabelDefault
    labelStyle.font.size = 20
    connector.content = .connector(
      ConnectorContent(
        source: .free(SionPoint(x: 100, y: 120)),
        target: .free(SionPoint(x: 120, y: 120)),
        routingStyle: .straight,
        label: TextContent(string: label, style: labelStyle)
      )
    )
    connector.style.shadows = [
      ShadowStyle(color: .black, offset: .zero, blurRadius: 0)
    ]

    let svg = try export([connector])
    let filter = try openingTag(startingWith: "<filter id=\"shadow-\(id)\"", in: svg)
    let minimumTextWidth = Double(label.count) * 20
    let filterX = try XCTUnwrap(numberAttribute("x", in: filter.text))
    let filterWidth = try XCTUnwrap(numberAttribute("width", in: filter.text))

    XCTAssertLessThanOrEqual(filterX, 110 - minimumTextWidth / 2)
    XCTAssertGreaterThanOrEqual(filterX + filterWidth, 110 + minimumTextWidth / 2)
  }

  func testTextAndImageGroupsContainOnlyElementEffects() throws {
    let textID = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000003"))
    var text = SceneElement.text(
      id: textID,
      frame: SionRect(x: 20, y: 20, width: 120, height: 60),
      text: "Text"
    )
    text.style.opacity = 0.3
    text.style.blendMode = .screen

    let display = try SionAsset.safeDisplayPNG(data: testPNGData())
    let imageID = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000004"))
    var image = SceneElement.image(
      id: imageID,
      frame: SionRect(x: 160, y: 20, width: 80, height: 80),
      assetID: display.id,
      displayAssetID: display.id
    )
    image.style.opacity = 0.6
    image.style.blendMode = .multiply

    let document = SionDocument(scene: SionScene(elements: [text, image]))
    let svg = try SVGExporter.export(
      document: document,
      assets: [display.id: display]
    )

    for (id, opacity, blend) in [
      (textID, "0.3", "screen"),
      (imageID, "0.6", "multiply"),
    ] {
      let group = try openingTag(startingWith: "<g id=\"element-\(id)\"", in: svg)

      XCTAssertTrue(group.text.contains("opacity=\"\(opacity)\""))
      XCTAssertTrue(group.text.contains("mix-blend-mode:\(blend)"))
      XCTAssertFalse(group.text.contains(" fill="))
      XCTAssertFalse(group.text.contains(" stroke="))
    }
  }

  func testElementGroupIncludesNestedContent() throws {
    let id = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000008"))
    let source =
      "<svg><g id=\"element-\(id)\"><path/><g><circle/></g><text>inside</text></g><text>outside</text></svg>"

    let group = try elementGroup(id: id, in: source)

    XCTAssertTrue(group.contains("<text>inside</text>"))
    XCTAssertFalse(group.contains("<text>outside</text>"))
  }

  func testElementGroupIgnoresNonGroupTagPrefixes() throws {
    let id = try XCTUnwrap(ElementID("00000000-0000-0000-0000-000000000009"))
    let source =
      "<svg><g id=\"element-\(id)\"><glyph/><text>inside</text></g><text>outside</text></svg>"

    let group = try elementGroup(id: id, in: source)

    XCTAssertTrue(group.contains("<text>inside</text>"))
    XCTAssertFalse(group.contains("<text>outside</text>"))
  }

  func testNumberAttributeMatchesExactName() {
    let tag = Substring(#"<filter dx="9" x="-4" dy="8" y="-3">"#)

    XCTAssertEqual(numberAttribute("x", in: tag), -4)
    XCTAssertEqual(numberAttribute("y", in: tag), -3)
  }

  private func export(_ elements: [SceneElement]) throws -> String {
    try SVGExporter.export(
      document: SionDocument(scene: SionScene(elements: elements)),
      assets: [:]
    )
  }

  private func openingTag(
    startingWith prefix: String,
    after index: String.Index? = nil,
    in source: String
  ) throws -> (text: Substring, startIndex: String.Index, endIndex: String.Index) {
    let searchRange = (index ?? source.startIndex)..<source.endIndex
    let start = try XCTUnwrap(source.range(of: prefix, range: searchRange)?.lowerBound)
    let end = try XCTUnwrap(source[start...].firstIndex(of: ">"))

    return (source[start...end], start, source.index(after: end))
  }

  private func elementGroup(id: ElementID, in source: String) throws -> Substring {
    let opening = try openingTag(startingWith: "<g id=\"element-\(id)\"", in: source)
    var depth = 1
    var searchStart = opening.endIndex

    // Match the element's closing group, not a nested effect group.
    while depth > 0 {
      let nextOpening = ["<g>", "<g "]
        .compactMap {
          source.range(of: $0, range: searchStart..<source.endIndex)
        }
        .min(by: { $0.lowerBound < $1.lowerBound })
      let nextClosing = try XCTUnwrap(
        source.range(of: "</g>", range: searchStart..<source.endIndex)
      )

      if let nextOpening, nextOpening.lowerBound < nextClosing.lowerBound {
        depth += 1
        searchStart = nextOpening.upperBound
        continue
      }

      depth -= 1
      searchStart = nextClosing.upperBound
    }

    return source[opening.startIndex..<searchStart]
  }

  private func numberAttribute(_ name: String, in tag: Substring) -> Double? {
    let prefix = "\(name)=\""
    guard
      let attribute =
        tag
        .split(whereSeparator: \Character.isWhitespace)
        .first(where: { $0.hasPrefix(prefix) }),
      let valueEnd =
        attribute.dropFirst(prefix.count).firstIndex(of: "\"")
    else {
      return nil
    }

    let valueStart = attribute.index(attribute.startIndex, offsetBy: prefix.count)
    return Double(attribute[valueStart..<valueEnd])
  }
}
