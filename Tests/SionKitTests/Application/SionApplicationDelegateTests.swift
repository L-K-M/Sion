import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionApplicationDelegateTests: XCTestCase {
  func testWillFinishLaunchingRegistersInlineFindAndSpellingMenus() throws {
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

    let editMenu = try XCTUnwrap(application.mainMenu?.item(withTitle: "Edit")?.submenu)
    let selectAllItem = try XCTUnwrap(editMenu.item(withTitle: "Select All"))
    let findItem = try XCTUnwrap(editMenu.item(withTitle: "Find"))
    let spellingItem = try XCTUnwrap(editMenu.item(withTitle: "Spelling and Grammar"))
    let selectAllIndex = editMenu.index(of: selectAllItem)

    // Native text commands follow selection without mixing with scene commands.
    XCTAssertTrue(editMenu.item(at: selectAllIndex + 1)?.isSeparatorItem == true)
    XCTAssertEqual(editMenu.index(of: findItem), selectAllIndex + 2)
    XCTAssertEqual(editMenu.index(of: spellingItem), selectAllIndex + 3)

    let findMenu = try XCTUnwrap(findItem.submenu)
    XCTAssertEqual(
      findMenu.items.map(\.title),
      [
        "Find…", "Find Next", "Find Previous", "", "Use Selection for Find",
        "Jump to Selection",
      ]
    )
    XCTAssertTrue(findMenu.item(at: 3)?.isSeparatorItem == true)
    assertFinderItem(
      findMenu,
      title: "Find…",
      action: .showFindInterface,
      key: "f"
    )
    assertFinderItem(
      findMenu,
      title: "Find Next",
      action: .nextMatch,
      key: "g"
    )
    assertFinderItem(
      findMenu,
      title: "Find Previous",
      action: .previousMatch,
      key: "g",
      modifiers: [.command, .shift]
    )
    assertFinderItem(
      findMenu,
      title: "Use Selection for Find",
      action: .setSearchString,
      key: "e"
    )
    assertItem(
      findMenu,
      title: "Jump to Selection",
      action: #selector(NSTextView.centerSelectionInVisibleArea(_:)),
      key: "j"
    )

    let spellingMenu = try XCTUnwrap(spellingItem.submenu)
    XCTAssertEqual(
      spellingMenu.items.map(\.title),
      ["Show Spelling and Grammar", "Check Document Now"]
    )
    assertItem(
      spellingMenu,
      title: "Show Spelling and Grammar",
      action: #selector(NSText.showGuessPanel(_:)),
      key: ":"
    )
    assertItem(
      spellingMenu,
      title: "Check Document Now",
      action: #selector(NSText.checkSpelling(_:)),
      key: ";"
    )
  }

  func testWillFinishLaunchingRegistersServicesSubmenu() throws {
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
    application.servicesMenu = nil
    let delegate: NSApplicationDelegate = SionApplicationDelegate()
    delegate.applicationWillFinishLaunching?(
      Notification(name: NSApplication.willFinishLaunchingNotification, object: application)
    )

    let applicationMenu = try XCTUnwrap(application.mainMenu?.item(at: 0)?.submenu)
    let servicesItem = try XCTUnwrap(applicationMenu.item(withTitle: "Services"))
    let servicesMenu = try XCTUnwrap(servicesItem.submenu)

    let roleMenu = application.servicesMenu
    XCTAssertTrue(
      roleMenu === servicesMenu,
      "DIAG role="
        + (roleMenu.map { "\($0) super=\($0.supermenu.map(String.init(describing:)) ?? "nil")" }
          ?? "nil")
        + " item=" + String(describing: servicesMenu)
        + " itemSuper=" + (servicesMenu.supermenu.map(String.init(describing:)) ?? "nil"))
    let hideItem = try XCTUnwrap(applicationMenu.item(withTitle: "Hide Sion"))
    XCTAssertLessThan(
      applicationMenu.index(of: servicesItem),
      applicationMenu.index(of: hideItem)
    )
  }

  func testWillFinishLaunchingRegistersHelpMenu() throws {
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

    application.helpMenu = nil
    let delegate: NSApplicationDelegate = SionApplicationDelegate()
    delegate.applicationWillFinishLaunching?(
      Notification(name: NSApplication.willFinishLaunchingNotification, object: application)
    )

    let mainMenu = try XCTUnwrap(application.mainMenu)
    let helpParent = try XCTUnwrap(mainMenu.item(withTitle: HelpMenuContract.menuTitle))
    let helpMenu = try XCTUnwrap(helpParent.submenu)
    let helpItem = try XCTUnwrap(helpMenu.item(withTitle: HelpMenuContract.itemTitle))

    XCTAssertEqual(mainMenu.items.last, helpParent)
    XCTAssertTrue(application.helpMenu === helpMenu)
    XCTAssertEqual(helpItem.action, #selector(NSApplication.showHelp(_:)))
    XCTAssertTrue(helpItem.target === application)
    XCTAssertEqual(helpItem.keyEquivalent, HelpMenuContract.keyEquivalent)
    XCTAssertEqual(helpItem.keyEquivalentModifierMask, NSEvent.ModifierFlags.command)
  }

  private func assertFinderItem(
    _ menu: NSMenu,
    title: String,
    action: NSTextFinder.Action,
    key: String,
    modifiers: NSEvent.ModifierFlags = [.command],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let item = menu.item(withTitle: title)

    XCTAssertEqual(
      item?.action,
      #selector(NSResponder.performTextFinderAction(_:)),
      file: file,
      line: line
    )
    XCTAssertEqual(item?.tag, action.rawValue, file: file, line: line)
    // A nil target routes the command to the active text responder.
    XCTAssertNil(item?.target, file: file, line: line)
    XCTAssertEqual(item?.keyEquivalent, key, file: file, line: line)
    XCTAssertEqual(item?.keyEquivalentModifierMask, modifiers, file: file, line: line)
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

private enum HelpMenuContract {
  static let menuTitle = "Help"
  static let itemTitle = "Sion Help"
  static let keyEquivalent = "?"
}
