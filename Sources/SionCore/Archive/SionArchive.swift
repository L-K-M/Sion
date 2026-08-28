import Foundation

public struct EncodedSionArchive: Equatable, Sendable {
  public let data: Data
  public let committedHistory: DocumentHistory

  public init(data: Data, committedHistory: DocumentHistory) {
    self.data = data
    self.committedHistory = committedHistory
  }
}

public struct SionArchiveGenerator: Equatable, Sendable {
  public let name: String
  public let version: String

  public init(name: String, version: String) {
    self.name = name
    self.version = version
  }
}

public enum SionArchiveError: Error, Equatable {
  case duplicateManifestEntry(String)
  case entryHashMismatch(String)
  case invalidHistoryIdentifier(String)
  case invalidManifestEntry(String)
  case invalidManifestFormat(String)
  case invalidMimetype
  case invalidSceneFormat(String)
  case missingEntry(String)
  case sceneDescriptorMismatch
  case sceneAssetSetMismatch
  case tooManyHistorySnapshots(Int)
  case tooManyManifestEntries(Int)
  case unsupportedFormatVersion(Int)
  case unsupportedHistoryVersion(Int)
  case unsupportedSceneVersion(Int)
  case unreferencedAuthoritativeEntry(String)
  case unexpectedEntry(String)
}

/// Encodes and validates the `.sion` recovery container.
public enum SionArchive {
  public static func encode(
    package: SionPackage,
    intent: SaveIntent,
    at date: Date = Date(),
    generator: SionArchiveGenerator
  ) throws -> EncodedSionArchive {
    try package.validate()

    let writtenAt = wholeSecond(date)
    let document = documentWithResolvedRoutes(package.document)
    let currentAssets = SionPackage.referencedAssetIDs(in: document).compactMap {
      package.assets[$0]
    }
    let sceneFile = SceneFile(document: document, assets: currentAssets)
    let sceneData = try CanonicalJSON.encode(sceneFile)
    let candidateHistory = package.history.appending(
      sceneData: sceneData,
      at: writtenAt,
      intent: intent
    )
    let history = usableHistory(candidateHistory, assets: package.assets)
    let mermaid = MermaidExporter.export(document: document)

    var contents = [String: EntryContent]()
    contents[SionArchiveConstants.scenePath] = EntryContent(
      data: sceneData,
      role: .authoritative,
      mediaType: "application/json"
    )

    let currentAssetIDs = sceneFile.referencedAssetIDs
    let requiredAssetIDs = history.revisions.reduce(currentAssetIDs) { result, revision in
      guard
        let historicalScene = try? CanonicalJSON.decodeStrict(
          SceneFile.self,
          from: revision.sceneData
        )
      else {
        return result
      }

      return result.union(historicalScene.referencedAssetIDs)
    }
    for assetID in requiredAssetIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let asset = package.assets[assetID] else {
        throw SionPackageError.missingAsset(assetID)
      }

      contents[asset.archivePath] = EntryContent(
        data: asset.data,
        role: currentAssetIDs.contains(assetID) ? .authoritative : .derived,
        mediaType: asset.mediaType
      )
    }

    let svg = try SVGExporter.export(document: document, assets: package.assets)
    contents[SionArchiveConstants.svgPath] = EntryContent(
      data: Data(svg.utf8),
      role: .derived,
      mediaType: "image/svg+xml"
    )
    contents[SionArchiveConstants.mermaidPath] = EntryContent(
      data: Data(mermaid.source.utf8),
      role: .derived,
      mediaType: "text/vnd.mermaid"
    )

    if let preview = package.previewPNG {
      contents[SionArchiveConstants.previewPath] = EntryContent(
        data: preview,
        role: .derived,
        mediaType: "image/png"
      )
    }

    let historyEntries = history.revisions.map(historyEntry)
    if !historyEntries.isEmpty {
      let index = HistoryIndex(
        format: SionArchiveConstants.historyFormatIdentifier,
        version: SionArchiveConstants.historyVersion,
        entries: historyEntries.map(\.index)
      )
      contents[SionArchiveConstants.historyIndexPath] = EntryContent(
        data: try CanonicalJSON.encode(index),
        role: .derived,
        mediaType: "application/json"
      )

      for entry in historyEntries {
        contents[entry.path] = EntryContent(
          data: entry.revision.sceneData,
          role: .derived,
          mediaType: "application/json"
        )
      }
    }

