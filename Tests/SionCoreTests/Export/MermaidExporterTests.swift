import XCTest

@testable import SionCore

final class MermaidExporterTests: XCTestCase {
  func testLabelsRemainParseableWhenTextContainsControls() {
    let shape = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 160, height: 80),
      text: "before\u{0000}after\rline"
    )

    let export = MermaidExporter.export(
      document: SionDocument(scene: SionScene(elements: [shape]))
    )

    XCTAssertFalse(export.source.unicodeScalars.contains { $0.value == 0 || $0.value == 13 })
    XCTAssertTrue(export.source.contains("before�after<br>line"))
  }
}
