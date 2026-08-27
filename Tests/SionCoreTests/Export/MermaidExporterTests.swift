import XCTest

@testable import SionCore

final class MermaidExporterTests: XCTestCase {
  func testReportsOmittedElementKindsAndCounts() {
    let frame = SionRect(x: 0, y: 0, width: 100, height: 100)
    let path = VectorPath(commands: [
      .move(to: SionPoint(x: 0, y: 0)),
      .line(to: SionPoint(x: 1, y: 1)),
    ])
    let document = SionDocument(
      scene: SionScene(elements: [
        .path(frame: frame, path: path),
        .path(frame: frame, path: path),
        .group(frame: frame),
      ])
    )

    let export = MermaidExporter.export(document: document)

    XCTAssertEqual(export.coverage, .none)
    XCTAssertEqual(
      export.omissions,
      [
        MermaidOmission(kind: .group, count: 1),
        MermaidOmission(kind: .path, count: 2),
      ]
    )
  }

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
