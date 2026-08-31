#if canImport(AppKit)
  import Foundation
  import SionCore

  /// One Mermaid insertion policy shared by every command that offers it.
  @MainActor
  enum SionMermaidInsertion {
    enum Origin {
      case paste
      case file

      var undoActionName: String {
        switch self {
        case .paste: "Paste Mermaid"
        case .file: "Import Mermaid"
        }
      }

      fileprivate var failure: SionEditorFeedback.Command {
        switch self {
        case .paste: .pasteMermaid
        case .file: .importMermaid
        }
      }
    }

    /// Inserts the diagram as one undoable command and reports what was kept.
    @discardableResult
    static func insert(
      _ source: String,
      at point: SionPoint,
      origin: Origin,
      using editorController: SionEditorController,
      feedback: @MainActor (SionEditorFeedbackRequest) -> Void
    ) -> SionEditorController.MermaidInsertionResult? {
      do {
        let result = try editorController.insertMermaid(
          source,
          at: point,
          actionName: origin.undoActionName
        )
        switch result {
        case .diagram:
          feedback(.clear(.mermaidSource))
        case .sourceText(_, let omissions):
          feedback(.show(.mermaidSourcePreserved(omissions: omissions)))
        }
        return result
      } catch {
        NSLog("Mermaid insertion failed: %@", String(describing: error))
        feedback(.show(.commandFailed(origin.failure)))
        return nil
      }
    }
  }
#endif
