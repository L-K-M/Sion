import XCTest

@testable import SionCore

final class ElementHitGeometryTests: XCTestCase {
  // Generous ceiling that still catches quadratic blowups without flaking on
  // loaded CI runners or Debug builds.
  private static let interactiveHitDeadline = Duration.seconds(10)
  private static let largeSceneElementCount = 25_000
  private static let maximumCurvedPathQueryCount = 10
  private static let maximumPathQueryCount = 1_000

  func testTransparentFrameCornersMissNonrectangularShapes() {
    let frame = SionRect(x: 120, y: 80, width: 160, height: 100)
    let customPath = VectorPath(commands: [
      .move(to: SionPoint(x: 0.5, y: 0.1)),
      .line(to: SionPoint(x: 0.9, y: 0.9)),
      .line(to: SionPoint(x: 0.1, y: 0.9)),
      .close,
    ])
    let kinds: [ShapeKind] = [.ellipse, .diamond, .triangle, .custom(customPath)]

    for kind in kinds {
      var element = SceneElement.shape(frame: frame, kind: kind)
      element.style = ElementStyle(fill: .solid(.black))

      XCTAssertFalse(
        ElementHitGeometry.contains(frame.origin, in: element, tolerance: 2),
        "Unexpected corner hit for \(kind)"
      )
      XCTAssertTrue(
        ElementHitGeometry.contains(frame.center, in: element, tolerance: 2),
        "Missing fill hit for \(kind)"
      )
    }
  }

