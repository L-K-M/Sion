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
      shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0, width: 50),
      shape(id: "00000000-0000-0000-0000-000000000002", x: 60, y: 0, width: 80),
      shape(id: "00000000-0000-0000-0000-000000000003", x: 300, y: 0, width: 20),
    ]
    let controller = try makeController(elements: frames)
    controller.selectAll()

    try controller.distributeSelection(.horizontal)

    let sorted = frames.map(\.id).compactMap { controller.frame(of: $0) }.sorted {
      $0.minX < $1.minX
    }
    // Varied widths pin the extremes and equalize the gaps.
    XCTAssertEqual(sorted[0].minX, 0, accuracy: 1e-6)
    XCTAssertEqual(sorted[2].maxX, 320, accuracy: 1e-6)
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

    // A nudge against a locked selection is refused, not just unadvertised.
    try controller.nudgeSelection(by: SionVector(dx: 10, dy: 0))
    XCTAssertEqual(controller.frame(of: element.id)?.minX, 0)

    try controller.setSelectionLockState(.editable)
    XCTAssertTrue(controller.canMoveSelection)
  }

  func testAlignWithGroupAndChildSelectedDoesNotDoubleMoveChild() throws {
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    var child = shape(id: "00000000-0000-0000-0000-00000000000B", x: 10, y: 10)
    child.parentID = group.id
    let controller = try makeController(elements: [group, child])
    controller.select(group.id)
    controller.select(child.id, mode: .extend)

    try controller.alignSelection(.trailing)

    // The child rides its parent exactly once; a second translate would
    // move it past the parent's edge.
    XCTAssertEqual(controller.frame(of: child.id)?.minX, 10)
    XCTAssertEqual(controller.frame(of: group.id)?.minX, 0)
  }

  func testAlignUsesRotatedPaintedBounds() throws {
    var rotated = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0, width: 100)
    rotated.geometry.rotationRadians = .pi / 2
    let plain = shape(id: "00000000-0000-0000-0000-000000000002", x: 0, y: 100, width: 20)
    let controller = try makeController(elements: [rotated, plain])
    controller.select(rotated.id)
    controller.select(plain.id, mode: .extend)

    try controller.alignSelection(.top)

    // The 100x40 frame rotated 90 degrees paints 40x100 around its center,
    // so its painted top sits 30pt above the frame origin, at y=-30. Frame-
    // based alignment would put the plain element at 0; bounds-based at -30.
    let rotatedFrame = try XCTUnwrap(controller.frame(of: rotated.id))
    let plainFrame = try XCTUnwrap(controller.frame(of: plain.id))
    XCTAssertEqual(rotatedFrame.minY, 0, accuracy: 1e-6)
    XCTAssertEqual(plainFrame.minY, -30, accuracy: 1e-6)
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
