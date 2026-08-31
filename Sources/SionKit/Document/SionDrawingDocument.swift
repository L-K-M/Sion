#if canImport(AppKit)
  import AppKit
  import SionCore
  import UniformTypeIdentifiers

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

  @MainActor
  /// Bridges AppKit document lifecycle to Sion's validated recovery archive.
  public final class SionDrawingDocument: NSDocument {
    public static let typeIdentifier = "ch.lkmc.sion.document"

    private var initialPackage = SionPackage()
    private var editingControllerStorage: SionEditorController?
    private var sceneRendererStorage: SionSceneRenderer?
    private var pendingSaveIntent = SaveIntent.manual
    private var pendingSavedTitle: String?
    private var stagedHistory: DocumentHistory?
    private let archiveGenerator: SionArchiveGenerator

    var editingController: SionEditorController {
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

    public override init() {
      archiveGenerator = ApplicationArchiveMetadata(bundle: .main).archiveGenerator
      super.init()

      hasUndoManager = true
    }

    package init(archiveGenerator: SionArchiveGenerator) {
      self.archiveGenerator = archiveGenerator
      super.init()

      hasUndoManager = true
    }

    public override class var autosavesInPlace: Bool { true }

    /// The filename extension owned by Sion's exported document type.
    public static let filenameExtension = "sion"

    public override func updateChangeCount(_ change: NSDocument.ChangeType) {
      switch change {
      case .changeDone, .changeUndone, .changeRedone:
        // The editor records these while an edit is live; ignore AppKit's later duplicate.
        return
      default:
        super.updateChangeCount(change)
      }
    }

    public override func makeWindowControllers() {
      let controller = SionDocumentWindowController(editorController: editingController)
      addWindowController(controller)
    }

    public override func canClose(
      withDelegate delegate: Any,
      shouldClose shouldCloseSelector: Selector?,
      contextInfo: UnsafeMutableRawPointer?
    ) {
      commitPendingWindowEdits()
      super.canClose(
        withDelegate: delegate,
        shouldClose: shouldCloseSelector,
        contextInfo: contextInfo
      )
    }

    public override func close() {
      sceneRendererStorage?.invalidate()
      sceneRendererStorage = nil
      super.close()
    }

    /// Renders scene content for print and image export without needing a
    /// window, so the on-screen canvas keeps its own interaction state.
    private var sceneRenderer: SionSceneRenderer {
      if let sceneRendererStorage {
        return sceneRendererStorage
      }

      let renderer = SionSceneRenderer(editorController: editingController)
      sceneRendererStorage = renderer
      return renderer
    }

    public override func data(ofType typeName: String) throws -> Data {
      for case let windowController as SionDocumentWindowController in windowControllers {
        windowController.checkpointPendingEdits()
      }

      // The preview pipeline only runs here: edits invalidate it, and the
      // first window's canvas re-renders it on demand.
      if !editingController.document.scene.elements.isEmpty,
        !editingController.hasPreviewPNG,
        let preview = renderPreviewFromFirstWindow()
      {
        editingController.setPreviewPNG(preview)
      }

      var package = editingController.packageForArchiving()
      if let pendingSavedTitle {
        package.document.title = pendingSavedTitle
      }

      let archive = try SionArchive.encode(
        package: package,
        intent: pendingSaveIntent,
        generator: archiveGenerator
      )
      stagedHistory = archive.committedHistory
      return archive.data
    }

    public nonisolated override func read(from data: Data, ofType typeName: String) throws {
      let package = try SionArchive.decode(data)

      try MainActor.assumeIsolated {
        for case let windowController as SionDocumentWindowController in windowControllers {
          windowController.discardPendingEdits()
        }

        if let editingControllerStorage {
          try editingControllerStorage.load(package)
        } else {
          initialPackage = package
        }
      }
    }

    public nonisolated override func write(
      to url: URL,
      ofType typeName: String,
      for saveOperation: NSDocument.SaveOperationType,
      originalContentsURL absoluteOriginalContentsURL: URL?
    ) throws {
      MainActor.assumeIsolated {
        pendingSaveIntent = saveIntent(for: saveOperation)
        pendingSavedTitle = savedTitle(for: url, operation: saveOperation)
        stagedHistory = nil
      }

      do {
        try super.write(
          to: url,
          ofType: typeName,
          for: saveOperation,
          originalContentsURL: absoluteOriginalContentsURL
        )
      } catch {
        MainActor.assumeIsolated {
          pendingSaveIntent = .manual
          pendingSavedTitle = nil
          stagedHistory = nil
        }
        throw error
      }

      MainActor.assumeIsolated {
        pendingSaveIntent = .manual
        pendingSavedTitle = nil
        if let stagedHistory {
          editingController.commitArchivedHistory(stagedHistory)
        }
        self.stagedHistory = nil
      }
    }

    /// AppKit's Print… command and the print panel both route here. Page
    /// Setup only edits `printInfo`, so paper, orientation, and margins arrive
    /// through it and need no custom UI.
    public override func printOperation(
      withSettings printSettings: [NSPrintInfo.AttributeKey: Any]
    ) throws -> NSPrintOperation {
      commitPendingWindowEdits()

      guard let settings = printInfo.copy() as? NSPrintInfo else {
        throw SionExportError.contextUnavailable
      }

      let attributes = settings.dictionary()
      for (key, value) in printSettings {
        attributes.setValue(value, forKey: key.rawValue)
      }

      // The print view reports its own single-page range and scales to fit, so
      // AppKit must not paginate or rescale on top of it.
      settings.horizontalPagination = .clip
      settings.verticalPagination = .clip

      let renderer = sceneRenderer
      let printView = SionScenePrintView(
        contentBounds: renderer.contentBounds,
        pageSize: SionScenePrintView.printableSize(for: settings),
        drawScene: renderer.sceneDrawing
      )
      let operation = NSPrintOperation(view: printView, printInfo: settings)
      operation.jobTitle = displayName
      return operation
    }

    @objc func exportImage(_ sender: Any?) {
      commitPendingWindowEdits()

      guard let window = windowControllers.first?.window else { return }

      let accessory = SionImageExportAccessoryView()
      let panel = NSSavePanel()
      panel.canCreateDirectories = true
      panel.accessoryView = accessory
      applyImageExportFormat(accessory.options.format, to: panel)
      accessory.onChange = { [weak self, weak panel] options in
        guard let self, let panel else { return }

        self.applyImageExportFormat(options.format, to: panel)
      }
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url, let self else { return }

        do {
          let data = try self.imageExportData(options: accessory.options)
          try data.write(to: url, options: .atomic)
        } catch {
          self.presentError(error)
        }
      }
    }

    /// Encodes export data with no panel, so formats stay testable headlessly.
    func imageExportData(options: SionImageExportOptions) throws -> Data {
      commitPendingWindowEdits()

      return try SionSceneImageExporter.data(options: options, renderer: sceneRenderer)
    }

    /// Keeps the panel's suggested name and content type on the chosen format.
    private func applyImageExportFormat(
      _ format: SionImageExportFormat,
      to panel: NSSavePanel
    ) {
      panel.allowedContentTypes = [format.contentType]
      panel.nameFieldStringValue = exportFilename(extension: format.fileExtension)
    }

    @objc func importMermaid(_ sender: Any?) {
      commitPendingWindowEdits()

      guard let window = windowForSheet else { return }

      let panel = SionMermaidFile.makeOpenPanel()
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url, let self else { return }

        do {
          try self.importMermaid(contentsOf: url)
        } catch {
          self.presentError(error)
        }
      }
    }

    /// Reads a Mermaid file and inserts it as one undoable command. A read
    /// failure is thrown rather than presented, so only the command that owns
    /// the panel puts an alert on screen.
    @discardableResult
    func importMermaid(
      contentsOf url: URL
    ) throws -> SionEditorController.MermaidInsertionResult? {
      insertMermaid(try SionMermaidFile.source(at: url))
    }

    @discardableResult
    func insertMermaid(_ source: String) -> SionEditorController.MermaidInsertionResult? {
      commitPendingWindowEdits()

      return SionMermaidInsertion.insert(
        source,
        at: mermaidInsertionCenter,
        origin: .file,
        using: editingController,
        feedback: { presentEditorFeedback($0) }
      )
    }

    /// The visible canvas centre when a window exists, and the canvas centre
    /// otherwise, so an import into a windowless document still lands on paper.
    private var mermaidInsertionCenter: SionPoint {
      for case let windowController as SionDocumentWindowController in windowControllers {
        return windowController.canvasVisibleCenter
      }

      return editingController.defaultInsertionCenter
    }

    private func presentEditorFeedback(_ request: SionEditorFeedbackRequest) {
      for case let windowController as SionDocumentWindowController in windowControllers {
        windowController.presentEditorFeedback(request)
      }
    }

    @objc func exportSVG(_ sender: Any?) {
      commitPendingWindowEdits()

      do {
        let package = editingController.packageForArchiving()
        let source = try SVGExporter.export(document: package.document, assets: package.assets)
        presentExportPanel(
          suggestedFilename: exportFilename(extension: "svg"),
          data: Data(source.utf8)
        )
      } catch {
        presentError(error)
      }
    }

    @objc func exportMermaid(_ sender: Any?) {
      commitPendingWindowEdits()

      let export = MermaidExporter.export(document: editingController.document)
      guard let warning = MermaidExportWarning(coverage: export.coverage) else {
        presentMermaidExportPanel(export)
        return
      }

      presentMermaidExportWarning(warning, export: export)
    }

    private func presentMermaidExportWarning(
      _ warning: MermaidExportWarning,
      export: MermaidExport
    ) {
      guard let window = windowForSheet else { return }

      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = warning.messageText
      alert.informativeText = warning.informativeText(for: export.omissions)
      alert.addButton(withTitle: "Cancel")
      alert.addButton(withTitle: "Export Anyway")
      alert.beginSheetModal(for: window) { [weak self] response in
        guard response == .alertSecondButtonReturn else { return }

        self?.presentMermaidExportPanel(export)
      }
    }

    private func presentMermaidExportPanel(_ export: MermaidExport) {
      presentExportPanel(
        suggestedFilename: exportFilename(extension: "mmd"),
        data: Data(export.source.utf8)
      )
    }

    private func presentExportPanel(suggestedFilename: String, data: Data) {
      guard let window = windowControllers.first?.window else { return }

      let panel = NSSavePanel()
      panel.nameFieldStringValue = suggestedFilename
      panel.canCreateDirectories = true
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }

        do {
          try data.write(to: url, options: .atomic)
        } catch {
          self?.presentError(error)
        }
      }
    }

    private func commitPendingWindowEdits() {
      for case let windowController as SionDocumentWindowController in windowControllers {
        windowController.commitPendingEdits()
      }
    }

    private func renderPreviewFromFirstWindow() -> Data? {
      for case let windowController as SionDocumentWindowController in windowControllers {
        if let preview = windowController.renderPreviewPNG() {
          return preview
        }
      }

      return nil
    }

    private func recordEditorChange(_ change: SionEditorController.DocumentChange) {
      super.updateChangeCount(change.documentChangeType)
    }

    private func exportFilename(extension fileExtension: String) -> String {
      let base =
        fileURL?.deletingPathExtension().lastPathComponent
        ?? editingController.document.title
      return "\(base).\(fileExtension)"
    }

    private func saveIntent(for operation: NSDocument.SaveOperationType) -> SaveIntent {
      switch operation {
      case .autosaveInPlaceOperation, .autosaveElsewhereOperation:
        return .autosave
      case .saveAsOperation, .saveToOperation:
        return .saveAs
      default:
        return .manual
      }
    }

    private func savedTitle(
      for url: URL,
      operation: NSDocument.SaveOperationType
    ) -> String? {
      // Autosave-elsewhere URLs are recovery locations, not user filenames.
      guard operation != .autosaveElsewhereOperation else { return nil }

      let title = url.deletingPathExtension().lastPathComponent
      return title.isEmpty ? nil : title
    }
  }

  extension SionEditorController.DocumentChange {
    fileprivate var documentChangeType: NSDocument.ChangeType {
      switch self {
      case .done: .changeDone
      case .undone: .changeUndone
      case .redone: .changeRedone
      }
    }
  }
#endif
