import Foundation

public struct MermaidExport: Equatable, Sendable {
  public let source: String
  public let coverage: MermaidCoverage
  public let omissions: [MermaidOmission]

  public init(
    source: String,
    coverage: MermaidCoverage,
    omissions: [MermaidOmission] = []
  ) {
    self.source = source
    self.coverage = coverage
    self.omissions = omissions
  }
}

public struct MermaidOmission: Equatable, Sendable {
  public let kind: MermaidOmissionKind
  public let count: Int

  public init(kind: MermaidOmissionKind, count: Int) {
    self.kind = kind
    self.count = count
  }
}

public enum MermaidOmissionKind: String, Hashable, Sendable {
  case connector
  case group
  case image
  case path
  case shape
  case text
}

/// Projects diagram semantics into a recoverable Mermaid flowchart.
public enum MermaidExporter {
  public static func export(document: SionDocument) -> MermaidExport {
    let visible = document.scene.elements.filter { $0.visibility == .visible }
    let nodes = visible.filter(\.isMermaidNode)
    let nodeIDs = Set(nodes.map(\.id))
    let connectors = visible.compactMap { element -> (SceneElement, ConnectorContent)? in
      guard case .connector(let content) = element.content else {
        return nil
      }

      return (element, content)
    }

    let edges = connectors.compactMap { element, connector -> String? in
      guard let sourceID = connector.source.elementID,
        let targetID = connector.target.elementID,
        nodeIDs.contains(sourceID),
        nodeIDs.contains(targetID)
      else {
        return nil
      }

      let edgeID = mermaidID(prefix: "edge", id: element.id)
      let label = connector.label?.string.nonempty.map { "|\(quoted($0))|" } ?? ""
      return "  \(nodeID(sourceID)) \(edgeID)@-->\(label) \(nodeID(targetID))"
    }

    let unsupported = visible.filter { element in
      if element.isMermaidNode {
        return false
      }

      guard case .connector(let connector) = element.content else {
        return true
      }

      guard let sourceID = connector.source.elementID,
        let targetID = connector.target.elementID
      else {
        return true
      }

      return !nodeIDs.contains(sourceID) || !nodeIDs.contains(targetID)
    }

    var lines = ["flowchart TB"]
    for element in unsupported {
      lines.append("  %% Omitted Sion \(element.content.mermaidKind.rawValue): \(element.id)")
    }
    lines.append(contentsOf: nodes.map(nodeDeclaration))
    lines.append(contentsOf: edges)

    let coverage: MermaidCoverage
    if unsupported.isEmpty {
      coverage = .complete
    } else if nodes.isEmpty, edges.isEmpty {
      coverage = .none
    } else {
      coverage = .partial
    }

    let omissions = Dictionary(grouping: unsupported, by: { $0.content.mermaidKind })
      .map { MermaidOmission(kind: $0.key, count: $0.value.count) }
      .sorted { $0.kind.rawValue < $1.kind.rawValue }
    return MermaidExport(
      source: lines.joined(separator: "\n") + "\n",
      coverage: coverage,
      omissions: omissions
    )
  }

  private static func nodeDeclaration(_ element: SceneElement) -> String {
    let id = nodeID(element.id)
    let label = quoted(element.mermaidLabel.nonempty ?? " ")

    switch element.content {
    case .shape(let shape):
      let brackets = brackets(for: shape.kind)
      return "  \(id)\(brackets.open)\(label)\(brackets.close)"
    case .text:
      return "  \(id)[\(label)]"
    case .path, .image, .group, .connector:
      preconditionFailure("Only Mermaid nodes reach nodeDeclaration(_:).")
    }
  }

  private static func brackets(for kind: ShapeKind) -> (open: String, close: String) {
    switch kind {
    case .roundedRectangle, .capsule:
      return ("(", ")")
    case .ellipse:
      return ("((", "))")
    case .diamond:
      return ("{", "}")
    case .hexagon:
      return ("{{", "}}")
    case .cylinder:
      return ("[(", ")]")
    case .rectangle, .triangle, .custom:
      return ("[", "]")
    }
  }

  private static func nodeID(_ id: ElementID) -> String {
    mermaidID(prefix: "node", id: id)
  }

  private static func mermaidID(prefix: String, id: ElementID) -> String {
    "\(prefix)_\(id.description.replacingOccurrences(of: "-", with: "_"))"
  }

  private static func quoted(_ value: String) -> String {
    let normalized =
      value
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let safe = normalized.unicodeScalars.map { scalar in
      MermaidScalar.isAllowed(scalar) ? String(scalar) : MermaidScalar.replacement
    }.joined()
    let encoded =
      safe
      .replacingOccurrences(of: "#", with: "#35;")
      .replacingOccurrences(of: "&", with: "#38;")
      .replacingOccurrences(of: "\"", with: "#quot;")
      .replacingOccurrences(of: "\n", with: "<br>")

    return "\"\(encoded)\""
  }
}

private enum MermaidScalar {
  static let replacement = "\u{FFFD}"

  static func isAllowed(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A:
      return true
    case 0x00...0x1F, 0x7F...0x9F:
      return false
    default:
      return true
    }
  }
}

extension SceneElement {
  fileprivate var isMermaidNode: Bool {
    switch content {
    case .shape, .text:
      return true
    case .path, .image, .group, .connector:
      return false
    }
  }

  fileprivate var mermaidLabel: String {
    switch content {
    case .shape(let shape):
      return shape.label?.string ?? name ?? ""
    case .text(let text):
      return text.string
    case .path, .image, .group, .connector:
      return name ?? ""
    }
  }
}

extension ElementContent {
  fileprivate var mermaidKind: MermaidOmissionKind {
    switch self {
    case .shape:
      return .shape
    case .path:
      return .path
    case .text:
      return .text
    case .image:
      return .image
    case .group:
      return .group
    case .connector:
      return .connector
    }
  }
}

extension String {
  fileprivate var nonempty: String? {
    isEmpty ? nil : self
  }
}
