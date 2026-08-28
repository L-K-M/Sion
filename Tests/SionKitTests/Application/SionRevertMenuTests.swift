import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionRevertMenuTests: XCTestCase {
  func testLaunchInstallsNativeRevertCommand() throws {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    let previousWindowsMenu = application.windowsMenu
    let existingWindows = Set(application.windows.map(ObjectIdentifier.init))

    defer {
      for window in application.windows
      where !existingWindows.contains(ObjectIdentifier(window)) {
        window.close()
      }

      application.mainMenu = previousMainMenu
      application.windowsMenu = previousWindowsMenu
    }

    let delegate = SionApplicationDelegate()
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification, object: application)
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
  static let revertToSaved = "Revert to Saved"
}

private enum TestAction {
  static let revertToSaved = #selector(NSDocument.revertToSaved(_:))
}