  func testStrokeOnlyEllipseHitsOutlineButNotInterior() {
    let frame = SionRect(x: 40, y: 70, width: 120, height: 80)
    var ellipse = SceneElement.shape(frame: frame, kind: .ellipse)
    ellipse.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 4)
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(
        SionPoint(x: frame.maxX + 1, y: frame.center.y),
        in: ellipse,
        tolerance: 2
      )
    )
    XCTAssertFalse(ElementHitGeometry.contains(frame.center, in: ellipse, tolerance: 2))
  }

  func testStrokeOnlyCylinderHitsFrontRimAtEveryAspectRatio() {
    let sizes = [
      SionSize(width: 200, height: 80),
      SionSize(width: 100, height: 100),
      SionSize(width: 60, height: 180),
    ]

    for size in sizes {
      for rotation in [0.0, Double.pi / 3] {
        let frame = SionRect(origin: SionPoint(x: 40, y: 30), size: size)
        var cylinder = SceneElement.shape(frame: frame, kind: .cylinder)
        cylinder.geometry.rotationRadians = rotation
        cylinder.style = ElementStyle(
          fill: .none,
          stroke: StrokeStyle(color: .black, width: 4)
        )
        let arcHeight = frame.height * ShapeGeometryDefaults.cylinderArcFraction
        let localRimPoint = SionPoint(
          x: frame.center.x,
          y: frame.minY + (2 * arcHeight)
        )
        let rimPoint = InteractionGeometry.rotated(
          localRimPoint,
          around: frame.center,
          by: rotation
        )

        XCTAssertTrue(
          ElementHitGeometry.contains(rimPoint, in: cylinder),
          "Missing front rim hit for \(size), rotation \(rotation)"
        )
      }
    }
  }

  func testFillOnlyShapeUsesHitToleranceAtEdge() {
    let frame = SionRect(x: 40, y: 70, width: 120, height: 80)
    var ellipse = SceneElement.shape(frame: frame, kind: .ellipse)
    ellipse.style = ElementStyle(fill: .solid(.black))

    XCTAssertTrue(
      ElementHitGeometry.contains(
        SionPoint(x: frame.maxX + 1, y: frame.center.y),
        in: ellipse,
        tolerance: 2
      )
    )
  }

  func testFilledCurveIncludesFlatteningMargin() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .quadratic(
          control: SionPoint(x: 50, y: -0.24),
          to: SionPoint(x: 100, y: 0)
        ),
        .line(to: SionPoint(x: 100, y: 100)),
        .line(to: SionPoint(x: 0, y: 100)),
        .close,
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(fill: .solid(.black))

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 50, y: -0.05), in: element)
    )
  }

  func testImplicitlyClosedShallowCurveHitsFill() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .quadratic(
          control: SionPoint(x: 50, y: -0.24),
          to: SionPoint(x: 100, y: 0)
        ),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(fill: .solid(.black))

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 50, y: -0.05), in: element)
    )
  }

  func testImplicitlyClosedSubepsilonCurveHitsFill() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .quadratic(
          control: SionPoint(x: 0.5, y: 1e-10),
          to: SionPoint(x: 1, y: 0)
        ),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(fill: .solid(.black))

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 0.5, y: 2e-11), in: element)
    )
  }

  func testThinCurvedStrokeIncludesFlatteningMargin() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .quadratic(
          control: SionPoint(x: 50, y: -0.24),
          to: SionPoint(x: 100, y: 0)
        ),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 0.1, lineCap: .butt)
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 50, y: -0.12), in: element)
    )
  }

  func testLabelOnlyShapeHitsLabelAreaButNotFrameCorner() {
    let frame = SionRect(x: 40, y: 70, width: 120, height: 80)
    var ellipse = SceneElement.shape(frame: frame, kind: .ellipse, text: "Label")
    ellipse.style = ElementStyle(fill: .none)

    XCTAssertTrue(ElementHitGeometry.contains(frame.center, in: ellipse, tolerance: 2))
    XCTAssertFalse(ElementHitGeometry.contains(frame.origin, in: ellipse, tolerance: 2))
  }

  func testDashedStrokeHitsDashAndMissesGap() {
    let frame = SionRect(x: 100, y: 200, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0, y: 0.5)),
      .line(to: SionPoint(x: 1, y: 0.5)),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 4,
        dashPattern: [20, 20],
        lineCap: .butt
      )
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 110, y: 250), in: element, tolerance: 0)
    )
    XCTAssertFalse(
      ElementHitGeometry.contains(SionPoint(x: 130, y: 250), in: element, tolerance: 0)
    )
  }

  func testZeroLengthDashPreservesGapAndCap() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 100, y: 0)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    let capExpectations: [(StrokeLineCap, Bool)] = [
      (.butt, false),
      (.round, true),
      (.square, true),
    ]

    for (lineCap, expectsCap) in capExpectations {
      element.style = ElementStyle(
        fill: .none,
        stroke: StrokeStyle(
          color: .black,
          width: 10,
          dashPattern: [0, 20],
          lineCap: lineCap
        )
      )

      XCTAssertFalse(ElementHitGeometry.contains(SionPoint(x: 10, y: 0), in: element))
      XCTAssertEqual(
        ElementHitGeometry.contains(SionPoint(x: 20, y: 4), in: element),
        expectsCap
      )
    }
  }

  func testWholePathDashKeepsOpenEndpointCaps() {
    // An open subpath has no seam, so a dash covering the whole path still
    // paints the endpoint caps.
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 50, y: 0)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )

    let capExpectations: [(StrokeLineCap, Bool)] = [
      (.butt, false),
      (.round, true),
      (.square, true),
    ]

    for (lineCap, expectsCap) in capExpectations {
      element.style = ElementStyle(
        fill: .none,
        stroke: StrokeStyle(
          color: .black,
          width: 10,
          dashPattern: [1000],
          lineCap: lineCap
        )
      )

      // 0.9 * stroke radius beyond each endpoint follows the cap shape.
      XCTAssertEqual(
        ElementHitGeometry.contains(SionPoint(x: -4.5, y: 0), in: element),
        expectsCap
      )
      XCTAssertEqual(
        ElementHitGeometry.contains(SionPoint(x: 54.5, y: 0), in: element),
        expectsCap
      )
      // The dash body covers the whole open path.
      XCTAssertTrue(ElementHitGeometry.contains(SionPoint(x: 25, y: 0), in: element))
    }
  }

  func testZeroLengthGapDoesNotJoinDistinctDashes() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 20, y: 0)),
        .line(to: SionPoint(x: 20, y: 20)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 10,
        dashPattern: [20, 0],
        lineCap: .butt,
        lineJoin: .miter
      )
    )

    XCTAssertFalse(ElementHitGeometry.contains(SionPoint(x: 24, y: -4), in: element))

    let closedPath = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 20, y: 0)),
        .line(to: SionPoint(x: 20, y: 20)),
        .line(to: SionPoint(x: 0, y: 20)),
        .close,
      ]
    )
    var closedElement = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: closedPath
    )
    closedElement.style = element.style

    XCTAssertFalse(
      ElementHitGeometry.contains(SionPoint(x: -4, y: -4), in: closedElement)
    )
  }

  func testZeroLengthGapKeepsBothSquareCapsAtTurn() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 20, y: 0)),
        .line(to: SionPoint(x: 40, y: 20)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 10,
        dashPattern: [20, 0],
        lineCap: .square
      )
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 24.5, y: -4.5), in: element)
    )
  }

  func testTinyDashPatternCompletesWithinInteractiveDeadline() {
    let frame = SionRect(x: 100, y: 200, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0, y: 0.5)),
      .line(to: SionPoint(x: 1, y: 0.5)),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    let validSubpixelDashLength = Double.ulpOfOne
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 4,
        dashPattern: [validSubpixelDashLength, validSubpixelDashLength],
        lineCap: .butt
      )
    )

    let started = ContinuousClock.now
    let containsPoint = ElementHitGeometry.contains(
      SionPoint(x: 150, y: 250),
      in: element,
      tolerance: 2
    )
    let elapsed = started.duration(to: .now)

    XCTAssertTrue(containsPoint)
    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testAccumulatedCurveLengthErrorKeepsPaintedDashSelectable() {
    let curveCount = 1_000
    let curveWidth = 800.0
    var commands: [PathCommand] = [.move(to: .zero)]
    for index in 0..<curveCount {
      let startX = Double(index) * curveWidth
      commands.append(
        .quadratic(
          control: SionPoint(x: startX + (curveWidth / 2), y: -500),
          to: SionPoint(x: startX + curveWidth, y: 0)
        )
      )
    }
    let path = VectorPath(coordinateSpace: .localPoints, commands: commands)
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 2,
        dashPattern: [40, 40],
        lineCap: .butt,
        lineJoin: .round
      )
    )

    // Exact curve length puts this vertex 6.646 points inside a painted dash.
    let paintedVertex = SionPoint(x: Double(curveCount - 1) * curveWidth, y: 0)

    XCTAssertTrue(ElementHitGeometry.contains(paintedVertex, in: element, tolerance: 2))
  }

  func testCollapsedAccumulatedLineLengthKeepsPaintedDashSelectable() {
    let tinyLength = 0.000_000_01
    let terminalCommands: [PathCommand] = [
      .line(to: .zero),
      .line(to: SionPoint(x: -tinyLength, y: 0)),
    ]
    var commands: [PathCommand] = [
      .move(to: .zero),
      .line(to: SionPoint(x: SceneLimits.maximumCoordinateMagnitude, y: 0)),
    ]
    let availableSegmentCount =
      SceneLimits.maximumPathCommandCount - commands.count - terminalCommands.count
    // An odd count ends at x=1 and puts the terminal segment in a painted dash.
    let accumulationSegmentCount =
      availableSegmentCount.isMultiple(of: 2)
      ? availableSegmentCount - 1 : availableSegmentCount
    for index in 0..<accumulationSegmentCount {
      commands.append(
        .line(
          to: SionPoint(
            x: index.isMultiple(of: 2) ? 1 : SceneLimits.maximumCoordinateMagnitude,
            y: 0
          )
        )
      )
    }
    commands += terminalCommands
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: commands
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: tinyLength / 16,
        dashPattern: [1, 1],
        lineCap: .butt,
        lineJoin: .bevel
      )
    )
    let paintedPoint = SionPoint(x: -(tinyLength * 0.75), y: 0)
    var withoutTinySegment = element
    withoutTinySegment.content = .path(
      PathContent(
        path: VectorPath(
          coordinateSpace: .localPoints,
          commands: Array(path.commands.dropLast())
        )
      )
    )
    XCTAssertFalse(
      ElementHitGeometry.contains(paintedPoint, in: withoutTinySegment)
    )

    XCTAssertTrue(ElementHitGeometry.contains(paintedPoint, in: element))
  }

  func testCurveLengthUncertaintyKeepsDistantDashGapClear() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .quadratic(
          control: SionPoint(x: 400, y: -500),
          to: SionPoint(x: 800, y: 0)
        ),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 2,
        dashPattern: [40, 40],
        lineCap: .butt
      )
    )

    // This curve point is 20 points from either boundary of its dash gap.
    let distantGapPoint = SionPoint(x: 38.602_581_7, y: -45.924_853_2)

    XCTAssertFalse(ElementHitGeometry.contains(distantGapPoint, in: element, tolerance: 2))
  }

  func testTruncatedCurveDoesNotFillDashGapInSeparateSubpath() throws {
    let curveCount = 513
    let distantY = SceneLimits.maximumCoordinateMagnitude / 2
    var commands: [PathCommand] = [
      .move(to: .zero),
      .line(to: SionPoint(x: 100, y: 0)),
      .move(to: SionPoint(x: 0, y: distantY)),
    ]
    for index in 0..<curveCount {
      let endX =
        index.isMultiple(of: 2)
        ? SceneLimits.maximumCoordinateMagnitude : 0
      commands.append(
        .quadratic(
          control: SionPoint(
            x: SceneLimits.maximumCoordinateMagnitude / 2,
            y: SceneLimits.maximumCoordinateMagnitude
          ),
          to: SionPoint(x: endX, y: distantY)
        )
      )
    }
    let path = VectorPath(coordinateSpace: .localPoints, commands: commands)
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.magnetConfiguration = .preset(.none)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 2,
        dashPattern: [20, 20],
        lineCap: .butt
      )
    )

    XCTAssertNoThrow(try SionScene(elements: [element]).validate())
    XCTAssertFalse(
      ElementHitGeometry.contains(SionPoint(x: 25, y: 0), in: element)
    )
  }

  func testOversizedDashPatternUsesBoundedConservativeStroke() {
    let repeatedPatternCount = (SceneLimits.maximumPathCommandCount / 2) + 1
    let dashPattern = Array(
      repeating: [20.0, 20.0],
      count: repeatedPatternCount
    ).flatMap { $0 }
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 100, y: 0)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 2,
        dashPattern: dashPattern,
        lineCap: .butt
      )
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 30, y: 0), in: element)
    )
  }

  func testPathCommandSizedDashPatternUsesBoundedFallbackWithinDeadline() {
    let pairCount = SceneLimits.maximumPathCommandCount / 2
    let dashPattern = Array(repeating: [1.0, 1_000.0], count: pairCount).flatMap { $0 }
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 1_000, y: 0)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 2,
        dashPattern: dashPattern,
        lineCap: .butt
      )
    )

    // The command-sized pattern exceeds the interactive budget, so hit
    // testing falls back to the conservative whole-stroke solid: a point in
    // a nominal gap still hits, while a point off the stroke must miss.
    let gapPoint = SionPoint(x: 500, y: 0)
    XCTAssertTrue(ElementHitGeometry.contains(gapPoint, in: element))
    XCTAssertFalse(ElementHitGeometry.contains(SionPoint(x: 500, y: 50), in: element))

    let started = ContinuousClock.now
    var containsPoint = false
    for _ in 0..<Self.largeSceneElementCount {
      if ElementHitGeometry.contains(gapPoint, in: element) {
        containsPoint = true
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertTrue(containsPoint)
    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testInteractiveDashPatternBudgetCompletesWithinDeadline() {
    let dashPattern = Array(repeating: [1.0, 1_000.0], count: 16).flatMap { $0 }
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 1_000, y: 0)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 2,
        dashPattern: dashPattern,
        lineCap: .butt
      )
    )

    let gapPoint = SionPoint(x: 500, y: 0)
    let started = ContinuousClock.now
    var containsPoint = false
    for _ in 0..<Self.largeSceneElementCount {
      if ElementHitGeometry.contains(gapPoint, in: element) {
        containsPoint = true
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertFalse(containsPoint)
    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testCurvedButtDashKeepsVisibleGapClear() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .quadratic(
          control: SionPoint(x: 50, y: 0.1),
          to: SionPoint(x: 100, y: 0)
        ),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 10,
        dashPattern: [20, 5],
        lineCap: .butt
      )
    )

    let curvePointInGap = SionPoint(x: 22.5, y: 0.034_875)

    XCTAssertFalse(ElementHitGeometry.contains(curvePointInGap, in: element, tolerance: 2))
  }

  func testClosedDashSpanningPerimeterKeepsMiterAtSeam() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.2, y: 0.2)),
      .line(to: SionPoint(x: 0.8, y: 0.2)),
      .line(to: SionPoint(x: 0.8, y: 0.8)),
      .line(to: SionPoint(x: 0.2, y: 0.8)),
      .close,
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 20,
        dashPattern: [1_000, 1],
        lineCap: .butt,
        lineJoin: .miter
      )
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 13, y: 13), in: element, tolerance: 0)
    )
  }

  func testUncertainClosedDashKeepsPossibleCapAtSeam() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 100, y: 0)),
        .quadratic(
          control: SionPoint(x: 150, y: 100),
          to: SionPoint(x: 200, y: 0)
        ),
        .line(to: .zero),
        .close,
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 10,
        dashPattern: [447.87, 1_000],
        lineCap: .square,
        lineJoin: .bevel
      )
    )

    // The true curve length enters the gap, leaving a square cap at the seam.
    XCTAssertTrue(ElementHitGeometry.contains(SionPoint(x: -4, y: 0), in: element))
  }

  func testExplicitClosingLineKeepsMiterAtSeam() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.2, y: 0.2)),
      .line(to: SionPoint(x: 0.8, y: 0.2)),
      .line(to: SionPoint(x: 0.8, y: 0.8)),
      .line(to: SionPoint(x: 0.2, y: 0.8)),
      .line(to: SionPoint(x: 0.2, y: 0.2)),
      .close,
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 20,
        lineCap: .butt,
        lineJoin: .miter
      )
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 13, y: 13), in: element, tolerance: 0)
    )
  }

  func testClosedTwoPointStrokeKeepsRoundJoins() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.2, y: 0.5)),
      .line(to: SionPoint(x: 0.8, y: 0.5)),
      .close,
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 20,
        lineCap: .butt,
        lineJoin: .round
      )
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 15, y: 50), in: element, tolerance: 0)
    )
    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 85, y: 50), in: element, tolerance: 0)
    )
  }

  func testDashCapsExtendOnlyPaintedRuns() {
    let frame = SionRect(x: 100, y: 200, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.2, y: 0.5)),
      .line(to: SionPoint(x: 0.8, y: 0.5)),
    ])

    func element(lineCap: StrokeLineCap) -> SceneElement {
      var element = SceneElement.path(frame: frame, path: path)
      element.style = ElementStyle(
        fill: .none,
        stroke: StrokeStyle(
          color: .black,
          width: 10,
          dashPattern: [20, 20],
          lineCap: lineCap
        )
      )
      return element
    }

    let pointPastDash = SionPoint(x: 142, y: 250)
    XCTAssertFalse(
      ElementHitGeometry.contains(pointPastDash, in: element(lineCap: .butt))
    )
    XCTAssertTrue(
      ElementHitGeometry.contains(pointPastDash, in: element(lineCap: .round))
    )
    XCTAssertTrue(
      ElementHitGeometry.contains(pointPastDash, in: element(lineCap: .square))
    )
  }

  func testButtCapDoesNotExtendByStrokeRadius() {
    let frame = SionRect(x: 100, y: 200, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.2, y: 0.5)),
      .line(to: SionPoint(x: 0.8, y: 0.5)),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 10, lineCap: .butt)
    )

    XCTAssertFalse(
      ElementHitGeometry.contains(SionPoint(x: 119, y: 250), in: element, tolerance: 0)
    )

    var round = element
    round.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 10, lineCap: .round)
    )
    var square = element
    square.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 10, lineCap: .square)
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 119, y: 250), in: round, tolerance: 0)
    )
    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 119, y: 250), in: square, tolerance: 0)
    )
  }

  func testMoveOnlyPathMissesEveryStrokeCap() {
    let point = SionPoint(x: 20, y: 20)
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [.move(to: point)]
    )
    let dashPatterns: [[Double]] = [[], [20, 20]]

    for dashPattern in dashPatterns {
      for lineCap in StrokeLineCap.allCases {
        var element = SceneElement.path(
          frame: SionRect(x: 0, y: 0, width: 1, height: 1),
          path: path
        )
        element.style = ElementStyle(
          fill: .none,
          stroke: StrokeStyle(
            color: .black,
            width: 10,
            dashPattern: dashPattern,
            lineCap: lineCap
          )
        )

        XCTAssertFalse(
          ElementHitGeometry.contains(point, in: element),
          "Unexpected \(lineCap) cap for dash \(dashPattern)"
        )
      }
    }
  }

  func testZeroLengthLineHonorsSolidAndDashedCaps() {
    let point = SionPoint(x: 20, y: 20)
    let squareCorner = SionPoint(x: 24, y: 24)
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: point),
        .line(to: point),
      ]
    )
    let dashPatterns: [[Double]] = [[], [20, 20]]

    for dashPattern in dashPatterns {
      func element(lineCap: StrokeLineCap) -> SceneElement {
        var element = SceneElement.path(
          frame: SionRect(x: 0, y: 0, width: 1, height: 1),
          path: path
        )
        element.style = ElementStyle(
          fill: .none,
          stroke: StrokeStyle(
            color: .black,
            width: 10,
            dashPattern: dashPattern,
            lineCap: lineCap
          )
        )
        return element
      }

      XCTAssertFalse(ElementHitGeometry.contains(point, in: element(lineCap: .butt)))
      XCTAssertTrue(ElementHitGeometry.contains(point, in: element(lineCap: .round)))
      XCTAssertFalse(
        ElementHitGeometry.contains(squareCorner, in: element(lineCap: .round))
      )
      XCTAssertTrue(ElementHitGeometry.contains(point, in: element(lineCap: .square)))
      XCTAssertTrue(
        ElementHitGeometry.contains(squareCorner, in: element(lineCap: .square))
      )
    }
  }

  func testZeroLengthEndpointSegmentsPreserveSquareCaps() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: .zero),
        .line(to: SionPoint(x: 100, y: 0)),
        .line(to: SionPoint(x: 100, y: 0)),
      ]
    )
    let dashPatterns: [[Double]] = [[], [1_000, 1]]

    for dashPattern in dashPatterns {
      var element = SceneElement.path(
        frame: SionRect(x: 0, y: 0, width: 1, height: 1),
        path: path
      )
      element.style = ElementStyle(
        fill: .none,
        stroke: StrokeStyle(
          color: .black,
          width: 10,
          dashPattern: dashPattern,
          lineCap: .square
        )
      )

      XCTAssertTrue(ElementHitGeometry.contains(SionPoint(x: -4, y: 0), in: element))
      XCTAssertTrue(ElementHitGeometry.contains(SionPoint(x: 104, y: 0), in: element))
    }
  }

  func testZeroLengthInteriorSegmentPreservesMiterJoin() {
    let path = VectorPath(
      coordinateSpace: .normalized,
      commands: [
        .move(to: SionPoint(x: 0.2, y: 0.2)),
        .line(to: SionPoint(x: 0.8, y: 0.2)),
        .line(to: SionPoint(x: 0.8, y: 0.2)),
        .line(to: SionPoint(x: 0.8, y: 0.8)),
      ]
    )
    let dashPatterns: [[Double]] = [[], [1_000, 1]]

    for dashPattern in dashPatterns {
      var element = SceneElement.path(
        frame: SionRect(x: 0, y: 0, width: 100, height: 100),
        path: path
      )
      element.style = ElementStyle(
        fill: .none,
        stroke: StrokeStyle(
          color: .black,
          width: 20,
          dashPattern: dashPattern,
          lineCap: .butt,
          lineJoin: .miter
        )
      )

      XCTAssertTrue(ElementHitGeometry.contains(SionPoint(x: 87, y: 13), in: element))
    }
  }

  func testSubepsilonLineRetainsStrokeBodyAndDirection() {
    let endpoint = SionPoint(x: 1e-10, y: 1e-10)
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: endpoint),
      ]
    )
    let dashPatterns: [[Double]] = [[], [1_000, 1]]

    for dashPattern in dashPatterns {
      func element(lineCap: StrokeLineCap) -> SceneElement {
        var element = SceneElement.path(
          frame: SionRect(x: 0, y: 0, width: 1, height: 1),
          path: path
        )
        element.style = ElementStyle(
          fill: .none,
          stroke: StrokeStyle(
            color: .black,
            width: 10,
            dashPattern: dashPattern,
            lineCap: lineCap
          )
        )
        return element
      }

      XCTAssertTrue(
        ElementHitGeometry.contains(
          endpoint.interpolated(to: .zero, fraction: 0.5), in: element(lineCap: .butt))
      )
      XCTAssertTrue(
        ElementHitGeometry.contains(SionPoint(x: 6, y: 0), in: element(lineCap: .square))
      )
    }
  }

  func testClosedZeroLengthPathsHonorSolidAndDashedCaps() {
    let point = SionPoint(x: 20, y: 20)
    let paths = [
      VectorPath(
        coordinateSpace: .localPoints,
        commands: [
          .move(to: point),
          .close,
        ]
      ),
      VectorPath(
        coordinateSpace: .localPoints,
        commands: [
          .move(to: point),
          .line(to: point),
          .close,
        ]
      ),
    ]
    let dashPatterns: [[Double]] = [[], [20, 20]]

    for path in paths {
      for dashPattern in dashPatterns {
        func element(lineCap: StrokeLineCap) -> SceneElement {
          var element = SceneElement.path(
            frame: SionRect(x: 0, y: 0, width: 1, height: 1),
            path: path
          )
          element.style = ElementStyle(
            fill: .none,
            stroke: StrokeStyle(
              color: .black,
              width: 10,
              dashPattern: dashPattern,
              lineCap: lineCap
            )
          )
          return element
        }

        XCTAssertFalse(ElementHitGeometry.contains(point, in: element(lineCap: .butt)))
        XCTAssertTrue(ElementHitGeometry.contains(point, in: element(lineCap: .round)))
        XCTAssertTrue(ElementHitGeometry.contains(point, in: element(lineCap: .square)))
      }
    }
  }

  func testCurvedButtCapUsesEndpointTangent() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .cubic(
          control1: SionPoint(x: 0, y: 0.1),
          control2: SionPoint(x: 100, y: 0),
          to: SionPoint(x: 100, y: 0)
        ),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    let dashPatterns: [[Double]] = [[], [1_000, 1]]
    for dashPattern in dashPatterns {
      element.style = ElementStyle(
        fill: .none,
        stroke: StrokeStyle(
          color: .black,
          width: 20,
          dashPattern: dashPattern,
          lineCap: .butt
        )
      )

      // The curve starts upward, so its butt cap admits this forward-side point.
      XCTAssertTrue(
        ElementHitGeometry.contains(SionPoint(x: -5, y: 5), in: element, tolerance: 2)
      )
    }
  }

  func testDiagonalSquareCapSurvivesBroadPhase() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 100, y: 100)),
      ]
    )
    var element = SceneElement.path(
      frame: SionRect(x: 0, y: 0, width: 1, height: 1),
      path: path
    )
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 20, lineCap: .square)
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: -13, y: 0), in: element, tolerance: 2)
    )
  }

  func testBevelAndMiterJoinsUseDifferentCorners() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.2, y: 0.2)),
      .line(to: SionPoint(x: 0.8, y: 0.2)),
      .line(to: SionPoint(x: 0.8, y: 0.8)),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 20, lineCap: .butt, lineJoin: .bevel)
    )

    XCTAssertFalse(
      ElementHitGeometry.contains(SionPoint(x: 87, y: 13), in: element, tolerance: 0)
    )

    var miter = element
    miter.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 20, lineCap: .butt, lineJoin: .miter)
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 87, y: 13), in: miter, tolerance: 0)
    )
  }

  func testCurvedMiterUsesEndpointTangentForSolidAndDashedStrokes() {
    let vertex = SionPoint(x: 0.2, y: 0.2)
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .quadratic(control: SionPoint(x: 0, y: 0.2), to: vertex),
        .line(to: SionPoint(x: -865.825, y: 500.2)),
      ]
    )
    let dashPatterns: [[Double]] = [[], [10_000, 1]]
    for dashPattern in dashPatterns {
      var element = SceneElement.path(
        frame: SionRect(x: 0, y: 0, width: 1, height: 1),
        path: path
      )
      element.style = ElementStyle(
        fill: .none,
        stroke: StrokeStyle(
          color: .black,
          width: 200,
          dashPattern: dashPattern,
          lineCap: .butt,
          lineJoin: .miter
        )
      )

      XCTAssertTrue(
        ElementHitGeometry.contains(
          SionPoint(x: vertex.x + 300, y: vertex.y - 75),
          in: element
        )
      )
    }
  }

  func testSubepsilonTurnPreservesBevelGeometry() {
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: .zero),
        .line(to: SionPoint(x: 1, y: 0)),
        .line(to: SionPoint(x: 0, y: 5e-10)),
      ]
    )
    let dashPatterns: [[Double]] = [[], [1_000, 1]]

    for dashPattern in dashPatterns {
      for lineJoin in [StrokeLineJoin.bevel, .miter] {
        var element = SceneElement.path(
          frame: SionRect(x: 0, y: 0, width: 1, height: 1),
          path: path
        )
        element.style = ElementStyle(
          fill: .none,
          stroke: StrokeStyle(
            color: .black,
            width: 1_000_000,
            dashPattern: dashPattern,
            lineCap: .butt,
            lineJoin: lineJoin
          )
        )

        XCTAssertTrue(
          ElementHitGeometry.contains(SionPoint(x: 1.000_1, y: 0), in: element)
        )
      }
    }
  }

  func testOpenPathHitsStrokeOnly() {
    let frame = SionRect(x: 100, y: 200, width: 200, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.1, y: 0.5)),
      .quadratic(
        control: SionPoint(x: 0.5, y: 0.1),
        to: SionPoint(x: 0.9, y: 0.5)
      ),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 2)
    )
    element.geometry.rotationRadians = Double.pi / 4
    let hitPoint = InteractionGeometry.rotated(
      SionPoint(x: frame.center.x, y: frame.minY + 30),
      around: frame.center,
      by: element.geometry.rotationRadians
    )
    let missPoint = InteractionGeometry.rotated(
      SionPoint(x: frame.center.x, y: frame.maxY - 10),
      around: frame.center,
      by: element.geometry.rotationRadians
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(
        hitPoint,
        in: element,
        tolerance: 2
      )
    )
    XCTAssertFalse(
      ElementHitGeometry.contains(
        missPoint,
        in: element,
        tolerance: 2
      )
    )
  }

  func testCommandAfterCloseContinuesFromSubpathOrigin() {
    let frame = SionRect(x: 100, y: 200, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0.1, y: 0.1)),
      .line(to: SionPoint(x: 0.9, y: 0.1)),
      .close,
      .line(to: SionPoint(x: 0.9, y: 0.9)),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 2)
    )

    XCTAssertTrue(ElementHitGeometry.contains(frame.center, in: element, tolerance: 2))
  }

  func testLocalPointPathCanHitOutsideFrame() {
    let frame = SionRect(x: 100, y: 200, width: 100, height: 100)
    let path = VectorPath(
      coordinateSpace: .localPoints,
      commands: [
        .move(to: SionPoint(x: 120, y: 50)),
        .line(to: SionPoint(x: 180, y: 50)),
      ]
    )
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 2)
    )

    XCTAssertTrue(
      ElementHitGeometry.contains(SionPoint(x: 250, y: 250), in: element, tolerance: 2)
    )
  }

  func testRotationAndNonzeroOriginTransformHitPoint() {
    let frame = SionRect(x: 130, y: 240, width: 140, height: 80)
    var ellipse = SceneElement.shape(frame: frame, kind: .ellipse)
    ellipse.style = ElementStyle(fill: .solid(.black))
    ellipse.geometry.rotationRadians = Double.pi / 3

    // Expected points are hand-rotated by +60° around the center (200, 280):
    // x' = 200 + dx·cosθ - dy·sinθ, y' = 280 + dx·sinθ + dy·cosθ. The
    // corner (130, 240) maps to (199.641, 199.378); the local point
    // (200, 250) maps to (225.981, 265).
    let corner = SionPoint(x: 199.641_016_151_377_5, y: 199.378_221_735_089_3)
    let visiblePoint = SionPoint(x: 225.980_762_113_533_2, y: 265)

    XCTAssertFalse(ElementHitGeometry.contains(corner, in: ellipse, tolerance: 2))
    XCTAssertTrue(ElementHitGeometry.contains(visiblePoint, in: ellipse, tolerance: 2))
  }

  func testLargeCubicCurveStaysWithinHitTolerance() {
    let frame = SionRect(x: 100, y: 200, width: 900_000, height: 900_000)
    let start = SionPoint(x: 0.1, y: 0.8)
    let control1 = SionPoint(x: 0.2, y: 0.1)
    let control2 = SionPoint(x: 0.8, y: 0.1)
    let end = SionPoint(x: 0.9, y: 0.8)
    let path = VectorPath(commands: [
      .move(to: start),
      .cubic(control1: control1, control2: control2, to: end),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 2)
    )
    let fraction = 0.37
    let complement = 1 - fraction
    let curvePoint = frame.point(
      atNormalized: SionPoint(
        x: (complement * complement * complement * start.x)
          + (3 * complement * complement * fraction * control1.x)
          + (3 * complement * fraction * fraction * control2.x)
          + (fraction * fraction * fraction * end.x),
        y: (complement * complement * complement * start.y)
          + (3 * complement * complement * fraction * control1.y)
          + (3 * complement * fraction * fraction * control2.y)
          + (fraction * fraction * fraction * end.y)
      )
    )

    XCTAssertTrue(ElementHitGeometry.contains(curvePoint, in: element, tolerance: 2))
  }

  func testLargeCurvedShapeMissesStayWithinInteractiveDeadline() {
    let frame = SionRect(
      x: 0,
      y: 0,
      width: SceneLimits.maximumCoordinateMagnitude,
      height: SceneLimits.maximumCoordinateMagnitude
    )
    let kinds: [ShapeKind] = [
      .roundedRectangle(radius: frame.width / 2),
      .ellipse,
      .capsule,
      .cylinder,
    ]
    // Correctness first: the corner misses and the center hits, so the timed
    // loop below cannot be satisfied by an always-miss shortcut.
    for kind in kinds {
      var element = SceneElement.shape(frame: frame, kind: kind)
      element.style = ElementStyle(fill: .solid(.black))

      XCTAssertFalse(ElementHitGeometry.contains(frame.origin, in: element, tolerance: 2))
      XCTAssertTrue(ElementHitGeometry.contains(frame.center, in: element, tolerance: 2))
    }

    let started = ContinuousClock.now
    for kind in kinds {
      var element = SceneElement.shape(frame: frame, kind: kind)
      element.style = ElementStyle(fill: .solid(.black))
      for _ in 0..<Self.largeSceneElementCount {
        if ElementHitGeometry.contains(frame.origin, in: element, tolerance: 2) {
          XCTFail("Corner unexpectedly hit for \(kind)")
          return
        }
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testLargeDashedEllipseGapsStayWithinInteractiveDeadline() {
    let frame = SionRect(x: 0, y: 0, width: 1_000, height: 1_000)
    var element = SceneElement.shape(frame: frame, kind: .ellipse)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(
        color: .black,
        width: 2,
        dashPattern: [1, 1_000],
        lineCap: .butt
      )
    )
    let gapPoint = SionPoint(x: frame.maxX, y: frame.center.y)

    // Positive control: the flattened ellipse starts at (500, 0), inside the
    // first dash, so the miss below cannot come from dashes never hitting.
    XCTAssertTrue(ElementHitGeometry.contains(SionPoint(x: 500, y: 0), in: element, tolerance: 2))

    let started = ContinuousClock.now
    var containsPoint = false
    for _ in 0..<Self.largeSceneElementCount {
      if ElementHitGeometry.contains(gapPoint, in: element, tolerance: 2) {
        containsPoint = true
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertFalse(containsPoint)
    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testLargeEllipseBoundaryMissesStayWithinInteractiveDeadline() {
    let frame = SionRect(x: 0, y: 0, width: 1_000, height: 1_000)
    var element = SceneElement.shape(frame: frame, kind: .ellipse)
    element.style = ElementStyle(fill: .solid(.black))
    let angle = Double.pi / 8
    let miss = SionPoint(
      x: frame.center.x + (500.5 * cos(angle)),
      y: frame.center.y + (500.5 * sin(angle))
    )

    let started = ContinuousClock.now
    var containsPoint = false
    for _ in 0..<Self.largeSceneElementCount {
      if ElementHitGeometry.contains(miss, in: element, tolerance: 0) {
        containsPoint = true
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertFalse(containsPoint)
    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testMaximumNormalizedPathsDistantMissesStayWithinInteractiveDeadline() {
    var commands: [PathCommand] = [.move(to: .zero)]
    for index in 1..<SceneLimits.maximumPathCommandCount {
      commands.append(
        .line(
          to: SionPoint(
            x: index.isMultiple(of: 2) ? 0 : 1,
            y: 1
          )
        )
      )
    }
    let frame = SionRect(x: 0, y: 0, width: 100, height: 100)
    let path = VectorPath(commands: commands)
    var pathElement = SceneElement.path(
      frame: frame,
      path: path
    )
    pathElement.style = ElementStyle(fill: .solid(.black))
    var customShape = SceneElement.shape(frame: frame, kind: .custom(path))
    customShape.style = ElementStyle(fill: .solid(.black))
    let distantPoint = SionPoint(x: frame.maxX + 100, y: frame.center.y)

    // Correctness first: the distant point misses and a point on the path
    // hits, so the timed loop cannot be satisfied by never-hit shortcuts.
    XCTAssertFalse(ElementHitGeometry.contains(distantPoint, in: pathElement))
    XCTAssertTrue(ElementHitGeometry.contains(SionPoint(x: 50, y: 100), in: pathElement))

    let started = ContinuousClock.now
    for element in [pathElement, customShape] {
      for _ in 0..<Self.largeSceneElementCount {
        if ElementHitGeometry.contains(distantPoint, in: element) {
          XCTFail("Distant point unexpectedly hit")
          return
        }
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testMaximumUnpaintedPathsStayWithinInteractiveDeadline() {
    var commands: [PathCommand] = [.move(to: .zero)]
    for index in 1..<SceneLimits.maximumPathCommandCount {
      commands.append(
        .line(
          to: SionPoint(
            x: index.isMultiple(of: 2) ? 0 : 1,
            y: 1
          )
        )
      )
    }
    let frame = SionRect(x: 0, y: 0, width: 100, height: 100)
    let path = VectorPath(commands: commands)
    var pathElement = SceneElement.path(frame: frame, path: path)
    pathElement.style = ElementStyle(fill: .none)
    var customShape = SceneElement.shape(frame: frame, kind: .custom(path))
    customShape.style = ElementStyle(fill: .none)

    let started = ContinuousClock.now
    for element in [pathElement, customShape] {
      for _ in 0..<Self.maximumPathQueryCount {
        XCTAssertFalse(ElementHitGeometry.contains(frame.center, in: element))
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testMaximumCurvedPathCompletesWithinInteractiveDeadline() {
    let frame = SionRect(
      x: 0,
      y: 0,
      width: SceneLimits.maximumCoordinateMagnitude,
      height: SceneLimits.maximumCoordinateMagnitude
    )
    var commands: [PathCommand] = [.move(to: SionPoint(x: 0, y: 0.5))]
    for index in 1..<SceneLimits.maximumPathCommandCount {
      if index.isMultiple(of: 2) {
        commands.append(
          .cubic(
            control1: SionPoint(x: 0, y: 0),
            control2: SionPoint(x: 1, y: 1),
            to: SionPoint(x: 1, y: 0.5)
          )
        )
        continue
      }

      commands.append(
        .cubic(
          control1: SionPoint(x: 1, y: 0),
          control2: SionPoint(x: 0, y: 1),
          to: SionPoint(x: 0, y: 0.5)
        )
      )
    }
    let path = VectorPath(commands: commands)
    var element = SceneElement.path(frame: frame, path: path)
    element.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 2)
    )

    let started = ContinuousClock.now
    let containsPoint = ElementHitGeometry.contains(
      SionPoint(x: frame.center.x, y: frame.minY + (frame.height * 0.6)),
      in: element,
      tolerance: 2
    )
    let elapsed = started.duration(to: .now)

    XCTAssertFalse(containsPoint)
    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testNonintersectingSubpathsDoNotForceMaximumCurveTraversal() {
    let frame = SionRect(
      x: 0,
      y: 0,
      width: SceneLimits.maximumCoordinateMagnitude,
      height: SceneLimits.maximumCoordinateMagnitude
    )
    var commands: [PathCommand] = [.move(to: SionPoint(x: 0, y: 0.1))]
    for index in 1..<(SceneLimits.maximumPathCommandCount - 2) {
      let startsAtLeft = index.isMultiple(of: 2) == false
      commands.append(
        .cubic(
          control1: SionPoint(x: startsAtLeft ? 0 : 1, y: 0),
          control2: SionPoint(x: startsAtLeft ? 1 : 0, y: 0.4),
          to: SionPoint(x: startsAtLeft ? 1 : 0, y: 0.1)
        )
      )
    }
    let strokeStyle = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .black, width: 2)
    )
    // None of these cases paints at the query point.
    let cases: [([PathCommand], ElementStyle, SionPoint)] = [
      (
        [.move(to: SionPoint(x: 1, y: 1))],
        strokeStyle,
        SionPoint(x: 0.5, y: 0.9)
      ),
      (
        [
          .move(to: SionPoint(x: 1, y: 1)),
          .line(to: SionPoint(x: 1, y: 1)),
        ],
        strokeStyle,
        SionPoint(x: 0.5, y: 0.9)
      ),
      (
        [
          .move(to: SionPoint(x: 0, y: 1)),
          .line(to: SionPoint(x: 1, y: 1)),
        ],
        ElementStyle(fill: .solid(.black)),
        SionPoint(x: 0.5, y: 0.9)
      ),
      (
        [],
        ElementStyle(
          fill: .none,
          stroke: StrokeStyle(
            color: .black,
            width: 2,
            dashPattern: [0, 20],
            lineCap: .butt
          )
        ),
        SionPoint(x: 0.5, y: 0.35)
      ),
    ]

    let started = ContinuousClock.now
    for (outlier, style, normalizedMiss) in cases {
      var element = SceneElement.path(
        frame: frame,
        path: VectorPath(commands: commands + outlier)
      )
      element.style = style
      let miss = frame.point(atNormalized: normalizedMiss)
      // Correctness outside the timed loop below.
      XCTAssertFalse(ElementHitGeometry.contains(miss, in: element))
      for _ in 0..<Self.maximumCurvedPathQueryCount {
        if ElementHitGeometry.contains(miss, in: element) {
          XCTFail("Normalized miss unexpectedly hit")
          return
        }
      }
    }
    let elapsed = started.duration(to: .now)

    XCTAssertLessThan(elapsed, Self.interactiveHitDeadline)
  }

  func testCustomPathHonorsFillRule() {
    let commands: [PathCommand] = [
      .move(to: SionPoint(x: 0.1, y: 0.1)),
      .line(to: SionPoint(x: 0.9, y: 0.1)),
      .line(to: SionPoint(x: 0.9, y: 0.9)),
      .line(to: SionPoint(x: 0.1, y: 0.9)),
      .close,
      .move(to: SionPoint(x: 0.35, y: 0.35)),
      .line(to: SionPoint(x: 0.65, y: 0.35)),
      .line(to: SionPoint(x: 0.65, y: 0.65)),
      .line(to: SionPoint(x: 0.35, y: 0.65)),
      .close,
    ]
    let frame = SionRect(x: 50, y: 75, width: 200, height: 120)
    let center = frame.center
    var evenOdd = SceneElement.shape(
      frame: frame,
      kind: .custom(VectorPath(fillRule: .evenOdd, commands: commands))
    )
    evenOdd.style = ElementStyle(fill: .solid(.black))
    var nonZero = evenOdd
    nonZero.content = .shape(
      ShapeContent(kind: .custom(VectorPath(fillRule: .nonZero, commands: commands)))
    )

    XCTAssertFalse(ElementHitGeometry.contains(center, in: evenOdd, tolerance: 0))
    XCTAssertTrue(ElementHitGeometry.contains(center, in: nonZero, tolerance: 0))
  }
}
