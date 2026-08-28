import AppKit

@MainActor
public final class SionApplicationDelegate: NSObject, NSApplicationDelegate {
  private let documentController: SionDocumentController
  // NSMenu retains its delegate weakly, so keep the adapter for the app lifetime.
  private let recentDocumentsMenuController: SionRecentDocumentsMenuController

  public override init() {
    let documentController = SionDocumentController()
    self.documentController = documentController
    recentDocumentsMenuController = SionRecentDocumentsMenuController(
      documentController: documentController
    )
    super.init()
  }

  init(
    documentController: SionDocumentController,
    recentDocumentsMenuController: SionRecentDocumentsMenuController
  ) {
    self.documentController = documentController
    self.recentDocumentsMenuController = recentDocumentsMenuController
    super.init()
  }

  public func applicationWillFinishLaunching(_ notification: Notification) {
    // Install before AppKit discovers system-managed menu roles.
    SionMainMenu.install(recentDocumentsMenuController: recentDocumentsMenuController)
  }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate(ignoringOtherApps: true)

    guard documentController.documents.isEmpty else {
      return
    }

    documentController.newDocument(nil)
  }

  public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    true
  }

  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  public func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag, let window = documentController.documents.first?.windowControllers.first?.window {
      window.makeKeyAndOrderFront(nil)
      return true
    }

    if documentController.documents.isEmpty {
      documentController.newDocument(nil)
    }
    return true
  }
}

@MainActor
private enum SionMainMenu {
  static func install(recentDocumentsMenuController: SionRecentDocumentsMenuController) {
    let applicationMenu = applicationMenu()
    let menu = NSMenu()
    menu.addItem(applicationMenu.item)
    menu.addItem(fileMenu(recentDocumentsMenuController: recentDocumentsMenuController))
    menu.addItem(editMenu())
    menu.addItem(arrangeMenu())
    menu.addItem(viewMenu())
    menu.addItem(windowMenu())
    menu.addItem(helpMenu())
    NSApp.mainMenu = menu

    // Attaching the main menu can install AppKit's shared Services submenu,
    // leaving the application role and the visible item pointing at different
    // menus. Whatever menu the role names becomes the item's submenu; release
    // its previous owner first so no attached menu is re-parented.
    var servicesMenu = applicationMenu.servicesMenu
    if let attached = NSApp.servicesMenu, attached !== servicesMenu {
      // Release the role's menu from any previous owner item before adopting
      // it; assigning an attached menu to our item would throw.
      if let ownerMenu = attached.supermenu {
        ownerMenu.items.first { $0.submenu === attached }?.submenu = nil
      }
      servicesMenu = attached
    }
    if applicationMenu.servicesItem.submenu !== servicesMenu {
      applicationMenu.servicesItem.submenu = servicesMenu
    }
    NSApp.servicesMenu = servicesMenu
  }

