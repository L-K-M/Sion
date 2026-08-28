import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerArrangeTests: XCTestCase {
  private func makeController(
    elements: [SceneElement],
    canvas: SionCanvas = SionCanvas(),
    undoManager: UndoManager? = nil,
    didChange: @escaping (SionEditorController.DocumentChange) -> Void = { _ in }
  ) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(canvas: canvas, elements: elements))
      ),
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
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes = 0
    let controller = try makeController(
      elements: [thin, thick],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    let document = controller.document
    controller.select([thin.id, thick.id])

    undoManager.beginUndoGrouping()
    try controller.alignSelection(.leading)
    undoManager.endUndoGrouping()

    let alignedThin = try XCTUnwrap(controller.document.scene.element(withID: thin.id))
    let alignedThick = try XCTUnwrap(controller.document.scene.element(withID: thick.id))
    XCTAssertEqual(
      SceneRenderGeometry.paintedBounds(of: alignedThin).minX,
      SceneRenderGeometry.paintedBounds(of: alignedThick).minX,
      accuracy: 1e-6
    )
    XCTAssertEqual(changes, 1)
    XCTAssertTrue(undoManager.canUndo)
    XCTAssertEqual(undoManager.undoActionName, "Align")

    undoManager.undo()

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 2)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testDistributeHorizontallyEqualizesGaps() throws {
    let frames = [
      shape(id: "00000000-0000-0000-0000-000000000003", x: 300, y: 0, width: 20),
      shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0, width: 50),
      shape(id: "00000000-0000-0000-0000-000000000002", x: 60, y: 0, width: 80),
    ]
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes = 0
    let controller = try makeController(
      elements: frames,
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    let document = controller.document
    controller.selectAll()

    undoManager.beginUndoGrouping()
    try controller.distributeSelection(.horizontal)
    undoManager.endUndoGrouping()

    let sorted = frames.map(\.id).compactMap { controller.frame(of: $0) }.sorted {
      $0.minX < $1.minX
    }
    // Varied widths pin the extremes and equalize the gaps.
    XCTAssertEqual(sorted[0].minX, 0, accuracy: 1e-6)
    XCTAssertEqual(sorted[2].maxX, 320, accuracy: 1e-6)
    XCTAssertEqual(sorted[1].minX - sorted[0].maxX, sorted[2].minX - sorted[1].maxX, accuracy: 1e-6)
    XCTAssertEqual(changes, 1)
    XCTAssertEqual(undoManager.undoActionName, "Distribute")

    undoManager.undo()

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 2)
    XCTAssertFalse(undoManager.canUndo)
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

  func testZOrderCommitsOneUndo() throws {
    let first = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    let second = shape(id: "00000000-0000-0000-0000-000000000002", x: 200, y: 0)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes = 0
    let controller = try makeController(
      elements: [first, second],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    let document = controller.document
    controller.select(first.id)

    undoManager.beginUndoGrouping()
    try controller.moveSelectionInZOrder(.front)
    undoManager.endUndoGrouping()

    XCTAssertEqual(controller.orderedIDs(), [second.id, first.id])
    XCTAssertEqual(changes, 1)
    XCTAssertEqual(undoManager.undoActionName, "Bring to Front")

    undoManager.undo()

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 2)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testLockedSelectionCannotMoveInZOrder() throws {
    var locked = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    locked.lockState = .locked
    let other = shape(id: "00000000-0000-0000-0000-000000000002", x: 200, y: 0)
    let undoManager = UndoManager()
    var changes = 0
    let controller = try makeController(
      elements: [locked, other],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    let document = controller.document
    controller.select(locked.id)

    XCTAssertNoThrow(try controller.moveSelectionInZOrder(.front))
    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 0)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testDuplicateCopiesWithOffsetAndRepeatsManualOffset() throws {
    let defaultOffset = CanvasDefaults.gridSpacing
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

    let thirdIDs = try controller.duplicateSelection()
    let thirdCopyFrame = try XCTUnwrap(controller.frame(of: thirdIDs[0]))
    XCTAssertEqual(thirdCopyFrame.minX, secondCopyFrame.minX + manualOffset.dx, accuracy: 1e-6)
    XCTAssertEqual(thirdCopyFrame.minY, secondCopyFrame.minY + manualOffset.dy, accuracy: 1e-6)
  }

  func testPowerDuplicateIgnoresTrailingResize() throws {
    let offset = CanvasDefaults.gridSpacing
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 100, y: 100)
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    let firstID = try XCTUnwrap(controller.duplicateSelection().first)
    let firstFrame = try XCTUnwrap(controller.frame(of: firstID))
    try controller.beginResize()
    try controller.resize(
      firstID,
      to: SionRect(
        x: firstFrame.minX,
        y: firstFrame.minY,
        width: firstFrame.width + 80,
        height: firstFrame.height
      )
    )
    try controller.endResize()
    let resizedFrame = try XCTUnwrap(controller.frame(of: firstID))

    let secondID = try XCTUnwrap(controller.duplicateSelection().first)
    let secondFrame = try XCTUnwrap(controller.frame(of: secondID))

    XCTAssertEqual(secondFrame.minX, resizedFrame.minX + offset, accuracy: 1e-6)
    XCTAssertEqual(secondFrame.minY, resizedFrame.minY + offset, accuracy: 1e-6)
  }

  func testPowerDuplicateIgnoresLeadingResize() throws {
    let offset = CanvasDefaults.gridSpacing
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 100, y: 100)
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    let firstID = try XCTUnwrap(controller.duplicateSelection().first)
    let firstFrame = try XCTUnwrap(controller.frame(of: firstID))
    try controller.beginResize()
    try controller.resize(
      firstID,
      to: SionRect(
        x: firstFrame.minX - 80,
        y: firstFrame.minY,
        width: firstFrame.width + 80,
        height: firstFrame.height
      )
    )
    try controller.endResize()
    let resizedFrame = try XCTUnwrap(controller.frame(of: firstID))

    let secondID = try XCTUnwrap(controller.duplicateSelection().first)
    let secondFrame = try XCTUnwrap(controller.frame(of: secondID))

    XCTAssertEqual(secondFrame.minX, resizedFrame.minX + offset, accuracy: 1e-6)
    XCTAssertEqual(secondFrame.minY, resizedFrame.minY + offset, accuracy: 1e-6)
  }

  func testPowerDuplicateAdoptsAccumulatedNudges() throws {
    let firstNudge = SionVector(dx: 4, dy: -2)
    let secondNudge = SionVector(dx: 8, dy: 6)
    let expectedOffset = firstNudge + secondNudge
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 100, y: 100)
    let controller = try makeController(elements: [element])
    controller.select(element.id)

    let firstID = try XCTUnwrap(controller.duplicateSelection().first)
    try controller.nudgeSelection(by: firstNudge)
    try controller.nudgeSelection(by: secondNudge)
    let movedFrame = try XCTUnwrap(controller.frame(of: firstID))

    let secondID = try XCTUnwrap(controller.duplicateSelection().first)
    let secondFrame = try XCTUnwrap(controller.frame(of: secondID))

    XCTAssertEqual(secondFrame.minX, movedFrame.minX + expectedOffset.dx, accuracy: 1e-6)
    XCTAssertEqual(secondFrame.minY, movedFrame.minY + expectedOffset.dy, accuracy: 1e-6)
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

  func testDuplicateCommitsOneUndo() throws {
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 100, y: 100)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes = 0
    let controller = try makeController(
      elements: [element],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    let document = controller.document
    controller.select(element.id)

    undoManager.beginUndoGrouping()
    let insertedIDs = try controller.duplicateSelection()
    undoManager.endUndoGrouping()

    XCTAssertEqual(insertedIDs.count, 1)
    XCTAssertEqual(controller.document.scene.elements.count, 2)
    XCTAssertEqual(changes, 1)
    XCTAssertEqual(undoManager.undoActionName, "Duplicate")

    undoManager.undo()

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 2)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testDuplicateCapsImportedGridSpacing() throws {
    let maximumAutomaticOffset = CanvasDefaults.gridSpacing * 4
    let element = shape(id: "00000000-0000-0000-0000-000000000001", x: 100, y: 100)
    let canvas = SionCanvas(
      grid: CanvasGrid(spacing: SceneLimits.maximumCoordinateMagnitude)
    )
    let controller = try makeController(elements: [element], canvas: canvas)
    controller.select(element.id)

    let insertedIDs = try controller.duplicateSelection()
    let copyFrame = try XCTUnwrap(controller.frame(of: insertedIDs[0]))

    XCTAssertEqual(
      copyFrame.minX,
      element.geometry.frame.minX + maximumAutomaticOffset,
      accuracy: 1e-6
    )
    XCTAssertEqual(
      copyFrame.minY,
      element.geometry.frame.minY + maximumAutomaticOffset,
      accuracy: 1e-6
    )
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

  func testLockedSelectionCannotAlignOrDistribute() throws {
    let elements = [
      shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0),
      shape(id: "00000000-0000-0000-0000-000000000002", x: 100, y: 40),
      shape(id: "00000000-0000-0000-0000-000000000003", x: 300, y: 80),
    ].map { element in
      var locked = element
      locked.lockState = .locked
      return locked
    }
    let undoManager = UndoManager()
    var changes = 0
    let controller = try makeController(
      elements: elements,
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    let document = controller.document
    controller.select(Set(elements.map(\.id)))

    XCTAssertNoThrow(try controller.alignSelection(.leading))
    XCTAssertNoThrow(try controller.distributeSelection(.horizontal))
    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 0)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testAlignExcludesSelectedGroupHierarchy() throws {
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    var child = shape(id: "00000000-0000-0000-0000-00000000000B", x: 10, y: 10)
    child.parentID = group.id
    let firstOutside = shape(id: "00000000-0000-0000-0000-00000000000C", x: 200, y: 10)
    let secondOutside = shape(id: "00000000-0000-0000-0000-00000000000D", x: 320, y: 10)
    let controller = try makeController(elements: [group, child, firstOutside, secondOutside])
    controller.select([group.id, child.id, firstOutside.id, secondOutside.id])

    XCTAssertEqual(controller.arrangeableSelectionCount, 2)

    try controller.alignSelection(.leading)

    // Group hierarchy behavior is deferred, so the selected subtree stays put.
    XCTAssertEqual(controller.frame(of: child.id)?.minX, 10)
    XCTAssertEqual(controller.frame(of: group.id)?.minX, 0)
    XCTAssertEqual(controller.frame(of: firstOutside.id)?.minX, 200)
    XCTAssertEqual(controller.frame(of: secondOutside.id)?.minX, 200)
  }

  func testAlignParentedChildUsesAbsoluteCanvasCoordinates() throws {
    var group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    group.geometry.rotationRadians = .pi / 2
    var child = shape(id: "00000000-0000-0000-0000-00000000000B", x: 20, y: 20)
    child.parentID = group.id
    let outside = shape(id: "00000000-0000-0000-0000-00000000000C", x: 200, y: 20)
    let controller = try makeController(elements: [group, child, outside])
    controller.select([child.id, outside.id])

    try controller.alignSelection(.leading)

    let alignedChild = try XCTUnwrap(controller.document.scene.element(withID: child.id))
    let alignedOutside = try XCTUnwrap(controller.document.scene.element(withID: outside.id))
    XCTAssertEqual(
      SceneRenderGeometry.paintedBounds(of: alignedChild).minX,
      SceneRenderGeometry.paintedBounds(of: alignedOutside).minX,
      accuracy: 1e-6
    )
    XCTAssertEqual(controller.document.scene.element(withID: group.id), group)
  }

  func testGroupRecordIsExcludedFromZOrderLockAndHide() throws {
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    var child = shape(id: "00000000-0000-0000-0000-00000000000B", x: 10, y: 10)
    child.parentID = group.id
    let outside = shape(id: "00000000-0000-0000-0000-00000000000C", x: 200, y: 10)
    let elements = [group, child, outside]

    let zOrderController = try makeController(elements: elements)
    let zOrderDocument = zOrderController.document
    zOrderController.select([group.id, child.id])
    try zOrderController.moveSelectionInZOrder(.front)
    XCTAssertEqual(zOrderController.document, zOrderDocument)

    let lockController = try makeController(elements: elements)
    let lockDocument = lockController.document
    lockController.select([group.id, child.id])
    try lockController.setSelectionLockState(.locked)
    XCTAssertEqual(lockController.document, lockDocument)

    let hideController = try makeController(elements: elements)
    let hideDocument = hideController.document
    hideController.select([group.id, child.id])
    try hideController.hideSelection()
    XCTAssertEqual(hideController.document, hideDocument)
  }

  func testAlignUsesRotatedPaintedBounds() throws {
    var rotated = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0, width: 100)
    rotated.geometry.rotationRadians = .pi / 2
    let plain = shape(id: "00000000-0000-0000-0000-000000000002", x: 0, y: 100, width: 20)
    let controller = try makeController(elements: [rotated, plain])
    controller.select(rotated.id)
    controller.select(plain.id, mode: .extend)

    try controller.alignSelection(.top)

    let alignedRotated = try XCTUnwrap(
      controller.document.scene.element(withID: rotated.id)
    )
    let alignedPlain = try XCTUnwrap(
      controller.document.scene.element(withID: plain.id)
    )
    XCTAssertEqual(
      SceneRenderGeometry.paintedBounds(of: alignedRotated).minY,
      SceneRenderGeometry.paintedBounds(of: alignedPlain).minY,
      accuracy: 1e-6
    )
    XCTAssertEqual(alignedRotated.geometry.frame.minY, 0, accuracy: 1e-6)
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
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes = 0
    let controller = try makeController(
      elements: [element],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    let document = controller.document

    undoManager.beginUndoGrouping()
    try controller.revealHiddenElements()
    undoManager.endUndoGrouping()

    XCTAssertEqual(controller.visibility(of: element.id), .visible)
    XCTAssertEqual(controller.lockState(of: element.id), .locked)
    XCTAssertEqual(changes, 1)
    XCTAssertTrue(undoManager.canUndo)
    XCTAssertEqual(undoManager.undoActionName, "Reveal All")

    undoManager.undo()

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(changes, 2)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testRevealAllEndsAnchorEditing() throws {
    let editing = shape(id: "00000000-0000-0000-0000-000000000001", x: 0, y: 0)
    var hidden = shape(id: "00000000-0000-0000-0000-000000000002", x: 100, y: 0)
    hidden.visibility = .hidden
    let controller = try makeController(elements: [editing, hidden])
    controller.select(editing.id)
    controller.beginAnchorEditing(on: editing.id)
    XCTAssertEqual(controller.anchorEditingState, .editing(editing.id))

    try controller.revealHiddenElements()

    XCTAssertEqual(controller.anchorEditingState, .inactive)
    XCTAssertEqual(controller.visibility(of: hidden.id), .visible)
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
    let top = shape(id: "00000000-0000-0000-0000-000000000004", x: 300, y: 0)
    let controller = try makeController(elements: [editable, locked, group, top])
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

    controller.select(top.id)
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.bringToFront(_:))))
    XCTAssertFalse(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.bringForward(_:))))
    XCTAssertTrue(canvas.menuItemIsEnabled(action: #selector(SionCanvasView.sendBackward(_:))))
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
