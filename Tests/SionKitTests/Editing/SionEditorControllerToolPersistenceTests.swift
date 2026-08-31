import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerToolPersistenceTests: XCTestCase {
  func testDefaultToolIsStickySelect() throws {
    let controller = try makeController()

    XCTAssertEqual(controller.tool, .select)
    XCTAssertEqual(controller.toolPersistence, .sticky)
  }

  func testOneShotToolRevertsToSelectAfterOneUse() throws {
    let controller = try makeController()
    controller.setTool(.rectangle, persistence: .oneShot)

    XCTAssertTrue(controller.toolDidComplete(.rectangle))
    XCTAssertEqual(controller.tool, .select)
    XCTAssertEqual(controller.toolPersistence, .sticky)
  }

  func testStickyToolSurvivesEveryUse() throws {
    let controller = try makeController()
    controller.setTool(.rectangle, persistence: .sticky)

    XCTAssertFalse(controller.toolDidComplete(.rectangle))
    XCTAssertFalse(controller.toolDidComplete(.rectangle))
    XCTAssertEqual(controller.tool, .rectangle)
    XCTAssertEqual(controller.toolPersistence, .sticky)
  }

  func testCompletingADifferentToolDoesNotSpendTheArmedOne() throws {
    let controller = try makeController()
    controller.setTool(.rectangle, persistence: .oneShot)

    XCTAssertFalse(controller.toolDidComplete(.connector))
    XCTAssertEqual(controller.tool, .rectangle)
    XCTAssertEqual(controller.toolPersistence, .oneShot)
  }

  func testSelectIsAlwaysSticky() throws {
    let controller = try makeController()
    controller.setTool(.select, persistence: .oneShot)

    XCTAssertEqual(controller.toolPersistence, .sticky)
    XCTAssertFalse(controller.toolDidComplete(.select))
    XCTAssertEqual(controller.tool, .select)
  }

  func testSecondClickUpgradesTheSameToolInPlace() throws {
    let controller = try makeController()
    var notifications = 0
    controller.observeChanges { notifications += 1 }

    controller.setTool(.text, persistence: .oneShot)
    controller.setTool(.text, persistence: .sticky)

    XCTAssertEqual(controller.tool, .text)
    XCTAssertEqual(controller.toolPersistence, .sticky)
    XCTAssertEqual(notifications, 2)

    // A repeat with no change stays a no-op.
    controller.setTool(.text, persistence: .sticky)

    XCTAssertEqual(notifications, 2)
  }

  func testUpgradingInPlaceKeepsAnchorEditingWhileASwitchClearsIt() throws {
    let element = SceneElement.shape(frame: SionRect(x: 0, y: 0, width: 120, height: 80))
    let controller = try makeController(elements: [element])
    controller.setTool(.rectangle, persistence: .oneShot)
    controller.select(element.id)
    controller.beginAnchorEditing(on: element.id)
    XCTAssertEqual(controller.anchorEditingState, .editing(element.id))

    controller.setTool(.rectangle, persistence: .sticky)

    XCTAssertEqual(controller.anchorEditingState, .editing(element.id))

    controller.setTool(.text, persistence: .oneShot)

    XCTAssertEqual(controller.anchorEditingState, .inactive)
  }

  private func makeController(elements: [SceneElement] = []) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument(scene: SionScene(elements: elements))),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }
}