    contents[SionArchiveConstants.readmePath] = EntryContent(
      data: Data(recoveryReadme.utf8),
      role: .derived,
      mediaType: "text/plain"
    )

    let manifestEntries =
      contents
      .filter { $0.key != SionArchiveConstants.scenePath }
      .map { path, content in
        ManifestEntry(
          path: path,
          role: content.role,
          mediaType: content.mediaType,
          bytes: content.data.count,
          sha256: SHA256.hexDigest(content.data)
        )
      }
      .sorted { $0.path < $1.path }
    let manifest = SionManifest(
      format: SionArchiveConstants.formatIdentifier,
      formatVersion: SionArchiveConstants.formatVersion,
      generator: GeneratorDescriptor(name: generator.name, version: generator.version),
      writtenAt: writtenAt,
      scene: CurrentSceneDescriptor(
        path: SionArchiveConstants.scenePath,
        schemaVersion: SionArchiveConstants.sceneSchemaVersion,
        bytes: sceneData.count,
        sha256: SHA256.hexDigest(sceneData)
      ),
      entries: manifestEntries,
      mermaidCoverage: mermaid.coverage
    )

    let entries = try orderedEntries(
      manifest: CanonicalJSON.encode(manifest),
      contents: contents
    )
    let archive = try StoredZIPArchive.encode(entries)

