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

      XCTAssertEqual(nodes.count, 4, direction.rawValue)
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

  func testDefaultsDirectionlessHeadersToTopToBottom() throws {
    for header in ImportedHeader.allCases {
      let step = try primaryStep(
        in: """
          \(header.rawValue)
            A
            B
          """
      )

      XCTAssertEqual(step, .south, header.rawValue)
    }
  }

  func testHonorsSemicolonTerminatedFlowchartDirections() throws {
    for direction in ImportedDirection.allCases {
      let step = try primaryStep(
        in: """
          flowchart \(direction.rawValue);
            A
            B
          """
      )

      XCTAssertEqual(step, direction.expectedStep, direction.rawValue)
    }
  }

  func testHonorsDirectionWithEachHeaderKeyword() throws {
    for header in ImportedHeader.allCases {
      for direction in ImportedDirection.allCases {
        let step = try primaryStep(
          in: """
            \(header.rawValue) \(direction.rawValue)
              A
              B
            """
        )

        XCTAssertEqual(
          step,
          direction.expectedStep,
          "\(header.rawValue) \(direction.rawValue)"
        )
      }
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

  func testRejectsTrailingFlowchartHeaderTokenWithoutSeparator() {
    let source = """
      flowchart LR unexpected
        A
      """

    XCTAssertTrue(MermaidImporter.looksLikeMermaid(source))
    XCTAssertTrue(MermaidImporter.elements(from: source, centeredAt: .zero).isEmpty)
  }

  func testRejectsUnsupportedSameLineHeaderStatements() {
    let sources = [
      """
      flowchart LR; A --> B
        C
      """,
      """
      flowchart LR;A --> B
        C
      """,
    ]

    for source in sources {
      XCTAssertTrue(MermaidImporter.looksLikeMermaid(source))
      XCTAssertTrue(MermaidImporter.elements(from: source, centeredAt: .zero).isEmpty)
    }
  }

  func testRejectsLossyPartialImports() {
    let fixtures = [
      LossyImportFixture(
        name: "style",
        source: """
          flowchart LR
            A --> B
            style A fill:#fff
          """
      ),
      LossyImportFixture(
        name: "arrow",
        source: """
          flowchart LR
            A ==> B
          """
      ),
      LossyImportFixture(
        name: "trailing syntax",
        source: """
          flowchart LR
            A[Start] trailing
          """
      ),
      LossyImportFixture(
        name: "subgraph",
        source: """
          flowchart LR
            subgraph Cluster
              A
            end
          """
      ),
    ]

    for fixture in fixtures {
      XCTAssertTrue(
        MermaidImporter.elements(from: fixture.source, centeredAt: .zero).isEmpty,
        fixture.name
      )
    }
  }

  func testReportsEveryLossyStatementInSourceOrder() {
    let report = MermaidImporter.importReport(
      from: """
        flowchart LR
          A --> B
          style A fill:#fff
          C ==> D
          E[Label] trailing
          subgraph Cluster
            F
          end
        """,
      centeredAt: .zero
    )

    XCTAssertEqual(
      report.omissions,
      [
        MermaidImportOmission(
          line: 3,
          statement: "style A fill:#fff",
          reason: .unsupportedStatement("style")
        ),
        MermaidImportOmission(
          line: 4,
          statement: "C ==> D",
          reason: .unsupportedArrow("==>")
        ),
        MermaidImportOmission(
          line: 5,
          statement: "E[Label] trailing",
          reason: .unrecognizedStatement
        ),
        MermaidImportOmission(
          line: 6,
          statement: "subgraph Cluster",
          reason: .unsupportedStatement("subgraph")
        ),
        MermaidImportOmission(
          line: 8,
          statement: "end",
          reason: .unsupportedStatement("end")
        ),
      ]
    )
    XCTAssertEqual(
      report.elements.filter { $0.content.connector == nil }.map(\.name),
      ["A", "B", "C", "D", "F"]
    )
  }

  func testReportsInvalidHeaderLocation() {
    let report = MermaidImporter.importReport(
      from: """
        ---
        title: Example
        ---
        flowchart XY
          A
        """,
      centeredAt: .zero
    )

    XCTAssertEqual(
      report.omissions,
      [
        MermaidImportOmission(
          line: 4,
          statement: "flowchart XY",
          reason: .invalidHeader
        )
      ]
    )
    XCTAssertTrue(report.elements.isEmpty)
  }

  func testReportsEachUnsupportedArrowVariant() {
    for importedArrow in UnsupportedImportedArrow.allCases {
      let arrow = importedArrow.rawValue
      let statement = "A \(arrow) B"
      let report = MermaidImporter.importReport(
        from: "flowchart LR\n  \(statement)",
        centeredAt: .zero
      )

      XCTAssertEqual(
        report.omissions,
        [
          MermaidImportOmission(
            line: 2,
            statement: statement,
            reason: .unsupportedArrow(arrow)
          )
        ],
        arrow
      )
    }
  }

  func testRejectsUnsupportedNodeDecorations() {
    for decoration in UnsupportedNodeDecoration.allCases {
      let source = "flowchart LR\n  \(decoration.rawValue)"

      XCTAssertTrue(
        MermaidImporter.elements(from: source, centeredAt: .zero).isEmpty,
        decoration.rawValue
      )
    }
  }

  func testPreservesEdgeIdentifiersAsConnectorNames() throws {
    let edgeIdentifier = "edge_one"
    let source = "flowchart LR\n  A \(edgeIdentifier)@--> B"
    let report = MermaidImporter.importReport(
      from: source,
      centeredAt: .zero
    )
    let connector = try XCTUnwrap(
      report.elements.first { $0.content.connector != nil }
    )

    XCTAssertTrue(report.omissions.isEmpty)
    XCTAssertEqual(connector.name, edgeIdentifier)
    XCTAssertEqual(
      MermaidImporter.elements(
        from: source,
        centeredAt: .zero
      ).count,
      3
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

  private func primaryStep(in source: String) throws -> SionVector {
    let nodes = MermaidImporter.elements(from: source, centeredAt: .zero)
    XCTAssertEqual(nodes.count, 2)

    let first = try XCTUnwrap(nodes.first)
    let second = try XCTUnwrap(nodes.dropFirst().first)
    return (second.geometry.frame.center - first.geometry.frame.center).normalized
  }
}

private struct LossyImportFixture {
  let name: String
  let source: String
}

private enum ImportedHeader: String, CaseIterable {
  case flowchart
  case graph
}

private enum UnsupportedImportedArrow: String, CaseIterable {
  case dotted = "-.->"
  case thick = "==>"
  case line = "---"
}

private enum UnsupportedNodeDecoration: String, CaseIterable {
  case stadium = "A([Stadium])"
  case subroutine = "A[[Subroutine]]"
  case cylinder = "A[(Cylinder)]"
  case circle = "A((Circle))"
  case hexagon = "A{{Hexagon}}"
  case parallelogram = "A[/Parallelogram/]"
  case reversedParallelogram = "A[\\Reversed\\]"
  case trapezoid = "A[/Trapezoid\\]"
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
