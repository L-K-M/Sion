#if canImport(AppKit)
  import AppKit

  /// The canvas's right-click menu.
  ///
  /// Every entry sends the same selector its main-menu twin does, with no
  /// target: the responder chain resolves it, and the canvas's own
  /// `validateMenuItem(_:)` decides what is enabled and what is checked. So
  /// nothing here has to know what is selected, and neither menu can drift
  /// into offering a command the other one does not.
  @MainActor
  enum SionCanvasContextMenu {
    enum Entry: Equatable {
      case command(title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags)
      case separator
      case submenu(title: String, entries: [Entry])

      /// Most rows carry no key equivalent, and the ones that do carry the
      /// same modifiers as their main-menu twin.
      static func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
      ) -> Entry {
        .command(title: title, action: action, key: key, modifiers: modifiers)
      }
    }

    static let entries: [Entry] = [
      .item("Cut", AppAction.cut, key: "x"),
      .item("Copy", AppAction.copy, key: "c"),
      .item("Paste", AppAction.paste, key: "v"),
      .item("Duplicate", AppAction.duplicate, key: "d"),
      .item("Delete", AppAction.delete, key: "\u{8}", modifiers: []),
      .separator,
      .submenu(
        title: "Add to Library",
        entries: [
          .item("This Document", AppAction.addSelectionToDocumentLibrary),
          .item("All Documents", AppAction.addSelectionToGlobalLibrary),
        ]
      ),
      .separator,
      .submenu(
        title: "Arrange",
        entries: [
          .item(
            "Bring to Front",
            AppAction.bringToFront,
            key: "]",
            modifiers: [.command, .option]
          ),
          .item("Bring Forward", AppAction.bringForward, key: "]"),
          .item("Send Backward", AppAction.sendBackward, key: "["),
          .item(
            "Send to Back",
            AppAction.sendToBack,
            key: "[",
            modifiers: [.command, .option]
          ),
          .separator,
          .item("Align Left", AppAction.alignLeading),
          .item("Align Center Horizontally", AppAction.alignCenterHorizontally),
          .item("Align Right", AppAction.alignTrailing),
          .item("Align Top", AppAction.alignTop),
          .item("Align Center Vertically", AppAction.alignCenterVertically),
          .item("Align Bottom", AppAction.alignBottom),
          .separator,
          .item("Distribute Horizontally", AppAction.distributeHorizontally),
          .item("Distribute Vertically", AppAction.distributeVertically),
        ]
      ),
      .item("Lock", AppAction.lockSelection, key: "l", modifiers: [.command, .shift]),
      .item("Unlock", AppAction.unlockSelection),
      .item("Hide Selection", AppAction.hideSelection),
      .item("Reveal All Hidden", AppAction.revealHiddenElements),
      .separator,
      .item("Select All", AppAction.selectAll, key: "a"),
      .item("Show Grid", AppAction.toggleGridVisibility),
      .item("Snap to Objects", AppAction.toggleObjectSnapping),
      .item("Zoom to Fit", AppAction.zoomToFit, key: "1"),
    ]

    static func make() -> NSMenu {
      menu(titled: "", entries: entries)
    }

    private static func menu(titled title: String, entries: [Entry]) -> NSMenu {
      let menu = NSMenu(title: title)

      for entry in entries {
        menu.addItem(item(for: entry))
      }

      return menu
    }

    private static func item(for entry: Entry) -> NSMenuItem {
      switch entry {
      case .separator:
        return .separator()
      case .command(let title, let action, let key, let modifiers):
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
      case .submenu(let title, let entries):
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu(titled: title, entries: entries)
        return item
      }
    }
  }
#endif
