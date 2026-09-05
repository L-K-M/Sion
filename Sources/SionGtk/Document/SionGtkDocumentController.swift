import CGtk
import Foundation
import SionCore
import SionKit

/// Owns the open documents and their windows, tracks which is in front, and
/// opens new ones from files, Mermaid sources, or the recent list. It mirrors
/// `SionDocumentController` on macOS.
@MainActor
package final class SionGtkDocumentController {
  package private(set) var documents: [SionGtkDocument] = []
  package private(set) weak var frontDocument: SionGtkDocument?
  package let recentDocuments = SionGtkRecentDocuments()

  /// The menu model every new window shows; the application sets it.
  package var menuModel: UnsafeMutablePointer<GMenuModel>?
  /// Rewrites the shared Edit menu's undo and redo titles for the front window.
  package var updateUndoTitles: (@MainActor (_ undo: String, _ redo: String) -> Void)?
  /// Called whenever the set of documents or one of their titles changes.
  package var onDocumentsChange: (@MainActor () -> Void)?

  private let application: UnsafeMutablePointer<GtkApplication>
  private var windows: [ObjectIdentifier: SionGtkDocumentWindow] = [:]
  private var untitledCounter = 0

  package init(application: UnsafeMutablePointer<GtkApplication>) {
    self.application = application
  }

  package func window(for document: SionGtkDocument) -> SionGtkDocumentWindow? {
    windows[ObjectIdentifier(document)]
  }

  package var frontWindow: SionGtkDocumentWindow? {
    frontDocument.flatMap { window(for: $0) }
  }

  package var recentDocumentURLs: [URL] {
    recentDocuments.urls
  }

  /// A new untitled drawing in its own window.
  @discardableResult
  package func newDocument(display: Bool = true) -> SionGtkDocument {
    let document = SionGtkDocument()
    untitledCounter += 1
    document.untitledNumber = untitledCounter
    add(document, display: display)
    return document
  }

  /// Opens a drawing, or raises the window that already shows it.
  package func openDocument(at url: URL) {
    let standardized = url.standardizedFileURL
    if let existing = documents.first(where: { $0.fileURL?.standardizedFileURL == standardized }) {
      window(for: existing)?.present()
      return
    }

    let document = SionGtkDocument()
    do {
      try document.read(from: standardized)
    } catch {
      presentError(error)
      return
    }
    recentDocuments.noteOpened(standardized)
    add(document, display: true)
  }

  /// Reads the source before creating anything, so an unreadable file leaves
  /// no empty document behind.
  package func openMermaidDocument(at url: URL) {
    do {
      let source = try SionMermaidFile.source(at: url)
      makeMermaidDocument(source: source, display: true)
    } catch {
      presentError(error)
    }
  }

  /// Displaying first gives the insertion a laid-out canvas to centre on.
  @discardableResult
  package func makeMermaidDocument(source: String, display: Bool) -> SionGtkDocument {
    let document = newDocument(display: display)
    document.insertMermaid(source)
    if display {
      window(for: document)?.canvasView.zoomToFit()
    }
    return document
  }

  package func openRecentDocument(at url: URL) {
    openDocument(at: url)
  }

  package func clearRecentDocuments() {
    recentDocuments.clear()
  }

  /// Runs every document's close check in turn; any refusal stops quitting.
  package func terminate(completion: @escaping @MainActor (Bool) -> Void) {
    var pending = documents
    func closeNext() {
      guard let document = pending.popLast() else {
        completion(true)
        return
      }
      guard let window = window(for: document) else {
        closeNext()
        return
      }
      window.present()
      document.canClose { allowed in
        guard allowed else {
          completion(false)
          return
        }
        closeNext()
      }
    }
    closeNext()
  }

  private func add(_ document: SionGtkDocument, display: Bool) {
    documents.append(document)
    document.didOpenOrSave = { [weak self] url in
      self?.recentDocuments.noteOpened(url)
      self?.onDocumentsChange?()
    }
    let window = SionGtkDocumentWindow(
      document: document, application: application, menuModel: menuModel)
    windows[ObjectIdentifier(document)] = window
    window.updateUndoTitles = updateUndoTitles
    window.onBecameActive = { [weak self, weak document] in
      guard let self, let document else { return }
      self.frontDocument = document
      SionGtkPaletteCenter.shared.frontDocumentDidChange()
    }
    window.onClose = { [weak self, weak document] in
      guard let self, let document else { return }
      self.documents.removeAll { $0 === document }
      self.windows[ObjectIdentifier(document)] = nil
      if self.frontDocument === document {
        self.frontDocument = self.documents.last
      }
      SionGtkPaletteCenter.shared.frontDocumentDidChange()
      self.onDocumentsChange?()
    }
    frontDocument = document
    onDocumentsChange?()
    if display {
      window.present()
    }
  }

  private func presentError(_ error: Error) {
    SionGtkDialogs.presentError(error, parent: frontWindow?.window)
  }
}
