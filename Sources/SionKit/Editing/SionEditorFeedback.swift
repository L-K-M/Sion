#if canImport(AppKit)
  import SionCore

  enum SionEditorFeedback: Equatable {
    enum Context: Equatable {
      case mermaidSource
    }

    enum MermaidSourcePreservation: Equatable {
      case noSupportedElements
      case omissions(firstLine: Int, count: Int)
    }

    enum Command: Equatable {
      case importMermaid
      case pasteMermaid
    }

    case mermaidSourcePreserved(MermaidSourcePreservation)
    case commandFailed(Command)

    var context: Context {
      // Paste and import share one banner slot, so a later success clears it.
      switch self {
      case .mermaidSourcePreserved, .commandFailed:
        .mermaidSource
      }
    }

    var message: String {
      switch self {
      case .mermaidSourcePreserved(.noSupportedElements):
        "Mermaid contained no supported elements. The source was kept as text."
      case .mermaidSourcePreserved(.omissions(let firstLine, let count)):
        if count == 1 {
          "Mermaid line \(firstLine) is unsupported. The source was kept as text."
        } else {
          "Mermaid has \(count) unsupported items, first on line \(firstLine). "
            + "The source was kept as text."
        }
      case .commandFailed(.pasteMermaid):
        "Mermaid could not be pasted. The document was not changed."
      case .commandFailed(.importMermaid):
        "Mermaid could not be imported. The document was not changed."
      }
    }

    static func mermaidSourcePreserved(
      omissions: [MermaidImportOmission]
    ) -> SionEditorFeedback {
      guard let firstOmission = omissions.first else {
        return .mermaidSourcePreserved(.noSupportedElements)
      }

      return .mermaidSourcePreserved(
        .omissions(firstLine: firstOmission.line, count: omissions.count)
      )
    }
  }

  enum SionEditorFeedbackRequest: Equatable {
    case show(SionEditorFeedback)
    case clear(SionEditorFeedback.Context)
  }
#endif
