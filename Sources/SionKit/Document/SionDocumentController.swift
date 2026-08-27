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
}
