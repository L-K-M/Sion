import Foundation
import XCTest

@testable import SionCore

final class TextLineWrapEstimatorTests: XCTestCase {
  private let style = TextStyle.shapeLabelDefault

  func testShortTextStaysOnOneLine() {
    let lines = TextLineWrapEstimator.wrappedLines(of: "Start", fitting: 200, style: style)

    XCTAssertEqual(lines, ["Start"])
  }

  func testLongTextWrapsOnWordBoundaries() {
    let text = "Deploy the worker fleet before the freeze window closes tonight"
    let lines = TextLineWrapEstimator.wrappedLines(of: text, fitting: 160, style: style)

    XCTAssertGreaterThan(lines.count, 1)
    XCTAssertEqual(lines.joined(separator: " "), text)
    for line in lines {
      XCTAssertLessThanOrEqual(
        TextLineWrapEstimator.estimatedWidth(of: line, style: style),
        160
      )
    }
  }

  func testOverlongWordBreaksHard() {
    let text = "supercalifragilisticexpialidocious"
    let lines = TextLineWrapEstimator.wrappedLines(of: text, fitting: 100, style: style)

    XCTAssertGreaterThan(lines.count, 1)
    XCTAssertEqual(lines.joined(), text)
  }

  func testEmptyAndBlankLinesSurvive() {
    XCTAssertEqual(
      TextLineWrapEstimator.wrappedLines(of: "", fitting: 100, style: style),
      [""]
    )
  }

  func testNonPositiveWidthPassesThrough() {
    XCTAssertEqual(
      TextLineWrapEstimator.wrappedLines(of: "any text here", fitting: 0, style: style),
      ["any text here"]
    )
  }

  func testExportWrapsLongShapeLabelInsideTspans() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 120, height: 60),
      kind: .rectangle,
      text: "Quarterly revenue reconciliation checkpoint review"
    )
    let document = SionDocument(scene: SionScene(elements: [shape]))

    let svg = try SVGExporter.export(document: document, assets: [:])

    let tspanCount = svg.components(separatedBy: "<tspan").count - 1
    XCTAssertGreaterThan(tspanCount, 1)
  }

  func testExportClampsWrappedLinesToFrameHeight() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 90, height: 50),
      kind: .rectangle,
      text:
        "Alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike"
    )
    let document = SionDocument(scene: SionScene(elements: [shape]))

    let svg = try SVGExporter.export(document: document, assets: [:])

    // 50 - 24 insets = 26 pt of room at 18 pt line height: one line plus an
    // ellipsis-terminated remainder.
    let tspanCount = svg.components(separatedBy: "<tspan").count - 1
    XCTAssertLessThanOrEqual(tspanCount, 2)
    XCTAssertTrue(svg.contains("…"))
  }

  func testCJKTextEstimatesFullWidth() {
    let latin = TextLineWrapEstimator.estimatedWidth(of: "mmmm", style: style)
    let cjk = TextLineWrapEstimator.estimatedWidth(of: "日本語の文章", style: style)

    XCTAssertGreaterThan(cjk, latin)
  }
}
