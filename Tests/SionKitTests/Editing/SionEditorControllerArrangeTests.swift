import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerArrangeTests: XCTestCase {
  private func makeController(
    elements: [SceneElement],
    undoManager: UndoManager? = nil,
    didChange: @escaping (SionEditorController.DocumentChange) -> Void = { _ in }
  ) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument(scene: SionScene(elements: elements))),
      undoManagerProvider: { undoManager },
      didChange: didChange
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

  func testAlignUsesPaintedBoundsAndCommitsOneUndo() throws {
    var thin = shape(id: "00000000-0000-0000-0000-000000000001", x: 10, y: 0)
    thin.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .primaryInk, width: 2)
    )
    var thick = shape(id: "00000000-0000-0000-0000-000000000002", x: 200, y: 90)
    thick.style = ElementStyle(
      fill: .none,
      stroke: StrokeStyle(color: .primaryInk, width: 20)
    )
    let document = SionDocument(scene: SionScene(elements: [thin, thick]))
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes = 0
    let controller = try makeController(
      elements: [thin, thick],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    controller.select([thin.id, thick.id])

    try controller.alignSelection(.leading)

    let alignedThin = try XCTUnwrap(controller.document.scene.element(withID: thin.id))
    let alignedThick = try XCTUnwrap(controller.document.scene.element(withID: thick.id))
    XCTAssertEqual(
      SceneRenderGeometry.paintedBounds(of: alignedThin).minX,
      SceneRenderGeometry.paintedBounds(of: alignedThick).minX,
      accuracy: 1e-6
    )
    XCTAssertEqual(changes, 1)
    XCTAssertTrue(undoManager.canUndo)

    undoManager.undo()

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 2)
    XCTAssertFalse(undoManager.canUndo)
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

  func testLockedSelectionCannotMoveInZOrder() throws {
    var locked = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    locked.lockState = .locked
    let other = shape(id: "00000000-0000-0000-0000-000000000002", x: 200, y: 0)
    let document = SionDocument(scene: SionScene(elements: [locked, other]))
    let undoManager = UndoManager()
    var changes = 0
    let controller = try makeController(
      elements: [locked, other],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    controller.select(locked.id)

    XCTAssertNoThrow(try controller.moveSelectionInZOrder(.front))
    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 0)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testDuplicateCopiesWithOffsetAndRepeatsManualOffset() throws {
    let defaultOffset = 16.0
    let manualOffset = SionVector(dx: 100, dy: 0)
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 100, y: 100)
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    let firstIDs = try controller.duplicateSelection()

    XCTAssertEqual(firstIDs.count, 1)
    let firstCopyFrame = try XCTUnwrap(controller.frame(of: firstIDs[0]))
    XCTAssertEqual(firstCopyFrame.minX, element.geometry.frame.minX + defaultOffset, accuracy: 1e-6)
    XCTAssertEqual(firstCopyFrame.minY, element.geometry.frame.minY + defaultOffset, accuracy: 1e-6)
    XCTAssertEqual(controller.selectedElementIDs(), Set(firstIDs))

    // Move the copy by hand, then duplicate again: the manual offset repeats.
    try controller.beginMove()
    try controller.moveSelection(by: manualOffset)
    try controller.endMove()
    let movedCopyFrame = try XCTUnwrap(controller.frame(of: firstIDs[0]))

    let secondIDs = try controller.duplicateSelection()
    let secondCopyFrame = try XCTUnwrap(controller.frame(of: secondIDs[0]))
    XCTAssertEqual(secondCopyFrame.minX, movedCopyFrame.minX + manualOffset.dx, accuracy: 1e-6)
    XCTAssertEqual(secondCopyFrame.minY, movedCopyFrame.minY + manualOffset.dy, accuracy: 1e-6)
  }

  func testDuplicateCopiesGroupHierarchy() throws {
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    var child = shape(id: "00000000-0000-0000-0000-00000000000B", x: 10, y: 10)
    child.parentID = group.id
    let controller = try makeController(elements: [group, child])
    controller.select(group.id)

    let insertedIDs = try controller.duplicateSelection()

    XCTAssertEqual(insertedIDs.count, 2)
    let inserted = insertedIDs.compactMap(controller.document.scene.element(withID:))
    let copiedGroup = try XCTUnwrap(inserted.first { $0.content.isGroup })
    let copiedChild = try XCTUnwrap(inserted.first { !$0.content.isGroup })
    XCTAssertEqual(copiedChild.parentID, copiedGroup.id)
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

  func testAlignExcludesGroupRecordButMovesSelectedChild() throws {
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    var child = shape(id: "00000000-0000-0000-0000-00000000000B", x: 10, y: 10)
    child.parentID = group.id
    let outside = shape(id: "00000000-0000-0000-0000-00000000000C", x: 200, y: 10)
    let controller = try makeController(elements: [group, child, outside])
    controller.select([group.id, child.id, outside.id])

    XCTAssertEqual(controller.arrangeableSelectionCount, 2)

    try controller.alignSelection(.leading)

    // Groups have no painted content; explicitly selected children still act.
    XCTAssertEqual(controller.frame(of: child.id)?.minX, 10)
    XCTAssertEqual(controller.frame(of: group.id)?.minX, 0)
    XCTAssertEqual(controller.frame(of: outside.id)?.minX, 10)
  }

  func testGroupRecordIsExcludedFromZOrderLockAndHide() throws {
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    var child = shape(id: "00000000-0000-0000-0000-00000000000B", x: 10, y: 10)
    child.parentID = group.id
    let outside = shape(id: "00000000-0000-0000-0000-00000000000C", x: 200, y: 10)
    let document = SionDocument(scene: SionScene(elements: [group, child, outside]))

    let zOrderController = try makeController(elements: document.scene.elements)
    zOrderController.select(group.id)
    try zOrderController.moveSelectionInZOrder(.front)
    XCTAssertEqual(zOrderController.document, document)

    let lockController = try makeController(elements: document.scene.elements)
    lockController.select(group.id)
    try lockController.setSelectionLockState(.locked)
    XCTAssertEqual(lockController.document, document)

    let hideController = try makeController(elements: document.scene.elements)
    hideController.select(group.id)
    try hideController.hideSelection()
    XCTAssertEqual(hideController.document, document)
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

  func testRevealAllRestoresLockedHiddenElementAndOneUndo() throws {
    var element = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    element.visibility = .hidden
    element.lockState = .locked
    let document = SionDocument(scene: SionScene(elements: [element]))
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes = 0
    let controller = try makeController(
      elements: [element],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )

    try controller.revealHiddenElements()

    XCTAssertEqual(controller.visibility(of: element.id), .visible)
    XCTAssertEqual(controller.lockState(of: element.id), .locked)
    XCTAssertEqual(changes, 1)
    XCTAssertTrue(undoManager.canUndo)

    undoManager.undo()

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 2)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testArrangeMenuValidationMatchesExecutableSelection() throws {
    _ = NSApplication.shared
    let editable = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    var locked = shape(id: "00000000-0000-0000-0000-000000000002", x: 100, y: 0)
    locked.lockState = .locked
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
      frame: SionRect(x: 200, y: 0, width: 100, height: 100)
    )
    let controller = try makeController(elements: [editable, locked, group])
    let canvas = SionCanvasView(editorController: controller)

    controller.select(editable.id)
    XCTAssertTrue(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.lockSelection(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.unlockSelection(_:))))
    XCTAssertTrue(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.hideSelection(_:))))
    XCTAssertTrue(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.bringForward(_:))))

    controller.select(locked.id)
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.lockSelection(_:))))
    XCTAssertTrue(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.unlockSelection(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.hideSelection(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.bringForward(_:))))

    controller.select(group.id)
    XCTAssertTrue(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.duplicate(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.lockSelection(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.unlockSelection(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.hideSelection(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.bringToFront(_:))))
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

  fileprivate func lockState(of id: ElementID) -> ElementLockState? {
    document.scene.element(withID: id)?.lockState
  }
}

extension SionCanvasView {
  fileprivate func menuItemIsEnabled(action: Selector) -> Bool {
    validateMenuItem(NSMenuItem(title: "Test", action: action, keyEquivalent: ""))
  }
}
