import XCTest
@testable import SionCore

/// chonk.md finding 2: the lock contract must cover connectors too — a locked
/// connector is neither cascade-deleted with an endpoint nor rewritten when its
/// endpoint moves.
final class LockContractTests: XCTestCase {

  private func elementID(_ string: String) -> ElementID {
    ElementID(string)!
  }

  private func sceneWithLockedConnector() -> (SionScene, ElementID, ElementID, ElementID) {
    let sourceID = elementID("20000000-0000-0000-0000-000000000021")
    let targetID = elementID("20000000-0000-0000-0000-000000000022")
    let connectorID = elementID("20000000-0000-0000-0000-000000000023")
    let source = SceneElement.shape(
      id: sourceID, frame: SionRect(x: 0, y: 0, width: 100, height: 80))
    let target = SceneElement.shape(
      id: targetID, frame: SionRect(x: 300, y: 0, width: 100, height: 80))
    var connector = SceneElement.connector(
      id: connectorID,
      source: .element(sourceID, attachment: .automatic, fallbackPoint: SionPoint(x: 100, y: 40)),
      target: .element(targetID, attachment: .automatic, fallbackPoint: SionPoint(x: 300, y: 40)))
    connector.lockState = .locked
    return (SionScene(elements: [source, target, connector]), sourceID, targetID, connectorID)
  }

  func testDeleteOfEndpointRefusesBecauseLockedConnectorCascades() throws {
    let (scene, sourceID, _, connectorID) = sceneWithLockedConnector()
    var editor = try SceneEditor(document: SionDocument(scene: scene))

    let transaction = SceneTransaction(
      name: "Delete source",
      command: .remove(elementIDs: [sourceID])
    )
    XCTAssertThrowsError(try editor.perform(transaction)) { error in
      XCTAssertEqual(
        error as? SceneEditingError,
        .elementLocked(connectorID),
        "the locked connector must block the cascade delete"
      )
    }
    XCTAssertEqual(
      editor.document.scene.elements.count,
      3,
      "no partial delete may happen"
    )
  }

  func testDeleteOfUnrelatedElementStillDeletesLockedConnectorFreeScene() throws {
    // Control: without a locked connector, deleting an endpoint removes it.
    let sourceID = elementID("20000000-0000-0000-0000-000000000024")
    let targetID = elementID("20000000-0000-0000-0000-000000000025")
    let connectorID = elementID("20000000-0000-0000-0000-000000000026")
    let source = SceneElement.shape(
      id: sourceID, frame: SionRect(x: 0, y: 0, width: 100, height: 80))
    let target = SceneElement.shape(
      id: targetID, frame: SionRect(x: 300, y: 0, width: 100, height: 80))
    let connector = SceneElement.connector(
      id: connectorID,
      source: .element(
        sourceID,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 100, y: 40)
      ),
      target: .element(
        targetID,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 300, y: 40)
      )
    )
    let scene = SionScene(elements: [source, target, connector])
    var editor = try SceneEditor(document: SionDocument(scene: scene))

    let transaction = SceneTransaction(
      name: "Delete source",
      command: .remove(elementIDs: [sourceID])
    )
    _ = try editor.perform(transaction)
    XCTAssertNil(editor.document.scene.element(withID: sourceID))
    XCTAssertNil(
      editor.document.scene.element(withID: connectorID),
      "an editable connector still cascades with its endpoint"
    )
    XCTAssertNotNil(editor.document.scene.element(withID: targetID))
  }

  func testMovingEndpointDoesNotMutateLockedConnector() throws {
    let (scene, sourceID, _, connectorID) = sceneWithLockedConnector()
    var editor = try SceneEditor(document: SionDocument(scene: scene))
    let before = editor.document.scene.element(withID: connectorID)

    let move = SceneTransaction(
      name: "Move",
      command: .translate(
        elementIDs: [sourceID],
        by: SionVector(dx: 50, dy: 20)
      )
    )
    _ = try editor.perform(move)

    let after = editor.document.scene.element(withID: connectorID)
    XCTAssertEqual(
      after,
      before,
      "a locked connector's endpoints/waypoints/route must not be rewritten"
    )
    let movedOrigin = editor.document.scene.element(withID: sourceID)?.geometry.frame.origin
    XCTAssertEqual(
      movedOrigin,
      SionPoint(x: 50, y: 20),
      "the editable endpoint itself still moves"
    )
  }
}
