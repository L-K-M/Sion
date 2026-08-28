import Foundation

package struct MermaidImportResult: Sendable {
  package let elements: [SceneElement]
  package let omissions: [MermaidImportOmission]

  package init(elements: [SceneElement], omissions: [MermaidImportOmission]) {
    self.elements = elements
    self.omissions = omissions
  }
}

package struct MermaidImportOmission: Equatable, Sendable {
  package enum Reason: Equatable, Sendable {
    case invalidHeader
    case unsupportedArrow(String)
    case unsupportedStatement(String)
    case unrecognizedStatement
  }

  package let line: Int
  package let statement: String
  package let reason: Reason

  package init(line: Int, statement: String, reason: Reason) {
    self.line = line
    self.statement = statement
    self.reason = reason
  }
}

/// Converts Mermaid flowcharts into editable Sion elements.
public enum MermaidImporter {
  public static func looksLikeMermaid(_ source: String) -> Bool {
    diagram(in: source) != nil
  }

  /// Returns elements only when every statement can be preserved.
  public static func elements(from source: String, centeredAt origin: SionPoint) -> [SceneElement] {
    let report = importReport(from: source, centeredAt: origin)
    guard report.omissions.isEmpty else { return [] }

    return report.elements
  }

  /// Builds the supported projection and records every statement it cannot preserve.
  package static func importReport(
    from source: String,
    centeredAt origin: SionPoint
  ) -> MermaidImportResult {
    guard let diagram = diagram(in: source) else {
      return MermaidImportResult(elements: [], omissions: [])
    }
    guard let direction = diagram.direction else {
      return MermaidImportResult(
        elements: [],
        omissions: [
          MermaidImportOmission(
            line: diagram.headerLine,
            statement: diagram.header,
            reason: .invalidHeader
          )
        ]
      )
    }

    var nodes: [String: Node] = [:]
    var nodeOrder: [String] = []
    var links: [Link] = []
    var omissions: [MermaidImportOmission] = []

    // Import the graph projection; Mermaid remains a recovery format.
    for index in diagram.lines.indices {
      let rawLine = diagram.lines[index]
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix(MermaidSyntax.commentPrefix) else {
        continue
      }

      let firstToken =
        line.split(whereSeparator: \Character.isWhitespace).first?
        .lowercased() ?? ""
      if MermaidSyntax.ignoredStatements.contains(firstToken) {
        omissions.append(
          MermaidImportOmission(
            line: index + 1,
            statement: line,
            reason: .unsupportedStatement(firstToken)
          )
        )
        continue
      }

      if let parsedLink = parseLink(line) {
        merge(parsedLink.source, into: &nodes, order: &nodeOrder)
        merge(parsedLink.target, into: &nodes, order: &nodeOrder)
        links.append(
          Link(
            source: parsedLink.source.identifier,
            target: parsedLink.target.identifier,
            label: parsedLink.label
          )
        )

        if parsedLink.arrow != MermaidSyntax.supportedArrow {
          omissions.append(
            MermaidImportOmission(
              line: index + 1,
              statement: line,
              reason: .unsupportedArrow(parsedLink.arrow)
            )
          )
        }
        continue
      }

      if let node = parseNode(line) {
        merge(node, into: &nodes, order: &nodeOrder)
        continue
      }

      omissions.append(
        MermaidImportOmission(
          line: index + 1,
          statement: line,
          reason: .unrecognizedStatement
        )
      )
    }

    guard !nodeOrder.isEmpty else {
      return MermaidImportResult(elements: [], omissions: omissions)
    }

    let layout = MermaidLayout(
      nodeCount: nodeOrder.count,
      center: origin,
      direction: direction
    )
    var identifiers: [String: ElementID] = [:]
    var centers: [String: SionPoint] = [:]
    var elements: [SceneElement] = []

    for (index, nodeIdentifier) in nodeOrder.enumerated() {
      guard let node = nodes[nodeIdentifier] else {
        continue
      }

      let frame = layout.frame(at: index)
      let id = ElementID()
      var element = SceneElement.shape(
        id: id,
        frame: frame,
        kind: node.kind,
        text: node.label
      )
      element.name = node.identifier

      identifiers[nodeIdentifier] = id
      centers[nodeIdentifier] = frame.center
      elements.append(element)
    }

    for link in links {
      guard let sourceID = identifiers[link.source],
        let sourcePoint = centers[link.source],
        let targetID = identifiers[link.target],
        let targetPoint = centers[link.target]
      else {
        continue
      }

      var connector = SceneElement.connector(
        source: .element(
          sourceID,
          attachment: .automatic,
          fallbackPoint: sourcePoint
        ),
        target: .element(
          targetID,
          attachment: .automatic,
          fallbackPoint: targetPoint
        )
      )
      if let label = link.label {
        connector.content = connector.content.withConnectorLabel(label)
      }
      elements.append(connector)
    }

    return MermaidImportResult(elements: elements, omissions: omissions)
  }

