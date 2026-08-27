import XCTest

@testable import SionCore

final class SceneSelectionPayloadTests: XCTestCase {
  func testCaptureIncludesGroupDescendantsInternalConnectorsAndAssets() throws {
    let fixture = try makeFixture()

    let payload = try SceneSelectionPayload(
      package: fixture.package,
      selectedElementIDs: [fixture.groupID]
    )

    XCTAssertEqual(
      payload.elements.map(\.id),
      [fixture.groupID, fixture.imageID, fixture.textID, fixture.connectorID]
    )
    XCTAssertEqual(payload.assets, [fixture.asset.id: fixture.asset])
    XCTAssertEqual(try SceneSelectionPayload(data: payload.dataRepresentation()), payload)
  }

  func testCaptureDetachesReferencesOutsideSelection() throws {
    let fixture = try makeFixture()

    let payload = try SceneSelectionPayload(
      package: fixture.package,
      selectedElementIDs: [fixture.imageID, fixture.externalConnectorID]
    )

    let image = try XCTUnwrap(payload.elements.first { $0.id == fixture.imageID })
    XCTAssertNil(image.parentID)

    let connector = try XCTUnwrap(
      payload.elements.first { $0.id == fixture.externalConnectorID }?.content.connector
    )
    XCTAssertEqual(connector.source.elementID, fixture.imageID)
    XCTAssertNil(connector.target.elementID)
    XCTAssertEqual(connector.target, .free(SionPoint(x: 700, y: 90)))
  }

  func testConnectorOnlyCaptureDetachesAtRenderedRouteEndpoints() throws {
    let fixture = try makeFixture()

    let payload = try SceneSelectionPayload(
      package: fixture.package,
      selectedElementIDs: [fixture.externalConnectorID]
    )

    let connector = try XCTUnwrap(payload.elements.first?.content.connector)
    XCTAssertEqual(connector.source, .free(SionPoint(x: 150, y: 90)))
    XCTAssertEqual(connector.target, .free(SionPoint(x: 700, y: 90)))
  }

  func testInsertionCentersAndRemapsHierarchyAndConnectorGeometry() throws {
    let fixture = try makeFixture()
    let payload = try SceneSelectionPayload(
      package: fixture.package,
      selectedElementIDs: [fixture.groupID]
    )
    let newIDs = [
      elementID("30000000-0000-0000-0000-000000000001"),
      elementID("30000000-0000-0000-0000-000000000002"),
      elementID("30000000-0000-0000-0000-000000000003"),
      elementID("30000000-0000-0000-0000-000000000004"),
    ]
    var nextID = newIDs.makeIterator()

    let insertion = try payload.insertion(
      centeredAt: SionPoint(x: 1_000, y: 1_000),
      excluding: Set(fixture.package.document.scene.elements.map(\.id)),
      generateElementID: { nextID.next()! }
    )

    XCTAssertEqual(insertion.elements.map(\.id), newIDs)
    XCTAssertEqual(insertion.assets, payload.assets)

    let group = insertion.elements[0]
    let image = insertion.elements[1]
    let text = insertion.elements[2]
    let connector = try XCTUnwrap(insertion.elements[3].content.connector)
    XCTAssertEqual(group.geometry.frame.center, SionPoint(x: 1_000, y: 1_000))
    XCTAssertEqual(image.parentID, group.id)
    XCTAssertEqual(text.parentID, group.id)
    XCTAssertEqual(connector.source.elementID, image.id)
    XCTAssertEqual(connector.target.elementID, text.id)
    XCTAssertEqual(
      connector.manualRoute,
      .bezier(
        sourceControl: SionPoint(x: 950, y: 990),
        targetControl: SionPoint(x: 1_050, y: 990)
      )
    )
    XCTAssertNil(connector.resolvedRoute)
  }

  func testInsertionIsOneSceneEditorUndoStep() throws {
    let fixture = try makeFixture()
    let payload = try SceneSelectionPayload(
      package: fixture.package,
      selectedElementIDs: [fixture.groupID]
    )
    let insertion = try payload.insertion(centeredAt: SionPoint(x: 600, y: 500))
    var editor = try SceneEditor()

    try editor.perform(
      SceneTransaction(
        name: "Paste",
        command: .insert(elements: insertion.elements, at: nil)
      )
    )

    XCTAssertEqual(editor.document.scene.elements.count, insertion.elements.count)
    XCTAssertEqual(editor.undo(), "Paste")
    XCTAssertTrue(editor.document.scene.elements.isEmpty)
    XCTAssertNil(editor.undo())
  }