  private static func applicationMenu() -> ApplicationMenu {
    let submenu = NSMenu(title: "Sion")
    submenu.addItem(
      item("About Sion", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
    submenu.addItem(.separator())

    let servicesMenu = NSMenu(title: ApplicationMenuCopy.servicesTitle)
    let servicesItem = parentItem(title: servicesMenu.title, submenu: servicesMenu)
    submenu.addItem(servicesItem)
    submenu.addItem(.separator())

    submenu.addItem(item("Hide Sion", action: #selector(NSApplication.hide(_:)), key: "h"))
    submenu.addItem(
      item(
        "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h",
        modifiers: [.command, .option]))
    submenu.addItem(item("Show All", action: #selector(NSApplication.unhideAllApplications(_:))))
    submenu.addItem(.separator())
    submenu.addItem(item("Quit Sion", action: #selector(NSApplication.terminate(_:)), key: "q"))
    return ApplicationMenu(
      item: parentItem(title: "Sion", submenu: submenu),
      servicesItem: servicesItem,
      servicesMenu: servicesMenu
    )
  }

  private struct ApplicationMenu {
    let item: NSMenuItem
    let servicesItem: NSMenuItem
    let servicesMenu: NSMenu
  }

  private enum ApplicationMenuCopy {
    static let servicesTitle = "Services"
  }

  private static func fileMenu(
    recentDocumentsMenuController: SionRecentDocumentsMenuController
  ) -> NSMenuItem {
    let submenu = NSMenu(title: "File")
    submenu.addItem(item("New", action: #selector(NSDocumentController.newDocument(_:)), key: "n"))
    submenu.addItem(
      item("Open…", action: #selector(NSDocumentController.openDocument(_:)), key: "o"))
    let recentMenu = recentDocumentsMenuController.makeMenu()
    submenu.addItem(parentItem(title: recentMenu.title, submenu: recentMenu))
    submenu.addItem(.separator())
    submenu.addItem(item("Close", action: AppAction.close, key: "w"))
    submenu.addItem(item("Save", action: AppAction.save, key: "s"))
    submenu.addItem(item("Save As…", action: AppAction.saveAs, key: "S"))
    submenu.addItem(item("Revert to Saved…", action: AppAction.revertToSaved))
    submenu.addItem(.separator())
    submenu.addItem(
      item("Export SVG…", action: AppAction.exportSVG, key: "e", modifiers: [.command, .shift]))
    submenu.addItem(item("Export Mermaid…", action: AppAction.exportMermaid))
    return parentItem(title: "File", submenu: submenu)
  }

  private static func editMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "Edit")
    submenu.addItem(item("Undo", action: AppAction.undo, key: "z"))
    submenu.addItem(item("Redo", action: AppAction.redo, key: "Z"))
    submenu.addItem(.separator())
    submenu.addItem(item("Cut", action: AppAction.cut, key: "x"))
    submenu.addItem(item("Copy", action: AppAction.copy, key: "c"))
    submenu.addItem(item("Paste", action: AppAction.paste, key: "v"))
    submenu.addItem(item("Duplicate", action: AppAction.duplicate, key: "d"))
    submenu.addItem(item("Delete", action: AppAction.delete, key: "\u{8}", modifiers: []))
    submenu.addItem(.separator())
    submenu.addItem(item("Select All", action: AppAction.selectAll, key: "a"))
    submenu.addItem(.separator())
    submenu.addItem(findMenu())
    submenu.addItem(spellingMenu())
    return parentItem(title: "Edit", submenu: submenu)
  }

  private static func findMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "Find")
    submenu.addItem(
      finderItem("Find…", action: .showFindInterface, key: "f")
    )
    submenu.addItem(
      finderItem("Find Next", action: .nextMatch, key: "g")
    )
    submenu.addItem(
      finderItem(
        "Find Previous",
        action: .previousMatch,
        key: "g",
        modifiers: [.command, .shift]
      )
    )
    submenu.addItem(.separator())
    submenu.addItem(
      finderItem("Use Selection for Find", action: .setSearchString, key: "e")
    )
    submenu.addItem(
      item(
        "Jump to Selection",
        action: #selector(NSTextView.centerSelectionInVisibleArea(_:)),
        key: "j"
      )
    )
    return parentItem(title: submenu.title, submenu: submenu)
  }

  private static func spellingMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "Spelling and Grammar")
    submenu.addItem(
      item(
        "Show Spelling and Grammar",
        action: #selector(NSText.showGuessPanel(_:)),
        key: ":"
      )
    )
    submenu.addItem(
      item(
        "Check Document Now",
        action: #selector(NSText.checkSpelling(_:)),
        key: ";"
      )
    )
    return parentItem(title: submenu.title, submenu: submenu)
  }

  private static func arrangeMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "Arrange")
    submenu.addItem(
      item(
        "Bring to Front", action: AppAction.bringToFront, key: "]",
        modifiers: [.command, .option]))
    submenu.addItem(item("Bring Forward", action: AppAction.bringForward, key: "]"))
    submenu.addItem(item("Send Backward", action: AppAction.sendBackward, key: "["))
    submenu.addItem(
      item(
        "Send to Back", action: AppAction.sendToBack, key: "[",
        modifiers: [.command, .option]))
    submenu.addItem(.separator())
    submenu.addItem(item("Align Left", action: AppAction.alignLeading))
    submenu.addItem(
      item("Align Center Horizontally", action: AppAction.alignCenterHorizontally))
    submenu.addItem(item("Align Right", action: AppAction.alignTrailing))
    submenu.addItem(item("Align Top", action: AppAction.alignTop))
    submenu.addItem(item("Align Center Vertically", action: AppAction.alignCenterVertically))
    submenu.addItem(item("Align Bottom", action: AppAction.alignBottom))
    submenu.addItem(.separator())
    submenu.addItem(item("Distribute Horizontally", action: AppAction.distributeHorizontally))
    submenu.addItem(item("Distribute Vertically", action: AppAction.distributeVertically))
    submenu.addItem(.separator())
    submenu.addItem(
      item("Lock", action: AppAction.lockSelection, key: "l", modifiers: [.command, .shift]))
    submenu.addItem(item("Unlock", action: AppAction.unlockSelection))
    submenu.addItem(item("Hide Selection", action: AppAction.hideSelection))
    submenu.addItem(item("Reveal All Hidden", action: AppAction.revealHiddenElements))
    return parentItem(title: "Arrange", submenu: submenu)
  }

  private static func viewMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "View")
    submenu.addItem(item("Zoom In", action: AppAction.zoomIn, key: "+"))
    submenu.addItem(item("Zoom Out", action: AppAction.zoomOut, key: "-"))
    submenu.addItem(item("Actual Size", action: AppAction.actualSize, key: "0"))
    submenu.addItem(item("Zoom to Fit", action: AppAction.zoomToFit, key: "1"))
    submenu.addItem(.separator())
    submenu.addItem(item("Show Grid", action: AppAction.toggleGridVisibility))
    submenu.addItem(.separator())
    submenu.addItem(
      item("Inspector", action: AppAction.showInspector, key: "i", modifiers: [.command, .option]))
    submenu.addItem(
      item("Library", action: AppAction.showLibrary, key: "l", modifiers: [.command, .option]))
    submenu.addItem(
      item("History", action: AppAction.showHistory, key: "y", modifiers: [.command, .option]))
    submenu.addItem(.separator())
    submenu.addItem(
      item(
        "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), key: "f",
        modifiers: [.command, .control]))
    return parentItem(title: "View", submenu: submenu)
  }

  private static func windowMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "Window")
    submenu.addItem(item("Minimize", action: #selector(NSWindow.miniaturize(_:)), key: "m"))
    submenu.addItem(item("Zoom", action: #selector(NSWindow.performZoom(_:))))
    submenu.addItem(.separator())
    submenu.addItem(item("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:))))
    NSApp.windowsMenu = submenu
    return parentItem(title: "Window", submenu: submenu)
  }

  private static func helpMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "Help")
    let helpItem = item(
      "Sion Help",
      action: #selector(NSApplication.showHelp(_:)),
      key: "?"
    )
    helpItem.target = NSApp
    submenu.addItem(helpItem)

    // AppKit adds its menu search UI and opens the registered help book.
    NSApp.helpMenu = submenu
    return parentItem(title: submenu.title, submenu: submenu)
  }

  private static func parentItem(title: String, submenu: NSMenu) -> NSMenuItem {
    let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    menuItem.submenu = submenu
    return menuItem
  }

  private static func item(
    _ title: String,
    action: Selector?,
    key: String = "",
    modifiers: NSEvent.ModifierFlags = [.command]
  ) -> NSMenuItem {
    let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
    menuItem.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
    return menuItem
  }

  private static func finderItem(
    _ title: String,
    action: NSTextFinder.Action,
    key: String,
    modifiers: NSEvent.ModifierFlags = [.command]
  ) -> NSMenuItem {
    // NSTextView owns searching; the tag selects its AppKit operation.
    let menuItem = item(
      title,
      action: #selector(NSResponder.performTextFinderAction(_:)),
      key: key,
      modifiers: modifiers
    )
    menuItem.tag = action.rawValue
    return menuItem
  }
}

private enum AppAction {
  static let actualSize = Selector(("actualSize:"))
  static let alignBottom = Selector(("alignBottom:"))
  static let alignCenterHorizontally = Selector(("alignCenterHorizontally:"))
  static let alignCenterVertically = Selector(("alignCenterVertically:"))
  static let alignLeading = Selector(("alignLeading:"))
  static let alignTop = Selector(("alignTop:"))
  static let alignTrailing = Selector(("alignTrailing:"))
  static let bringForward = Selector(("bringForward:"))
  static let bringToFront = Selector(("bringToFront:"))
  static let close = Selector(("performClose:"))
  static let copy = Selector(("copy:"))
  static let cut = Selector(("cut:"))
  static let delete = Selector(("delete:"))
  static let distributeHorizontally = Selector(("distributeHorizontally:"))
  static let distributeVertically = Selector(("distributeVertically:"))
  static let duplicate = Selector(("duplicate:"))
  static let exportMermaid = Selector(("exportMermaid:"))
  static let exportSVG = Selector(("exportSVG:"))
  static let hideSelection = Selector(("hideSelection:"))
  static let lockSelection = Selector(("lockSelection:"))
  static let paste = Selector(("paste:"))
  static let redo = Selector(("redo:"))
  static let revealHiddenElements = Selector(("revealHiddenElements:"))
  static let revertToSaved = #selector(NSDocument.revertToSaved(_:))
  static let save = Selector(("saveDocument:"))
  static let saveAs = Selector(("saveDocumentAs:"))
  static let selectAll = Selector(("selectAll:"))
  static let sendBackward = Selector(("sendBackward:"))
  static let sendToBack = Selector(("sendToBack:"))
  static let showHistory = Selector(("showHistory:"))
  static let showInspector = Selector(("showInspector:"))
  static let showLibrary = Selector(("showLibrary:"))
  static let toggleGridVisibility = Selector(("toggleGridVisibility:"))
  static let undo = Selector(("undo:"))
  static let unlockSelection = Selector(("unlockSelection:"))
  static let zoomIn = Selector(("zoomIn:"))
  static let zoomOut = Selector(("zoomOut:"))
  static let zoomToFit = Selector(("zoomToFit:"))
}
