import XCTest

@testable import SionCore

final class InteractionGeometryTests: XCTestCase {
  func testCreationFrameUsesDefaultForClickAndBoundsForDrag() {
    let anchor = SionPoint(x: 100, y: 80)
    let defaultSize = SionSize(width: 160, height: 76)

    let click = InteractionGeometry.creationFrame(
      from: anchor,
      to: SionPoint(x: 102, y: 81),
      dragThreshold: 4,
      defaultSize: defaultSize,
      minimumSize: minimumSize
    )
    let drag = InteractionGeometry.creationFrame(
      from: anchor,
      to: SionPoint(x: 40, y: 20),
      dragThreshold: 4,
      defaultSize: defaultSize,
      minimumSize: minimumSize
    )

    XCTAssertEqual(click.mode, .click)
    XCTAssertEqual(click.frame, SionRect(x: 100, y: 80, width: 160, height: 76))
    XCTAssertEqual(drag.mode, .drag)
    XCTAssertEqual(drag.frame, SionRect(x: 40, y: 20, width: 60, height: 60))
  }

  func testDragFramePreservesDirectionWhenEnforcingMinimumSize() {
    XCTAssertEqual(
      InteractionGeometry.dragFrame(
        from: SionPoint(x: 100, y: 100),
        to: SionPoint(x: 104, y: 95),
        minimumSize: minimumSize
      ),
      SionRect(x: 100, y: 88, width: 12, height: 12)
    )
    XCTAssertEqual(
      InteractionGeometry.dragFrame(
        from: SionPoint(x: 100, y: 100),
        to: SionPoint(x: 100, y: 100),
        minimumSize: minimumSize
      ),
      SionRect(x: 100, y: 100, width: 12, height: 12)
    )
  }

  func testAllResizeHandlePoints() {
    let frame = SionRect(x: 10, y: 20, width: 100, height: 60)
    let expected: [ResizeHandle: SionPoint] = [
      .northWest: SionPoint(x: 10, y: 20),
      .north: SionPoint(x: 60, y: 20),
      .northEast: SionPoint(x: 110, y: 20),
      .east: SionPoint(x: 110, y: 50),
      .southEast: SionPoint(x: 110, y: 80),
      .south: SionPoint(x: 60, y: 80),
      .southWest: SionPoint(x: 10, y: 80),
      .west: SionPoint(x: 10, y: 50),
    ]

    XCTAssertEqual(ResizeHandle.allCases.count, expected.count)
    for handle in ResizeHandle.allCases {
      XCTAssertEqual(
        InteractionGeometry.resizeHandlePoint(handle, in: frame),
        expected[handle]
      )
    }
  }