    // Commit only history that the complete artifact can restore.
    let verifiedPackage = try decode(archive)
    return EncodedSionArchive(data: archive, committedHistory: verifiedPackage.history)
  }

  /// Strictly restores one retained scene using assets already loaded from its package.
  public static func document(
    from revision: HistoryRevision,
    assets: [AssetID: SionAsset]
  ) throws -> SionDocument {
    guard revision.identifier == SHA256.hexDigest(revision.sceneData) else {
      throw SionArchiveError.invalidHistoryIdentifier(revision.identifier)
    }

    let scene = try CanonicalJSON.decodeStrict(SceneFile.self, from: revision.sceneData)
    let assetData = Dictionary(
      uniqueKeysWithValues: assets.values.map { asset in
        (asset.archivePath, asset.data)
      })
    return try scene.model(assetData: assetData).0
  }

  public static func decode(_ data: Data) throws -> SionPackage {
    let entries = try StoredZIPArchive.decodeDeferringChecksums(data)
    guard entries.first?.path == SionArchiveConstants.mimetypePath,
      entries.first?.data == Data(SionArchiveConstants.mediaType.utf8)
    else {
      throw SionArchiveError.invalidMimetype
    }

    let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
    let manifestData = try required(SionArchiveConstants.manifestPath, in: byPath)
    let manifest = try CanonicalJSON.decodeStrict(SionManifest.self, from: manifestData)
    try validate(manifest)
    try rejectUnexpectedEntries(in: byPath, manifest: manifest)

    let sceneData = try required(SionArchiveConstants.scenePath, in: byPath)
    guard manifest.scene.path == SionArchiveConstants.scenePath,
      manifest.scene.schemaVersion == SionArchiveConstants.sceneSchemaVersion,
      manifest.scene.bytes == sceneData.count,
      manifest.scene.sha256 == SHA256.hexDigest(sceneData)
    else {
      throw SionArchiveError.sceneDescriptorMismatch
    }

    let verified = try verifiedManifestEntries(manifest.entries, archive: byPath)
    let sceneFile = try CanonicalJSON.decodeStrict(SceneFile.self, from: sceneData)
    guard sceneFile.assetPaths.isSubset(of: verified.authoritative) else {
      let missing = sceneFile.assetPaths.subtracting(verified.authoritative).sorted().first
      throw SionArchiveError.missingEntry(missing ?? SionArchiveConstants.scenePath)
    }
    let authoritativeAssets = Set(
      verified.authoritative.filter { $0.hasPrefix(assetPathPrefix) }
    )
    guard authoritativeAssets == sceneFile.assetPaths else {
      let unexpected = authoritativeAssets.subtracting(sceneFile.assetPaths).sorted().first
      throw SionArchiveError.unreferencedAuthoritativeEntry(
        unexpected ?? SionArchiveConstants.scenePath
      )
    }

    let (document, currentAssets) = try sceneFile.model(assetData: byPath)
    var assets = currentAssets
    let history = try decodeHistory(
      from: byPath,
      verifiedDerivedPaths: verified.derived,
      verifiedAuthoritativePaths: verified.authoritative,
      assets: &assets
    )
    let preview =
      verified.derived.contains(SionArchiveConstants.previewPath)
      ? byPath[SionArchiveConstants.previewPath]
      : nil

    return SionPackage(
      document: document,
      assets: assets,
      history: history,
      previewPNG: preview
    )
  }

  private static func documentWithResolvedRoutes(_ document: SionDocument) -> SionDocument {
    var resolved = document
    var elements = document.scene.elements

    for index in elements.indices {
      guard case .connector(var connector) = elements[index].content,
        connector.resolvedRoute == nil,
        let route = SceneRenderGeometry.connectorRoute(
          for: elements[index],
          in: document.scene
        )
      else {
        continue
      }

      connector.resolvedRoute = route
      elements[index].content = .connector(connector)
    }

    resolved.scene.elements = elements
    return resolved
  }

  private static func usableHistory(
    _ history: DocumentHistory,
    assets: [AssetID: SionAsset]
  ) -> DocumentHistory {
    var assetData = [String: Data]()
    for asset in assets.values {
      assetData[asset.archivePath] = asset.data
    }

    var revisions: [HistoryRevision] = []
    var seenIdentifiers = Set<String>()
    for revision in history.revisions {
      guard SHA256.hexDigest(revision.sceneData) == revision.identifier,
        let scene = try? CanonicalJSON.decodeStrict(SceneFile.self, from: revision.sceneData)
      else {
        continue
      }

      guard scene.assetsAreAvailable(in: assets) else {
        continue
      }

      do {
        _ = try scene.model(assetData: assetData)
      } catch {
        continue
      }

      guard seenIdentifiers.insert(revision.identifier).inserted else {
        continue
      }

      revisions.append(
        HistoryRevision(
          identifier: revision.identifier,
          savedAt: wholeSecond(revision.savedAt),
          intent: revision.intent,
          sceneData: revision.sceneData
        )
      )
    }

    return DocumentHistory(revisions: revisions)
  }

  private static func historyEntry(_ revision: HistoryRevision) -> ArchiveHistoryEntry {
    let timestamp = historyTimestamp(revision.savedAt)
    let hashPrefix = String(revision.identifier.prefix(historyHashPrefixLength))
    let path = "history/\(timestamp)-\(hashPrefix).scene.json"
    let index = HistoryIndexEntry(
      id: "\(SionArchiveConstants.assetIDPrefix)\(revision.identifier)",
      savedAt: revision.savedAt,
      scene: path,
      reason: revision.intent
    )

    return ArchiveHistoryEntry(path: path, revision: revision, index: index)
  }

  private static func orderedEntries(
    manifest: Data,
    contents: [String: EntryContent]
  ) throws -> [ZIPEntry] {
    var result = [
      ZIPEntry(
        path: SionArchiveConstants.mimetypePath,
        data: Data(SionArchiveConstants.mediaType.utf8)
      ),
      ZIPEntry(path: SionArchiveConstants.manifestPath, data: manifest),
      ZIPEntry(
        path: SionArchiveConstants.scenePath,
        data: try required(SionArchiveConstants.scenePath, in: contents.mapValues(\.data))
      ),
    ]

    let assetPaths = contents.keys.filter { $0.hasPrefix("assets/") }.sorted()
    result += assetPaths.compactMap { path in
      contents[path].map { ZIPEntry(path: path, data: $0.data) }
    }
    for path in [SionArchiveConstants.svgPath, SionArchiveConstants.mermaidPath] {
      if let content = contents[path] {
        result.append(ZIPEntry(path: path, data: content.data))
      }
    }
    if let preview = contents[SionArchiveConstants.previewPath] {
      result.append(ZIPEntry(path: SionArchiveConstants.previewPath, data: preview.data))
    }
    if let index = contents[SionArchiveConstants.historyIndexPath] {
      result.append(ZIPEntry(path: SionArchiveConstants.historyIndexPath, data: index.data))
    }

    let historyPaths = contents.keys
      .filter { $0.hasPrefix("history/") && $0 != SionArchiveConstants.historyIndexPath }
      .sorted()
    result += historyPaths.compactMap { path in
      contents[path].map { ZIPEntry(path: path, data: $0.data) }
    }
    if let readme = contents[SionArchiveConstants.readmePath] {
      result.append(ZIPEntry(path: SionArchiveConstants.readmePath, data: readme.data))
    }

    return result
  }

  private static func validate(_ manifest: SionManifest) throws {
    guard manifest.format == SionArchiveConstants.formatIdentifier else {
      throw SionArchiveError.invalidManifestFormat(manifest.format)
    }
    guard manifest.formatVersion == SionArchiveConstants.formatVersion else {
      throw SionArchiveError.unsupportedFormatVersion(manifest.formatVersion)
    }
    guard manifest.entries.count <= ArchiveLimits.maximumManifestEntryCount else {
      throw SionArchiveError.tooManyManifestEntries(manifest.entries.count)
    }
  }

  private static func rejectUnexpectedEntries(
    in archive: [String: Data],
    manifest: SionManifest
  ) throws {
    let expected = Set(manifest.entries.map(\.path)).union([
      SionArchiveConstants.mimetypePath,
      SionArchiveConstants.manifestPath,
      SionArchiveConstants.scenePath,
    ])
    guard let unexpected = archive.keys.filter({ !expected.contains($0) }).sorted().first else {
      return
    }

    throw SionArchiveError.unexpectedEntry(unexpected)
  }

  private static func verifiedManifestEntries(
    _ entries: [ManifestEntry],
    archive: [String: Data]
  ) throws -> VerifiedPaths {
    var seen = Set<String>()
    var authoritative = Set<String>()
    var derived = Set<String>()

    for entry in entries {
      guard seen.insert(entry.path).inserted else {
        throw SionArchiveError.duplicateManifestEntry(entry.path)
      }
      guard !reservedManifestEntryPaths.contains(entry.path) else {
        throw SionArchiveError.duplicateManifestEntry(entry.path)
      }
      try validateManifestEntry(entry)
      guard let data = archive[entry.path] else {
        if entry.role == .authoritative {
          throw SionArchiveError.missingEntry(entry.path)
        }
        continue
      }

      let matches = entry.bytes == data.count && entry.sha256 == SHA256.hexDigest(data)
      guard matches else {
        if entry.role == .authoritative {
          throw SionArchiveError.entryHashMismatch(entry.path)
        }
        continue
      }

      switch entry.role {
      case .authoritative:
        authoritative.insert(entry.path)
      case .derived:
        derived.insert(entry.path)
      }
    }

    return VerifiedPaths(authoritative: authoritative, derived: derived)
  }

  private static func validateManifestEntry(_ entry: ManifestEntry) throws {
    if let mediaType = fixedDerivedEntries[entry.path] {
      guard entry.role == .derived, entry.mediaType == mediaType else {
        throw SionArchiveError.invalidManifestEntry(entry.path)
      }
      return
    }

    if isAssetPath(entry.path) {
      guard !entry.mediaType.isEmpty else {
        throw SionArchiveError.invalidManifestEntry(entry.path)
      }
      return
    }

    if historyFilename(entry.path) != nil {
      guard entry.role == .derived, entry.mediaType == jsonMediaType else {
        throw SionArchiveError.invalidManifestEntry(entry.path)
      }
      return
    }

    throw SionArchiveError.invalidManifestEntry(entry.path)
  }

  private static func isAssetPath(_ path: String) -> Bool {
    guard path.hasPrefix(assetPathPrefix) else {
      return false
    }

    let filename = path.dropFirst(assetPathPrefix.count)
    let components = filename.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 2,
      components[0].count == sha256HexLength,
      components[0].allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
      (1...SionArchiveConstants.maximumAssetExtensionLength).contains(
        components[1].count
      )
    else {
      return false
    }

    return components[1].unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0)
    }
  }

  private static func decodeHistory(
    from archive: [String: Data],
    verifiedDerivedPaths: Set<String>,
    verifiedAuthoritativePaths: Set<String>,
    assets: inout [AssetID: SionAsset]
  ) throws -> DocumentHistory {
    let snapshotCount = archive.keys.lazy.filter { historyFilename($0) != nil }.count
    guard snapshotCount <= DocumentHistory.maximumRevisionCount else {
      throw SionArchiveError.tooManyHistorySnapshots(snapshotCount)
    }

    var candidates: [HistoryCandidate] = []

    if verifiedDerivedPaths.contains(SionArchiveConstants.historyIndexPath),
      let data = archive[SionArchiveConstants.historyIndexPath],
      let index = try? CanonicalJSON.decodeStrict(HistoryIndex.self, from: data),
      index.format == SionArchiveConstants.historyFormatIdentifier,
      index.version == SionArchiveConstants.historyVersion,
      index.entries.count <= DocumentHistory.maximumRevisionCount
    {
      for entry in index.entries {
        guard verifiedDerivedPaths.contains(entry.scene),
          let filename = historyFilename(entry.scene),
          wholeSecond(entry.savedAt) == filename.savedAt
        else {
          continue
        }

        candidates.append(
          HistoryCandidate(
            path: entry.scene,
            identifier: entry.id,
            savedAt: filename.savedAt,
            intent: entry.reason
          )
        )
      }
    }

    // The index is derived. Valid snapshots remain recoverable without it.
    for path in verifiedDerivedPaths.sorted() {
      guard let filename = historyFilename(path) else {
        continue
      }

      candidates.append(
        HistoryCandidate(
          path: path,
          identifier: nil,
          savedAt: filename.savedAt,
          intent: .manual
        )
      )
    }

    candidates.sort { lhs, rhs in
      if lhs.savedAt != rhs.savedAt {
        return lhs.savedAt > rhs.savedAt
      }
      if lhs.path != rhs.path {
        return lhs.path < rhs.path
      }

      // Prefer index metadata, then retry the snapshot directly if it is corrupt.
      return lhs.identifier != nil && rhs.identifier == nil
    }

    var revisions: [HistoryRevision] = []
    var seenIdentifiers = Set<String>()
    var acceptedPaths = Set<String>()
    let verifiedAssetPaths = verifiedAuthoritativePaths.union(verifiedDerivedPaths)
    for candidate in candidates {
      guard !acceptedPaths.contains(candidate.path),
        revisions.count < DocumentHistory.maximumRevisionCount,
        let sceneData = archive[candidate.path],
        let filename = historyFilename(candidate.path)
      else {
        continue
      }

      let identifier = SHA256.hexDigest(sceneData)
      let expectedIdentifier: String
      if let value = candidate.identifier {
        guard value.hasPrefix(SionArchiveConstants.assetIDPrefix) else {
          continue
        }

        expectedIdentifier = String(
          value.dropFirst(SionArchiveConstants.assetIDPrefix.count)
        )
      } else {
        expectedIdentifier = identifier
      }

      guard expectedIdentifier == identifier,
        identifier.hasPrefix(filename.hashPrefix),
        let scene = try? CanonicalJSON.decodeStrict(SceneFile.self, from: sceneData),
        scene.assetPaths.isSubset(of: verifiedAssetPaths),
        let decoded = try? scene.model(assetData: archive)
      else {
        continue
      }

      let hasConflictingAsset = decoded.1.contains { id, historicalAsset in
        guard let loadedAsset = assets[id] else { return false }

        return loadedAsset != historicalAsset
      }
      guard !hasConflictingAsset,
        seenIdentifiers.insert(identifier).inserted
      else {
        continue
      }

      for (id, asset) in decoded.1 where assets[id] == nil {
        assets[id] = asset
      }
      acceptedPaths.insert(candidate.path)
      revisions.append(
        HistoryRevision(
          identifier: identifier,
          savedAt: candidate.savedAt,
          intent: candidate.intent,
          sceneData: sceneData
        )
      )
    }

    return DocumentHistory(preservingValidatedRevisions: revisions)
  }

  private static func historyFilename(_ path: String) -> HistoryFilename? {
    guard path.hasPrefix(historyPathPrefix), path.hasSuffix(historyPathSuffix) else {
      return nil
    }

    let start = path.index(path.startIndex, offsetBy: historyPathPrefix.count)
    let end = path.index(path.endIndex, offsetBy: -historyPathSuffix.count)
    let stem = path[start..<end]
    let parts = stem.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2,
      parts[1].count == historyHashPrefixLength,
      parts[1].allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
      let savedAt = parseHistoryTimestamp(String(parts[0]))
    else {
      return nil
    }

    return HistoryFilename(savedAt: savedAt, hashPrefix: String(parts[1]))
  }

  private static func wholeSecond(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
  }

  private static func historyTimestamp(_ date: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents(
      in: historyTimeZone,
      from: date
    )
    return String(
      format: "%04d%02d%02dT%02d%02d%02dZ",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0,
      components.hour ?? 0,
      components.minute ?? 0,
      components.second ?? 0
    )
  }

  private static func parseHistoryTimestamp(_ value: String) -> Date? {
    let characters = Array(value)
    guard characters.count == historyTimestampLength,
      characters[8] == "T",
      characters[15] == "Z",
      let year = Int(String(characters[0..<4])),
      let month = Int(String(characters[4..<6])),
      let day = Int(String(characters[6..<8])),
      let hour = Int(String(characters[9..<11])),
      let minute = Int(String(characters[11..<13])),
      let second = Int(String(characters[13..<15]))
    else {
      return nil
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = historyTimeZone
    return calendar.date(
      from: DateComponents(
        calendar: calendar,
        timeZone: historyTimeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
      )
    )
  }

  private static func required<Value>(_ key: String, in values: [String: Value]) throws -> Value {
    guard let value = values[key] else {
      throw SionArchiveError.missingEntry(key)
    }

    return value
  }

  private static let historyHashPrefixLength = 12
  private static let sha256HexLength = 64
  private static let historyTimestampLength = 16
  private static let historyPathPrefix = "history/"
  private static let historyPathSuffix = ".scene.json"
  private static let assetPathPrefix = "assets/"
  private static let jsonMediaType = "application/json"
  private static let historyTimeZone = TimeZone(secondsFromGMT: 0)!
  private static let reservedManifestEntryPaths: Set<String> = [
    SionArchiveConstants.mimetypePath,
    SionArchiveConstants.manifestPath,
    SionArchiveConstants.scenePath,
  ]
  private static let fixedDerivedEntries: [String: String] = [
    SionArchiveConstants.svgPath: "image/svg+xml",
    SionArchiveConstants.mermaidPath: "text/vnd.mermaid",
    SionArchiveConstants.previewPath: "image/png",
    SionArchiveConstants.historyIndexPath: jsonMediaType,
    SionArchiveConstants.readmePath: "text/plain",
  ]

  private static let recoveryReadme = """
    Sion document recovery

    - Open exports/diagram.svg in any browser or vector editor.
    - Open exports/diagram.mmd in a Mermaid-compatible editor.
    - Original pasted files are under assets/.
    - scene.json is the authoritative editable scene.
    - history/ contains retained scene snapshots.

    Derived exports may omit illustration-only semantics. Do not replace
    scene.json with an export.
    """ + "\n"
}

private struct EntryContent {
  let data: Data
  let role: ManifestEntryRole
  let mediaType: String
}

private struct ArchiveHistoryEntry {
  let path: String
  let revision: HistoryRevision
  let index: HistoryIndexEntry
}

private struct VerifiedPaths {
  let authoritative: Set<String>
  let derived: Set<String>
}

private struct HistoryCandidate {
  let path: String
  let identifier: String?
  let savedAt: Date
  let intent: SaveIntent
}

private struct HistoryFilename {
  let savedAt: Date
  let hashPrefix: String
}

private enum ArchiveLimits {
  /// ZIP reserves three entries outside the manifest list.
  static let maximumManifestEntryCount = 4_093
}
