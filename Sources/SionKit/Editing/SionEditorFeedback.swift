import SionCore

package enum SionEditorFeedback: Equatable {
  package enum Context: Equatable {
    case mermaidSource
    case library
  }

  package enum MermaidSourcePreservation: Equatable {
    case noSupportedElements
    case omissions(firstLine: Int, count: Int)
  }

  package enum Command: Equatable {
    case importMermaid
    case pasteMermaid
  }

  /// Why a library command could not do what it was asked to.
  package enum LibraryFailure: Equatable {
    case full
    case tooLarge
    case unavailable
    case itemUnavailable
  }

  case mermaidSourcePreserved(MermaidSourcePreservation)
  case commandFailed(Command)
  case libraryCommandFailed(LibraryFailure)

  package var context: Context {
    // Paste and import share one banner slot, so a later success clears it.
    switch self {
    case .mermaidSourcePreserved, .commandFailed:
      .mermaidSource
    case .libraryCommandFailed:
      .library
    }
  }

  package var message: String {
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
    case .libraryCommandFailed(.full):
      "The library is full. Remove an item and try again."
    case .libraryCommandFailed(.tooLarge):
      "That selection is too large to keep in the library."
    case .libraryCommandFailed(.unavailable):
      "The library could not be updated. Nothing was changed."
    case .libraryCommandFailed(.itemUnavailable):
      "That library item could not be placed. The document was not changed."
    }
  }

  package static func mermaidSourcePreserved(
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

extension SionEditorFeedback.LibraryFailure {
  /// Maps what the stores throw onto what the banner can say about it.
  package init(_ error: Error) {
    guard let libraryError = error as? SceneLibraryError else {
      self = .unavailable
      return
    }

    switch libraryError {
    case .libraryIsFull:
      self = .full
    case .payloadTooLarge:
      self = .tooLarge
    case .malformedStorage, .unsupportedVersion, .duplicateItem, .itemNotFound:
      self = .unavailable
    }
  }
}

package enum SionEditorFeedbackRequest: Equatable {
  case show(SionEditorFeedback)
  case clear(SionEditorFeedback.Context)
}
