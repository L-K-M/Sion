import XCTest

@testable import SionCore

final class CanvasGridRenderGeometryTests: XCTestCase {
  func testPlansConfiguredSubdivisionsAtReadableZoom() throws {
    let grid = CanvasGrid(visibility: .visible, spacing: 16, subdivisions: 4)

    let plan = try XCTUnwrap(
      CanvasGridRenderGeometry.plan(for: grid, magnification: 1)
    )

    XCTAssertEqual(plan.lineSpacing, 4)
    XCTAssertEqual(plan.linesPerMajor, 4)
  }

  func testCoarsensOnlyAlongTheConfiguredLattice() throws {
    let grid = CanvasGrid(visibility: .visible, spacing: 16, subdivisions: 4)

    let halfScale = try XCTUnwrap(
      CanvasGridRenderGeometry.plan(for: grid, magnification: 0.5)
    )
    let distantScale = try XCTUnwrap(
      CanvasGridRenderGeometry.plan(for: grid, magnification: 0.1)
    )

    XCTAssertEqual(halfScale.lineSpacing, 8)
    XCTAssertEqual(halfScale.linesPerMajor, 2)
    XCTAssertEqual(distantScale.lineSpacing, 64)
    XCTAssertEqual(distantScale.linesPerMajor, 2)
  }

  func testSmallSpacingIsNotReplacedWithAnUnrelatedValue() throws {
    let grid = CanvasGrid(visibility: .visible, spacing: 3, subdivisions: 1)

    let plan = try XCTUnwrap(
      CanvasGridRenderGeometry.plan(for: grid, magnification: 1)
    )

    XCTAssertEqual(plan.lineSpacing, 6)
    XCTAssertEqual(plan.linesPerMajor, 2)
  }

  func testDensePlansStayBoundedAcrossZoom() throws {
    let grid = CanvasGrid(visibility: .visible, spacing: 16, subdivisions: 4)

    for magnification in [0.1, 0.25, 0.5, 1, 2, 4, 8] {
      let plan = try XCTUnwrap(
        CanvasGridRenderGeometry.plan(for: grid, magnification: magnification)
      )
      let screenLineSpacing = plan.lineSpacing * magnification
      let screenMajorSpacing = screenLineSpacing * Double(plan.linesPerMajor)

      XCTAssertGreaterThanOrEqual(screenLineSpacing, 4)
      XCTAssertGreaterThanOrEqual(screenMajorSpacing, 8)
      XCTAssertEqual(
        plan.lineSpacing.truncatingRemainder(
          dividingBy: grid.spacing / Double(grid.subdivisions)
        ),
        0,
        accuracy: 0.000_001
      )
    }
  }

  func testPreservesFineGridAtHighZoom() throws {
    let grid = CanvasGrid(visibility: .visible, spacing: 1, subdivisions: 1)

    let plan = try XCTUnwrap(
      CanvasGridRenderGeometry.plan(for: grid, magnification: 8)
    )

    XCTAssertEqual(plan.lineSpacing, 1)
    XCTAssertEqual(plan.linesPerMajor, 1)
  }

  func testRejectsHiddenAndUnsafeInputs() {
    XCTAssertNil(
      CanvasGridRenderGeometry.plan(
        for: CanvasGrid(visibility: .hidden),
        magnification: 1
      )
    )
    XCTAssertNil(
      CanvasGridRenderGeometry.plan(
        for: CanvasGrid(visibility: .visible, spacing: 0),
        magnification: 1
      )
    )
    XCTAssertNil(
      CanvasGridRenderGeometry.plan(
        for: CanvasGrid(
          visibility: .visible,
          spacing: .leastNonzeroMagnitude
        ),
        magnification: 1
      )
    )
    XCTAssertNil(
      CanvasGridRenderGeometry.plan(
        for: CanvasGrid(visibility: .visible),
        magnification: .infinity
      )
    )
  }
}
