import Foundation
import XCTest

@testable import SionCore

final class SceneArrangementTests: XCTestCase {
  func testAlignLeadingMovesAllToMinimumX() {
    let frames = [
      SionRect(x: 10, y: 0, width: 50, height: 20),
      SionRect(x: 100, y: 40, width: 30, height: 20),
    ]

    let offsets = SceneArrangement.alignedOffsets(frames, edge: .leading)

    XCTAssertEqual(offsets[0], .zero)
    XCTAssertEqual(offsets[1], SionVector(dx: -90, dy: 0))
  }

  func testAlignTrailingMovesAllToMaximumX() {
    let frames = [
      SionRect(x: 10, y: 0, width: 50, height: 20),
      SionRect(x: 100, y: 40, width: 30, height: 20),
    ]

    let offsets = SceneArrangement.alignedOffsets(frames, edge: .trailing)

    XCTAssertEqual(offsets[0], SionVector(dx: 70, dy: 0))
    XCTAssertEqual(offsets[1], .zero)
  }

  func testAlignCenterYAlignsBothCentersToTheUnionCenter() {
    let frames = [
      SionRect(x: 0, y: 0, width: 10, height: 20),
      SionRect(x: 0, y: 100, width: 10, height: 40),
    ]

    let offsets = SceneArrangement.alignedOffsets(frames, edge: .centerY)
    let centers = zip(frames, offsets).map { frame, offset in
      (frame.origin + offset).y + frame.height / 2
    }

    // The union spans y 0...140, so both centers land on 70.
    XCTAssertEqual(centers[0], 70, accuracy: 0.000_001)
    XCTAssertEqual(centers[1], 70, accuracy: 0.000_001)
  }

  func testAlignWithASingleFrameIsANoOp() {
    let offsets = SceneArrangement.alignedOffsets(
      [SionRect(x: 5, y: 5, width: 10, height: 10)],
      edge: .leading
    )

    XCTAssertEqual(offsets, [.zero])
  }

  func testDistributeEqualizesGaps() {
    // Widths 10, 20, 30 between x=0 and x=130: gaps become (130 - 60) / 2.
    let frames = [
      SionRect(x: 0, y: 0, width: 10, height: 10),
      SionRect(x: 30, y: 0, width: 20, height: 10),
      SionRect(x: 100, y: 0, width: 30, height: 10),
    ]

    let offsets = SceneArrangement.distributedOffsets(frames, axis: .horizontal)
    let moved = zip(frames, offsets).map { $0.translated(by: $1) }.sorted {
      $0.minX < $1.minX
    }

    XCTAssertEqual(moved[0].minX, 0, accuracy: 0.000_001)
    XCTAssertEqual(moved[2].minX, 100, accuracy: 0.000_001)
    let firstGap = moved[1].minX - moved[0].maxX
    let secondGap = moved[2].minX - moved[1].maxX
    XCTAssertEqual(firstGap, secondGap, accuracy: 0.000_001)
    XCTAssertEqual(firstGap, 35, accuracy: 0.000_001)
  }

  func testDistributeKeepsMembershipButReordersAlongAxis() {
    // Out-of-order input still distributes in sorted order.
    let frames = [
      SionRect(x: 100, y: 0, width: 10, height: 10),
      SionRect(x: 0, y: 0, width: 10, height: 10),
      SionRect(x: 40, y: 0, width: 10, height: 10),
    ]

    let offsets = SceneArrangement.distributedOffsets(frames, axis: .horizontal)

    XCTAssertEqual(offsets[0], .zero)
    XCTAssertEqual(offsets[1], .zero)
    XCTAssertEqual(offsets[2], SionVector(dx: 10, dy: 0))
  }

  func testDistributeVerticalUsesY() {
    let frames = [
      SionRect(x: 0, y: 0, width: 10, height: 10),
      SionRect(x: 0, y: 20, width: 10, height: 10),
      SionRect(x: 0, y: 60, width: 10, height: 10),
    ]

    let offsets = SceneArrangement.distributedOffsets(frames, axis: .vertical)
    let moved = zip(frames, offsets).map { $0.translated(by: $1) }.sorted {
      $0.minY < $1.minY
    }

    XCTAssertEqual(moved[0].minY, 0, accuracy: 0.000_001)
    XCTAssertEqual(moved[1].minY, 30, accuracy: 0.000_001)
    XCTAssertEqual(moved[2].minY, 60, accuracy: 0.000_001)
    XCTAssertEqual(moved[1].minY - moved[0].maxY, 20, accuracy: 0.000_001)
  }

  func testDistributeWithFewerThanThreeIsANoOp() {
    let frames = [
      SionRect(x: 0, y: 0, width: 10, height: 10),
      SionRect(x: 50, y: 0, width: 10, height: 10),
    ]

    XCTAssertEqual(
      SceneArrangement.distributedOffsets(frames, axis: .horizontal),
      [.zero, .zero]
    )
  }
}
