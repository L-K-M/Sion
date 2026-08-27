#if canImport(AppKit)
  import AppKit
  import SionCore

  @MainActor
  /// Bridges AppKit document lifecycle to Sion's validated recovery archive.
  public final class SionDrawingDocument: NSDocument {
    public static let typeIdentifier = "ch.lkmc.sion.document"

    private var initialPackage = SionPackage()
    private var editingControllerStorage: SionEditorController?
    private var pendingSaveIntent = SaveIntent.manual
    private var stagedHistory: DocumentHistory?

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
      super.init()

      hasUndoManager = true
    }

    public override class var autosavesInPlace: Bool { true }

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

    public override func data(ofType typeName: String) throws -> Data {
      for case let windowController as SionDocumentWindowController in windowControllers {
        windowController.checkpointPendingEdits()
      }

      let archive = try SionArchive.encode(
        package: editingController.packageForArchiving(),
        intent: pendingSaveIntent
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
          stagedHistory = nil
        }
        throw error
      }

      MainActor.assumeIsolated {
        pendingSaveIntent = .manual
        if let stagedHistory {
          editingController.commitArchivedHistory(stagedHistory)
        }
        self.stagedHistory = nil
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

      let source = MermaidExporter.export(document: editingController.document).source
      presentExportPanel(
        suggestedFilename: exportFilename(extension: "mmd"),
        data: Data(source.utf8)
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
