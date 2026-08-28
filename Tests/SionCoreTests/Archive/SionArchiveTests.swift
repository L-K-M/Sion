import Foundation
import XCTest

@testable import SionCore

final class SionArchiveTests: XCTestCase {
  func testSceneFileExpandsTriangleMagnetsAndPreservesPreset() throws {
    var triangle = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 200, height: 100),
      kind: .triangle
    )
    triangle.magnetConfiguration = .preset(.vertices)
    let sceneFile = SceneFile(
      document: SionDocument(scene: SionScene(elements: [triangle])),
      assets: []
    )

    let storedElement = try XCTUnwrap(sceneFile.scene.elements.first)
    XCTAssertEqual(
      storedElement.magnets.map(\.normalizedPosition),
      [
        SionPoint(x: 0.5, y: 0),
        SionPoint(x: 1, y: 1),
        SionPoint(x: 0, y: 1),
      ])

    let restored = try sceneFile.model(assetData: [:]).0
    XCTAssertEqual(
      restored.scene.elements.first?.magnetConfiguration,
      .preset(.vertices)
    )

    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: CanonicalJSON.encode(sceneFile)
      ) as? [String: Any]
    )
    let scene = try XCTUnwrap(object["scene"] as? [String: Any])
    let elements = try XCTUnwrap(scene["elements"] as? [[String: Any]])
    let wireElement = try XCTUnwrap(elements.first)
    XCTAssertNotNil(wireElement["magnetConfiguration"])
    XCTAssertNotNil(wireElement["magnets"])
    XCTAssertNil(wireElement["magnetOutline"])
  }

  func testPortableFixtureMatchesExpectedMermaid() throws {
    let sceneURL = try XCTUnwrap(
      Bundle.module.url(
        forResource: "simple-flow.scene",
        withExtension: "json",
        subdirectory: "Fixtures"
      )
    )
    let mermaidURL = try XCTUnwrap(
      Bundle.module.url(
        forResource: "simple-flow",
        withExtension: "mmd",
        subdirectory: "Fixtures"
      )
    )
    let scene = try CanonicalJSON.decodeStrict(
      SceneFile.self,
      from: Data(contentsOf: sceneURL)
    )
    let document = try scene.model(assetData: [:]).0
    let expected = try String(contentsOf: mermaidURL, encoding: .utf8)

    XCTAssertEqual(MermaidExporter.export(document: document).source, expected)
  }

  func testArchiveRoundTripsWithStableOrderAndHistory() throws {
    let fixture = try makeFixture()
    let date = Date(timeIntervalSince1970: 1_787_830_522.875)

    let encoded = try SionArchive.encode(package: fixture.package, intent: .manual, at: date)
    let entries = try StoredZIPArchive.decode(encoded.data)
    let decoded = try SionArchive.decode(encoded.data)

    XCTAssertEqual(
      entries.map(\.path), expectedPaths(asset: fixture.asset, history: encoded.committedHistory))
    XCTAssertEqual(entries.first?.data, Data(SionArchiveConstants.mediaType.utf8))
    XCTAssertEqual(
      encoded.committedHistory.revisions.first?.savedAt.timeIntervalSince1970, 1_787_830_522)

    var expected = fixture.package
    expected.history = encoded.committedHistory
    XCTAssertEqual(decoded, expected)
  }

  func testArchiveWritesDeterministicGenerator() throws {
    let encoded = try SionArchive.encode(
      package: SionPackage(),
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )
    let entries = Dictionary(
      uniqueKeysWithValues: try StoredZIPArchive.decode(encoded.data).map { ($0.path, $0.data) }
    )
    let manifestData = try XCTUnwrap(entries[SionArchiveConstants.manifestPath])
    let manifest = try CanonicalJSON.decodeStrict(
      SionManifest.self,
      from: manifestData
    )

    XCTAssertEqual(
      manifest.generator,
      GeneratorDescriptor(
        name: testArchiveGenerator.name,
        version: testArchiveGenerator.version
      )
    )
  }

  func testExistingHistoryDatesNormalizeBeforeCommit() throws {
    let fixture = try makeFixture()
    let sceneData = try CanonicalJSON.encode(
      SceneFile(document: fixture.package.document, assets: [fixture.asset])
    )
    let revision = HistoryRevision(
      identifier: SHA256.hexDigest(sceneData),
      savedAt: Date(timeIntervalSince1970: 1_787_830_000.75),
      intent: .manual,
      sceneData: sceneData
    )
    var package = fixture.package
    package.history = DocumentHistory(revisions: [revision])

    let encoded = try SionArchive.encode(
      package: package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_831_000)
    )
    let decoded = try SionArchive.decode(encoded.data)

    XCTAssertEqual(
      encoded.committedHistory.revisions.first?.savedAt.timeIntervalSince1970,
      1_787_830_000
    )
    XCTAssertEqual(decoded.history, encoded.committedHistory)
  }

  func testRecoveryExportsRemainUsefulWithoutSion() throws {
    let fixture = try makeFixture()
    let encoded = try SionArchive.encode(
      package: fixture.package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )
    let entries = Dictionary(
      uniqueKeysWithValues: try StoredZIPArchive.decode(encoded.data).map { ($0.path, $0.data) }
    )
    let svg = try XCTUnwrap(String(data: entries[SionArchiveConstants.svgPath]!, encoding: .utf8))
    let mermaid = try XCTUnwrap(
      String(data: entries[SionArchiveConstants.mermaidPath]!, encoding: .utf8)
    )
    let manifest = try CanonicalJSON.decodeStrict(
      SionManifest.self,
      from: entries[SionArchiveConstants.manifestPath]!
    )

    XCTAssertTrue(svg.contains("<svg"))
    XCTAssertTrue(svg.contains("<rect id=\"canvas-background\""))
    XCTAssertTrue(svg.contains("href=\"data:image/png;base64,"))
    XCTAssertTrue(svg.contains("<path d=\"M200 78L300 78\""))
    XCTAssertFalse(svg.contains("<script"))
    XCTAssertFalse(svg.contains("foreignObject"))

    XCTAssertTrue(mermaid.hasPrefix("flowchart TB\n"))
    XCTAssertTrue(mermaid.contains("node_00000000_0000_0000_0000_000000000001"))
    XCTAssertTrue(mermaid.contains("edge_00000000_0000_0000_0000_000000000005@-->"))
    XCTAssertTrue(mermaid.contains("%% Omitted Sion image"))
    XCTAssertEqual(manifest.mermaidCoverage, .partial)
  }

  func testSVGUsesFixedCanvasAndCapsuleGeometry() throws {
    let capsule = SceneElement.shape(
      frame: SionRect(x: 10, y: 20, width: 200, height: 50),
      kind: .capsule
    )
    let document = SionDocument(
      scene: SionScene(
        canvas: SionCanvas(extent: .fixed(SionSize(width: 640, height: 480))),
        elements: [capsule]
      )
    )

    let svg = try SVGExporter.export(document: document, assets: [:])

    XCTAssertTrue(svg.contains("viewBox=\"0 0 640 480\""))
    XCTAssertTrue(svg.contains("x=\"0\" y=\"0\" width=\"640\" height=\"480\""))
    XCTAssertTrue(svg.contains("d=\"M35 20H185"))
    XCTAssertFalse(svg.contains("d=\"M10 45A100 25"))
  }

  func testSVGTilesImagesAndHandlesExtremeShapeValues() throws {
    let fixture = try makeFixture()
    let tiledImage = SceneElement(
      geometry: ElementGeometry(frame: SionRect(x: 10, y: 20, width: 100, height: 80)),
      magnetConfiguration: .preset(.eight),
      style: .imageDefault,
      content: .image(
        ImageContent(
          assetID: fixture.asset.id,
          displayAssetID: fixture.asset.id,
          scalingMode: .tile
        )
      )
    )
    let extremeShape = SceneElement(
      geometry: ElementGeometry(
        frame: SionRect(x: 140, y: 20, width: 100, height: 80),
        rotationRadians: Double.greatestFiniteMagnitude
      ),
      magnetConfiguration: .preset(.cardinalFour),
      style: .shapeDefault,
      content: .shape(
        ShapeContent(kind: .roundedRectangle(radius: .nan))
      )
    )
    let document = SionDocument(scene: SionScene(elements: [tiledImage, extremeShape]))

    let svg = try SVGExporter.export(
      document: document,
      assets: [fixture.asset.id: fixture.asset]
    )

    XCTAssertTrue(svg.contains("<pattern id=\"image-pattern-"))
    XCTAssertTrue(svg.contains("patternUnits=\"userSpaceOnUse\" width=\"1\" height=\"1\""))
    XCTAssertTrue(svg.contains("fill=\"url(#image-pattern-"))
    XCTAssertFalse(svg.lowercased().contains("nan"))
    XCTAssertFalse(svg.lowercased().contains("inf"))
  }

  func testCorruptDerivedPayloadIsIgnoredAfterZIPCRCFailure() throws {
    let encoded = try encodedFixture()
    let entries = try StoredZIPArchive.decode(encoded.data)
    let svg = try XCTUnwrap(entries.first { $0.path == SionArchiveConstants.svgPath }?.data)
    let range = try XCTUnwrap(encoded.data.range(of: svg))
    var corrupted = encoded.data
    corrupted[range.lowerBound] ^= 0x01

    XCTAssertThrowsError(try StoredZIPArchive.decode(corrupted)) { error in
      XCTAssertEqual(
        error as? ZIPArchiveError,
        .checksumMismatch(SionArchiveConstants.svgPath)
      )
    }
    XCTAssertNoThrow(try SionArchive.decode(corrupted))
  }

  func testSceneHashMismatchBlocksLoading() throws {
    let encoded = try encodedFixture()
    let damaged = try replacingEntry(
      in: encoded.data,
      path: SionArchiveConstants.scenePath,
      with: Data("{}".utf8)
    )

    XCTAssertThrowsError(try SionArchive.decode(damaged)) { error in
      XCTAssertEqual(error as? SionArchiveError, .sceneDescriptorMismatch)
    }
  }

  func testUnknownManifestAndSceneMembersAreRejected() throws {
    let encoded = try encodedFixture()
    let manifestUnknown = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.manifestPath
    ) { object in
      object["future"] = true
    }

    XCTAssertThrowsError(try SionArchive.decode(manifestUnknown)) { error in
      XCTAssertEqual(error as? CanonicalJSONError, .unknownMember("$.future"))
    }

    let sceneUnknown = try modifyingScene(in: encoded.data) { object in
      object["future"] = true
    }
    XCTAssertThrowsError(try SionArchive.decode(sceneUnknown)) { error in
      XCTAssertEqual(error as? CanonicalJSONError, .unknownMember("$.future"))
    }
  }

  func testManifestCannotAliasReservedEntries() throws {
    let encoded = try encodedFixture()
    let aliased = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]
      entries.append([
        "path": SionArchiveConstants.scenePath,
        "role": "derived",
        "mediaType": "application/json",
        "bytes": 0,
        "sha256": String(repeating: "0", count: 64),
      ])
      object["entries"] = entries
    }

    XCTAssertThrowsError(try SionArchive.decode(aliased)) { error in
      XCTAssertEqual(
        error as? SionArchiveError,
        .duplicateManifestEntry(SionArchiveConstants.scenePath)
      )
    }
  }

  func testManifestEnforcesPathRolesAndFamilies() throws {
    let encoded = try encodedFixture()
    let authoritativeSVG = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]
      let index = entries.firstIndex {
        $0["path"] as? String == SionArchiveConstants.svgPath
      }!
      entries[index]["role"] = "authoritative"
      object["entries"] = entries
    }
    XCTAssertThrowsError(try SionArchive.decode(authoritativeSVG)) { error in
      XCTAssertEqual(
        error as? SionArchiveError,
        .invalidManifestEntry(SionArchiveConstants.svgPath)
      )
    }

    let arbitraryPath = "notes/private.txt"
    let arbitrary = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]
      entries.append([
        "path": arbitraryPath,
        "role": "derived",
        "mediaType": "text/plain",
        "bytes": 0,
        "sha256": SHA256.hexDigest(Data()),
      ])
      object["entries"] = entries
    }
    XCTAssertThrowsError(try SionArchive.decode(arbitrary)) { error in
      XCTAssertEqual(error as? SionArchiveError, .invalidManifestEntry(arbitraryPath))
    }
  }

  func testUnreferencedAuthoritativeAssetIsRejected() throws {
    let encoded = try encodedFixture()
    let data = Data("orphan".utf8)
    let digest = SHA256.hexDigest(data)
    let path = "assets/\(digest).bin"
    let withManifest = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]
      entries.append([
        "path": path,
        "role": "authoritative",
        "mediaType": "application/octet-stream",
        "bytes": data.count,
        "sha256": digest,
      ])
      object["entries"] = entries
    }
    var entries = try StoredZIPArchive.decode(withManifest)
    entries.append(ZIPEntry(path: path, data: data))

    XCTAssertThrowsError(try SionArchive.decode(StoredZIPArchive.encode(entries))) { error in
      XCTAssertEqual(error as? SionArchiveError, .unreferencedAuthoritativeEntry(path))
    }
  }

  func testSceneRejectsAssetDescriptorWithoutImageReference() throws {
    let encoded = try encodedFixture()
    let data = Data("orphan".utf8)
    let digest = SHA256.hexDigest(data)
    let path = "assets/\(digest).bin"
    let withScene = try modifyingScene(in: encoded.data) { object in
      var assets = object["assets"] as! [[String: Any]]
      assets.append([
        "id": "sha256:\(digest)",
        "path": path,
        "mediaType": "application/octet-stream",
        "fileExtension": "bin",
        "byteLength": data.count,
        "sha256": digest,
      ])
      object["assets"] = assets
    }
    let withManifest = try modifyingJSONEntry(
      in: withScene,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]
      entries.append([
        "path": path,
        "role": "authoritative",
        "mediaType": "application/octet-stream",
        "bytes": data.count,
        "sha256": digest,
      ])
      object["entries"] = entries
    }
    var entries = try StoredZIPArchive.decode(withManifest)
    entries.append(ZIPEntry(path: path, data: data))

    XCTAssertThrowsError(try SionArchive.decode(StoredZIPArchive.encode(entries))) { error in
      XCTAssertEqual(error as? SionArchiveError, .sceneAssetSetMismatch)
    }
  }

  func testUnlistedArchiveEntriesAreRejected() throws {
    let encoded = try encodedFixture()
    var entries = try StoredZIPArchive.decode(encoded.data)
    entries.append(ZIPEntry(path: "hidden.bin", data: Data()))

    XCTAssertThrowsError(try SionArchive.decode(StoredZIPArchive.encode(entries))) { error in
      XCTAssertEqual(error as? SionArchiveError, .unexpectedEntry("hidden.bin"))
    }
  }

  func testDuplicateJSONMembersAreRejected() throws {
    let data = Data("{\"value\":1,\"value\":2}".utf8)

    XCTAssertThrowsError(try CanonicalJSON.decodeStrict(DuplicateKeyFixture.self, from: data)) {
      error in
      XCTAssertEqual(error as? CanonicalJSONError, .duplicateMember("$.value"))
    }
  }

  func testAssetDescriptorLengthAndPathMustMatchOriginalAsset() throws {
    let fixture = try makeFixture()
    let encoded = try SionArchive.encode(
      package: fixture.package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )

    let wrongLength = try modifyingScene(in: encoded.data) { object in
      var assets = object["assets"] as! [[String: Any]]
      assets[0]["byteLength"] = fixture.asset.data.count + 1
      object["assets"] = assets
    }
    XCTAssertThrowsError(try SionArchive.decode(wrongLength)) { error in
      XCTAssertEqual(error as? SionArchiveError, .entryHashMismatch(fixture.asset.archivePath))
    }

    let aliasPath = fixture.asset.archivePath.replacingOccurrences(
      of: ".png",
      with: ".jpg"
    )
    let aliased = try aliasingAsset(
      in: encoded.data,
      originalPath: fixture.asset.archivePath,
      aliasPath: aliasPath
    )
    XCTAssertThrowsError(try SionArchive.decode(aliased)) { error in
      XCTAssertEqual(error as? SionArchiveError, .entryHashMismatch(aliasPath))
    }
  }

  func testHistoryRebuildsWithoutIndexAndCanRestoreStrictly() throws {
    let fixture = try makeFixture()
    let encoded = try SionArchive.encode(
      package: fixture.package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )
    let withoutIndex = try removingEntry(
      from: encoded.data,
      path: SionArchiveConstants.historyIndexPath
    )

    let decoded = try SionArchive.decode(withoutIndex)
    let revision = try XCTUnwrap(decoded.history.revisions.first)

    XCTAssertEqual(decoded.history, encoded.committedHistory)
    XCTAssertEqual(
      try SionArchive.document(from: revision, assets: decoded.assets),
      fixture.package.document
    )

    let invalid = HistoryRevision(
      identifier: String(repeating: "0", count: 64),
      savedAt: revision.savedAt,
      intent: revision.intent,
      sceneData: revision.sceneData
    )
    XCTAssertThrowsError(try SionArchive.document(from: invalid, assets: decoded.assets)) {
      error in
      XCTAssertEqual(
        error as? SionArchiveError,
        .invalidHistoryIdentifier(String(repeating: "0", count: 64))
      )
    }
  }

  func testInvalidHistoryIndexIDDoesNotSuppressValidSnapshot() throws {
    let encoded = try encodedFixture()
    let corruptedIndex = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.historyIndexPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]
      entries[0]["id"] = "sha256:\(String(repeating: "0", count: 64))"
      object["entries"] = entries
    }
    let entries = try StoredZIPArchive.decode(corruptedIndex)
    let indexData = try XCTUnwrap(
      entries.first { $0.path == SionArchiveConstants.historyIndexPath }?.data
    )
    let archive = try modifyingJSONEntry(
      in: corruptedIndex,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]
      let index = entries.firstIndex {
        $0["path"] as? String == SionArchiveConstants.historyIndexPath
      }!
      entries[index]["bytes"] = indexData.count
      entries[index]["sha256"] = SHA256.hexDigest(indexData)
      object["entries"] = entries
    }

    let decoded = try SionArchive.decode(archive)

    XCTAssertEqual(
      decoded.history.revisions.map(\.identifier),
      encoded.committedHistory.revisions.map(\.identifier)
    )
  }

  func testHistoryIndexCannotAliasCurrentScene() throws {
    let encoded = try encodedFixture()
    var entries = try StoredZIPArchive.decode(encoded.data).filter { entry in
      !entry.path.hasPrefix("history/")
        || entry.path == SionArchiveConstants.historyIndexPath
    }
    let indexPosition = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.historyIndexPath }
    )
    var index = try jsonObject(entries[indexPosition].data)
    var historyEntries = index["entries"] as! [[String: Any]]
    historyEntries[0]["scene"] = SionArchiveConstants.scenePath
    index["entries"] = historyEntries
    let indexData = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    entries[indexPosition] = ZIPEntry(
      path: SionArchiveConstants.historyIndexPath,
      data: indexData
    )

    let manifestPosition = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.manifestPath }
    )
    var manifest = try jsonObject(entries[manifestPosition].data)
    var manifestEntries = manifest["entries"] as! [[String: Any]]
    let manifestIndexPosition = try XCTUnwrap(
      manifestEntries.firstIndex {
        $0["path"] as? String == SionArchiveConstants.historyIndexPath
      }
    )
    manifestEntries[manifestIndexPosition]["bytes"] = indexData.count
    manifestEntries[manifestIndexPosition]["sha256"] = SHA256.hexDigest(indexData)
    manifest["entries"] = manifestEntries
    entries[manifestPosition] = ZIPEntry(
      path: SionArchiveConstants.manifestPath,
      data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    )

    let decoded = try SionArchive.decode(StoredZIPArchive.encode(entries))

    XCTAssertTrue(decoded.history.revisions.isEmpty)
  }

  func testHistoricalOnlyAssetIsDerivedAndCorruptionDropsItsRevision() throws {
    let fixture = try makeFixture()
    let first = try SionArchive.encode(
      package: fixture.package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_000)
    )
    let currentDocument = SionDocument(
      id: fixture.package.document.id,
      title: "Current",
      scene: SionScene(elements: [fixture.shapeA, fixture.shapeB])
    )
    let currentPackage = SionPackage(
      document: currentDocument,
      assets: fixture.package.assets,
      history: first.committedHistory
    )
    let second = try SionArchive.encode(
      package: currentPackage,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_831_000)
    )
    let entries = Dictionary(
      uniqueKeysWithValues: try StoredZIPArchive.decode(second.data).map { ($0.path, $0.data) }
    )
    let manifest = try CanonicalJSON.decodeStrict(
      SionManifest.self,
      from: entries[SionArchiveConstants.manifestPath]!
    )
    let assetEntry = try XCTUnwrap(
      manifest.entries.first { $0.path == fixture.asset.archivePath }
    )

    XCTAssertEqual(assetEntry.role, .derived)

    let corrupted = try replacingEntry(
      in: second.data,
      path: fixture.asset.archivePath,
      with: Data("damaged".utf8)
    )
    let decoded = try SionArchive.decode(corrupted)

    XCTAssertEqual(decoded.document, currentDocument)
    XCTAssertEqual(decoded.history.revisions.count, 1)
    XCTAssertNil(decoded.assets[fixture.asset.id])
  }

  func testHistoryWithConflictingAssetExtensionIsDroppedBeforeCommit() throws {
    let fixture = try makeFixture()
    let historicalScene = try CanonicalJSON.encode(
      SceneFile(document: fixture.package.document, assets: [fixture.asset])
    )
    let historicalIdentifier = SHA256.hexDigest(historicalScene)
    let revision = HistoryRevision(
      identifier: historicalIdentifier,
      savedAt: Date(timeIntervalSince1970: 1_787_830_000),
      intent: .manual,
      sceneData: historicalScene
    )
    let conflictingAsset = try SionAsset(
      data: fixture.asset.data,
      mediaType: "image/jpeg",
      fileExtension: "jpg"
    )
    let currentDocument = SionDocument(
      id: fixture.package.document.id,
      title: "Current",
      scene: SionScene(elements: [fixture.shapeA])
    )
    let package = SionPackage(
      document: currentDocument,
      assets: [conflictingAsset.id: conflictingAsset],
      history: DocumentHistory(revisions: [revision])
    )

    let encoded = try SionArchive.encode(
      package: package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_831_000)
    )
    let decoded = try SionArchive.decode(encoded.data)

    XCTAssertEqual(encoded.committedHistory.revisions.count, 1)
    XCTAssertFalse(
      encoded.committedHistory.revisions.contains { $0.identifier == historicalIdentifier }
    )
    XCTAssertEqual(decoded.history, encoded.committedHistory)
  }

  func testDecodeDropsHistoryWithConflictingAssetDescriptor() throws {
    let originalData = Data("shared original".utf8)
    let currentOriginal = try SionAsset(
      data: originalData,
      mediaType: "application/octet-stream",
      fileExtension: "bin"
    )
    let historicalOriginal = try SionAsset(
      data: originalData,
      mediaType: "application/pdf",
      fileExtension: "pdf"
    )
    let display = try SionAsset.safeDisplayPNG(data: testPNGData())
    let image = SceneElement.image(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      assetID: currentOriginal.id,
      displayAssetID: display.id
    )
    let package = SionPackage(
      document: SionDocument(scene: SionScene(elements: [image])),
      assets: [
        currentOriginal.id: currentOriginal,
        display.id: display,
      ]
    )
    let encoded = try SionArchive.encode(
      package: package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )
    let archive = try replacingHistoricalAssetDescriptor(
      in: encoded.data,
      assetID: currentOriginal.id,
      with: historicalOriginal
    )

    let decoded = try SionArchive.decode(archive)

    XCTAssertEqual(decoded.document, package.document)
    XCTAssertTrue(decoded.history.revisions.isEmpty)
  }

  func testHistoryDeduplicatesAcrossNonAdjacentSaves() throws {
    let documentA = SionDocument(
      id: documentID("10000000-0000-0000-0000-000000000020"),
      title: "A"
    )
    let documentB = SionDocument(
      id: documentA.id,
      title: "B"
    )
    let sceneA = try CanonicalJSON.encode(SceneFile(document: documentA, assets: []))
    let sceneB = try CanonicalJSON.encode(SceneFile(document: documentB, assets: []))
    let oldA = HistoryRevision(
      identifier: SHA256.hexDigest(sceneA),
      savedAt: Date(timeIntervalSince1970: 1_000),
      intent: .manual,
      sceneData: sceneA
    )
    let revisionB = HistoryRevision(
      identifier: SHA256.hexDigest(sceneB),
      savedAt: Date(timeIntervalSince1970: 2_000),
      intent: .manual,
      sceneData: sceneB
    )
    let package = SionPackage(
      document: documentA,
      history: DocumentHistory(revisions: [revisionB, oldA])
    )

    let encoded = try SionArchive.encode(
      package: package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 3_000)
    )
    let decoded = try SionArchive.decode(encoded.data)

    XCTAssertEqual(
      encoded.committedHistory.revisions.map(\.identifier),
      [
        SHA256.hexDigest(sceneA),
        SHA256.hexDigest(sceneB),
      ])
    XCTAssertEqual(decoded.history, encoded.committedHistory)
  }

  func testDecodePreservesAllValidRetainedHistory() throws {
    let encoded = try encodedFixture()
    let archive = try replacingHistory(in: encoded.data, snapshotCount: 20)

    let decoded = try SionArchive.decode(archive)

    XCTAssertEqual(decoded.history.revisions.count, 20)
  }

  func testDecodeRejectsTooManyHistorySnapshots() throws {
    let encoded = try encodedFixture()
    let archive = try replacingHistory(
      in: encoded.data,
      snapshotCount: ArchiveTestLimits.maximumHistorySnapshotCount + 1
    )

    XCTAssertThrowsError(try SionArchive.decode(archive)) { error in
      XCTAssertEqual(
        error as? SionArchiveError,
        .tooManyHistorySnapshots(ArchiveTestLimits.maximumHistorySnapshotCount + 1)
      )
    }
  }

  func testOversizedHistoryIndexIsRebuiltFromSnapshots() throws {
    let fixture = try makeFixture()
    let encoded = try SionArchive.encode(
      package: fixture.package,
      intent: .autosave,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )
    let oversizedIndex = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.historyIndexPath
    ) { object in
      let entry = (object["entries"] as! [[String: Any]])[0]
      object["entries"] = Array(
        repeating: entry,
        count: ArchiveTestLimits.maximumHistorySnapshotCount + 1
      )
    }
    let entries = try StoredZIPArchive.decode(oversizedIndex)
    let indexData = try XCTUnwrap(
      entries.first { $0.path == SionArchiveConstants.historyIndexPath }?.data
    )
    let verifiedIndex = try modifyingJSONEntry(
      in: oversizedIndex,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var manifestEntries = object["entries"] as! [[String: Any]]
      let index = manifestEntries.firstIndex {
        $0["path"] as? String == SionArchiveConstants.historyIndexPath
      }!
      manifestEntries[index]["bytes"] = indexData.count
      manifestEntries[index]["sha256"] = SHA256.hexDigest(indexData)
      object["entries"] = manifestEntries
    }

    let decoded = try SionArchive.decode(verifiedIndex)

    XCTAssertEqual(decoded.history.revisions.count, 1)
    XCTAssertEqual(decoded.history.revisions.first?.intent, .manual)
  }

  func testDecodeRejectsTooManyManifestEntries() throws {
    let encoded = try encodedFixture()
    let oversized = try modifyingJSONEntry(
      in: encoded.data,
      path: SionArchiveConstants.manifestPath
    ) { object in
      var entries = object["entries"] as! [[String: Any]]

      while entries.count <= ArchiveTestLimits.maximumManifestEntryCount {
        let digest = String(format: "%064x", entries.count)
        entries.append([
          "path": "assets/\(digest).bin",
          "role": "derived",
          "mediaType": "application/octet-stream",
          "bytes": 0,
          "sha256": SHA256.hexDigest(Data()),
        ])
      }

      object["entries"] = entries
    }

    XCTAssertThrowsError(try SionArchive.decode(oversized)) { error in
      XCTAssertEqual(
        error as? SionArchiveError,
        .tooManyManifestEntries(ArchiveTestLimits.maximumManifestEntryCount + 1)
      )
    }
  }

  func testCommittedHistoryContainsOnlyRestorableScenes() throws {
    let invalidElement = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: -100, height: 50)
    )
    let invalidDocument = SionDocument(
      title: "Invalid history",
      scene: SionScene(elements: [invalidElement])
    )
    let invalidScene = try CanonicalJSON.encode(
      SceneFile(document: invalidDocument, assets: [])
    )
    let invalidRevision = HistoryRevision(
      identifier: SHA256.hexDigest(invalidScene),
      savedAt: Date(timeIntervalSince1970: 1_000),
      intent: .manual,
      sceneData: invalidScene
    )
    let package = SionPackage(
      document: SionDocument(title: "Current"),
      history: DocumentHistory(revisions: [invalidRevision])
    )

    let encoded = try SionArchive.encode(
      package: package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 2_000)
    )
    let decoded = try SionArchive.decode(encoded.data)

    XCTAssertEqual(encoded.committedHistory, decoded.history)
    XCTAssertFalse(
      encoded.committedHistory.revisions.contains { $0.identifier == invalidRevision.identifier }
    )
  }

  private func encodedFixture() throws -> EncodedSionArchive {
    let fixture = try makeFixture()
    return try SionArchive.encode(
      package: fixture.package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )
  }

  private func makeFixture() throws -> ArchiveFixture {
    let asset = try SionAsset(
      data: testPNGData(),
      mediaType: "image/png",
      fileExtension: "png",
      originalFilename: "source.png",
      pixelSize: SionSize(width: 1, height: 1)
    )
    let shapeA = SceneElement.shape(
      id: elementID("00000000-0000-0000-0000-000000000001"),
      frame: SionRect(x: 40, y: 40, width: 160, height: 76),
      text: "Start"
    )
    let shapeB = SceneElement.shape(
      id: elementID("00000000-0000-0000-0000-000000000002"),
      frame: SionRect(x: 300, y: 40, width: 160, height: 76),
      kind: .diamond,
      text: "Finish"
    )
    let image = SceneElement.image(
      id: elementID("00000000-0000-0000-0000-000000000003"),
      frame: SionRect(x: 40, y: 160, width: 96, height: 72),
      assetID: asset.id,
      displayAssetID: asset.id
    )
    let path = SceneElement.path(
      id: elementID("00000000-0000-0000-0000-000000000004"),
      frame: SionRect(x: 180, y: 160, width: 80, height: 80),
      path: VectorPath(commands: [
        .move(to: SionPoint(x: 0, y: 0)),
        .line(to: SionPoint(x: 1, y: 1)),
      ])
    )
    let route = ConnectorRoute(
      start: SionPoint(x: 200, y: 78),
      segments: [.line(to: SionPoint(x: 300, y: 78))]
    )
    let connector = SceneElement(
      id: elementID("00000000-0000-0000-0000-000000000005"),
      geometry: ElementGeometry(frame: .zero),
      magnetConfiguration: .preset(.none),
      style: .connectorDefault,
      content: .connector(
        ConnectorContent(
          source: .element(
            shapeA.id,
            attachment: .automatic,
            fallbackPoint: route.start
          ),
          target: .element(
            shapeB.id,
            attachment: .automatic,
            fallbackPoint: route.end
          ),
          routingStyle: .straight,
          resolvedRoute: route
        )
      )
    )
    let document = SionDocument(
      id: documentID("10000000-0000-0000-0000-000000000001"),
      title: "Recovery & routing",
      scene: SionScene(elements: [shapeA, shapeB, image, path, connector]),
      extensions: ["ch.lkmc.fixture": .string("kept")]
    )
    return ArchiveFixture(
      package: SionPackage(
        document: document,
        assets: [asset.id: asset],
        previewPNG: Data([0x89, 0x50, 0x4E, 0x47])
      ),
      asset: asset,
      shapeA: shapeA,
      shapeB: shapeB
    )
  }

  private func expectedPaths(asset: SionAsset, history: DocumentHistory) -> [String] {
    let revision = history.revisions[0]
    let timestamp = "20260827T113522Z"
    let historyPath = "history/\(timestamp)-\(revision.identifier.prefix(12)).scene.json"
    return [
      SionArchiveConstants.mimetypePath,
      SionArchiveConstants.manifestPath,
      SionArchiveConstants.scenePath,
      asset.archivePath,
      SionArchiveConstants.svgPath,
      SionArchiveConstants.mermaidPath,
      SionArchiveConstants.previewPath,
      SionArchiveConstants.historyIndexPath,
      historyPath,
      SionArchiveConstants.readmePath,
    ]
  }

  private func replacingHistory(in archive: Data, snapshotCount: Int) throws -> Data {
    var entries = try StoredZIPArchive.decode(archive).filter {
      !$0.path.hasPrefix("history/")
    }
    let sceneData = try XCTUnwrap(
      entries.first { $0.path == SionArchiveConstants.scenePath }?.data
    )
    var scene = try jsonObject(sceneData)
    var historyEntries: [ZIPEntry] = []
    var manifestHistoryEntries: [[String: Any]] = []
    let start = Date(timeIntervalSince1970: 1_787_830_000)

    for index in 0..<snapshotCount {
      scene["title"] = "History \(index)"
      let data = try JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])
      let digest = SHA256.hexDigest(data)
      let savedAt = start.addingTimeInterval(TimeInterval(index))
      let path = "history/\(historyTimestamp(savedAt))-\(digest.prefix(12)).scene.json"

      historyEntries.append(ZIPEntry(path: path, data: data))
      manifestHistoryEntries.append([
        "path": path,
        "role": "derived",
        "mediaType": "application/json",
        "bytes": data.count,
        "sha256": digest,
      ])
    }

    let manifestIndex = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.manifestPath }
    )
    var manifest = try jsonObject(entries[manifestIndex].data)
    var manifestEntries = (manifest["entries"] as! [[String: Any]]).filter {
      !(($0["path"] as? String)?.hasPrefix("history/") ?? false)
    }
    manifestEntries.append(contentsOf: manifestHistoryEntries)
    manifest["entries"] = manifestEntries
    entries[manifestIndex] = ZIPEntry(
      path: SionArchiveConstants.manifestPath,
      data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    )
    entries.append(contentsOf: historyEntries)

    return try StoredZIPArchive.encode(entries)
  }

  private func historyTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: date)
  }

  private func replacingHistoricalAssetDescriptor(
    in archive: Data,
    assetID: AssetID,
    with replacement: SionAsset
  ) throws -> Data {
    var entries = try StoredZIPArchive.decode(archive)
    let historyIndex = try XCTUnwrap(
      entries.firstIndex {
        $0.path.hasPrefix("history/")
          && $0.path != SionArchiveConstants.historyIndexPath
      }
    )
    let oldHistoryPath = entries[historyIndex].path
    var historicalScene = try jsonObject(entries[historyIndex].data)
    var assets = historicalScene["assets"] as! [[String: Any]]
    let assetIndex = try XCTUnwrap(
      assets.firstIndex { $0["id"] as? String == assetID.rawValue }
    )
    assets[assetIndex]["path"] = replacement.archivePath
    assets[assetIndex]["mediaType"] = replacement.mediaType
    assets[assetIndex]["fileExtension"] = replacement.fileExtension
    historicalScene["assets"] = assets

    let historyData = try JSONSerialization.data(
      withJSONObject: historicalScene,
      options: [.sortedKeys]
    )
    let historyDigest = SHA256.hexDigest(historyData)
    let timestamp = oldHistoryPath.dropFirst("history/".count).prefix(16)
    let historyPath = "history/\(timestamp)-\(historyDigest.prefix(12)).scene.json"
    entries[historyIndex] = ZIPEntry(path: historyPath, data: historyData)

    let indexPosition = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.historyIndexPath }
    )
    var index = try jsonObject(entries[indexPosition].data)
    var indexEntries = index["entries"] as! [[String: Any]]
    let indexedHistory = try XCTUnwrap(
      indexEntries.firstIndex { $0["scene"] as? String == oldHistoryPath }
    )
    indexEntries[indexedHistory]["id"] = "sha256:\(historyDigest)"
    indexEntries[indexedHistory]["scene"] = historyPath
    index["entries"] = indexEntries
    let indexData = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    entries[indexPosition] = ZIPEntry(
      path: SionArchiveConstants.historyIndexPath,
      data: indexData
    )

    let manifestPosition = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.manifestPath }
    )
    var manifest = try jsonObject(entries[manifestPosition].data)
    var manifestEntries = manifest["entries"] as! [[String: Any]]
    let historyManifestIndex = try XCTUnwrap(
      manifestEntries.firstIndex { $0["path"] as? String == oldHistoryPath }
    )
    manifestEntries[historyManifestIndex]["path"] = historyPath
    manifestEntries[historyManifestIndex]["bytes"] = historyData.count
    manifestEntries[historyManifestIndex]["sha256"] = historyDigest
    let indexManifestIndex = try XCTUnwrap(
      manifestEntries.firstIndex {
        $0["path"] as? String == SionArchiveConstants.historyIndexPath
      }
    )
    manifestEntries[indexManifestIndex]["bytes"] = indexData.count
    manifestEntries[indexManifestIndex]["sha256"] = SHA256.hexDigest(indexData)
    manifestEntries.append([
      "path": replacement.archivePath,
      "role": "derived",
      "mediaType": replacement.mediaType,
      "bytes": replacement.data.count,
      "sha256": SHA256.hexDigest(replacement.data),
    ])
    manifest["entries"] = manifestEntries
    entries[manifestPosition] = ZIPEntry(
      path: SionArchiveConstants.manifestPath,
      data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    )
    entries.append(ZIPEntry(path: replacement.archivePath, data: replacement.data))

    return try StoredZIPArchive.encode(entries)
  }

  private func replacingEntry(in archive: Data, path: String, with data: Data) throws -> Data {
    let entries = try StoredZIPArchive.decode(archive).map { entry in
      entry.path == path ? ZIPEntry(path: path, data: data) : entry
    }
    return try StoredZIPArchive.encode(entries)
  }

  private func removingEntry(from archive: Data, path: String) throws -> Data {
    try StoredZIPArchive.encode(
      StoredZIPArchive.decode(archive).filter { $0.path != path }
    )
  }

  private func modifyingJSONEntry(
    in archive: Data,
    path: String,
    mutation: (inout [String: Any]) -> Void
  ) throws -> Data {
    let entries = try StoredZIPArchive.decode(archive)
    let data = try XCTUnwrap(entries.first { $0.path == path }?.data)
    var object = try jsonObject(data)
    mutation(&object)
    let changed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try replacingEntry(in: archive, path: path, with: changed)
  }

  private func modifyingScene(
    in archive: Data,
    mutation: (inout [String: Any]) -> Void
  ) throws -> Data {
    var entries = try StoredZIPArchive.decode(archive)
    let sceneIndex = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.scenePath }
    )
    var scene = try jsonObject(entries[sceneIndex].data)
    mutation(&scene)
    let sceneData = try JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])
    entries[sceneIndex] = ZIPEntry(path: SionArchiveConstants.scenePath, data: sceneData)

    let manifestIndex = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.manifestPath }
    )
    var manifest = try jsonObject(entries[manifestIndex].data)
    var descriptor = manifest["scene"] as! [String: Any]
    descriptor["bytes"] = sceneData.count
    descriptor["sha256"] = SHA256.hexDigest(sceneData)
    manifest["scene"] = descriptor
    entries[manifestIndex] = ZIPEntry(
      path: SionArchiveConstants.manifestPath,
      data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    )

    return try StoredZIPArchive.encode(entries)
  }

  private func aliasingAsset(
    in archive: Data,
    originalPath: String,
    aliasPath: String
  ) throws -> Data {
    var entries = try StoredZIPArchive.decode(archive)
    let assetIndex = try XCTUnwrap(entries.firstIndex { $0.path == originalPath })
    entries[assetIndex] = ZIPEntry(path: aliasPath, data: entries[assetIndex].data)

    let sceneIndex = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.scenePath }
    )
    var scene = try jsonObject(entries[sceneIndex].data)
    var assets = scene["assets"] as! [[String: Any]]
    assets[0]["path"] = aliasPath
    scene["assets"] = assets
    let sceneData = try JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])
    entries[sceneIndex] = ZIPEntry(path: SionArchiveConstants.scenePath, data: sceneData)

    let manifestIndex = try XCTUnwrap(
      entries.firstIndex { $0.path == SionArchiveConstants.manifestPath }
    )
    var manifest = try jsonObject(entries[manifestIndex].data)
    var descriptor = manifest["scene"] as! [String: Any]
    descriptor["bytes"] = sceneData.count
    descriptor["sha256"] = SHA256.hexDigest(sceneData)
    manifest["scene"] = descriptor
    var manifestEntries = manifest["entries"] as! [[String: Any]]
    let manifestAssetIndex = try XCTUnwrap(
      manifestEntries.firstIndex { $0["path"] as? String == originalPath }
    )
    manifestEntries[manifestAssetIndex]["path"] = aliasPath
    manifest["entries"] = manifestEntries
    entries[manifestIndex] = ZIPEntry(
      path: SionArchiveConstants.manifestPath,
      data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    )

    return try StoredZIPArchive.encode(entries)
  }

  private func jsonObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func documentID(_ value: String) -> DocumentID {
    DocumentID(value)!
  }

  private func elementID(_ value: String) -> ElementID {
    ElementID(value)!
  }
}

private struct ArchiveFixture {
  let package: SionPackage
  let asset: SionAsset
  let shapeA: SceneElement
  let shapeB: SceneElement
}

private struct DuplicateKeyFixture: Codable {
  let value: Int
}

private enum ArchiveTestLimits {
  static let maximumManifestEntryCount = 4_093
  static let maximumHistorySnapshotCount = 120
}
