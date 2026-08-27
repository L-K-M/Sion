import XCTest

@testable import SionCore

final class SceneValidationTests: XCTestCase {
  private let elementID = ElementID("00000000-0000-0000-0000-000000000101")!

  func testRejectsNonFiniteAndOutOfRangeColors() {
    var nonFinite = shape()
    nonFinite.style.fill = .solid(SionColor(red: .nan, green: 0, blue: 0))

    assertInvalid(nonFinite, expected: .invalidStyle(elementID))

    var outOfRange = shape()
    outOfRange.style.fill = .solid(SionColor(red: 0, green: 1.01, blue: 0))

    assertInvalid(outOfRange, expected: .invalidStyle(elementID))
  }

  func testRejectsInvalidStrokeGradientShadowAndOpacity() {
    var invalidStroke = shape()
    invalidStroke.style.stroke = StrokeStyle(
      color: .black,
      width: -1,
      dashPattern: [4, -2]
    )

    assertInvalid(invalidStroke, expected: .invalidStyle(elementID))

    var invalidGradient = shape()
    invalidGradient.style.fill = .linearGradient(
      LinearGradientFill(
        stops: [
          GradientStop(color: .black, location: 0.75),
          GradientStop(color: .white, location: 0.25),
        ],
        start: SionPoint(x: 0, y: 0),
        end: SionPoint(x: 1, y: 1)
      )
    )

    assertInvalid(invalidGradient, expected: .invalidStyle(elementID))

    var invalidShadow = shape()
    invalidShadow.style.shadows = [
      ShadowStyle(color: .black, offset: .zero, blurRadius: -1)
    ]

    assertInvalid(invalidShadow, expected: .invalidStyle(elementID))

    var invalidOpacity = shape()
    invalidOpacity.style.opacity = 1.01

    assertInvalid(invalidOpacity, expected: .invalidStyle(elementID))
  }

  func testRejectsInvalidTextMetrics() {
    var invalidFont = SceneElement.text(
      id: elementID,
      frame: SionRect(x: 0, y: 0, width: 100, height: 30),
      text: "Label"
    )
    invalidFont.content = .text(
      TextContent(
        string: "Label",
        style: TextStyle(
          font: FontDescriptor(size: 0),
          color: .black,
          horizontalAlignment: .leading,
          verticalAlignment: .top,
          insets: TextInsets(all: 0),
          autoSizing: .fixed
        )
      )
    )

    assertInvalid(invalidFont, expected: .invalidText(elementID))

    var nonFiniteSpacing = invalidFont
    nonFiniteSpacing.content = .text(
      TextContent(
        string: "Label",
        style: TextStyle(
          font: FontDescriptor(size: 14),
          color: .black,
          horizontalAlignment: .leading,
          verticalAlignment: .top,
          lineSpacing: .infinity,
          insets: TextInsets(all: 0),
          autoSizing: .fixed
        )
      )
    )

    assertInvalid(nonFiniteSpacing, expected: .invalidText(elementID))
  }

  func testRejectsMalformedVectorPaths() {
    let missingMove = VectorPath(commands: [
      .line(to: SionPoint(x: 1, y: 1))
    ])
    let normalizedPointOutsideUnitSquare = VectorPath(commands: [
      .move(to: .zero),
      .line(to: SionPoint(x: 1.01, y: 1)),
    ])

    for path in [missingMove, normalizedPointOutsideUnitSquare] {
      let element = SceneElement.path(
        id: elementID,
        frame: SionRect(x: 0, y: 0, width: 100, height: 100),
        path: path
      )

      assertInvalid(element, expected: .invalidVectorPath(elementID))
    }
  }

  func testAcceptsSVGCommandAfterClosingSubpath() throws {
    let path = VectorPath(commands: [
      .move(to: .zero),
      .line(to: SionPoint(x: 1, y: 0)),
      .close,
      .line(to: SionPoint(x: 1, y: 1)),
    ])
    let element = SceneElement.path(
      id: elementID,
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      path: path
    )

    XCTAssertNoThrow(try SionScene(elements: [element]).validate())
  }

  func testRejectsInvalidManualConnectorRoutes() {
    let outOfBounds = ManualConnectorRoute.curved(
      controlPoint: SionPoint(x: SceneLimits.maximumCoordinateMagnitude + 1, y: 0)
    )
    let incompatible = ManualConnectorRoute.bezier(
      sourceControl: SionPoint(x: 10, y: 0),
      targetControl: SionPoint(x: 90, y: 0)
    )

    assertInvalid(
      connector(routingStyle: .curved, manualRoute: outOfBounds),
      expected: .invalidManualRoute(elementID)
    )
    assertInvalid(
      connector(routingStyle: .straight, manualRoute: incompatible),
      expected: .invalidManualRoute(elementID)
    )
  }

