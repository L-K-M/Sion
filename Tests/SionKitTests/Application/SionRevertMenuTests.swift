import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionRevertMenuTests: XCTestCase {
  func testLaunchInstallsNativeRevertCommand() throws {
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

    let fileMenu = try XCTUnwrap(
      application.mainMenu?.item(withTitle: TestMenu.file)?.submenu
    )
    let revert = try XCTUnwrap(fileMenu.item(withTitle: TestMenu.revertToSaved))

    XCTAssertEqual(revert.action, TestAction.revertToSaved)
    XCTAssertNil(revert.target)
    XCTAssertTrue(revert.keyEquivalent.isEmpty)
  }
}

private enum TestMenu {
  static let file = "File"
  static let revertToSaved = "Revert to Saved…"
}

private enum TestAction {
  static let revertToSaved = #selector(NSDocument.revertToSaved(_:))
}
