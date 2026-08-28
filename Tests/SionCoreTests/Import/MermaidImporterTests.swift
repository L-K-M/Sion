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

  func testHonorsEachFlowchartDirection() throws {
    let center = SionPoint(x: 500, y: 400)

    for direction in ImportedDirection.allCases {
      let nodes = MermaidImporter.elements(
        from: """
          flowchart \(direction.rawValue)
            A
            B
            C
            D
          """,
        centeredAt: center
      )

      let first = try XCTUnwrap(nodes.first)
      let second = try XCTUnwrap(nodes.dropFirst().first)
      let wrapped = try XCTUnwrap(nodes.dropFirst(3).first)
      let step = (second.geometry.frame.center - first.geometry.frame.center).normalized
      let wrapStep = (wrapped.geometry.frame.center - first.geometry.frame.center).normalized

      XCTAssertEqual(step, direction.expectedStep, direction.rawValue)
      XCTAssertEqual(wrapStep, direction.expectedWrapStep, direction.rawValue)
      XCTAssertEqual(
        nodes.dropFirst().reduce(first.geometry.frame) { bounds, node in
          bounds.union(node.geometry.frame)
        }.center,
        center,
        direction.rawValue
      )
    }
  }

  func testRejectsUnknownFlowchartDirection() {
    let source = """
      flowchart XY
        A
      """

    XCTAssertTrue(MermaidImporter.looksLikeMermaid(source))
    XCTAssertTrue(MermaidImporter.elements(from: source, centeredAt: .zero).isEmpty)
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

private enum ImportedDirection: String, CaseIterable {
  case topToBottom = "TB"
  case topDown = "TD"
  case bottomToTop = "BT"
  case leftToRight = "LR"
  case rightToLeft = "RL"

  var expectedStep: SionVector {
    switch self {
    case .topToBottom, .topDown:
      return .south
    case .bottomToTop:
      return .north
    case .leftToRight:
      return .east
    case .rightToLeft:
      return .west
    }
  }

  var expectedWrapStep: SionVector {
    switch self {
    case .topToBottom, .topDown, .bottomToTop:
      return .east
    case .leftToRight, .rightToLeft:
      return .south
    }
  }
}
