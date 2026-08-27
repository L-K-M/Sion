import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerTransformTests: XCTestCase {
  func testNativeUndoDuringUntouchedDragKeepsHistoryInSync() throws {
    let frame = SionRect(x: 20, y: 30, width: 160, height: 96)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let controller = try makeController(elements: [], undoManager: undoManager)

    undoManager.beginUndoGrouping()
    let shapeID = try controller.insertShape(in: frame, kind: .rectangle)
    undoManager.endUndoGrouping()
    controller.select(shapeID)
    try controller.beginMove()

    XCTAssertTrue(undoManager.canUndo)
    XCTAssertFalse(undoManager.canRedo)

    undoManager.undo()

    XCTAssertNil(controller.document.scene.element(withID: shapeID))
    XCTAssertFalse(undoManager.canUndo)
    XCTAssertTrue(undoManager.canRedo)
    XCTAssertFalse(controller.hasPendingEditorGesture)

    undoManager.undo()

    XCTAssertNil(controller.document.scene.element(withID: shapeID))
    XCTAssertFalse(undoManager.canUndo)
    XCTAssertTrue(undoManager.canRedo)

    undoManager.redo()

    XCTAssertEqual(
      controller.document.scene.element(withID: shapeID)?.geometry.frame,
      frame
    )
    XCTAssertTrue(undoManager.canUndo)
    XCTAssertFalse(undoManager.canRedo)
  }

  func testRotationDragCommitsOneUndoableChange() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96)
    )
    let undoManager = UndoManager()
    var changes = 0
    let controller = try makeController(
      elements: [shape],
      undoManager: undoManager,
      didChange: { _ in changes += 1 }
    )
    controller.select(shape.id)

    try controller.beginRotation()
    try controller.rotate(shape.id, to: .pi / 4)
    try controller.rotate(shape.id, to: .pi / 2)
    try controller.endRotation()

    XCTAssertEqual(
      controller.document.scene.element(withID: shape.id)?.geometry.rotationRadians,
      .pi / 2
    )
    XCTAssertEqual(changes, 1)
    controller.undoSceneEdit()
    XCTAssertEqual(
      controller.document.scene.element(withID: shape.id)?.geometry.rotationRadians,
      0
    )
  }

  func testCornerRadiusDragChangesOnlyShapeKind() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96),
      kind: .rectangle,
      text: "Label"
    )
    shape.name = "Process"
    let controller = try makeController(elements: [shape])
    controller.select(shape.id)

    try controller.beginCornerRadiusChange()
    try controller.setCornerRadius(24, on: shape.id)
    try controller.endCornerRadiusChange()

    let changed = try XCTUnwrap(controller.document.scene.element(withID: shape.id))
    XCTAssertEqual(changed.name, "Process")
    guard case .shape(let content) = changed.content else {
      return XCTFail("Expected shape")
    }
    XCTAssertEqual(content.kind, .roundedRectangle(radius: 24))
    XCTAssertEqual(content.label?.string, "Label")
  }

  func testConnectorUsesDraggedMagnetEndpoints() throws {
    let source = SceneElement.shape(
      frame: SionRect(x: 20, y: 20, width: 160, height: 96),
      kind: .rectangle
    )
    let target = SceneElement.shape(
      frame: SionRect(x: 320, y: 20, width: 160, height: 96),
      kind: .rectangle
    )
    let controller = try makeController(elements: [source, target])
    let sourceMagnet = try XCTUnwrap(
      source.resolvedMagnets.first { $0.magnet.id == "east" }
    )
    let targetMagnet = try XCTUnwrap(
      target.resolvedMagnets.first { $0.magnet.id == "west" }
    )

    let connectorID = try controller.insertConnector(
      from: source.id,
      sourcePoint: sourceMagnet.endpoint.point,
      to: target.id,
      targetPoint: targetMagnet.endpoint.point
    )

    let connector = try XCTUnwrap(
      controller.document.scene.element(withID: connectorID)?.content.connector
    )
    XCTAssertEqual(
      connector.source,
      .element(
        source.id,
        attachment: .magnet("east"),
        fallbackPoint: sourceMagnet.endpoint.point
      )
    )
    XCTAssertEqual(
      connector.target,
      .element(
        target.id,
        attachment: .magnet("west"),
        fallbackPoint: targetMagnet.endpoint.point
      )
    )
  }

  func testConnectorRejectsAttachedSelfLoopWithoutMutation() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 20, width: 160, height: 96),
      kind: .rectangle
    )
    let document = SionDocument(scene: SionScene(elements: [shape]))
    let undoManager = UndoManager()
    var changes = 0
    let controller = try SionEditorController(
      package: SionPackage(document: document),
      undoManagerProvider: { undoManager },
      didChange: { _ in changes += 1 }
    )
    let sourceMagnet = try XCTUnwrap(
      shape.resolvedMagnets.first { $0.magnet.id == "east" }
    )
    let targetMagnet = try XCTUnwrap(
      shape.resolvedMagnets.first { $0.magnet.id == "west" }
    )
    controller.select(shape.id)

    XCTAssertThrowsError(
      try controller.insertConnector(
        from: shape.id,
        sourcePoint: sourceMagnet.endpoint.point,
        to: shape.id,
        targetPoint: targetMagnet.endpoint.point
      )
    )

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(controller.selection, [shape.id])
    XCTAssertEqual(changes, 0)
    XCTAssertFalse(undoManager.canUndo)
  }

  func testConnectorAllowsAttachedEndpointToFreePoint() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 20, width: 160, height: 96),
      kind: .rectangle
    )
    let controller = try makeController(elements: [shape])
    let sourceMagnet = try XCTUnwrap(
      shape.resolvedMagnets.first { $0.magnet.id == "east" }
    )
    let freePoint = SionPoint(x: 320, y: 220)

    let connectorID = try controller.insertConnector(
      from: shape.id,
      sourcePoint: sourceMagnet.endpoint.point,
      to: nil,
      targetPoint: freePoint
    )

    let connector = try XCTUnwrap(
      controller.document.scene.element(withID: connectorID)?.content.connector
    )
    XCTAssertEqual(connector.source.elementID, shape.id)
    XCTAssertNil(connector.target.elementID)
  }

  private func makeController(
    elements: [SceneElement],
    undoManager: UndoManager? = nil,
    didChange: @escaping (SionEditorController.DocumentChange) -> Void = { _ in }
  ) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: elements))
      ),
      undoManagerProvider: { undoManager },
      didChange: didChange
    )
  }
}
