import Foundation

#if canImport(AppKit)
  import AppKit
  import UniformTypeIdentifiers
#endif

/// One file-facing definition of a Mermaid source file.
package enum SionMermaidFile {
  /// An imported diagram is source text; anything larger is not one.
  package static let maximumByteCount = 1 << 20

  package static let fileExtensions = ["mmd", "mermaid"]

  #if canImport(AppKit)
    /// Declared text types plus the dynamic types unregistered extensions take.
    /// Resolving them queries Launch Services, which cannot change in-process.
    static let contentTypes: [UTType] =
      [.plainText, .text] + fileExtensions.compactMap { UTType(filenameExtension: $0) }

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
  #endif

  package static func source(at url: URL) throws -> String {
    // Probe first: a mapped read of an oversized or truncated file can fault
    // long after the cap would have rejected it.
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    guard (values.fileSize ?? 0) <= maximumByteCount else {
      throw SionMermaidFileError.tooLarge(url)
    }

    let data = try Data(contentsOf: url)
    guard data.count <= maximumByteCount else {
      throw SionMermaidFileError.tooLarge(url)
    }
    guard let source = String(data: data, encoding: .utf8) else {
      throw SionMermaidFileError.notUTF8(url)
    }

    return source
  }
}

package enum SionMermaidFileError: LocalizedError, Equatable {
  case notUTF8(URL)
  case tooLarge(URL)

  package var errorDescription: String? {
    switch self {
    case .notUTF8(let url):
      "“\(url.lastPathComponent)” is not UTF-8 text."
    case .tooLarge(let url):
      "“\(url.lastPathComponent)” is too large to import."
    }
  }

  package var recoverySuggestion: String? {
    switch self {
    case .notUTF8:
      "Save the diagram as UTF-8 Mermaid text, then import it again."
    case .tooLarge:
      "Sion imports Mermaid files up to 1 MB."
    }
  }
}

/// The file chooser copy both native applications show.
package enum MermaidFileCopy {
  package static let message = "Choose a Mermaid file."
  package static let prompt = "Import"
}
