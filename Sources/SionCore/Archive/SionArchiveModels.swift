import Foundation

struct SceneFile: Codable, Equatable {
  let format: String
  let schemaVersion: Int
  let id: DocumentID
  let title: String
  let scene: SceneFileScene
  let assets: [AssetDescriptor]
  let extensions: [String: PortableValue]

  init(document: SionDocument, assets: [SionAsset]) {
    format = SionArchiveConstants.sceneFormatIdentifier
    schemaVersion = SionArchiveConstants.sceneSchemaVersion
    id = document.id
    title = document.title
    scene = SceneFileScene(scene: document.scene)
    self.assets = assets.map(AssetDescriptor.init).sorted { $0.path < $1.path }
    extensions = document.extensions
  }

  var referencedAssetIDs: Set<AssetID> {
    Set(assets.map(\.id))
  }

  var assetPaths: Set<String> {
    Set(assets.map(\.path))
  }

  func assetsAreAvailable(in available: [AssetID: SionAsset]) -> Bool {
    assets.allSatisfy { descriptor in
      guard let asset = available[descriptor.id] else {
        return false
      }

      return descriptor.path == asset.archivePath
        && descriptor.byteLength == asset.data.count
        && descriptor.sha256 == SHA256.hexDigest(asset.data)
    }
  }

  func model(assetData: [String: Data]) throws -> (SionDocument, [AssetID: SionAsset]) {
    guard format == SionArchiveConstants.sceneFormatIdentifier else {
      throw SionArchiveError.invalidSceneFormat(format)
    }
    guard schemaVersion == SionArchiveConstants.sceneSchemaVersion else {
      throw SionArchiveError.unsupportedSceneVersion(schemaVersion)
    }

    let document = SionDocument(
      id: id,
      title: title,
      scene: scene.model,
      extensions: extensions
    )
    try document.validate()
    guard referencedAssetIDs == SionPackage.referencedAssetIDs(in: document) else {
      throw SionArchiveError.sceneAssetSetMismatch
    }

    var decodedAssets: [AssetID: SionAsset] = [:]
    for descriptor in assets {
      guard let data = assetData[descriptor.path] else {
        throw SionArchiveError.missingEntry(descriptor.path)
      }
      guard data.count == descriptor.byteLength,
        SHA256.hexDigest(data) == descriptor.sha256
      else {
        throw SionArchiveError.entryHashMismatch(descriptor.path)
      }

      let asset = try SionAsset(
        data: data,
        mediaType: descriptor.mediaType,
        fileExtension: descriptor.fileExtension,
        originalFilename: descriptor.originalFilename,
        pixelSize: descriptor.pixelSize
      )
      guard asset.id == descriptor.id,
        asset.archivePath == descriptor.path,
        decodedAssets[asset.id] == nil
      else {
        throw SionArchiveError.entryHashMismatch(descriptor.path)
      }
      decodedAssets[asset.id] = asset
    }

    let package = SionPackage(document: document, assets: decodedAssets)
    try package.validate()
    return (document, decodedAssets)
  }
}

struct SceneFileScene: Codable, Equatable {
  let canvas: SionCanvas
  let elements: [SceneFileElement]
  let extensions: [String: PortableValue]

  init(scene: SionScene) {
    canvas = scene.canvas
    elements = scene.elements.map(SceneFileElement.init)
    extensions = scene.extensions
  }

  var model: SionScene {
    SionScene(canvas: canvas, elements: elements.map(\.model), extensions: extensions)
  }
}

struct SceneFileElement: Codable, Equatable {
  let id: ElementID
  let parentID: ElementID?
  let name: String?
  let geometry: ElementGeometry
  let visibility: ElementVisibility
  let lockState: ElementLockState
  let magnetConfiguration: MagnetConfiguration
  let magnets: [Magnet]
  let style: ElementStyle
  let content: ElementContent
  let extensions: [String: PortableValue]

  init(element: SceneElement) {
    id = element.id
    parentID = element.parentID
    name = element.name
    geometry = element.geometry
    visibility = element.visibility
    lockState = element.lockState
    magnetConfiguration = element.magnetConfiguration
    magnets = element.expandedMagnets
    style = element.style
    content = element.content
    extensions = element.extensions
  }

  var model: SceneElement {
    var element = SceneElement(
      id: id,
      parentID: parentID,
      name: name,
      geometry: geometry,
      visibility: visibility,
      lockState: lockState,
      magnetConfiguration: magnetConfiguration,
      style: style,
      content: content,
      extensions: extensions
    )

    if !Self.magnetsMatch(element.expandedMagnets, magnets) {
      // Expanded points preserve appearance if a future preset changes.
      element.magnetConfiguration = .custom(magnets)
    }

    return element
  }

  private static func magnetsMatch(_ first: [Magnet], _ second: [Magnet]) -> Bool {
    guard first.count == second.count else {
      return false
    }

    return zip(first, second).allSatisfy { lhs, rhs in
      lhs.id == rhs.id
        && lhs.connectionDirection == rhs.connectionDirection
        && lhs.normalizedPosition.distance(to: rhs.normalizedPosition) <= magnetTolerance
        && (lhs.outwardDirection - rhs.outwardDirection).length <= magnetTolerance
    }
  }

  private static let magnetTolerance = 1e-12
}

struct AssetDescriptor: Codable, Equatable {
  let id: AssetID
  let path: String
  let mediaType: String
  let fileExtension: String
  let byteLength: Int
  let sha256: String
  let originalFilename: String?
  let pixelSize: SionSize?

  init(asset: SionAsset) {
    id = asset.id
    path = asset.archivePath
    mediaType = asset.mediaType
    fileExtension = asset.fileExtension
    byteLength = asset.data.count
    sha256 = SHA256.hexDigest(asset.data)
    originalFilename = asset.originalFilename
    pixelSize = asset.pixelSize
  }
}

struct SionManifest: Codable, Equatable {
  let format: String
  let formatVersion: Int
  let generator: GeneratorDescriptor
  let writtenAt: Date
  let scene: CurrentSceneDescriptor
  let entries: [ManifestEntry]
  let mermaidCoverage: MermaidCoverage
}

struct GeneratorDescriptor: Codable, Equatable {
  let name: String
  let version: String
}

struct CurrentSceneDescriptor: Codable, Equatable {
  let path: String
  let schemaVersion: Int
  let bytes: Int
  let sha256: String
}

enum ManifestEntryRole: String, Codable {
  case authoritative
  case derived
}

struct ManifestEntry: Codable, Equatable {
  let path: String
  let role: ManifestEntryRole
  let mediaType: String
  let bytes: Int
  let sha256: String
}

public enum MermaidCoverage: String, Codable, Equatable, Sendable {
  case complete
  case partial
  case none
}

struct HistoryIndex: Codable, Equatable {
  let format: String
  let version: Int
  let entries: [HistoryIndexEntry]
}

struct HistoryIndexEntry: Codable, Equatable {
  let id: String
  let savedAt: Date
  let scene: String
  let reason: SaveIntent
}
