import XCTest

@testable import SionCore

final class GeometryPrimitivesTests: XCTestCase {
  func testRectUsesTopLeftYDownCoordinates() {
    let rect = SionRect(x: 20, y: 30, width: 100, height: 60)

    XCTAssertEqual(rect.minX, 20)
    XCTAssertEqual(rect.minY, 30)
    XCTAssertEqual(rect.maxX, 120)
    XCTAssertEqual(rect.maxY, 90)
    XCTAssertEqual(rect.center, SionPoint(x: 70, y: 60))
  }

  func testStandardizedRectHandlesNegativeDimensions() {
    let rect = SionRect(x: 20, y: 30, width: -10, height: -20).standardized

    XCTAssertEqual(rect, SionRect(x: 10, y: 10, width: 10, height: 20))
  }

  func testRectExpansionAndIntersection() {
    let rect = SionRect(x: 10, y: 10, width: 20, height: 20)

    XCTAssertEqual(rect.expanded(by: 5), SionRect(x: 5, y: 5, width: 30, height: 30))
    XCTAssertTrue(rect.intersects(SionRect(x: 30, y: 15, width: 5, height: 5)))
    XCTAssertFalse(rect.intersects(SionRect(x: 31, y: 15, width: 5, height: 5)))
  }

  func testVectorNormalizationIsFiniteForZeroLength() {
    XCTAssertEqual(SionVector.zero.normalized, .zero)
    XCTAssertEqual(SionVector(dx: 3, dy: 4).normalized, SionVector(dx: 0.6, dy: 0.8))
  }
}