  private static func diagram(in source: String) -> MermaidDiagram? {
    let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline)
    var inFrontMatter = false

    for index in lines.indices {
      let line = lines[index].trimmingCharacters(in: .whitespaces)
      if line == MermaidSyntax.frontMatterDelimiter {
        inFrontMatter.toggle()
        continue
      }
      guard !inFrontMatter, !line.isEmpty, !line.hasPrefix(MermaidSyntax.commentPrefix) else {
        continue
      }

      let tokens = line.split(whereSeparator: \Character.isWhitespace)
      guard let header = tokens.first?.lowercased(), MermaidSyntax.headers.contains(header) else {
        return nil
      }
      return MermaidDiagram(
        direction: MermaidDirection(declarationTokens: tokens.dropFirst()),
        header: line,
        headerLine: index + 1,
        lines: lines[lines.index(after: index)...]
      )
    }

    return nil
  }

  private static func parseLink(_ line: String) -> ParsedLink? {
    guard let arrow = MermaidSyntax.arrows.first(where: line.contains),
      let range = line.range(of: arrow),
      let source = parseLinkSource(String(line[..<range.lowerBound]))
    else {
      return nil
    }

    let targetFragment = String(line[range.upperBound...])
    let parsedTarget = targetAndLabel(from: targetFragment)
    guard let target = parseNode(parsedTarget.target) else {
      return nil
    }

    return ParsedLink(
      source: source,
      target: target,
      label: parsedTarget.label,
      arrow: arrow
    )
  }

  private static func parseLinkSource(_ fragment: String) -> Node? {
    let value = fragment.trimmingCharacters(in: .whitespaces)
    guard let separator = value.lastIndex(where: \Character.isWhitespace) else {
      return parseNode(value)
    }

    let edgeIdentifier = value[value.index(after: separator)...]
    guard edgeIdentifier.last == MermaidSyntax.edgeIdentifierSuffix else {
      return parseNode(value)
    }

    let identifier = edgeIdentifier.dropLast()
    guard !identifier.isEmpty, identifier.allSatisfy(\.isMermaidIdentifierCharacter) else {
      return nil
    }

    return parseNode(String(value[..<separator]))
  }

  private static func targetAndLabel(from fragment: String) -> (target: String, label: String?) {
    let value = fragment.trimmingCharacters(in: .whitespaces)
    guard value.hasPrefix("|"),
      let closing = value.dropFirst().firstIndex(of: "|")
    else {
      return (value, nil)
    }

    let labelStart = value.index(after: value.startIndex)
    let label = cleanLabel(String(value[labelStart..<closing]))
    let target = String(value[value.index(after: closing)...])
      .trimmingCharacters(in: .whitespaces)
    return (target, label.isEmpty ? nil : label)
  }

  private static func parseNode(_ fragment: String) -> Node? {
    let value = fragment.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty else {
      return nil
    }

    let identifierEnd = value.firstIndex { !$0.isMermaidIdentifierCharacter }
    guard let identifierEnd else {
      return Node(
        identifier: value,
        label: value,
        kind: .roundedRectangle(radius: MermaidLayout.cornerRadius)
      )
    }

    let identifier = String(value[..<identifierEnd])
    guard !identifier.isEmpty else {
      return nil
    }

    let decoration = String(value[identifierEnd...]).trimmingCharacters(in: .whitespaces)
    guard !decoration.isEmpty else {
      return Node(
        identifier: identifier,
        label: identifier,
        kind: .roundedRectangle(radius: MermaidLayout.cornerRadius)
      )
    }
    guard !UnsupportedNodeDecoration.hasPrefix(in: decoration) else {
      return nil
    }
    guard let delimiters = delimiters(for: decoration.first) else {
      return nil
    }

    guard let closingIndex = decoration.lastIndex(of: delimiters.close) else {
      return nil
    }
    let trailing = decoration[decoration.index(after: closingIndex)...]
      .trimmingCharacters(in: .whitespaces)
    guard trailing.isEmpty else {
      return nil
    }

    let labelStart = decoration.index(after: decoration.startIndex)
    let label = cleanLabel(String(decoration[labelStart..<closingIndex]))
    return Node(
      identifier: identifier,
      label: label.isEmpty ? identifier : label,
      kind: delimiters.kind
    )
  }

  private static func delimiters(
    for first: Character?
  ) -> (close: Character, kind: ShapeKind)? {
    switch first {
    case "[":
      return ("]", .rectangle)
    case "(":
      return (")", .roundedRectangle(radius: MermaidLayout.pillRadius))
    case "{":
      return ("}", .diamond)
    default:
      return nil
    }
  }

  private static func cleanLabel(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespaces)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      .replacingOccurrences(of: "<br>", with: "\n")
      .replacingOccurrences(of: "<br/>", with: "\n")
  }

  private static func merge(
    _ node: Node,
    into nodes: inout [String: Node],
    order: inout [String]
  ) {
    guard let existing = nodes[node.identifier] else {
      nodes[node.identifier] = node
      order.append(node.identifier)
      return
    }

    if existing.label == existing.identifier, node.label != node.identifier {
      nodes[node.identifier] = node
    }
  }
}

