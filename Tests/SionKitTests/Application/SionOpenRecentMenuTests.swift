import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionOpenRecentMenuTests: XCTestCase {
  func testFinishedLaunchRoutesRecentDocumentActions() throws {
    let application = NSApplication.shared
    let previousDelegate = application.delegate
    let previousHelpMenu = application.helpMenu
    let previousMainMenu = application.mainMenu
    let previousServicesMenu = application.servicesMenu
    let previousWindowsMenu = application.windowsMenu
    var urls = [TestDocument.diagram]
    var openedURLs: [URL] = []
    var clearCount = 0
    let recentDocumentsMenuController = makeController(
      recentDocumentURLs: { urls },
      openDocument: { openedURLs.append($0) },
      clearRecentDocuments: {
        urls.removeAll()
        clearCount += 1
      }
    )
    let documentController = SionDocumentController()
    let sentinel = SionDrawingDocument()
    documentController.addDocument(sentinel)
    let delegate = LaunchProbeDelegate(
      documentController: documentController,
      recentDocumentsMenuController: recentDocumentsMenuController
    )

    defer {
      documentController.removeDocument(sentinel)
      application.delegate = previousDelegate
      application.helpMenu = previousHelpMenu
      application.mainMenu = previousMainMenu
      application.servicesMenu = previousServicesMenu
      application.windowsMenu = previousWindowsMenu
    }

    application.delegate = delegate
    application.mainMenu = nil
    application.finishLaunching()

    let fileMenu = try XCTUnwrap(
      application.mainMenu?.item(withTitle: TestMenu.file)?.submenu
    )
    let openRecentItems = fileMenu.items.filter { $0.title == TestMenu.openRecent }
    let openRecent = try XCTUnwrap(openRecentItems.first)
    let recentMenu = try XCTUnwrap(openRecent.submenu)

    XCTAssertEqual(openRecentItems.count, 1)
    XCTAssertTrue(recentMenu.delegate === recentDocumentsMenuController)

    recentMenu.delegate?.menuNeedsUpdate?(recentMenu)

    let recent = try XCTUnwrap(recentMenu.item(withTitle: TestDocument.diagram.lastPathComponent))
    XCTAssertTrue(
      application.sendAction(try XCTUnwrap(recent.action), to: recent.target, from: recent)
    )
    XCTAssertEqual(openedURLs, [TestDocument.diagram])

    let clear = try XCTUnwrap(recentMenu.item(withTitle: TestMenu.clear))
    XCTAssertTrue(
      application.sendAction(try XCTUnwrap(clear.action), to: clear.target, from: clear)
    )
    XCTAssertEqual(clearCount, 1)

    recentMenu.delegate?.menuNeedsUpdate?(recentMenu)

    XCTAssertEqual(recentMenu.items.count, 1)
    XCTAssertFalse(try XCTUnwrap(recentMenu.items.first).isEnabled)
  }

  func testWillFinishLaunchingInstallsOpenRecentAfterOpen() throws {
    let application = NSApplication.shared
    let previousHelpMenu = application.helpMenu
    let previousMainMenu = application.mainMenu
    let previousServicesMenu = application.servicesMenu
    let previousWindowsMenu = application.windowsMenu

    defer {
      application.helpMenu = previousHelpMenu
      application.mainMenu = previousMainMenu
      application.servicesMenu = previousServicesMenu
      application.windowsMenu = previousWindowsMenu
    }

    let delegate: NSApplicationDelegate = SionApplicationDelegate()
    delegate.applicationWillFinishLaunching?(
      Notification(name: NSApplication.willFinishLaunchingNotification, object: application)
    )

    let fileMenu = try XCTUnwrap(
      application.mainMenu?.item(withTitle: TestMenu.file)?.submenu
    )
    let open = try XCTUnwrap(fileMenu.item(withTitle: TestMenu.open))
    let openRecent = try XCTUnwrap(fileMenu.item(withTitle: TestMenu.openRecent))
    let openRecentIndex = fileMenu.index(of: openRecent)

    XCTAssertEqual(openRecentIndex, fileMenu.index(of: open) + 1)
    XCTAssertTrue(fileMenu.item(at: openRecentIndex + 1)?.isSeparatorItem == true)
    XCTAssertNotNil(openRecent.submenu?.delegate)
  }

  func testRecentMenuUsesCurrentDocumentURLs() throws {
    let urls = [TestDocument.diagram, TestDocument.notes]
    let controller = makeController(recentDocumentURLs: { urls })
    let menu = NSMenu(title: TestMenu.openRecent)

    controller.menuNeedsUpdate(menu)

    let recentItems = Array(menu.items.prefix(urls.count))
    XCTAssertEqual(recentItems.map(\.title), urls.map(\.lastPathComponent))
    XCTAssertEqual(recentItems.compactMap { $0.representedObject as? URL }, urls)
    XCTAssertTrue(
      menu.items.indices.contains(urls.count) && menu.items[urls.count].isSeparatorItem
    )

    let clear = try XCTUnwrap(menu.items.last)
    XCTAssertEqual(clear.title, TestMenu.clear)
    XCTAssertTrue(clear.isEnabled)
  }

  func testRecentMenuRoutesOpenAndClearActions() throws {
    var urls = [TestDocument.diagram]
    var openedURLs: [URL] = []
    var clearCount = 0
    let controller = makeController(
      recentDocumentURLs: { urls },
      openDocument: { openedURLs.append($0) },
      clearRecentDocuments: {
        urls.removeAll()
        clearCount += 1
      }
    )
    let menu = NSMenu(title: TestMenu.openRecent)

    controller.menuNeedsUpdate(menu)

    let recent = try XCTUnwrap(menu.items.first)
    XCTAssertTrue(
      NSApp.sendAction(try XCTUnwrap(recent.action), to: recent.target, from: recent)
    )
    XCTAssertEqual(openedURLs, [TestDocument.diagram])

    let clear = try XCTUnwrap(menu.items.last)
    XCTAssertTrue(
      NSApp.sendAction(try XCTUnwrap(clear.action), to: clear.target, from: clear)
    )
    XCTAssertEqual(clearCount, 1)
  }

  func testRecentMenuRebuildRemovesStaleItems() throws {
    var urls = [TestDocument.diagram, TestDocument.notes]
    let controller = makeController(recentDocumentURLs: { urls })
    let menu = NSMenu(title: TestMenu.openRecent)
    controller.menuNeedsUpdate(menu)

    urls.removeAll()
    controller.menuNeedsUpdate(menu)

    let clear = try XCTUnwrap(menu.items.first)
    XCTAssertEqual(menu.items.count, 1)
    XCTAssertEqual(clear.title, TestMenu.clear)
    XCTAssertFalse(clear.isEnabled)
  }

  private func makeController(
    recentDocumentURLs: @escaping () -> [URL],
    openDocument: @escaping (URL) -> Void = { _ in },
    clearRecentDocuments: @escaping () -> Void = {}
  ) -> SionRecentDocumentsMenuController {
    SionRecentDocumentsMenuController(
      recentDocumentURLs: recentDocumentURLs,
      openDocument: openDocument,
      clearRecentDocuments: clearRecentDocuments
    )
  }
}

@MainActor
private final class LaunchProbeDelegate: NSObject, NSApplicationDelegate {
  private let subject: SionApplicationDelegate

  init(
    documentController: SionDocumentController,
    recentDocumentsMenuController: SionRecentDocumentsMenuController
  ) {
    subject = SionApplicationDelegate(
      documentController: documentController,
      recentDocumentsMenuController: recentDocumentsMenuController
    )
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    subject.applicationWillFinishLaunching(notification)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    subject.applicationDidFinishLaunching(notification)
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    false
  }
}

private enum TestMenu {
  static let clear = "Clear Menu"
  static let file = "File"
  static let open = "Open…"
  static let openRecent = "Open Recent"
}

private enum TestDocument {
  static let diagram = URL(fileURLWithPath: "/tmp/diagram.sion")
  static let notes = URL(fileURLWithPath: "/tmp/notes.sion")
}
