import Foundation
import XCTest

@testable import SionCore

final class MagnetResolverTests: XCTestCase {
  private let bounds = SionRect(x: 100, y: 200, width: 200, height: 100)
  private let positionAccuracy = 1e-12

  func testCardinalPresetHasStableClockwiseIDs() {
    let magnets = MagnetResolver.magnets(for: .preset(.cardinalFour))

    XCTAssertEqual(magnets.map(\.id.rawValue), ["north", "east", "south", "west"])
    XCTAssertEqual(
      magnets.map(\.normalizedPosition),
      [
        SionPoint(x: 0.5, y: 0),
        SionPoint(x: 1, y: 0.5),
        SionPoint(x: 0.5, y: 1),
        SionPoint(x: 0, y: 0.5),
      ])
  }

  func testEightPresetIsStableAndUnique() {
    let magnets = MagnetResolver.magnets(for: .preset(.eight))

    XCTAssertEqual(magnets.count, 8)
    XCTAssertEqual(Set(magnets.map(\.id)).count, magnets.count)
    XCTAssertEqual(
      magnets.map(\.id.rawValue),
      [
        "north-west", "north", "north-east", "east",
        "south-east", "south", "south-west", "west",
      ])
    XCTAssertEqual(
      magnets.map(\.normalizedPosition),
      [
        SionPoint(x: 0, y: 0),
        SionPoint(x: 0.5, y: 0),
        SionPoint(x: 1, y: 0),
        SionPoint(x: 1, y: 0.5),
        SionPoint(x: 1, y: 1),
        SionPoint(x: 0.5, y: 1),
        SionPoint(x: 0, y: 1),
        SionPoint(x: 0, y: 0.5),
      ])
  }

  func testDirectionalPresetsIntersectNormalizedOutline() {
    let triangle = [
      SionPoint(x: 0.5, y: 0),
      SionPoint(x: 1, y: 1),
      SionPoint(x: 0, y: 1),
    ]
    let cardinal = MagnetResolver.magnets(
      for: .preset(.cardinalFour),
      normalizedOutline: triangle
    )
    let diagonal = MagnetResolver.magnets(
      for: .preset(.diagonalFour),
      normalizedOutline: triangle
    )

    assertPositions(
      cardinal,
      equal: [
        SionPoint(x: 0.5, y: 0),
        SionPoint(x: 0.75, y: 0.5),
        SionPoint(x: 0.5, y: 1),
        SionPoint(x: 0.25, y: 0.5),
      ])
    assertPositions(
      diagonal,
      equal: [
        SionPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
        SionPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
        SionPoint(x: 1, y: 1),
        SionPoint(x: 0, y: 1),
      ])
  }

  func testNonePresetProducesNoAdaptiveMagnets() {
    let triangle = [
      SionPoint(x: 0.5, y: 0),
      SionPoint(x: 1, y: 1),
      SionPoint(x: 0, y: 1),
    ]

    XCTAssertTrue(
      MagnetResolver.magnets(
        for: .preset(.none),
        normalizedOutline: triangle
      ).isEmpty)
  }

  func testPerSegmentPresetUsesNormalizedPolygon() {
    let triangle = [
      SionPoint(x: 0.5, y: 0),
      SionPoint(x: 1, y: 1),
      SionPoint(x: 0, y: 1),
    ]

    let magnets = MagnetResolver.magnets(
      for: .preset(.perSegment(2)),
      normalizedOutline: triangle
    )

    XCTAssertEqual(magnets.count, 6)
    XCTAssertEqual(
      magnets.map(\.id.rawValue),
      [
        "segment-0-1", "segment-0-2",
        "segment-1-1", "segment-1-2",
        "segment-2-1", "segment-2-2",
      ])
    XCTAssertEqual(magnets[0].normalizedPosition, SionPoint(x: 2.0 / 3.0, y: 1.0 / 3.0))
  }

  func testResolutionMapsNormalizedPointIntoBounds() {
    let endpoint = MagnetResolver.resolve(
      Magnet(
        id: "south-east",
        normalizedPosition: SionPoint(x: 1, y: 1),
        outwardDirection: SionVector(dx: 1, dy: 1)
      ),
      in: bounds
    )

    XCTAssertEqual(endpoint.point, SionPoint(x: 300, y: 300))
    XCTAssertEqual(endpoint.outwardDirection.length, 1, accuracy: 0.000_001)
  }

  func testNearestMagnetBreaksDistanceTiesByDeclarationOrder() {
    let configuration = MagnetConfiguration.custom([
      Magnet(
        id: "first",
        normalizedPosition: SionPoint(x: 0, y: 0.5),
        outwardDirection: .west
      ),
      Magnet(
        id: "second",
        normalizedPosition: SionPoint(x: 1, y: 0.5),
        outwardDirection: .east
      ),
    ])

    let resolved = MagnetResolver.resolveNearest(
      in: configuration,
      bounds: bounds,
      to: bounds.center
    )

    XCTAssertEqual(resolved?.magnet.id, MagnetID("first"))
  }

  func testMissingMagnetDoesNotInventAnEndpoint() {
    let endpoint = MagnetResolver.resolve(
      MagnetID("missing"),
      in: .preset(.northSouth),
      bounds: bounds
    )

    XCTAssertNil(endpoint)
  }

  func testDirectionFiltersIncomingAndOutgoingConnections() {
    let configuration = MagnetConfiguration.custom([
      Magnet(
        id: "input",
        normalizedPosition: SionPoint(x: 0, y: 0.5),
        outwardDirection: .west,
        connectionDirection: .incoming
      )
    ])

    XCTAssertNotNil(
      MagnetResolver.resolve(
        "input",
        in: configuration,
        bounds: bounds,
        use: .incoming
      ))
    XCTAssertNil(
      MagnetResolver.resolve(
        "input",
        in: configuration,
        bounds: bounds,
        use: .outgoing
      ))
  }

  func testAssociatedValuesUseStableDiscriminatedJSON() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let presetData = try encoder.encode(MagnetPreset.perSegment(3))
    let presetJSON = try XCTUnwrap(String(data: presetData, encoding: .utf8))

    XCTAssertEqual(presetJSON, #"{"count":3,"type":"perSegment"}"#)
    XCTAssertFalse(presetJSON.contains("_0"))

    let magnet = Magnet(
      id: "input",
      normalizedPosition: SionPoint(x: 0, y: 0.5),
      outwardDirection: .west,
      connectionDirection: .incoming
    )
    let magnetData = try encoder.encode(magnet)
    let magnetObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: magnetData) as? [String: Any]
    )

    XCTAssertNotNil(magnetObject["position"])
    XCTAssertNotNil(magnetObject["normal"])
    XCTAssertEqual(magnetObject["direction"] as? String, "incoming")
    XCTAssertNil(magnetObject["normalizedPosition"])
  }

  private func assertPositions(
    _ magnets: [Magnet],
    equal expected: [SionPoint],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(magnets.count, expected.count, file: file, line: line)

    for (magnet, point) in zip(magnets, expected) {
      XCTAssertEqual(
        magnet.normalizedPosition.x,
        point.x,
        accuracy: positionAccuracy,
        file: file,
        line: line
      )
      XCTAssertEqual(
        magnet.normalizedPosition.y,
        point.y,
        accuracy: positionAccuracy,
        file: file,
        line: line
      )
    }
  }
}
