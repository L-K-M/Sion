import AppKit
import XCTest

@testable import SionKit

@MainActor
final class SionApplicationDelegateTests: XCTestCase {
  func testWillFinishLaunchingRegistersServicesSubmenu() throws {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    let previousServicesMenu = application.servicesMenu

    defer {
      application.mainMenu = previousMainMenu
      application.servicesMenu = previousServicesMenu
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

    XCTAssertTrue(application.servicesMenu === servicesMenu)
  }
}
