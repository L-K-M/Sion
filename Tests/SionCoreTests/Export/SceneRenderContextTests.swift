import XCTest

@testable import SionCore

final class SceneRenderContextTests: XCTestCase {
  private enum Fixture {
    static let elementCount = 25_000
    static let columnCount = 250
    static let spacing = 1_000.0
    static let elementSize = 40.0
    static let maximumExaminedElementCount = 4
  }

  func testQueryBoundsWorkForTwentyFiveThousandElements() {
    let elements = (0..<Fixture.elementCount).map { index in
      SceneElement.shape(
        frame: SionRect(
          x: Double(index % Fixture.columnCount) * Fixture.spacing,
          y: Double(index / Fixture.columnCount) * Fixture.spacing,
          width: Fixture.elementSize,
          height: Fixture.elementSize
        ),
        kind: .rectangle
      )
    }
    let targetIndex = Fixture.elementCount / 2
    let target = elements[targetIndex]
    let queryBounds = target.geometry.frame.expanded(by: 1)
    let context = SceneRenderContext(scene: SionScene(elements: elements))

    let query = context.elements(intersecting: queryBounds)

    XCTAssertEqual(query.elements.map(\.id), [target.id])
    XCTAssertLessThanOrEqual(
      query.examinedElementCount,
      Fixture.maximumExaminedElementCount
    )
  }

  func testQueryPreservesSceneOrder() {
    let elements = (0..<3).map { _ in
      SceneElement.shape(
        frame: SionRect(x: 100, y: 100, width: 80, height: 60),
        kind: .rectangle
      )
    }
    let context = SceneRenderContext(scene: SionScene(elements: elements))

    let query = context.elements(
      intersecting: SionRect(x: 120, y: 120, width: 10, height: 10)
    )

    XCTAssertEqual(query.elements.map(\.id), elements.map(\.id))
  }

  func testQueryUsesConservativePaintedBounds() {
    var shape = SceneElement.shape(
      frame: SionRect(x: 100, y: 100, width: 40, height: 80),
      kind: .rectangle
    )
    shape.geometry.rotationRadians = .pi / 2
    shape.style = ElementStyle(
      fill: .solid(.black),
      stroke: StrokeStyle(color: .black, width: 20),
      shadows: [
        ShadowStyle(
          color: .black,
          offset: SionVector(dx: 80, dy: 0),
          blurRadius: 0
        )
      ]
    )
    let context = SceneRenderContext(scene: SionScene(elements: [shape]))

    let query = context.elements(
      intersecting: SionRect(x: 230, y: 130, width: 1, height: 1)
    )

    XCTAssertEqual(query.elements.map(\.id), [shape.id])
  }

  func testIncrementalUpdateMovesOneIndexedElement() {
    let stationary = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 40, height: 40),
      kind: .rectangle
    )
    var moved = SceneElement.shape(
      frame: SionRect(x: 4_000, y: 4_000, width: 40, height: 40),
      kind: .rectangle
    )
    var context = SceneRenderContext(
      scene: SionScene(elements: [stationary, moved])
    )
    moved.geometry.frame.origin = SionPoint(x: 80, y: 0)

    context.update(
      scene: SionScene(elements: [stationary, moved]),
      changedElementIDs: [moved.id]
    )
    let query = context.elements(
      intersecting: SionRect(x: 70, y: -10, width: 70, height: 60)
    )

    XCTAssertEqual(query.elements.map(\.id), [moved.id])
  }

  func testConnectorRouteResolvesOncePerContextState() throws {
    let connector = SceneElement.connector(
      source: .free(SionPoint(x: 0, y: 0)),
      target: .free(SionPoint(x: 100, y: 0))
    )
    let expectedRoute = ConnectorRoute(
      start: SionPoint(x: 0, y: 0),
      segments: [.line(to: SionPoint(x: 100, y: 0))]
    )
    var resolutionCount = 0
    var context = SceneRenderContext(
      scene: SionScene(elements: [connector]),
      connectorRouteResolver: { _, _ in
        resolutionCount += 1
        return expectedRoute
      }
    )

    XCTAssertEqual(context.connectorRoute(for: connector), expectedRoute)
    XCTAssertEqual(context.connectorRoute(for: connector), expectedRoute)
    XCTAssertEqual(resolutionCount, 1)

    context.update(
      scene: SionScene(elements: [connector]),
      changedElementIDs: [connector.id]
    )
    XCTAssertEqual(context.connectorRoute(for: connector), expectedRoute)
    XCTAssertEqual(resolutionCount, 2)
  }
}
