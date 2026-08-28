import XCTest

@testable import SionCore

final class ElementHitGeometryTests: XCTestCase {
  private static let interactiveHitDeadline = Duration.seconds(1)

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

  func testTinyDashPatternCompletesWithinInteractiveDeadline() {
    let frame = SionRect(x: 100, y: 200, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0, y: 0.5)),
      .line(to: SionPoint(x: 1, y: 0.5)),
    ])
    var element = SceneElement.path(frame: frame, path: path)
    let validSubpixelDashLength = 0.000_01
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
    let rotation = Double.pi / 3
    var ellipse = SceneElement.shape(frame: frame, kind: .ellipse)
    ellipse.style = ElementStyle(fill: .solid(.black))
    ellipse.geometry.rotationRadians = rotation
    let visibleLocalPoint = SionPoint(x: frame.center.x, y: frame.minY + 10)
    let corner = InteractionGeometry.rotated(frame.origin, around: frame.center, by: rotation)
    let visiblePoint = InteractionGeometry.rotated(
      visibleLocalPoint,
      around: frame.center,
      by: rotation
    )

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
    var ellipse = SceneElement.shape(frame: frame, kind: .ellipse)
    ellipse.style = ElementStyle(fill: .solid(.black))
    let largeCurvedShapeCount = 25_000

    let started = ContinuousClock.now
    for _ in 0..<largeCurvedShapeCount {
      XCTAssertFalse(ElementHitGeometry.contains(frame.origin, in: ellipse, tolerance: 2))
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
