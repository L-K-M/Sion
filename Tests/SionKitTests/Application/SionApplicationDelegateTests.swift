import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionApplicationDelegateTests: XCTestCase {
  func testLaunchRegistersServicesSubmenu() throws {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    let previousServicesMenu = application.servicesMenu
    let existingWindows = Set(application.windows.map(ObjectIdentifier.init))

    defer {
      for window in application.windows
      where !existingWindows.contains(ObjectIdentifier(window)) {
        window.close()
      }

      application.mainMenu = previousMainMenu
      application.servicesMenu = previousServicesMenu
    }

    application.servicesMenu = nil
    let delegate = SionApplicationDelegate()
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification, object: application)
    )

    let applicationMenu = try XCTUnwrap(application.mainMenu?.item(at: 0)?.submenu)
    let servicesItem = try XCTUnwrap(applicationMenu.item(withTitle: "Services"))
    let servicesMenu = try XCTUnwrap(servicesItem.submenu)

    XCTAssertTrue(application.servicesMenu === servicesMenu)
  }
}