  func testRejectsEmptyExplicitEndpointMagnetID() {
    let targetID = ElementID("00000000-0000-0000-0000-000000000102")!
    let target = SceneElement.shape(
      id: targetID,
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    let connector = SceneElement(
      id: elementID,
      geometry: ElementGeometry(frame: .zero),
      magnetConfiguration: .preset(.none),
      style: .connectorDefault,
      content: .connector(
        ConnectorContent(
          source: .element(
            targetID,
            attachment: .magnet(""),
            fallbackPoint: SionPoint(x: 100, y: 50)
          ),
          target: .free(SionPoint(x: 200, y: 50))
        )
      )
    )

    XCTAssertThrowsError(try SionScene(elements: [target, connector]).validate()) { error in
      XCTAssertEqual(
        error as? SceneValidationError,
        .invalidConnectorEndpoint(elementID)
      )
    }
  }

  func testRejectsInvalidRoundedRectangleRadii() {
    let invalidRadii = [
      Double.nan,
      -1,
      SceneLimits.maximumCoordinateMagnitude + 1,
    ]

    for radius in invalidRadii {
      let element = SceneElement.shape(
        id: elementID,
        frame: SionRect(x: 0, y: 0, width: 100, height: 100),
        kind: .roundedRectangle(radius: radius)
      )

      assertInvalid(element, expected: .invalidShape(elementID))
    }
  }

  func testRejectsUnreasonableGridSettings() {
    let excessiveSpacing = CanvasGrid(
      spacing: SceneLimits.maximumCoordinateMagnitude + 1
    )
    let excessiveSubdivisions = CanvasGrid(
      spacing: 16,
      subdivisions: SceneLimits.maximumGridSubdivisions + 1
    )

    XCTAssertThrowsError(
      try SionScene(canvas: SionCanvas(grid: excessiveSpacing)).validate()
    ) { error in
      XCTAssertEqual(error as? SceneValidationError, .invalidCanvas)
    }
    XCTAssertThrowsError(
      try SionScene(canvas: SionCanvas(grid: excessiveSubdivisions)).validate()
    ) { error in
      XCTAssertEqual(error as? SceneValidationError, .invalidCanvas)
    }
  }

  func testRejectsInvalidCanvasBackgroundColor() {
    let canvas = SionCanvas(
      background: SionColor(red: -0.01, green: 1, blue: 1)
    )

    XCTAssertThrowsError(try SionScene(canvas: canvas).validate()) { error in
      XCTAssertEqual(error as? SceneValidationError, .invalidCanvas)
    }
  }

  func testPortableValuePreservesLargeIntegers() throws {
    let signed = Int64.max
    let unsigned = UInt64.max
    let value = PortableValue.object([
      "signed": .integer(signed),
      "unsigned": .unsignedInteger(unsigned),
      "fraction": .number(1.25),
      "integralDouble": .number(1),
    ])

    let data = try CanonicalJSON.encode(value)
    let decoded = try CanonicalJSON.decode(PortableValue.self, from: data)

    XCTAssertEqual(decoded, value)
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(String(signed)))
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(String(unsigned)))
  }

  func testRejectsNonFiniteExtensionNumber() {
    let scene = SionScene(extensions: [
      "ch.lkmc.test": .object(["invalid": .number(.nan)])
    ])

    XCTAssertThrowsError(try scene.validate()) { error in
      XCTAssertEqual(error as? SceneValidationError, .invalidExtension)
    }
  }

  private func shape() -> SceneElement {
    SceneElement.shape(
      id: elementID,
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
  }

  private func connector(
    routingStyle: ConnectorRoutingStyle,
    manualRoute: ManualConnectorRoute
  ) -> SceneElement {
    SceneElement(
      id: elementID,
      geometry: ElementGeometry(frame: .zero),
      magnetConfiguration: .preset(.none),
      style: .connectorDefault,
      content: .connector(
        ConnectorContent(
          source: .free(.zero),
          target: .free(SionPoint(x: 100, y: 0)),
          routingStyle: routingStyle,
          manualRoute: manualRoute
        )
      )
    )
  }

  private func assertInvalid(
    _ element: SceneElement,
    expected: SceneValidationError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try SionScene(elements: [element]).validate(),
      file: file,
      line: line
    ) { error in
      XCTAssertEqual(error as? SceneValidationError, expected, file: file, line: line)
    }
  }
}
