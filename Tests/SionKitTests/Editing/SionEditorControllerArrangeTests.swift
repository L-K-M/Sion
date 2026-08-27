import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerArrangeTests: XCTestCase {
  private func makeController(elements: [SceneElement]) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument(scene: SionScene(elements: elements))),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func shape(id: String, x: Double, y: Double, width: Double = 50) -> SceneElement {
    SceneElement.shape(
      id: ElementID(rawValue: UUID(uuidString: id)!),
      frame: SionRect(x: x, y: y, width: width, height: 40)
    )
  }

  func testAlignLeadingSharesMinimumX() throws {
    let first = shape(id: "00000000-0000-0000-0000-000000000001", x: 10, y: 0)
    let second = shape(id: "00000000-0000-0000-0000-000000000002", x: 200, y: 90)
    let controller = try makeController(elements: [first, second])
    controller.select(first.id)
    controller.select(second.id, mode: .extend)

    try controller.alignSelection(.leading)

    XCTAssertEqual(controller.frame(of: first.id)?.minX, 10)
    XCTAssertEqual(controller.frame(of: second.id)?.minX, 10)
  }

  func testDistributeHorizontallyEqualizesGaps() throws {
    let frames = [
      shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0),
      shape(id: "00000000-0000-0000-0000-000000000002", x: 60, y: 0),
      shape(id: "00000000-0000-0000-0000-000000000003", x: 300, y: 0),
    ]
    let controller = try makeController(elements: frames)
    controller.selectAll()

    try controller.distributeSelection(.horizontal)

    let sorted = frames.map(\.id).compactMap { controller.frame(of: $0) }.sorted {
      $0.minX < $1.minX
    }
    XCTAssertEqual(sorted[1].minX - sorted[0].maxX, sorted[2].minX - sorted[1].maxX, accuracy: 1e-6)
  }

  func testBringForwardMovesSelectionAboveNextElement() throws {
    let first = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    let second = shape(id: "00000000-0000-0000-0000-000000000002", x: 200, y: 0)
    let third = shape(id: "00000000-0000-0000-0000-000000000003", x: 400, y: 0)
    let controller = try makeController(elements: [first, second, third])
    controller.select(first.id)

    try controller.moveSelectionInZOrder(.forward)

    XCTAssertEqual(controller.orderedIDs(), [second.id, first.id, third.id])

    try controller.moveSelectionInZOrder(.front)
    XCTAssertEqual(controller.orderedIDs(), [second.id, third.id, first.id])

    try controller.moveSelectionInZOrder(.backward)
    XCTAssertEqual(controller.orderedIDs(), [second.id, first.id, third.id])

    try controller.moveSelectionInZOrder(.back)
    XCTAssertEqual(controller.orderedIDs(), [first.id, second.id, third.id])
  }

  func testDuplicateCopiesWithOffsetAndRepeatsManualOffset() throws {
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 100, y: 100)
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    let firstIDs = try controller.duplicateSelection()

    XCTAssertEqual(firstIDs.count, 1)
    let firstCopyFrame = try XCTUnwrap(controller.frame(of: firstIDs[0]))
    XCTAssertEqual(firstCopyFrame.minX, 116, accuracy: 1e-6)
    XCTAssertEqual(firstCopyFrame.minY, 116, accuracy: 1e-6)
    XCTAssertEqual(controller.selectedElementIDs(), Set(firstIDs))

    // Move the copy by hand, then duplicate again: the manual offset repeats.
    try controller.beginMove()
    try controller.moveSelection(by: SionVector(dx: 100, dy: 0))
    try controller.endMove()

    let secondIDs = try controller.duplicateSelection()
    let secondCopyFrame = try XCTUnwrap(controller.frame(of: secondIDs[0]))
    XCTAssertEqual(secondCopyFrame.minX, firstCopyFrame.minX + 200, accuracy: 1e-6)
    XCTAssertEqual(secondCopyFrame.minY, firstCopyFrame.minY, accuracy: 1e-6)
  }

  func testLockPreventsMoveUntilUnlock() throws {
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    try controller.setSelectionLockState(.locked)
    XCTAssertFalse(controller.canMoveSelection)

    try controller.setSelectionLockState(.editable)
    XCTAssertTrue(controller.canMoveSelection)
  }

  func testHidePrunesSelectionAndRevealRestores() throws {
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    try controller.hideSelection()

    XCTAssertTrue(controller.selection.isEmpty)
    XCTAssertEqual(controller.visibility(of: element.id), .hidden)

    try controller.revealHiddenElements()
    XCTAssertEqual(controller.visibility(of: element.id), .visible)
  }
}

extension SionEditorController {
  fileprivate func frame(of id: ElementID) -> SionRect? {
    document.scene.element(withID: id)?.geometry.frame.standardized
  }

  fileprivate func orderedIDs() -> [ElementID] {
    document.scene.elements.map(\.id)
  }

  fileprivate func selectedElementIDs() -> Set<ElementID> {
    selection
  }

  fileprivate func visibility(of id: ElementID) -> ElementVisibility? {
    document.scene.element(withID: id)?.visibility
  }
}
