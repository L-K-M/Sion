import XCTest

@testable import SionCore

final class SceneEditorTests: XCTestCase {
  func testReplacingSceneIsAtomicAndUndoableAcrossLockedContent() throws {
    var locked = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 160, height: 96)
    )
    locked.lockState = .locked
    let original = SionDocument(scene: SionScene(elements: [locked]))
    let replacement = SionScene(
      elements: [
        SceneElement.text(
          frame: SionRect(x: 40, y: 40, width: 200, height: 50),
          text: "Recovered"
        )
      ]
    )
    var editor = try SceneEditor(document: original)

    let result = try editor.perform(
      SceneTransaction(
        name: "Restore Revision",
        command: .replaceScene(replacement)
      )
    )

    XCTAssertEqual(result, .applied)
    XCTAssertEqual(editor.document.scene, replacement)
    XCTAssertEqual(editor.undo(), "Restore Revision")
    XCTAssertEqual(editor.document, original)
  }

  func testTransactionIsOneUndoableIntent() throws {
    let shapeID = elementID("20000000-0000-0000-0000-000000000001")
    let textID = elementID("20000000-0000-0000-0000-000000000002")
    let shape = SceneElement.shape(
      id: shapeID,
      frame: SionRect(x: 20, y: 20, width: 160, height: 96)
    )
    let text = SceneElement.text(
      id: textID,
      frame: SionRect(x: 40, y: 40, width: 120, height: 30),
      text: "Start"
    )
    var editor = try SceneEditor()

    let result = try editor.perform(
      SceneTransaction(
        name: "Add idea",
        commands: [
          .insert(elements: [shape, text], at: nil),
          .setText(elementID: textID, text: "Draft"),
        ]
      )
    )

    XCTAssertEqual(result, .applied)
    XCTAssertEqual(editor.document.scene.elements.count, 2)
    XCTAssertEqual(editor.undo(), "Add idea")
    XCTAssertTrue(editor.document.scene.elements.isEmpty)
    XCTAssertEqual(editor.redo(), "Add idea")
    XCTAssertEqual(editor.document.scene.elements.count, 2)
  }

  func testRemovingGroupAlsoRemovesDescendantsAndAttachedConnectors() throws {
    let groupID = elementID("20000000-0000-0000-0000-000000000003")
    let childID = elementID("20000000-0000-0000-0000-000000000004")
    let survivorID = elementID("20000000-0000-0000-0000-000000000005")
    let connectorID = elementID("20000000-0000-0000-0000-000000000006")
    let group = SceneElement.group(
      id: groupID,
      frame: SionRect(x: 0, y: 0, width: 400, height: 300)
    )
    let child = SceneElement.shape(
      id: childID,
      frame: SionRect(x: 40, y: 40, width: 160, height: 96),
      parentID: groupID
    )
    let survivor = SceneElement.shape(
      id: survivorID,
      frame: SionRect(x: 500, y: 40, width: 160, height: 96)
    )
    let connector = SceneElement.connector(
      id: connectorID,
      source: .element(
        childID,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 200, y: 88)
      ),
      target: .element(
        survivorID,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 500, y: 88)
      )
    )
    let document = SionDocument(
      scene: SionScene(elements: [group, child, survivor, connector])
    )
    var editor = try SceneEditor(document: document)

    try editor.perform(
      SceneTransaction(
        name: "Delete group",
        command: .remove(elementIDs: [groupID])
      )
    )

    XCTAssertEqual(editor.document.scene.elements.map(\.id), [survivorID])
    editor.undo()
    XCTAssertEqual(editor.document, document)
  }

  func testInvalidTransactionRollsBackEveryCommand() throws {
    let shapeID = elementID("20000000-0000-0000-0000-000000000007")
    let missingParentID = elementID("20000000-0000-0000-0000-000000000008")
    let shape = SceneElement.shape(
      id: shapeID,
      frame: SionRect(x: 0, y: 0, width: 160, height: 96)
    )
    var editor = try SceneEditor()

    XCTAssertThrowsError(
      try editor.perform(
        SceneTransaction(
          name: "Invalid insert",
          commands: [
            .insert(elements: [shape], at: nil),
            .setParent(elementID: shapeID, parentID: missingParentID),
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? SceneValidationError,
        .missingParent(element: shapeID, parent: missingParentID)
      )
    }

    XCTAssertTrue(editor.document.scene.elements.isEmpty)
    XCTAssertFalse(editor.canUndo)
  }

  func testGestureCoalescesRepeatedFramesIntoOneHistoryEntry() throws {
    let shapeID = elementID("20000000-0000-0000-0000-000000000009")
    let initialFrame = SionRect(x: 0, y: 0, width: 160, height: 96)
    let shape = SceneElement.shape(id: shapeID, frame: initialFrame)
    var editor = try SceneEditor(
      document: SionDocument(scene: SionScene(elements: [shape]))
    )

    try editor.beginGesture(named: "Move shape")
    try editor.updateGesture(
      with: .setFrame(
        elementID: shapeID,
        frame: SionRect(x: 40, y: 20, width: 160, height: 96)
      )
    )
    try editor.updateGesture(
      with: .setFrame(
        elementID: shapeID,
        frame: SionRect(x: 80, y: 30, width: 160, height: 96)
      )
    )

    XCTAssertEqual(try editor.endGesture(), .applied)
    XCTAssertEqual(editor.undo(), "Move shape")
    XCTAssertEqual(editor.document.scene.element(withID: shapeID)?.geometry.frame, initialFrame)
    XCTAssertNil(editor.undo())
  }

  func testTranslatingGroupMovesDescendantsExactlyOnce() throws {
    let groupID = elementID("20000000-0000-0000-0000-000000000010")
    let childID = elementID("20000000-0000-0000-0000-000000000011")
    let group = SceneElement.group(
      id: groupID,
      frame: SionRect(x: 100, y: 100, width: 400, height: 300)
    )
    let child = SceneElement.shape(
      id: childID,
      frame: SionRect(x: 140, y: 140, width: 160, height: 96),
      parentID: groupID
    )
    var editor = try SceneEditor(
      document: SionDocument(scene: SionScene(elements: [group, child]))
    )

    try editor.perform(
      SceneTransaction(
        name: "Move group",
        command: .translate(
          elementIDs: [groupID, childID],
          by: SionVector(dx: 25, dy: 10)
        )
      )
    )

    XCTAssertEqual(
      editor.document.scene.element(withID: childID)?.geometry.frame.origin,
      SionPoint(x: 165, y: 150)
    )
  }

  func testLockedElementMakesTransactionFailWithoutPartialChanges() throws {
    let editableID = elementID("20000000-0000-0000-0000-000000000012")
    let lockedID = elementID("20000000-0000-0000-0000-000000000013")
    let editable = SceneElement.shape(
      id: editableID,
      frame: SionRect(x: 0, y: 0, width: 160, height: 96)
    )
    var locked = SceneElement.shape(
      id: lockedID,
      frame: SionRect(x: 200, y: 0, width: 160, height: 96)
    )
    locked.lockState = .locked
    let document = SionDocument(scene: SionScene(elements: [editable, locked]))
    var editor = try SceneEditor(document: document)

    XCTAssertThrowsError(
      try editor.perform(
        SceneTransaction(
          name: "Move both",
          commands: [
            .setFrame(
              elementID: editableID,
              frame: SionRect(x: 20, y: 0, width: 160, height: 96)
            ),
            .setFrame(
              elementID: lockedID,
              frame: SionRect(x: 220, y: 0, width: 160, height: 96)
            ),
          ]
        )
      )
    ) { error in
      XCTAssertEqual(error as? SceneEditingError, .elementLocked(lockedID))
    }

    XCTAssertEqual(editor.document, document)
  }

  func testMovingEndpointPreservesManualBezierIntentAndInvalidatesResolvedRoute() throws {
    let sourceID = elementID("20000000-0000-0000-0000-000000000014")
    let targetID = elementID("20000000-0000-0000-0000-000000000015")
    let connectorID = elementID("20000000-0000-0000-0000-000000000016")
    let source = SceneElement.shape(
      id: sourceID,
      frame: SionRect(x: 0, y: 0, width: 100, height: 80)
    )
    let target = SceneElement.shape(
      id: targetID,
      frame: SionRect(x: 300, y: 0, width: 100, height: 80)
    )
    var connector = SceneElement.connector(
      id: connectorID,
      source: .element(
        sourceID,
        attachment: .magnet("east"),
        fallbackPoint: SionPoint(x: 100, y: 40)
      ),
      target: .element(
        targetID,
        attachment: .magnet("west"),
        fallbackPoint: SionPoint(x: 300, y: 40)
      ),
      routingStyle: .bezier
    )

    guard case .connector(var connectorContent) = connector.content else {
      return XCTFail("Expected connector content")
    }
    connectorContent.manualRoute = .bezier(
      sourceControl: SionPoint(x: 150, y: 40),
      targetControl: SionPoint(x: 250, y: 40)
    )
    connectorContent.resolvedRoute = ConnectorRoute(
      start: SionPoint(x: 100, y: 40),
      segments: [
        .cubic(
          control1: SionPoint(x: 150, y: 40),
          control2: SionPoint(x: 250, y: 40),
          to: SionPoint(x: 300, y: 40)
        )
      ]
    )
    connector.content = .connector(connectorContent)
    var editor = try SceneEditor(
      document: SionDocument(scene: SionScene(elements: [source, target, connector]))
    )

    try editor.perform(
      SceneTransaction(
        name: "Move source",
        command: .translate(
          elementIDs: [sourceID],
          by: SionVector(dx: 20, dy: 10)
        )
      )
    )

    let edited = try XCTUnwrap(
      editor.document.scene.element(withID: connectorID)?.content.connector
    )
    guard case .element(_, _, let sourceFallback) = edited.source,
      case .element(_, _, let targetFallback) = edited.target,
      let manualRoute = edited.manualRoute,
      case .bezier(let sourceControl, let targetControl) = manualRoute
    else {
      return XCTFail("Expected attached Bezier connector")
    }

    XCTAssertEqual(sourceFallback, SionPoint(x: 120, y: 50))
    XCTAssertEqual(targetFallback, SionPoint(x: 300, y: 40))
    XCTAssertEqual(sourceControl, SionPoint(x: 170, y: 50))
    XCTAssertEqual(targetControl, SionPoint(x: 250, y: 40))
    XCTAssertNil(edited.resolvedRoute)
  }

  func testObstacleChangesInvalidateResolvedAutomaticRoutes() throws {
    let obstacleID = elementID("20000000-0000-0000-0000-000000000017")
    let insertedID = elementID("20000000-0000-0000-0000-000000000018")
    let changes: [(String, SceneCommand)] = [
      (
        "Insert obstacle",
        .insert(
          elements: [
            SceneElement.shape(
              id: insertedID,
              frame: SionRect(x: 180, y: 100, width: 80, height: 80)
            )
          ],
          at: nil
        )
      ),
      ("Remove obstacle", .remove(elementIDs: [obstacleID])),
      (
        "Replace obstacle",
        .replace(
          elements: [
            SceneElement.shape(
              id: obstacleID,
              frame: SionRect(x: 160, y: 20, width: 120, height: 120)
            )
          ]
        )
      ),
      (
        "Translate obstacle",
        .translate(elementIDs: [obstacleID], by: SionVector(dx: 0, dy: 40))
      ),
      (
        "Resize obstacle",
        .setFrame(
          elementID: obstacleID,
          frame: SionRect(x: 160, y: 20, width: 120, height: 120)
        )
      ),
      (
        "Rotate obstacle",
        .setRotation(elementID: obstacleID, radians: .pi / 4)
      ),
      (
        "Round obstacle",
        .setShapeKind(
          elementID: obstacleID,
          kind: .roundedRectangle(radius: 24)
        )
      ),
      (
        "Hide obstacle",
        .setVisibility(elementID: obstacleID, visibility: .hidden)
      ),
    ]

    for (name, command) in changes {
      var editor = try routeInvalidationEditor(obstacleID: obstacleID)

      try editor.perform(SceneTransaction(name: name, command: command))

      let connector = try XCTUnwrap(
        editor.document.scene.elements.compactMap(\.content.connector).first,
        name
      )
      XCTAssertNil(connector.resolvedRoute, name)
    }
  }

  func testObstacleChangePreservesManualRouteIntent() throws {
    let obstacleID = elementID("20000000-0000-0000-0000-000000000019")
    let manualRoute = ManualConnectorRoute.orthogonal(
      waypoints: [SionPoint(x: 140, y: 40), SionPoint(x: 140, y: 160)]
    )
    var editor = try routeInvalidationEditor(
      obstacleID: obstacleID,
      manualRoute: manualRoute
    )

    try editor.perform(
      SceneTransaction(
        name: "Move obstacle",
        command: .translate(
          elementIDs: [obstacleID],
          by: SionVector(dx: 0, dy: 40)
        )
      )
    )

    let connector = try XCTUnwrap(
      editor.document.scene.elements.compactMap(\.content.connector).first
    )
    XCTAssertEqual(connector.manualRoute, manualRoute)
    XCTAssertNil(connector.resolvedRoute)
  }

  func testNoOpShapeKindPreservesResolvedRoutes() throws {
    let obstacleID = elementID("20000000-0000-0000-0000-000000000020")
    var editor = try routeInvalidationEditor(obstacleID: obstacleID)
    let original = editor.document
    let obstacle = try XCTUnwrap(original.scene.element(withID: obstacleID))
    guard case .shape(let content) = obstacle.content else {
      return XCTFail("Expected shape content")
    }

    let result = try editor.perform(
      SceneTransaction(
        name: "Keep Shape",
        command: .setShapeKind(elementID: obstacleID, kind: content.kind)
      )
    )

    XCTAssertEqual(result, .noChange)
    XCTAssertEqual(editor.document, original)
  }

  func testNoOpRotationPreservesResolvedRoutes() throws {
    let obstacleID = elementID("20000000-0000-0000-0000-000000000021")
    var editor = try routeInvalidationEditor(obstacleID: obstacleID)
    let original = editor.document

    let result = try editor.perform(
      SceneTransaction(
        name: "Keep Rotation",
        command: .setRotation(elementID: obstacleID, radians: 0)
      )
    )

    XCTAssertEqual(result, .noChange)
    XCTAssertEqual(editor.document, original)
  }

  func testRotationAndShapeKindRejectLockedElement() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96)
    )
    shape.lockState = .locked
    let original = SionDocument(scene: SionScene(elements: [shape]))
    let commands: [SceneCommand] = [
      .setRotation(elementID: shape.id, radians: .pi / 2),
      .setShapeKind(elementID: shape.id, kind: .rectangle),
    ]

    for command in commands {
      var editor = try SceneEditor(document: original)

      XCTAssertThrowsError(
        try editor.perform(SceneTransaction(name: "Transform", command: command))
      ) { error in
        XCTAssertEqual(error as? SceneEditingError, .elementLocked(shape.id))
      }
      XCTAssertEqual(editor.document, original)
    }
  }

  func testShapeKindRejectsNonShape() throws {
    let text = SceneElement.text(
      frame: SionRect(x: 20, y: 30, width: 160, height: 56),
      text: "Text"
    )
    let original = SionDocument(scene: SionScene(elements: [text]))
    var editor = try SceneEditor(document: original)

    XCTAssertThrowsError(
      try editor.perform(
        SceneTransaction(
          name: "Change Shape",
          command: .setShapeKind(elementID: text.id, kind: .rectangle)
        )
      )
    ) { error in
      XCTAssertEqual(error as? SceneEditingError, .elementIsNotShape(text.id))
    }
    XCTAssertEqual(editor.document, original)
  }

  func testRotationAndShapeKindRejectInvalidValues() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96)
    )
    let original = SionDocument(scene: SionScene(elements: [shape]))
    let cases: [(SceneCommand, SceneValidationError)] = [
      (
        .setRotation(elementID: shape.id, radians: .infinity),
        .invalidGeometry(shape.id)
      ),
      (
        .setShapeKind(elementID: shape.id, kind: .roundedRectangle(radius: -1)),
        .invalidShape(shape.id)
      ),
    ]

    for (command, expectedError) in cases {
      var editor = try SceneEditor(document: original)

      XCTAssertThrowsError(
        try editor.perform(SceneTransaction(name: "Transform", command: command))
      ) { error in
        XCTAssertEqual(error as? SceneValidationError, expectedError)
      }
      XCTAssertEqual(editor.document, original)
    }
  }

  func testRotationGestureIsOneUndoableIntent() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96)
    )
    let original = SionDocument(scene: SionScene(elements: [shape]))
    var editor = try SceneEditor(document: original)

    try editor.beginGesture(named: "Rotate")
    try editor.updateGesture(
      with: .setRotation(elementID: shape.id, radians: .pi / 4)
    )
    try editor.updateGesture(
      with: .setRotation(elementID: shape.id, radians: .pi / 2)
    )
    XCTAssertEqual(try editor.endGesture(), .applied)

    XCTAssertEqual(
      editor.document.scene.element(withID: shape.id)?.geometry.rotationRadians,
      .pi / 2
    )
    XCTAssertEqual(editor.undo(), "Rotate")
    XCTAssertEqual(editor.document, original)
  }

  func testChangingRectangleRadiusPreservesElementState() throws {
    var shape = SceneElement.shape(
      frame: SionRect(x: 20, y: 30, width: 160, height: 96),
      kind: .rectangle,
      text: "Label"
    )
    shape.name = "Process"
    var editor = try SceneEditor(
      document: SionDocument(scene: SionScene(elements: [shape]))
    )

    try editor.perform(
      SceneTransaction(
        name: "Change Corner Radius",
        command: .setShapeKind(
          elementID: shape.id,
          kind: .roundedRectangle(radius: 24)
        )
      )
    )

    let changed = try XCTUnwrap(editor.document.scene.element(withID: shape.id))
    XCTAssertEqual(changed.name, "Process")
    XCTAssertEqual(
      changed.content,
      .shape(
        ShapeContent(
          kind: .roundedRectangle(radius: 24),
          label: TextContent(string: "Label", style: .shapeLabelDefault)
        )
      )
    )
  }

  private func routeInvalidationEditor(
    obstacleID: ElementID,
    manualRoute: ManualConnectorRoute? = nil
  ) throws -> SceneEditor {
    let connectorID = ElementID()
    let obstacle = SceneElement.shape(
      id: obstacleID,
      frame: SionRect(x: 160, y: 40, width: 80, height: 80)
    )
    var connector = SceneElement.connector(
      id: connectorID,
      source: .free(SionPoint(x: 40, y: 80)),
      target: .free(SionPoint(x: 360, y: 80)),
      routingStyle: .orthogonal
    )

    guard case .connector(var content) = connector.content else {
      throw SceneEditingError.elementIsNotConnector(connectorID)
    }

    content.manualRoute = manualRoute
    content.resolvedRoute = ConnectorRoute(
      start: SionPoint(x: 40, y: 80),
      segments: [.line(to: SionPoint(x: 360, y: 80))]
    )
    connector.content = .connector(content)

    return try SceneEditor(
      document: SionDocument(scene: SionScene(elements: [obstacle, connector]))
    )
  }

  private func elementID(_ string: String) -> ElementID {
    ElementID(string)!
  }
}
