import CGtk
import Dispatch
import XCTest

@testable import SionGtk

final class DispatchMainQueueBridgeTests: XCTestCase {
  func testMainQueueBlocksRunInsideTheGLibMainLoop() {
    DispatchMainQueueBridge.install()

    var ran = false
    DispatchQueue.main.async { ran = true }

    let deadline = Date().addingTimeInterval(2)
    while !ran, Date() < deadline {
      g_main_context_iteration(nil, 0)
    }

    XCTAssertTrue(ran)
  }

  func testMainActorTasksResumeInsideTheGLibMainLoop() {
    DispatchMainQueueBridge.install()

    let flag = Flag()
    Task { @MainActor in flag.value = true }

    let deadline = Date().addingTimeInterval(2)
    while !flag.value, Date() < deadline {
      g_main_context_iteration(nil, 0)
    }

    XCTAssertTrue(flag.value)
  }

  private final class Flag: @unchecked Sendable {
    var value = false
  }
}
