import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionOpenRecentMenuTests: XCTestCase {
  func testWillFinishLaunchingInstallsOpenRecentAfterOpen() throws {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    let previousServicesMenu = application.servicesMenu
    let previousWindowsMenu = application.windowsMenu

    defer {
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
}

private enum TestMenu {
  static let file = "File"
  static let open = "Open…"
  static let openRecent = "Open Recent"
}
