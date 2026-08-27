import XCTest

@testable import SionCore

final class CanvasViewportTests: XCTestCase {
  private let minimumInfiniteSize = SionSize(width: 4_000, height: 3_000)

  func testFixedCanvasUsesDeclaredExtent() {
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(SionSize(width: 640, height: 480)))
    )

    XCTAssertEqual(
      SceneRenderGeometry.editingCanvasBounds(
        of: scene,
        minimumInfiniteSize: minimumInfiniteSize
      ),
      SionRect(x: 0, y: 0, width: 640, height: 480)
    )
  }

  func testFixedCanvasEditingBoundsIncludeOutsideContent() {
    let outside = SceneElement.shape(
      frame: SionRect(x: -200, y: 600, width: 100, height: 80),
      kind: .rectangle
    )
    let scene = SionScene(
      canvas: SionCanvas(extent: .fixed(SionSize(width: 640, height: 480))),
      elements: [outside]
    )

    let bounds = SceneRenderGeometry.editingCanvasBounds(
      of: scene,
      minimumInfiniteSize: minimumInfiniteSize
    )

    XCTAssertLessThan(bounds.minX, outside.geometry.frame.minX)
    XCTAssertGreaterThan(bounds.maxY, outside.geometry.frame.maxY)
    XCTAssertTrue(bounds.contains(SionPoint(x: 0, y: 0)))
    XCTAssertTrue(bounds.contains(SionPoint(x: 640, y: 480)))
  }

  func testEmptyInfiniteCanvasUsesMinimumSize() {
    XCTAssertEqual(
      SceneRenderGeometry.editingCanvasBounds(
        of: SionScene(),
        minimumInfiniteSize: minimumInfiniteSize
      ),
      SionRect(x: 0, y: 0, width: 4_000, height: 3_000)
    )
  }

  func testInfiniteCanvasIncludesNegativeAndDistantContent() {
    let negative = SceneElement.shape(
      frame: SionRect(x: -500, y: -300, width: 100, height: 80),
      kind: .rectangle
    )
    let distant = SceneElement.shape(
      frame: SionRect(x: 4_500, y: 3_400, width: 200, height: 100),
      kind: .rectangle
    )
    let scene = SionScene(elements: [negative, distant])

    let bounds = SceneRenderGeometry.editingCanvasBounds(
      of: scene,
      minimumInfiniteSize: minimumInfiniteSize
    )

    XCTAssertLessThan(bounds.minX, negative.geometry.frame.minX)
    XCTAssertLessThan(bounds.minY, negative.geometry.frame.minY)
    XCTAssertGreaterThan(bounds.maxX, distant.geometry.frame.maxX)
    XCTAssertGreaterThan(bounds.maxY, distant.geometry.frame.maxY)
  }

  func testRouteProviderSuppliesConnectorBoundsWithoutReRouting() {
    let source = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 100, height: 60),
      kind: .rectangle
    )
    let target = SceneElement.shape(
      frame: SionRect(x: 400, y: 200, width: 100, height: 60),
      kind: .rectangle
    )
    let connector = SceneElement.connector(
      source: .element(
        source.id,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 100, y: 30)
      ),
      target: .element(
        target.id,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 400, y: 230)
      )
    )
    let scene = SionScene(elements: [source, target, connector])

    let expected = SceneRenderGeometry.editingCanvasBounds(
      of: scene,
      minimumInfiniteSize: minimumInfiniteSize
    )

    let routed = SceneRenderGeometry.connectorRoute(for: connector, in: scene)
    XCTAssertNotNil(routed)

    let providerBounds = SceneRenderGeometry.editingCanvasBounds(
      of: scene,
      minimumInfiniteSize: minimumInfiniteSize,
      connectorRoutes: { element in
        element.id == connector.id ? routed : nil
      }
    )

    XCTAssertEqual(providerBounds, expected)
  }
}
