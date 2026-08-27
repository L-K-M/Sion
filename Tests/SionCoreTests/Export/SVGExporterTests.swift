import XCTest

@testable import SionCore

final class SVGExporterTests: XCTestCase {
  private let pointAccuracy = 1e-12

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
}
