import XCTest

@testable import SionCore

final class MermaidImporterTests: XCTestCase {
  func testRecognizesExactFlowchartHeaderAfterFrontMatter() {
    let source = """
      ---
      title: Example
      ---
      %% comment
      flowchart LR
        A --> B
      """

    XCTAssertTrue(MermaidImporter.looksLikeMermaid(source))
    XCTAssertFalse(MermaidImporter.looksLikeMermaid("graphics are not Mermaid"))
  }

  func testImportsNodesAndLabeledLinkAroundPastePoint() throws {
    let center = SionPoint(x: 500, y: 400)
    let elements = MermaidImporter.elements(
      from: """
        flowchart LR
          A[Start] -->|continue| B{Ready?}
        """,
      centeredAt: center
    )

    let nodes = elements.filter { $0.content.connector == nil }
    let connector = try XCTUnwrap(elements.compactMap(\.content.connector).first)
    let firstNode = try XCTUnwrap(nodes.first)

    XCTAssertEqual(nodes.count, 2)
    XCTAssertEqual(nodes.map(\.name), ["A", "B"])
    XCTAssertEqual(connector.label?.string, "continue")
    XCTAssertEqual(
      nodes.dropFirst().reduce(firstNode.geometry.frame) { bounds, node in
        bounds.union(node.geometry.frame)
      }.center,
      center
    )
  }

  func testGeneratedMermaidCanBeImportedAgain() throws {
    let first = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 160, height: 80),
      text: "One"
    )
    let second = SceneElement.shape(
      frame: SionRect(x: 260, y: 0, width: 160, height: 80),
      text: "Two"
    )
    let connector = SceneElement.connector(
      source: .element(
        first.id, attachment: .automatic, fallbackPoint: first.geometry.frame.center),
      target: .element(
        second.id, attachment: .automatic, fallbackPoint: second.geometry.frame.center)
    )
    let document = SionDocument(scene: SionScene(elements: [first, second, connector]))
    let exported = MermaidExporter.export(document: document)

    let imported = MermaidImporter.elements(from: exported.source, centeredAt: .zero)

    XCTAssertEqual(imported.filter { $0.content.connector == nil }.count, 2)
    XCTAssertEqual(imported.compactMap(\.content.connector).count, 1)
  }
}
