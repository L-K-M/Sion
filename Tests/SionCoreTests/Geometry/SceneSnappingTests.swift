import XCTest

@testable import SionCore

final class SceneSnappingTests: XCTestCase {
  private let neighbour = SionRect(x: 100, y: 100, width: 200, height: 100)

  func testNothingSnapsWithoutNeighboursOrTolerance() {
    let moving = SionRect(x: 104, y: 104, width: 50, height: 50)

    XCTAssertEqual(SceneSnapping.snap(moving, to: [], tolerance: 8), .none)
    XCTAssertEqual(SceneSnapping.snap(moving, to: [neighbour], tolerance: 0), .none)
    XCTAssertEqual(SceneSnapping.snap(moving, to: [neighbour], tolerance: .nan), .none)
  }

  func testLeadingEdgesLineUpWithinTolerance() {
    let moving = SionRect(x: 104, y: 400, width: 50, height: 50)

    let snap = SceneSnapping.snap(moving, to: [neighbour], tolerance: 8)

    XCTAssertEqual(snap.offset, SionVector(dx: -4, dy: 0))
    XCTAssertEqual(snap.guides.count, 1)
    XCTAssertEqual(snap.guides.first?.axis, .vertical)
    XCTAssertEqual(snap.guides.first?.position, 100)
  }

  func testEdgesFurtherThanToleranceAreLeftAlone() {
    let moving = SionRect(x: 120, y: 400, width: 50, height: 50)

    XCTAssertEqual(SceneSnapping.snap(moving, to: [neighbour], tolerance: 8), .none)
  }

  func testCentersAndTrailingEdgesSnapToo() {
    let centered = SionRect(x: 173, y: 400, width: 50, height: 50)
    let trailing = SionRect(x: 253, y: 400, width: 50, height: 50)

    // The neighbour's center x is 200; the moving center is 198.
    XCTAssertEqual(
      SceneSnapping.snap(centered, to: [neighbour], tolerance: 8).offset,
      SionVector(dx: 2, dy: 0)
    )
    // The neighbour's trailing edge is 300; the moving trailing edge is 303.
    XCTAssertEqual(
      SceneSnapping.snap(trailing, to: [neighbour], tolerance: 8).offset,
      SionVector(dx: -3, dy: 0)
    )
  }

  func testEachAxisSnapsToItsOwnNearestNeighbour() {
    let other = SionRect(x: 600, y: 300, width: 80, height: 80)
    let moving = SionRect(x: 97, y: 303, width: 50, height: 50)

    let snap = SceneSnapping.snap(moving, to: [neighbour, other], tolerance: 8)

    XCTAssertEqual(snap.offset, SionVector(dx: 3, dy: -3))
    XCTAssertEqual(
      snap.guides.map(\.axis),
      [SceneSnapGuide.Axis.vertical, SceneSnapGuide.Axis.horizontal]
    )
  }

  func testTheNearestCandidateWins() {
    let far = SionRect(x: 106, y: 700, width: 10, height: 10)
    let moving = SionRect(x: 103, y: 400, width: 50, height: 50)

    // Leading 100 is 3 away and leading 106 is 3 away, but 106's trailing edge
    // at 116 and center at 111 are further, so the tie goes to the first.
    let snap = SceneSnapping.snap(moving, to: [neighbour, far], tolerance: 8)

    XCTAssertEqual(snap.offset, SionVector(dx: -3, dy: 0))
    XCTAssertEqual(snap.guides.first?.position, 100)
  }

  func testAGuideSpansBothFrames() {
    let moving = SionRect(x: 104, y: 400, width: 50, height: 50)

    let guide = SceneSnapping.snap(moving, to: [neighbour], tolerance: 8).guides.first

    // The neighbour covers y 100...200 and the snapped frame covers 400...450.
    XCTAssertEqual(guide?.start, 100)
    XCTAssertEqual(guide?.end, 450)
  }

  func testANonFiniteFrameNeverSnaps() {
    let moving = SionRect(x: .nan, y: 400, width: 50, height: 50)

    XCTAssertEqual(SceneSnapping.snap(moving, to: [neighbour], tolerance: 8), .none)
  }
}
