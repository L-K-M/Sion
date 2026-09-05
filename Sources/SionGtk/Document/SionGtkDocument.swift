import CGtk
import Foundation
import SionCore
import SionKit

enum MermaidExportWarning: Equatable {
  case partial
  case nothingRepresentable

  init?(coverage: MermaidCoverage) {
    switch coverage {
    case .complete:
      return nil
    case .partial:
      self = .partial
    case .none:
      self = .nothingRepresentable
    }
  }

  var messageText: String {
    switch self {
    case .partial:
      return "Mermaid will omit content"
    case .nothingRepresentable:
      return "Mermaid cannot represent this drawing"
    }
  }

  func informativeText(for omissions: [MermaidOmission]) -> String {
    let summary = omissions.map { omission in
      let suffix = omission.count == 1 ? "" : "s"
      return "\(omission.count) \(omission.kind.rawValue)\(suffix)"
    }.joined(separator: ", ")
    let omissionList = summary.isEmpty ? "unspecified content" : summary

    switch self {
    case .partial:
      return "Unsupported visible content will be omitted: \(omissionList)."
    case .nothingRepresentable:
      return "The file will contain omission comments only: \(omissionList)."
    }
  }
}

/// One open drawing: the editor controller, its undo manager, the file it was
/// read from, and the commands that read or write archives and exports. It
/// mirrors `SionDrawingDocument`, including autosave in place: an edited
/// document that has a file writes itself back a moment after the last change
/// and closes without asking, while an untitled one asks first.
@MainActor
package final class SionGtkDocument {
  package static let typeIdentifier = "ch.lkmc.sion.document"
  package static let mimeType = "application/vnd.lkmc.sion+zip"
  package static let filenameExtension = "sion"
  package static let typeName = "Sion Drawing"

  package let undoManager = SionUndoManager()
  package let printOperation = SionGtkPrintOperation()
  package private(set) var fileURL: URL?
  package private(set) weak var window: SionGtkDocumentWindow?
  package var untitledNumber = 1

  /// Reports a saved, reverted, or edited state so windows can retitle.
  package var onStateChange: (@MainActor () -> Void)?
  /// Reports that the file list of the application should record this URL.
  package var didOpenOrSave: (@MainActor (URL) -> Void)?

  private var initialPackage = SionPackage()
  private var editingControllerStorage: SionEditorController?
  private var sceneRendererStorage: SionGtkSceneRenderer?
  private var changeCount = 0
  private var lastSavedPackage: SionPackage?
  private var hasAutosavedSinceManualSave = false
  private var autosaveSource: guint = 0
  private let archiveGenerator: SionArchiveGenerator

  package init(archiveGenerator: SionArchiveGenerator = SionGtkResources.archiveGenerator) {
    self.archiveGenerator = archiveGenerator
  }

  package var editingController: SionEditorController {
    if let editingControllerStorage {
      return editingControllerStorage
    }

    guard
      let controller = try? SionEditorController(
        package: initialPackage,
        undoManagerProvider: { [weak self] in self?.undoManager },
        didChange: { [weak self] change in
          self?.recordEditorChange(change)
        }
      )
    else {
      preconditionFailure("The empty Sion document must validate")
    }
    editingControllerStorage = controller
    return controller
  }

  package var isDocumentEdited: Bool {
    changeCount != 0
  }

  /// The title without the owned extension, for window titles and exports.
  package var displayName: String {
    if let fileURL {
      return fileURL.deletingPathExtension().lastPathComponent
    }
    return untitledNumber > 1
      ? "\(SionDocument.untitledName) \(untitledNumber)" : SionDocument.untitledName
  }

  package func attach(window: SionGtkDocumentWindow) {
    self.window = window
  }

  // MARK: Reading and writing

  package func read(from url: URL) throws {
    let data = try Data(contentsOf: url)
    let package = try SionArchive.decode(data)
    window?.discardPendingEdits()
    if let editingControllerStorage {
      try editingControllerStorage.load(package)
    } else {
      initialPackage = package
    }
    fileURL = url
    lastSavedPackage = package
    changeCount = 0
    hasAutosavedSinceManualSave = false
    onStateChange?()
  }

  /// Encodes the archive the way `data(ofType:)` does on macOS.
  private func archive(intent: SaveIntent, savedTitle: String?) throws -> EncodedSionArchive {
    window?.checkpointPendingEdits()

    // The preview pipeline only runs here: edits invalidate it, and the
    // window's canvas re-renders it on demand.
    if !editingController.document.scene.elements.isEmpty,
      !editingController.hasPreviewPNG,
      let preview = window?.renderPreviewPNG()
    {
      editingController.setPreviewPNG(preview)
    }

    var package = editingController.packageForArchiving()
    if let savedTitle {
      package.document.title = savedTitle
    }

    return try SionArchive.encode(package: package, intent: intent, generator: archiveGenerator)
  }

  private func write(to url: URL, intent: SaveIntent) throws {
    let savedTitle: String? = {
      let title = url.deletingPathExtension().lastPathComponent
      return title.isEmpty ? nil : title
    }()
    let encoded = try archive(intent: intent, savedTitle: savedTitle)
    try encoded.data.write(to: url, options: .atomic)
    editingController.commitArchivedHistory(encoded.committedHistory)
    fileURL = url
    changeCount = 0

    switch intent {
    case .autosave:
      hasAutosavedSinceManualSave = true
    case .manual, .saveAs:
      hasAutosavedSinceManualSave = false
      lastSavedPackage = editingController.packageForArchiving()
    }
    cancelAutosave()
    didOpenOrSave?(url)
    onStateChange?()
  }

  /// Save writes in place; a document without a file asks where.
  package func save(completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
    guard let fileURL else {
      saveAs(completion: completion)
      return
    }

    do {
      try write(to: fileURL, intent: .manual)
      completion(true)
    } catch {
      presentError(error)
      completion(false)
    }
  }

  package func saveAs(completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
    window?.commitPendingEdits()
    SionGtkDialogs.save(
      title: "Save As",
      suggestedName: "\(displayName).\(Self.filenameExtension)",
      initialFolder: fileURL?.deletingLastPathComponent(),
      filters: [Self.fileFilter],
      parent: window?.toplevel
    ) { [weak self] url in
      guard let self, let url else {
        completion(false)
        return
      }

      var destination = url
      if destination.pathExtension.lowercased() != Self.filenameExtension {
        destination.appendPathExtension(Self.filenameExtension)
      }
      do {
        try self.write(to: destination, intent: .saveAs)
        completion(true)
      } catch {
        self.presentError(error)
        completion(false)
      }
    }
  }

  package var canRevert: Bool {
    fileURL != nil && lastSavedPackage != nil && (isDocumentEdited || hasAutosavedSinceManualSave)
  }

  /// Returns to the last version the user saved or opened, and writes it back
  /// so autosave has not left a newer state in the file.
  package func revertToSaved() {
    guard canRevert, let package = lastSavedPackage else { return }

    SionGtkDialogs.alert(
      heading: "Do you want to revert to the most recently saved version of “\(displayName)”?",
      body: "Your current changes will be lost.",
      responses: [
        .init("Cancel"),
        .init("Revert", appearance: .destructive),
      ],
      defaultResponse: 0,
      parent: window?.window
    ) { [weak self] response in
      guard let self, response == 1 else { return }

      do {
        self.window?.discardPendingEdits()
        try self.editingController.load(package)
        self.undoManager.removeAllActions()
        self.changeCount = 0
        if let fileURL = self.fileURL, self.hasAutosavedSinceManualSave {
          try self.write(to: fileURL, intent: .manual)
        }
        self.hasAutosavedSinceManualSave = false
        self.onStateChange?()
      } catch {
        self.presentError(error)
      }
    }
  }

  /// Asks about unsaved work the way AppKit does for an untitled document; a
  /// document with a file autosaves and closes.
  package func canClose(completion: @escaping @MainActor (Bool) -> Void) {
    window?.commitPendingEdits()
    guard isDocumentEdited else {
      completion(true)
      return
    }

    if let fileURL {
      do {
        try write(to: fileURL, intent: .autosave)
        completion(true)
      } catch {
        presentError(error)
        completion(false)
      }
      return
    }

    SionGtkDialogs.alert(
      heading: "Do you want to save the changes made to the document “\(displayName)”?",
      body: "Your changes will be lost if you don’t save them.",
      responses: [
        .init("Cancel"),
        .init("Delete", appearance: .destructive),
        .init("Save…", appearance: .suggested),
      ],
      defaultResponse: 2,
      parent: window?.window
    ) { [weak self] response in
      switch response {
      case 2:
        self?.save(completion: completion)
      case 1:
        completion(true)
      default:
        completion(false)
      }
    }
  }

  package func close() {
    cancelAutosave()
    sceneRendererStorage?.invalidate()
    sceneRendererStorage = nil
  }

  // MARK: Export and import

  /// Renders scene content for print and image export without needing a
  /// window, so the on-screen canvas keeps its own interaction state.
  private var sceneRenderer: SionGtkSceneRenderer {
    if let sceneRendererStorage, sceneRendererStorage.editorController === editingController {
      return sceneRendererStorage
    }

    sceneRendererStorage?.invalidate()
    let renderer = SionGtkSceneRenderer(editorController: editingController)
    sceneRendererStorage = renderer
    return renderer
  }

  package func exportImage() {
    window?.commitPendingEdits()
    SionGtkImageExportOptionsDialog.present(
      initial: SionImageExportOptions(), parent: window?.window
    ) { [weak self] options in
      guard let self, let options else { return }

      SionGtkDialogs.save(
        title: "Export Image",
        suggestedName: self.exportFilename(extension: options.format.fileExtension),
        initialFolder: self.fileURL?.deletingLastPathComponent(),
        filters: [
          .init(
            name: options.format.title,
            mimeTypes: [options.format.mimeType],
            suffixes: [options.format.fileExtension]
          )
        ],
        parent: self.window?.toplevel
      ) { [weak self] url in
        guard let self, let url else { return }

        do {
          let data = try self.imageExportData(options: options)
          try data.write(to: url, options: .atomic)
        } catch {
          self.presentError(error)
        }
      }
    }
  }

  /// Encodes export data with no dialog, so formats stay testable headlessly.
  package func imageExportData(options: SionImageExportOptions) throws -> Data {
    window?.commitPendingEdits()

    return try SionGtkSceneImageExporter.data(options: options, renderer: sceneRenderer)
  }

  package func exportSVG() {
    window?.commitPendingEdits()

    do {
      let package = editingController.packageForArchiving()
      let source = try SVGExporter.export(document: package.document, assets: package.assets)
      presentExportDialog(
        title: "Export SVG",
        suggestedFilename: exportFilename(extension: "svg"),
        filter: .init(name: "SVG Image", mimeTypes: ["image/svg+xml"], suffixes: ["svg"]),
        data: Data(source.utf8)
      )
    } catch {
      presentError(error)
    }
  }

  package func exportMermaid() {
    window?.commitPendingEdits()

    let export = MermaidExporter.export(document: editingController.document)
    guard let warning = MermaidExportWarning(coverage: export.coverage) else {
      presentMermaidExportDialog(export)
      return
    }

    SionGtkDialogs.alert(
      heading: warning.messageText,
      body: warning.informativeText(for: export.omissions),
      responses: [.init("Cancel"), .init("Export Anyway", appearance: .suggested)],
      defaultResponse: 0,
      parent: window?.window
    ) { [weak self] response in
      guard response == 1 else { return }

      self?.presentMermaidExportDialog(export)
    }
  }

  private func presentMermaidExportDialog(_ export: MermaidExport) {
    presentExportDialog(
      title: "Export Mermaid",
      suggestedFilename: exportFilename(extension: "mmd"),
      filter: Self.mermaidFilter,
      data: Data(export.source.utf8)
    )
  }

  private func presentExportDialog(
    title: String,
    suggestedFilename: String,
    filter: SionGtkDialogs.FileFilter,
    data: Data
  ) {
    SionGtkDialogs.save(
      title: title,
      suggestedName: suggestedFilename,
      initialFolder: fileURL?.deletingLastPathComponent(),
      filters: [filter],
      parent: window?.toplevel
    ) { [weak self] url in
      guard let url else { return }

      do {
        try data.write(to: url, options: .atomic)
      } catch {
        self?.presentError(error)
      }
    }
  }

  package func importMermaid() {
    window?.commitPendingEdits()
    SionGtkDialogs.open(
      title: MermaidFileCopy.message,
      acceptLabel: MermaidFileCopy.prompt,
      filters: [Self.mermaidFilter],
      parent: window?.toplevel
    ) { [weak self] url in
      guard let self, let url else { return }

      do {
        try self.importMermaid(contentsOf: url)
      } catch {
        self.presentError(error)
      }
    }
  }

  /// Reads a Mermaid file and inserts it as one undoable command.
  @discardableResult
  package func importMermaid(contentsOf url: URL) throws -> SionEditorController
    .MermaidInsertionResult?
  {
    insertMermaid(try SionMermaidFile.source(at: url))
  }

  @discardableResult
  package func insertMermaid(_ source: String) -> SionEditorController.MermaidInsertionResult? {
    window?.commitPendingEdits()

    return SionMermaidInsertion.insert(
      source,
      at: mermaidInsertionCenter,
      origin: .file,
      using: editingController,
      feedback: { [weak self] in self?.presentEditorFeedback($0) }
    )
  }

  /// The visible canvas centre when a window exists, and the canvas centre
  /// otherwise, so an import into a windowless document still lands on paper.
  private var mermaidInsertionCenter: SionPoint {
    window?.canvasVisibleCenter ?? editingController.defaultInsertionCenter
  }

  package func presentEditorFeedback(_ request: SionEditorFeedbackRequest) {
    window?.presentEditorFeedback(request)
  }

  // MARK: Printing

  package func printDocument() {
    window?.commitPendingEdits()
    let renderer = sceneRenderer
    printOperation.print(
      jobTitle: displayName,
      contentBounds: renderer.contentBounds,
      draw: renderer.sceneDrawing,
      parent: window?.toplevel
    ) { [weak self] error in
      if let error {
        self?.presentError(error)
      }
    }
  }

  package func pageSetup() {
    printOperation.runPageSetup(parent: window?.toplevel)
  }

  // MARK: Helpers

  package static let fileFilter = SionGtkDialogs.FileFilter(
    name: typeName, mimeTypes: [mimeType], suffixes: [filenameExtension])

  package static let mermaidFilter = SionGtkDialogs.FileFilter(
    name: "Mermaid Diagram",
    mimeTypes: ["text/plain", "text/vnd.mermaid"],
    suffixes: SionMermaidFile.fileExtensions
  )

  package func presentError(_ error: Error) {
    SionGtkDialogs.presentError(error, parent: window?.window)
  }

  private func exportFilename(extension fileExtension: String) -> String {
    "\(displayName).\(fileExtension)"
  }

  private func recordEditorChange(_ change: SionEditorController.DocumentChange) {
    switch change {
    case .done, .redone:
      changeCount += 1
    case .undone:
      changeCount -= 1
    }
    scheduleAutosave()
    onStateChange?()
  }

  /// Autosave in place: a document with a file writes itself back once the
  /// edits pause, so closing never has to ask.
  private func scheduleAutosave() {
    cancelAutosave()
    guard fileURL != nil, isDocumentEdited else { return }

    autosaveSource = MainLoop.perform(after: Self.autosaveDelay) { [weak self] in
      guard let self else { return }
      self.autosaveSource = 0
      guard let fileURL = self.fileURL, self.isDocumentEdited else { return }
      guard !self.editingController.hasPendingEditorGesture else {
        self.scheduleAutosave()
        return
      }
      try? self.write(to: fileURL, intent: .autosave)
    }
  }

  private func cancelAutosave() {
    MainLoop.cancel(autosaveSource)
    autosaveSource = 0
  }

  private static let autosaveDelay = 5.0
}
