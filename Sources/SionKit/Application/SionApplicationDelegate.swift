import AppKit

@MainActor
public final class SionApplicationDelegate: NSObject, NSApplicationDelegate {
  private let documentController = SionDocumentController()

  public override init() {
    super.init()
  }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    SionMainMenu.install()
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
  static func install() {
    let menu = NSMenu()
    menu.addItem(applicationMenu())
    menu.addItem(fileMenu())
    menu.addItem(editMenu())
    menu.addItem(viewMenu())
    menu.addItem(windowMenu())
    NSApp.mainMenu = menu
  }

  private static func applicationMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "Sion")
    submenu.addItem(
      item("About Sion", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
    submenu.addItem(.separator())
    submenu.addItem(item("Hide Sion", action: #selector(NSApplication.hide(_:)), key: "h"))
    submenu.addItem(
      item(
        "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h",
        modifiers: [.command, .option]))
    submenu.addItem(item("Show All", action: #selector(NSApplication.unhideAllApplications(_:))))
    submenu.addItem(.separator())
    submenu.addItem(item("Quit Sion", action: #selector(NSApplication.terminate(_:)), key: "q"))
    return parentItem(title: "Sion", submenu: submenu)
  }

  private static func fileMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "File")
    submenu.addItem(item("New", action: #selector(NSDocumentController.newDocument(_:)), key: "n"))
    submenu.addItem(
      item("Open…", action: #selector(NSDocumentController.openDocument(_:)), key: "o"))
    submenu.addItem(.separator())
    submenu.addItem(item("Close", action: AppAction.close, key: "w"))
    submenu.addItem(item("Save", action: AppAction.save, key: "s"))
    submenu.addItem(item("Save As…", action: AppAction.saveAs, key: "S"))
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
    submenu.addItem(item("Delete", action: AppAction.delete, key: "\u{8}", modifiers: []))
    submenu.addItem(.separator())
    submenu.addItem(item("Select All", action: AppAction.selectAll, key: "a"))
    return parentItem(title: "Edit", submenu: submenu)
  }

  private static func viewMenu() -> NSMenuItem {
    let submenu = NSMenu(title: "View")
    submenu.addItem(item("Zoom In", action: AppAction.zoomIn, key: "+"))
    submenu.addItem(item("Zoom Out", action: AppAction.zoomOut, key: "-"))
    submenu.addItem(item("Actual Size", action: AppAction.actualSize, key: "0"))
    submenu.addItem(item("Zoom to Fit", action: AppAction.zoomToFit, key: "1"))
    submenu.addItem(.separator())
    submenu.addItem(
      item("Show Grid", action: AppAction.toggleGrid, key: "g", modifiers: [.command, .option]))
    submenu.addItem(
      item("Snap to Grid", action: AppAction.toggleSnap, key: "g", modifiers: [.command, .shift]))
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
}

private enum AppAction {
  static let actualSize = Selector(("actualSize:"))
  static let close = Selector(("performClose:"))
  static let copy = Selector(("copy:"))
  static let cut = Selector(("cut:"))
  static let delete = Selector(("delete:"))
  static let exportMermaid = Selector(("exportMermaid:"))
  static let exportSVG = Selector(("exportSVG:"))
  static let paste = Selector(("paste:"))
  static let redo = Selector(("redo:"))
  static let save = Selector(("saveDocument:"))
  static let saveAs = Selector(("saveDocumentAs:"))
  static let selectAll = Selector(("selectAll:"))
  static let showHistory = Selector(("showHistory:"))
  static let showInspector = Selector(("showInspector:"))
  static let showLibrary = Selector(("showLibrary:"))
  static let toggleGrid = Selector(("toggleGridVisibility:"))
  static let toggleSnap = Selector(("toggleSnapToGrid:"))
  static let undo = Selector(("undo:"))
  static let zoomIn = Selector(("zoomIn:"))
  static let zoomOut = Selector(("zoomOut:"))
  static let zoomToFit = Selector(("zoomToFit:"))
}
