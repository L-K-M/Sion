#if canImport(AppKit)
  import AppKit

  @MainActor
  final class SionDocumentController: NSDocumentController {
    override var defaultType: String? {
      SionDrawingDocument.typeIdentifier
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
      SionDrawingDocument.self
    }

    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
      SionDrawingDocument()
    }

    /// Reads the source before creating anything, so an unreadable file leaves
    /// no empty document behind.
    func openMermaidDocument(at url: URL) {
      do {
        let source = try SionMermaidFile.source(at: url)
        try makeMermaidDocument(source: source, display: true)
      } catch {
        presentError(error)
      }
    }

    /// Displaying first gives the insertion a laid-out canvas to centre on.
    @discardableResult
    func makeMermaidDocument(source: String, display: Bool) throws -> SionDrawingDocument? {
      let opened = try openUntitledDocumentAndDisplay(display)
      guard let document = opened as? SionDrawingDocument else { return nil }

      document.insertMermaid(source)
      guard display else { return document }

      for case let windowController as SionDocumentWindowController in document.windowControllers {
        windowController.zoomToFit(nil)
      }
      return document
    }

    func openRecentDocument(at url: URL) {
      openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
        guard let error else {
          return
        }

        // Keep recent-file failures in AppKit's document error flow.
        self?.presentError(error)
      }
    }
  }
#endif