  func testEveryResizeHandleMovesItsAxes() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 80)
    let pointer = SionPoint(x: 50, y: 50)
    let expected: [ResizeHandle: SionRect] = [
      .northWest: SionRect(x: 50, y: 50, width: 50, height: 30),
      .north: SionRect(x: 0, y: 50, width: 100, height: 30),
      .northEast: SionRect(x: 0, y: 50, width: 50, height: 30),
      .east: SionRect(x: 0, y: 0, width: 50, height: 80),
      .southEast: SionRect(x: 0, y: 0, width: 50, height: 50),
      .south: SionRect(x: 0, y: 0, width: 100, height: 50),
      .southWest: SionRect(x: 50, y: 0, width: 50, height: 50),
      .west: SionRect(x: 50, y: 0, width: 50, height: 80),
    ]

    for handle in ResizeHandle.allCases {
      XCTAssertEqual(
        InteractionGeometry.resizedFrame(
          frame,
          moving: handle,
          to: pointer,
          minimumSize: minimumSize
        ),
        expected[handle]
      )
    }
  }

  func testRotatedResizeKeepsOppositeHandleFixed() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 40)
    let rotation = Double.pi / 2
    let resized = InteractionGeometry.resizedFrame(
      frame,
      moving: .east,
      to: SionPoint(x: 50, y: 100),
      minimumSize: minimumSize,
      rotationRadians: rotation
    )

    assertRect(resized, equals: SionRect(x: -15, y: 15, width: 130, height: 40))
    assertPoint(
      InteractionGeometry.resizeHandlePoint(.west, in: resized, rotationRadians: rotation),
      equals: SionPoint(x: 50, y: -30)
    )
    assertPoint(
      InteractionGeometry.resizeHandlePoint(.east, in: resized, rotationRadians: rotation),
      equals: SionPoint(x: 50, y: 100)
    )
  }

  func testEveryRotatedResizeHandleTracksPointerAndKeepsOppositeFixed() {
    let frame = SionRect(x: 10, y: 20, width: 100, height: 60)
    let rotation = 0.713
    let cases: [(ResizeHandle, ResizeHandle, SionPoint)] = [
      (.northWest, .southEast, SionPoint(x: -25, y: -15)),
      (.north, .south, SionPoint(x: 60, y: -15)),
      (.northEast, .southWest, SionPoint(x: 145, y: -15)),
      (.east, .west, SionPoint(x: 145, y: 50)),
      (.southEast, .northWest, SionPoint(x: 145, y: 115)),
      (.south, .north, SionPoint(x: 60, y: 115)),
      (.southWest, .northEast, SionPoint(x: -25, y: 115)),
      (.west, .east, SionPoint(x: -25, y: 50)),
    ]

    for (moving, fixed, localPointer) in cases {
      let pointer = InteractionGeometry.rotated(
        localPointer,
        around: frame.center,
        by: rotation
      )
      let fixedPoint = InteractionGeometry.resizeHandlePoint(
        fixed,
        in: frame,
        rotationRadians: rotation
      )
      let resized = InteractionGeometry.resizedFrame(
        frame,
        moving: moving,
        to: pointer,
        minimumSize: minimumSize,
        rotationRadians: rotation
      )

      assertPoint(
        InteractionGeometry.resizeHandlePoint(
          moving,
          in: resized,
          rotationRadians: rotation
        ),
        equals: pointer
      )
      assertPoint(
        InteractionGeometry.resizeHandlePoint(
          fixed,
          in: resized,
          rotationRadians: rotation
        ),
        equals: fixedPoint
      )
    }
  }

  func testRotationMathUsesClockwiseCanvasAngles() {
    let center = SionPoint.zero
    let point = SionPoint(x: 10, y: 0)
    let rotated = InteractionGeometry.rotated(point, around: center, by: .pi / 2)

    assertPoint(rotated, equals: SionPoint(x: 0, y: 10))
    assertPoint(
      InteractionGeometry.unrotated(rotated, around: center, by: .pi / 2),
      equals: point
    )
    XCTAssertEqual(
      InteractionGeometry.rotationRadians(
        at: SionPoint(x: 0, y: -10),
        around: center,
        offset: .pi / 2
      ),
      0,
      accuracy: tolerance
    )
    XCTAssertEqual(
      InteractionGeometry.rotationRadians(
        at: SionPoint(x: 10, y: 0),
        around: center,
        offset: .pi / 2
      ),
      .pi / 2,
      accuracy: tolerance
    )
  }

  func testRotationDeltaCrossesBranchCutByShortestPath() {
    let center = SionPoint.zero
    let start = point(angleDegrees: 170)
    let end = point(angleDegrees: -170)

    XCTAssertEqual(
      InteractionGeometry.rotationDelta(from: start, to: end, around: center),
      20 * .pi / 180,
      accuracy: tolerance
    )
  }

  func testRotationHandleFollowsElementRotation() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 40)

    assertPoint(
      InteractionGeometry.rotationHandlePoint(
        in: frame,
        rotationRadians: .pi / 2,
        offset: 20
      ),
      equals: SionPoint(x: 90, y: 20)
    )
  }

  func testRoundedRectangleRadiusDragClampsAndSupportsRotation() {
    let frame = SionRect(x: 10, y: 20, width: 100, height: 40)

    XCTAssertEqual(
      InteractionGeometry.roundedRectangleCornerRadiusHandle(
        in: frame,
        radius: 10
      ),
      SionPoint(x: 20, y: 30)
    )

    XCTAssertEqual(
      InteractionGeometry.roundedRectangleCornerRadius(
        in: frame,
        draggedTo: SionPoint(x: 25, y: 500)
      ),
      15
    )
    XCTAssertEqual(
      InteractionGeometry.roundedRectangleCornerRadius(
        in: frame,
        draggedTo: SionPoint(x: 100, y: 20)
      ),
      20
    )
    XCTAssertEqual(
      InteractionGeometry.roundedRectangleCornerRadius(
        in: frame,
        draggedTo: SionPoint(x: 0, y: 20)
      ),
      0
    )

    let rotatedHandle = InteractionGeometry.roundedRectangleCornerRadiusHandle(
      in: frame,
      radius: 10,
      rotationRadians: .pi / 2
    )
    XCTAssertEqual(
      InteractionGeometry.roundedRectangleCornerRadius(
        in: frame,
        draggedTo: rotatedHandle,
        rotationRadians: .pi / 2
      ),
      10,
      accuracy: tolerance
    )
  }

  func testConnectorAttachmentChoosesExplicitCompatibleMagnet() {
    var element = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 100, height: 40),
      kind: .rectangle
    )
    element.geometry.rotationRadians = .pi / 2
    let east = element.resolvedMagnets.first { $0.magnet.id == "east" }!

    XCTAssertEqual(
      ConnectorAttachmentResolver.endpoint(
        attachingTo: element,
        at: east.endpoint.point,
        use: .outgoing,
        magnetSnapDistance: 5
      ),
      .element(
        element.id,
        attachment: .magnet("east"),
        fallbackPoint: east.endpoint.point
      )
    )
  }

  func testConnectorAttachmentFallsBackToAutomaticOrFree() {
    var element = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 100, height: 40),
      kind: .rectangle
    )
    element.magnetConfiguration = .custom([
      Magnet(
        id: "incoming-only",
        normalizedPosition: SionPoint(x: 1, y: 0.5),
        outwardDirection: .east,
        connectionDirection: .incoming
      )
    ])
    let point = SionPoint(x: 100, y: 20)

    XCTAssertEqual(
      ConnectorAttachmentResolver.endpoint(
        attachingTo: element,
        at: point,
        use: .outgoing,
        magnetSnapDistance: 5
      ),
      .element(element.id, attachment: .automatic, fallbackPoint: point)
    )
    XCTAssertEqual(
      ConnectorAttachmentResolver.endpoint(
        attachingTo: nil,
        at: point,
        use: .outgoing,
        magnetSnapDistance: 5
      ),
      .free(point)
    )
  }

  private func point(angleDegrees: Double) -> SionPoint {
    let radians = angleDegrees * .pi / 180
    return SionPoint(x: cos(radians), y: sin(radians))
  }

  private func assertPoint(
    _ actual: SionPoint?,
    equals expected: SionPoint,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard let actual else {
      XCTFail("Missing point", file: file, line: line)
      return
    }

    XCTAssertEqual(actual.x, expected.x, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: tolerance, file: file, line: line)
  }

  func testConstrainedCornerResizeKeepsTheProportionAndTheOppositeCorner() {
    let frame = SionRect(x: 100, y: 100, width: 200, height: 100)

    let resized = InteractionGeometry.resizedFrame(
      frame,
      moving: .southEast,
      to: SionPoint(x: 500, y: 160),
      minimumSize: minimumSize,
      aspectRatio: 2
    )

    // The pointer pushes width further than height, so width leads.
    assertRect(resized, equals: SionRect(x: 100, y: 100, width: 400, height: 200))
  }

  func testConstrainedCornerResizeFollowsTheDominantAxis() {
    let frame = SionRect(x: 100, y: 100, width: 200, height: 100)

    let resized = InteractionGeometry.resizedFrame(
      frame,
      moving: .southEast,
      to: SionPoint(x: 320, y: 400),
      minimumSize: minimumSize,
      aspectRatio: 2
    )

    // Height pushes to 300, which needs a width of 600.
    assertRect(resized, equals: SionRect(x: 100, y: 100, width: 600, height: 300))
  }

  func testConstrainedEdgeResizeDrivesTheOtherAxis() {
    let frame = SionRect(x: 100, y: 100, width: 200, height: 100)

    let horizontal = InteractionGeometry.resizedFrame(
      frame,
      moving: .east,
      to: SionPoint(x: 500, y: 100),
      minimumSize: minimumSize,
      aspectRatio: 2
    )
    let vertical = InteractionGeometry.resizedFrame(
      frame,
      moving: .south,
      to: SionPoint(x: 100, y: 300),
      minimumSize: minimumSize,
      aspectRatio: 2
    )

    // An edge handle keeps the frame centered on the axis it does not move.
    assertRect(horizontal, equals: SionRect(x: 100, y: 50, width: 400, height: 200))
    assertRect(vertical, equals: SionRect(x: 0, y: 100, width: 400, height: 200))
  }

  func testConstrainedResizeKeepsTheHandlesFixedCornerAnchored() {
    let frame = SionRect(x: 100, y: 100, width: 200, height: 100)

    let resized = InteractionGeometry.resizedFrame(
      frame,
      moving: .northWest,
      to: SionPoint(x: 0, y: 60),
      minimumSize: minimumSize,
      aspectRatio: 2
    )

    // The south-east corner stays at (300, 200).
    XCTAssertEqual(resized.maxX, 300, accuracy: tolerance)
    XCTAssertEqual(resized.maxY, 200, accuracy: tolerance)
    XCTAssertEqual(resized.width / resized.height, 2, accuracy: tolerance)
  }

  func testConstrainedResizeGrowsBothAxesToClearTheMinimum() {
    let frame = SionRect(x: 100, y: 100, width: 200, height: 100)

    let resized = InteractionGeometry.resizedFrame(
      frame,
      moving: .southEast,
      to: SionPoint(x: 100, y: 100),
      minimumSize: SionSize(width: 12, height: 40),
      aspectRatio: 2
    )

    // Height reaches its minimum first and pulls the width along with it.
    assertRect(resized, equals: SionRect(x: 100, y: 100, width: 80, height: 40))
  }

  func testAnUnusableAspectRatioLeavesTheFreeResizeAlone() {
    let frame = SionRect(x: 100, y: 100, width: 200, height: 100)
    let pointer = SionPoint(x: 500, y: 160)
    let free = InteractionGeometry.resizedFrame(
      frame,
      moving: .southEast,
      to: pointer,
      minimumSize: minimumSize
    )

    for ratio in [0.0, -2.0, Double.nan, Double.infinity] {
      assertRect(
        InteractionGeometry.resizedFrame(
          frame,
          moving: .southEast,
          to: pointer,
          minimumSize: minimumSize,
          aspectRatio: ratio
        ),
        equals: free
      )
    }
  }

  private func assertRect(
    _ actual: SionRect,
    equals expected: SionRect,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.x, expected.x, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: tolerance, file: file, line: line)
  }

  private let minimumSize = SionSize(width: 12, height: 12)
  private let tolerance = 1e-9
}