private struct Node {
  let identifier: String
  let label: String
  let kind: ShapeKind
}

private struct ParsedLink {
  let source: Node
  let target: Node
  let label: String?
  let arrow: String
}

private struct Link {
  let source: String
  let target: String
  let label: String?
}

private struct MermaidDiagram {
  let direction: MermaidDirection?
  let header: String
  let headerLine: Int
  let lines: ArraySlice<Substring>
}

private enum MermaidDirection {
  case topToBottom
  case bottomToTop
  case leftToRight
  case rightToLeft

  init?(declarationTokens: ArraySlice<Substring>) {
    guard let firstToken = declarationTokens.first else {
      self = .topToBottom
      return
    }

    guard declarationTokens.dropFirst().isEmpty else {
      return nil
    }

    let directionToken =
      firstToken.last == MermaidSyntax.statementSeparator ? firstToken.dropLast() : firstToken[...]
    switch directionToken.lowercased() {
    case "tb", "td":
      self = .topToBottom
    case "bt":
      self = .bottomToTop
    case "lr":
      self = .leftToRight
    case "rl":
      self = .rightToLeft
    default:
      return nil
    }
  }

  var primaryStep: SionVector {
    switch self {
    case .topToBottom:
      return .south
    case .bottomToTop:
      return .north
    case .leftToRight:
      return .east
    case .rightToLeft:
      return .west
    }
  }

  var axis: MermaidLayoutAxis {
    switch self {
    case .topToBottom, .bottomToTop:
      return .vertical
    case .leftToRight, .rightToLeft:
      return .horizontal
    }
  }
}

