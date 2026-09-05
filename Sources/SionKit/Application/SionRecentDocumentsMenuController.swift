#if canImport(AppKit)
  import AppKit

  @MainActor
  final class SionRecentDocumentsMenuController: NSObject, NSMenuDelegate {
    private enum MenuTitle {
      static let clear = "Clear Menu"
      static let openRecent = "Open Recent"
    }

    private let clearHandler: () -> Void
    private let openHandler: (URL) -> Void
    private let recentURLProvider: () -> [URL]

    init(
      recentDocumentURLs: @escaping () -> [URL],
      openDocument: @escaping (URL) -> Void,
      clearRecentDocuments: @escaping () -> Void
    ) {
      recentURLProvider = recentDocumentURLs
      openHandler = openDocument
      clearHandler = clearRecentDocuments
    }

    convenience init(documentController: SionDocumentController) {
      self.init(
        recentDocumentURLs: { [documentController] in documentController.recentDocumentURLs },
        openDocument: { [documentController] in documentController.openRecentDocument(at: $0) },
        clearRecentDocuments: { [documentController] in
          documentController.clearRecentDocuments(nil)
        }
      )
    }

    func makeMenu() -> NSMenu {
      // A title alone does not opt a programmatic submenu into AppKit population.
      let menu = NSMenu(title: MenuTitle.openRecent)
      menu.autoenablesItems = false
      menu.delegate = self
      return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
      // Rebuild at display time so AppKit's persistent history stays authoritative.
      menu.removeAllItems()
      let recentURLs = recentURLProvider()

      for url in recentURLs {
        let item = NSMenuItem(
          title: url.lastPathComponent,
          action: #selector(openRecentDocument(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = url
        item.toolTip = url.path
        menu.addItem(item)
      }

      if !recentURLs.isEmpty {
        menu.addItem(.separator())
      }

      let clear = NSMenuItem(
        title: MenuTitle.clear,
        action: #selector(clearRecentDocuments(_:)),
        keyEquivalent: ""
      )
      clear.target = self
      clear.isEnabled = !recentURLs.isEmpty
      menu.addItem(clear)
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
      guard let url = sender.representedObject as? URL else {
        return
      }

      openHandler(url)
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
      clearHandler()
    }
  }
#endif