  func testCaptureRejectsEmptyOrUnknownSelection() throws {
    let fixture = try makeFixture()
    let unknownID = elementID("30000000-0000-0000-0000-000000000005")

    XCTAssertThrowsError(
      try SceneSelectionPayload(package: fixture.package, selectedElementIDs: [])
    ) { error in
      XCTAssertEqual(error as? SceneSelectionPayloadError, .emptySelection)
    }
    XCTAssertThrowsError(
      try SceneSelectionPayload(
        package: fixture.package,
        selectedElementIDs: [unknownID]
      )
    ) { error in
      XCTAssertEqual(error as? SceneSelectionPayloadError, .elementNotFound(unknownID))
    }
  }

  private func makeFixture() throws -> Fixture {
    let groupID = elementID("20000000-0000-0000-0000-000000000001")
    let imageID = elementID("20000000-0000-0000-0000-000000000002")
    let textID = elementID("20000000-0000-0000-0000-000000000003")
    let externalID = elementID("20000000-0000-0000-0000-000000000004")
    let connectorID = elementID("20000000-0000-0000-0000-000000000005")
    let externalConnectorID = elementID("20000000-0000-0000-0000-000000000006")
    let asset = try SionAsset(
      data: Data("image".utf8),
      mediaType: "image/png",
      fileExtension: "png",
      originalFilename: "source.png",
      pixelSize: SionSize(width: 100, height: 80)
    )
    let group = SceneElement.group(
      id: groupID,
      frame: SionRect(x: 0, y: 0, width: 400, height: 200)
    )
    let image = SceneElement.image(
      id: imageID,
      frame: SionRect(x: 50, y: 50, width: 100, height: 80),
      assetID: asset.id,
      parentID: groupID
    )
    let text = SceneElement.text(
      id: textID,
      frame: SionRect(x: 250, y: 50, width: 100, height: 80),
      text: "Target",
      parentID: groupID
    )
    let external = SceneElement.shape(
      id: externalID,
      frame: SionRect(x: 700, y: 50, width: 120, height: 80)
    )
    let connector = configuredConnector(
      id: connectorID,
      sourceID: imageID,
      sourcePoint: SionPoint(x: 100, y: 90),
      targetID: textID,
      targetPoint: SionPoint(x: 300, y: 90)
    )
    let externalConnector = SceneElement.connector(
      id: externalConnectorID,
      source: .element(
        imageID,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 100, y: 90)
      ),
      target: .element(
        externalID,
        attachment: .automatic,
        fallbackPoint: SionPoint(x: 760, y: 90)
      )
    )
    let document = SionDocument(
      scene: SionScene(
        elements: [group, image, text, external, connector, externalConnector]
      )
    )
    let package = SionPackage(document: document, assets: [asset.id: asset])

    return Fixture(
      package: package,
      asset: asset,
      groupID: groupID,
      imageID: imageID,
      textID: textID,
      connectorID: connectorID,
      externalConnectorID: externalConnectorID
    )
  }

  private func configuredConnector(
    id: ElementID,
    sourceID: ElementID,
    sourcePoint: SionPoint,
    targetID: ElementID,
    targetPoint: SionPoint
  ) -> SceneElement {
    var element = SceneElement.connector(
      id: id,
      source: .element(
        sourceID,
        attachment: .automatic,
        fallbackPoint: sourcePoint
      ),
      target: .element(
        targetID,
        attachment: .automatic,
        fallbackPoint: targetPoint
      ),
      routingStyle: .bezier
    )
    guard case .connector(var connector) = element.content else {
      preconditionFailure("Connector factory returned another content type")
    }

    connector.manualRoute = .bezier(
      sourceControl: SionPoint(x: 150, y: 90),
      targetControl: SionPoint(x: 250, y: 90)
    )
    connector.resolvedRoute = ConnectorRoute(
      start: sourcePoint,
      segments: [
        .cubic(
          control1: SionPoint(x: 150, y: 90),
          control2: SionPoint(x: 250, y: 90),
          to: targetPoint
        )
      ]
    )
    element.content = .connector(connector)
    return element
  }

  private func elementID(_ value: String) -> ElementID {
    ElementID(value)!
  }
}

private struct Fixture {
  let package: SionPackage
  let asset: SionAsset
  let groupID: ElementID
  let imageID: ElementID
  let textID: ElementID
  let connectorID: ElementID
  let externalConnectorID: ElementID
}
