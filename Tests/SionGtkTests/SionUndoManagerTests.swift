import XCTest

@testable import SionKit

@MainActor
final class SionUndoManagerTests: XCTestCase {
  private final class Counter {
    var value = 0
  }

  func testRegistrationsWithoutASchedulerCoalesceUntilUndo() {
    let manager = SionUndoManager()
    let counter = Counter()

    manager.registerUndo(withTarget: counter) { $0.value -= 1 }
    manager.setActionName("Add")
    manager.registerUndo(withTarget: counter) { $0.value -= 1 }
    counter.value = 2

    XCTAssertTrue(manager.canUndo)
    XCTAssertFalse(manager.canRedo)
    XCTAssertEqual(manager.undoActionName, "Add")
    XCTAssertEqual(manager.undoMenuItemTitle, "Undo Add")

    manager.undo()

    XCTAssertEqual(counter.value, 0)
    XCTAssertFalse(manager.canUndo)
  }

  func testUndoRegistrationsMadeWhileUndoingBecomeRedo() {
    let manager = SionUndoManager()
    let counter = Counter()

    func increment(_ manager: SionUndoManager) {
      counter.value += 1
      manager.registerUndo(withTarget: counter) { [weak manager] _ in
        guard let manager else { return }
        decrement(manager)
      }
      manager.setActionName("Increment")
    }

    func decrement(_ manager: SionUndoManager) {
      counter.value -= 1
      manager.registerUndo(withTarget: counter) { [weak manager] _ in
        guard let manager else { return }
        increment(manager)
      }
      manager.setActionName("Increment")
    }

    increment(manager)
    XCTAssertEqual(counter.value, 1)

    manager.undo()
    XCTAssertEqual(counter.value, 0)
    XCTAssertTrue(manager.canRedo)
    XCTAssertEqual(manager.redoMenuItemTitle, "Redo Increment")

    manager.redo()
    XCTAssertEqual(counter.value, 1)
    XCTAssertTrue(manager.canUndo)
    XCTAssertFalse(manager.canRedo)
  }

  func testANewEditDiscardsRedo() {
    let manager = SionUndoManager()
    let counter = Counter()

    manager.registerUndo(withTarget: counter) { [weak manager] target in
      target.value = 0
      manager?.registerUndo(withTarget: target) { $0.value = 1 }
    }
    manager.undo()
    XCTAssertTrue(manager.canRedo)

    manager.registerUndo(withTarget: counter) { $0.value = 2 }
    XCTAssertFalse(manager.canRedo)
  }

  func testExplicitGroupsCollectOneStep() {
    let manager = SionUndoManager()
    manager.groupsByEvent = false
    let counter = Counter()

    manager.beginUndoGrouping()
    manager.registerUndo(withTarget: counter) { $0.value += 1 }
    manager.registerUndo(withTarget: counter) { $0.value += 10 }
    manager.setActionName("Both")
    manager.endUndoGrouping()

    XCTAssertEqual(manager.undoActionName, "Both")
    manager.undo()
    XCTAssertEqual(counter.value, 11)
    XCTAssertFalse(manager.canUndo)
  }

  func testTheEventSchedulerClosesTheImplicitGroup() {
    let manager = SionUndoManager()
    var scheduled: [@MainActor () -> Void] = []
    manager.eventGroupScheduler = { scheduled.append($0) }
    let counter = Counter()

    manager.registerUndo(withTarget: counter) { $0.value += 1 }
    manager.setActionName("First")
    manager.registerUndo(withTarget: counter) { $0.value += 1 }
    XCTAssertEqual(scheduled.count, 1)

    scheduled.removeFirst()()

    manager.registerUndo(withTarget: counter) { $0.value += 100 }
    manager.setActionName("Second")
    XCTAssertEqual(scheduled.count, 1)
    scheduled.removeFirst()()

    XCTAssertEqual(manager.undoActionName, "Second")
    manager.undo()
    XCTAssertEqual(counter.value, 100)
    XCTAssertEqual(manager.undoActionName, "First")
    manager.undo()
    XCTAssertEqual(counter.value, 102)
  }

  func testLevelsOfUndoTrimTheOldestSteps() {
    let manager = SionUndoManager()
    manager.groupsByEvent = false
    manager.levelsOfUndo = 2
    let counter = Counter()

    for step in 1...3 {
      manager.beginUndoGrouping()
      manager.registerUndo(withTarget: counter) { $0.value += step }
      manager.endUndoGrouping()
    }

    manager.undo()
    manager.undo()
    XCTAssertFalse(manager.canUndo)
    XCTAssertEqual(counter.value, 5)
  }

  func testRemovingActionsForATargetDropsEmptyGroups() {
    let manager = SionUndoManager()
    manager.groupsByEvent = false
    let counter = Counter()
    let other = Counter()

    manager.beginUndoGrouping()
    manager.registerUndo(withTarget: counter) { $0.value += 1 }
    manager.endUndoGrouping()
    manager.beginUndoGrouping()
    manager.registerUndo(withTarget: other) { $0.value += 1 }
    manager.endUndoGrouping()

    manager.removeAllActions(withTarget: counter)
    XCTAssertTrue(manager.canUndo)
    manager.undo()
    XCTAssertEqual(other.value, 1)
    XCTAssertFalse(manager.canUndo)
  }
}