private enum MermaidLayoutAxis {
  case horizontal
  case vertical
}

private enum MermaidSyntax {
  static let headers = Set(["flowchart", "graph"])
  static let arrows = MermaidArrow.allCases.map(\.rawValue)
  static let edgeIdentifierSuffix: Character = "@"
  static let supportedArrow = MermaidArrow.solid.rawValue
  static let commentPrefix = "%%"
  static let frontMatterDelimiter = "---"
  static let statementSeparator: Character = ";"
  static let ignoredStatements = Set([
    "classdef", "class", "click", "direction", "end", "linkstyle", "style", "subgraph",
  ])
}

private enum MermaidArrow: String, CaseIterable {
  case dotted = "-.->"
  case solid = "-->"
  case thick = "==>"
  case line = "---"
}

private enum UnsupportedNodeDecoration: String, CaseIterable {
  case stadium = "(["
  case subroutine = "[["
  case cylinder = "[("
  case circle = "(("
  case hexagon = "{{"
  case parallelogramOrTrapezoid = "[/"
  case reversedParallelogramOrTrapezoid = "[\\"

  static func hasPrefix(in decoration: String) -> Bool {
    allCases.contains { decoration.hasPrefix($0.rawValue) }
  }
}

extension Character {
  fileprivate var isMermaidIdentifierCharacter: Bool {
    isLetter || isNumber || self == "_" || self == "-"
  }
}

private struct MermaidLayout {
  static let primarySlotCount = 3
  static let nodeWidth = 160.0
  static let nodeHeight = 88.0
  static let horizontalStep = 220.0
  static let verticalStep = 152.0
  static let cornerRadius = 12.0
  static let pillRadius = 24.0

  private let nodeCount: Int
  private let center: SionPoint
  private let direction: MermaidDirection

  init(nodeCount: Int, center: SionPoint, direction: MermaidDirection) {
    self.nodeCount = nodeCount
    self.center = center
    self.direction = direction
  }

  func frame(at index: Int) -> SionRect {
    // Preserve source order along the declared axis pending topology-aware ranking.
    let primaryCount = min(Self.primarySlotCount, nodeCount)
    let secondaryCount = Int(ceil(Double(nodeCount) / Double(Self.primarySlotCount)))
    let primaryIndex = index % Self.primarySlotCount
    let secondaryIndex = index / Self.primarySlotCount
    let primaryOffset = centeredOffset(index: primaryIndex, count: primaryCount)
    let secondaryOffset = centeredOffset(index: secondaryIndex, count: secondaryCount)
    let nodeCenter =
      center
      + (direction.primaryStep * primaryOffset * primarySpacing)
      + (secondaryStep * secondaryOffset * secondarySpacing)

    return SionRect(
      x: nodeCenter.x - (Self.nodeWidth / 2),
      y: nodeCenter.y - (Self.nodeHeight / 2),
      width: Self.nodeWidth,
      height: Self.nodeHeight
    )
  }

  private var primarySpacing: Double {
    switch direction.axis {
    case .horizontal:
      return Self.horizontalStep
    case .vertical:
      return Self.verticalStep
    }
  }

  private var secondarySpacing: Double {
    switch direction.axis {
    case .horizontal:
      return Self.verticalStep
    case .vertical:
      return Self.horizontalStep
    }
  }

  private var secondaryStep: SionVector {
    switch direction.axis {
    case .horizontal:
      return .south
    case .vertical:
      return .east
    }
  }

  private func centeredOffset(index: Int, count: Int) -> Double {
    Double(index) - (Double(count - 1) / 2)
  }
}

extension ElementContent {
  fileprivate func withConnectorLabel(_ label: String) -> ElementContent {
    guard var connector else {
      return self
    }

    connector.label = TextContent(string: label, style: .shapeLabelDefault)
    return .connector(connector)
  }
}
