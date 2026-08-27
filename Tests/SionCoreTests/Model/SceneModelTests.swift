import Foundation
import XCTest

@testable import SionCore

final class SceneModelTests: XCTestCase {
  private let magnetPositionAccuracy = 1e-12

  func testDocumentRoundTripsWithStableDiscriminatorsAndExtensions() throws {
    let shape = SceneElement.shape(
      id: elementID("00000000-0000-0000-0000-000000000001"),
      frame: SionRect(x: 20, y: 30, width: 160, height: 96),
      kind: .roundedRectangle(radius: 14),
      text: "Plan"
    )
    let document = SionDocument(
      id: documentID("10000000-0000-0000-0000-000000000001"),
      title: "Roadmap",
      scene: SionScene(
        elements: [shape],
        extensions: ["mermaid": .object(["id": .string("A")])]
      )
    )

    let data = try CanonicalJSON.encode(document)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    let decoded = try CanonicalJSON.decode(SionDocument.self, from: data)

    XCTAssertEqual(decoded, document)
    XCTAssertTrue(json.contains("\"type\" : \"roundedRectangle\""))
    XCTAssertFalse(json.contains("_0"))
    XCTAssertTrue(json.contains("00000000-0000-0000-0000-000000000001"))
  }

  func testShapeDefaultsIncludeReadableTextAndSubtleShadow() {
    let element = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 160, height: 96),
      text: "Decision"
    )

    XCTAssertFalse(element.style.shadows.isEmpty)
    XCTAssertEqual(element.magnetConfiguration, .preset(.cardinalFour))

    guard case .shape(let shape) = element.content else {
      return XCTFail("Expected shape content")
    }

    XCTAssertEqual(shape.label?.string, "Decision")
    XCTAssertEqual(shape.label?.style.horizontalAlignment, .center)
    XCTAssertEqual(shape.label?.style.verticalAlignment, .center)
  }

  func testAttachedEndpointPersistsFallbackWithStableKeys() throws {
    let endpoint = ConnectionEndpoint.element(
      elementID("00000000-0000-0000-0000-000000000010"),
      attachment: .magnet("east"),
      fallbackPoint: SionPoint(x: 240, y: 120)
    )

    let data = try CanonicalJSON.encode(endpoint)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    XCTAssertEqual(object["type"] as? String, "element")
    XCTAssertNotNil(object["fallbackPoint"])
    XCTAssertNil(object["_0"])
    XCTAssertEqual(try CanonicalJSON.decode(ConnectionEndpoint.self, from: data), endpoint)
  }

  func testExpandedVertexMagnetsFollowBuiltInPolygonOutlines() {
    let cases: [(ShapeKind, [SionPoint])] = [
      (
        .triangle,
        [
          SionPoint(x: 0.5, y: 0),
          SionPoint(x: 1, y: 1),
          SionPoint(x: 0, y: 1),
        ]
      ),
      (
        .diamond,
        [
          SionPoint(x: 0.5, y: 0),
          SionPoint(x: 1, y: 0.5),
          SionPoint(x: 0.5, y: 1),
          SionPoint(x: 0, y: 0.5),
        ]
      ),
      (
        .hexagon,
        [
          SionPoint(x: 0.2, y: 0),
          SionPoint(x: 0.8, y: 0),
          SionPoint(x: 1, y: 0.5),
          SionPoint(x: 0.8, y: 1),
          SionPoint(x: 0.2, y: 1),
          SionPoint(x: 0, y: 0.5),
        ]
      ),
    ]

    for (kind, expectedOutline) in cases {
      var element = SceneElement.shape(
        frame: SionRect(x: 0, y: 0, width: 200, height: 100),
        kind: kind
      )
      element.magnetConfiguration = .preset(.vertices)

      XCTAssertEqual(
        element.expandedMagnets.map(\.normalizedPosition),
        expectedOutline
      )
    }
  }

  func testExpandedPerSegmentMagnetsFollowDiamondEdges() {
    var element = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 200, height: 100),
      kind: .diamond
    )
    element.magnetConfiguration = .preset(.perSegment(1))

    XCTAssertEqual(
      element.expandedMagnets.map(\.id.rawValue),
      [
        "segment-0-1",
        "segment-1-1",
        "segment-2-1",
        "segment-3-1",
      ])
    XCTAssertEqual(
      element.expandedMagnets.map(\.normalizedPosition),
      [
        SionPoint(x: 0.75, y: 0.25),
        SionPoint(x: 0.75, y: 0.75),
        SionPoint(x: 0.25, y: 0.75),
        SionPoint(x: 0.25, y: 0.25),
      ])
  }

  func testExpandedDirectionalMagnetsFollowElementOutlines() {
    var triangle = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 200, height: 100),
      kind: .triangle
    )
    triangle.magnetConfiguration = .preset(.cardinalFour)

    var diamond = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 200, height: 100),
      kind: .diamond
    )
    diamond.magnetConfiguration = .preset(.diagonalFour)

    var hexagon = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 200, height: 100),
      kind: .hexagon
    )
    hexagon.magnetConfiguration = .preset(.eight)

    assertPositions(
      triangle.expandedMagnets.map(\.normalizedPosition),
      equal: [
        SionPoint(x: 0.5, y: 0),
        SionPoint(x: 0.75, y: 0.5),
        SionPoint(x: 0.5, y: 1),
        SionPoint(x: 0.25, y: 0.5),
      ])
    assertPositions(
      diamond.expandedMagnets.map(\.normalizedPosition),
      equal: [
        SionPoint(x: 0.25, y: 0.25),
        SionPoint(x: 0.75, y: 0.25),
        SionPoint(x: 0.75, y: 0.75),
        SionPoint(x: 0.25, y: 0.75),
      ])
    assertPositions(
      hexagon.expandedMagnets.map(\.normalizedPosition),
      equal: [
        SionPoint(x: 1.0 / 7.0, y: 1.0 / 7.0),
        SionPoint(x: 0.5, y: 0),
        SionPoint(x: 6.0 / 7.0, y: 1.0 / 7.0),
        SionPoint(x: 1, y: 0.5),
        SionPoint(x: 6.0 / 7.0, y: 6.0 / 7.0),
        SionPoint(x: 0.5, y: 1),
        SionPoint(x: 1.0 / 7.0, y: 6.0 / 7.0),
        SionPoint(x: 0, y: 0.5),
      ])
  }

  func testExpandedCardinalMagnetsFollowVectorPathOutline() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: SionPoint(x: 20, y: 10)),
        .line(to: SionPoint(x: 180, y: 10)),
        .line(to: SionPoint(x: 100, y: 90)),
        .close,
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 200, height: 100),
      path: path
    )
    element.magnetConfiguration = .preset(.cardinalFour)

    assertPositions(
      element.expandedMagnets.map(\.normalizedPosition),
      equal: [
        SionPoint(x: 0.5, y: 0.1),
        SionPoint(x: 0.7, y: 0.5),
        SionPoint(x: 0.5, y: 0.9),
        SionPoint(x: 0.3, y: 0.5),
      ])
  }

  func testResolvedMagnetsApplyElementRotation() throws {
    var element = SceneElement.shape(
      frame: SionRect(x: 100, y: 200, width: 200, height: 100)
    )
    element.geometry.rotationRadians = .pi / 2
    element.magnetConfiguration = .preset(.northSouth)

    let magnets = element.resolvedMagnets
    let north = try XCTUnwrap(magnets.first)
    let south = try XCTUnwrap(magnets.last)

    assertPositions(
      magnets.map(\.endpoint.point),
      equal: [
        SionPoint(x: 250, y: 250),
        SionPoint(x: 150, y: 250),
      ]
    )
    XCTAssertEqual(north.magnet.id, MagnetID("north"))
    XCTAssertEqual(north.endpoint.outwardDirection.dx, 1, accuracy: magnetPositionAccuracy)
    XCTAssertEqual(north.endpoint.outwardDirection.dy, 0, accuracy: magnetPositionAccuracy)
    XCTAssertEqual(south.magnet.id, MagnetID("south"))
    XCTAssertEqual(south.endpoint.outwardDirection.dx, -1, accuracy: magnetPositionAccuracy)
    XCTAssertEqual(south.endpoint.outwardDirection.dy, 0, accuracy: magnetPositionAccuracy)
  }

  func testExpandedMagnetsNormalizeVectorPathOutline() {
    let localPath = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: SionPoint(x: 20, y: 10)),
        .line(to: SionPoint(x: 180, y: 10)),
        .line(to: SionPoint(x: 100, y: 90)),
        .close,
      ]
    )
    let expected = [
      SionPoint(x: 0.1, y: 0.1),
      SionPoint(x: 0.9, y: 0.1),
      SionPoint(x: 0.5, y: 0.9),
    ]
    let pathElement = SceneElement.path(
      frame: SionRect(x: 300, y: 400, width: 200, height: 100),
      path: localPath
    )
    var customShape = SceneElement.shape(
      frame: SionRect(x: 300, y: 400, width: 200, height: 100),
      kind: .custom(localPath)
    )
    customShape.magnetConfiguration = .preset(.vertices)

    XCTAssertEqual(pathElement.expandedMagnets.map(\.normalizedPosition), expected)
    XCTAssertEqual(customShape.expandedMagnets.map(\.normalizedPosition), expected)
  }

  func testValidationRejectsDuplicateIDs() {
    let id = elementID("00000000-0000-0000-0000-000000000002")
    let first = SceneElement.shape(
      id: id,
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    let second = SceneElement.text(
      id: id,
      frame: SionRect(x: 120, y: 0, width: 100, height: 30),
      text: "Duplicate"
    )

    XCTAssertThrowsError(try SionScene(elements: [first, second]).validate()) { error in
      XCTAssertEqual(error as? SceneValidationError, .duplicateElementID(id))
    }
  }

  func testValidationRejectsParentCycles() {
    let firstID = elementID("00000000-0000-0000-0000-000000000003")
    let secondID = elementID("00000000-0000-0000-0000-000000000004")
    let first = SceneElement.group(
      id: firstID,
      frame: SionRect(x: 0, y: 0, width: 400, height: 300),
      parentID: secondID
    )
    let second = SceneElement.group(
      id: secondID,
      frame: SionRect(x: 20, y: 20, width: 200, height: 100),
      parentID: firstID
    )

    XCTAssertThrowsError(try SionScene(elements: [first, second]).validate()) { error in
      guard let validationError = error as? SceneValidationError,
        case .parentCycle = validationError
      else {
        return XCTFail("Expected a parent cycle, received \(error)")
      }
    }
  }

  func testValidationRejectsMissingConnectorTarget() {
    let missingID = elementID("00000000-0000-0000-0000-000000000005")
    let connectorID = elementID("00000000-0000-0000-0000-000000000006")
    let connector = SceneElement.connector(
      id: connectorID,
      source: .free(SionPoint(x: 10, y: 10)),
      target: .element(
        missingID,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 200, y: 10)
      )
    )

    XCTAssertThrowsError(try SionScene(elements: [connector]).validate()) { error in
      XCTAssertEqual(
        error as? SceneValidationError,
        .missingConnectedElement(connector: connectorID, target: missingID)
      )
    }
  }

  func testDescendantsUseLogicalGroupingWithoutChangingCanvasCoordinates() {
    let groupID = elementID("00000000-0000-0000-0000-000000000007")
    let childID = elementID("00000000-0000-0000-0000-000000000008")
    let grandchildID = elementID("00000000-0000-0000-0000-000000000009")
    let group = SceneElement.group(
      id: groupID,
      frame: SionRect(x: 100, y: 100, width: 400, height: 300)
    )
    let child = SceneElement.group(
      id: childID,
      frame: SionRect(x: 140, y: 150, width: 200, height: 100),
      parentID: groupID
    )
    let grandchild = SceneElement.text(
      id: grandchildID,
      frame: SionRect(x: 160, y: 170, width: 120, height: 30),
      text: "Absolute",
      parentID: childID
    )
    let scene = SionScene(elements: [group, child, grandchild])

    XCTAssertEqual(scene.descendantIDs(of: groupID), Set([childID, grandchildID]))
    XCTAssertEqual(scene.element(withID: grandchildID)?.geometry.frame.origin.x, 160)
  }

  private func documentID(_ string: String) -> DocumentID {
    DocumentID(string)!
  }

  private func elementID(_ string: String) -> ElementID {
    ElementID(string)!
  }

  private func assertPositions(
    _ actual: [SionPoint],
    equal expected: [SionPoint],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)

    for (actualPoint, expectedPoint) in zip(actual, expected) {
      XCTAssertEqual(
        actualPoint.x,
        expectedPoint.x,
        accuracy: magnetPositionAccuracy,
        file: file,
        line: line
      )
      XCTAssertEqual(
        actualPoint.y,
        expectedPoint.y,
        accuracy: magnetPositionAccuracy,
        file: file,
        line: line
      )
    }
  }
}
