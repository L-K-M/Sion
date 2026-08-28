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
