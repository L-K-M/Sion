import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionFileMenuCommandTests: XCTestCase {
  func testFileMenuExposesMermaidImportPrintAndImageExport() throws {
    try withFileMenu { fileMenu in
      assertItem(
        fileMenu,
        title: "New from Mermaid…",
        action: Selector(("newDocumentFromMermaid:")),
        key: "",
        modifiers: []
      )
      assertItem(
        fileMenu,
        title: "Import Mermaid…",
        action: Selector(("importMermaid:")),
        key: "",
        modifiers: []
      )
      assertItem(
        fileMenu,
        title: "Export Image…",
        action: Selector(("exportImage:")),
        key: "",
        modifiers: []
      )
      assertItem(
        fileMenu,
        title: "Page Setup…",
        action: #selector(NSDocument.runPageLayout(_:)),
        key: "P",
        modifiers: [.command, .shift]
      )
      assertItem(
        fileMenu,
        title: "Print…",
        action: #selector(NSDocument.printDocument(_:)),
        key: "p"
      )
    }
  }

  func testMermaidCommandsSitBesideTheirRelatedFileCommands() throws {
    try withFileMenu { fileMenu in
      let new = try XCTUnwrap(fileMenu.item(withTitle: "New"))
      let newFromMermaid = try XCTUnwrap(fileMenu.item(withTitle: "New from Mermaid…"))
      let importMermaid = try XCTUnwrap(fileMenu.item(withTitle: "Import Mermaid…"))
      let exportImage = try XCTUnwrap(fileMenu.item(withTitle: "Export Image…"))
      let exportSVG = try XCTUnwrap(fileMenu.item(withTitle: "Export SVG…"))
      let printItem = try XCTUnwrap(fileMenu.item(withTitle: "Print…"))

      XCTAssertEqual(fileMenu.index(of: newFromMermaid), fileMenu.index(of: new) + 1)
      XCTAssertEqual(fileMenu.index(of: exportImage), fileMenu.index(of: importMermaid) + 1)
      XCTAssertEqual(fileMenu.index(of: exportSVG), fileMenu.index(of: exportImage) + 1)
      XCTAssertTrue(fileMenu.item(at: fileMenu.index(of: printItem) - 2)?.isSeparatorItem == true)
    }
  }

  func testApplicationDelegateOwnsTheDocumentlessMermaidCommand() {
    let delegate = SionApplicationDelegate()

    XCTAssertTrue(delegate.responds(to: Selector(("newDocumentFromMermaid:"))))
  }

  /// Installing the main menu is process global, so every caller restores it.
  private func withFileMenu(_ body: (NSMenu) throws -> Void) throws {
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

    application.mainMenu = nil
    let delegate: NSApplicationDelegate = SionApplicationDelegate()
    delegate.applicationWillFinishLaunching?(
      Notification(name: NSApplication.willFinishLaunchingNotification, object: application)
    )

    try body(try XCTUnwrap(application.mainMenu?.item(withTitle: "File")?.submenu))
  }

  private func assertItem(
    _ menu: NSMenu,
    title: String,
    action: Selector,
    key: String,
    modifiers: NSEvent.ModifierFlags = [.command],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let item = menu.item(withTitle: title)

    XCTAssertEqual(item?.action, action, file: file, line: line)
    XCTAssertNil(item?.target, file: file, line: line)
    XCTAssertEqual(item?.keyEquivalent, key, file: file, line: line)
    XCTAssertEqual(item?.keyEquivalentModifierMask, modifiers, file: file, line: line)
  }
}
