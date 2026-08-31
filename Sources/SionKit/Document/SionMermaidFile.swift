#if canImport(AppKit)
  import AppKit
  import UniformTypeIdentifiers

  /// One file-facing definition of a Mermaid source file.
  enum SionMermaidFile {
    /// An imported diagram is source text; anything larger is not one.
    static let maximumByteCount = 1 << 20

    static let fileExtensions = ["mmd", "mermaid"]

    /// Declared text types plus the dynamic types unregistered extensions take.
    static var contentTypes: [UTType] {
      var types: [UTType] = [.plainText, .text]
      for fileExtension in fileExtensions {
        guard let type = UTType(filenameExtension: fileExtension) else { continue }

        types.append(type)
      }
      return types
    }

    static func makeOpenPanel() -> NSOpenPanel {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = contentTypes
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.message = MermaidFileCopy.message
      panel.prompt = MermaidFileCopy.prompt
      return panel
    }

    static func source(at url: URL) throws -> String {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard data.count <= maximumByteCount else {
        throw SionMermaidFileError.tooLarge(url)
      }
      guard let source = String(data: data, encoding: .utf8) else {
        throw SionMermaidFileError.notUTF8(url)
      }

      return source
    }
  }

  enum SionMermaidFileError: LocalizedError, Equatable {
    case notUTF8(URL)
    case tooLarge(URL)

    var errorDescription: String? {
      switch self {
      case .notUTF8(let url):
        "“\(url.lastPathComponent)” is not UTF-8 text."
      case .tooLarge(let url):
        "“\(url.lastPathComponent)” is too large to import."
      }
    }

    var recoverySuggestion: String? {
      switch self {
      case .notUTF8:
        "Save the diagram as UTF-8 Mermaid text, then import it again."
      case .tooLarge:
        "Sion imports Mermaid files up to 1 MB."
      }
    }
  }

  private enum MermaidFileCopy {
    static let message = "Choose a Mermaid file."
    static let prompt = "Import"
  }
#endif
