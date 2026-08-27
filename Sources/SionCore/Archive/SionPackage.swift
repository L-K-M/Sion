import Foundation

public struct SionAsset: Equatable, Sendable {
  public let id: AssetID
  public let mediaType: String
  public let fileExtension: String
  public let originalFilename: String?
  public let pixelSize: SionSize?
  public let data: Data

  public init(
    data: Data,
    mediaType: String,
    fileExtension: String,
    originalFilename: String? = nil,
    pixelSize: SionSize? = nil
  ) throws {
    let normalizedExtension = fileExtension.lowercased()
    guard Self.isSafe(fileExtension: normalizedExtension) else {
      throw SionPackageError.invalidAssetExtension(fileExtension)
    }

    let normalizedMediaType = mediaType.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedMediaType.isEmpty else {
      throw SionPackageError.invalidAssetMediaType(mediaType)
    }

    if let pixelSize, !Self.isValid(pixelSize: pixelSize) {
      throw SionPackageError.invalidAssetPixelSize(pixelSize)
    }

    let digest = SHA256.hexDigest(data)
    id = AssetID(rawValue: "sha256:\(digest)")
    self.mediaType = normalizedMediaType
    self.fileExtension = normalizedExtension
    self.originalFilename = originalFilename
    self.pixelSize = pixelSize
    self.data = data
  }

  public var archivePath: String {
    "assets/\(id.rawValue.dropFirst(SionArchiveConstants.assetIDPrefix.count)).\(fileExtension)"
  }

  private static func isSafe(fileExtension: String) -> Bool {
    guard (1...SionArchiveConstants.maximumAssetExtensionLength).contains(fileExtension.count)
    else {
      return false
    }

    return fileExtension.unicodeScalars.allSatisfy { scalar in
      CharacterSet.alphanumerics.contains(scalar)
    }
  }

  private static func isValid(pixelSize: SionSize) -> Bool {
    pixelSize.width.isFinite
      && pixelSize.height.isFinite
      && pixelSize.width > 0
      && pixelSize.height > 0
      && pixelSize.width <= SionArchiveConstants.maximumPixelDimension
      && pixelSize.height <= SionArchiveConstants.maximumPixelDimension
  }
}

public struct SionPackage: Equatable, Sendable {
  public var document: SionDocument
  public var assets: [AssetID: SionAsset]
  public var history: DocumentHistory
  public var previewPNG: Data?

  public init(
    document: SionDocument = SionDocument(),
    assets: [AssetID: SionAsset] = [:],
    history: DocumentHistory = DocumentHistory(),
    previewPNG: Data? = nil
  ) {
    self.document = document
    self.assets = assets
    self.history = history
    self.previewPNG = previewPNG
  }

  public mutating func insertAsset(_ asset: SionAsset) {
    assets[asset.id] = asset
  }

  public func validate() throws {
    try document.validate()

    let referenced = Self.referencedAssetIDs(in: document)
    for id in referenced where assets[id] == nil {
      throw SionPackageError.missingAsset(id)
    }

    for element in document.scene.elements {
      guard case .image(let image) = element.content,
        let displayAsset = assets[image.displayAssetID]
      else {
        continue
      }

      guard SafeDisplayImage.validates(displayAsset) else {
        throw SionPackageError.invalidDisplayAsset(displayAsset.id)
      }
    }
  }

  public static func referencedAssetIDs(in document: SionDocument) -> Set<AssetID> {
    document.scene.elements.reduce(into: Set<AssetID>()) { result, element in
      guard case .image(let image) = element.content else { return }

      result.insert(image.assetID)
      result.insert(image.displayAssetID)
    }
  }
}

public enum SionPackageError: Error, Equatable {
  case invalidAssetExtension(String)
  case invalidAssetMediaType(String)
  case invalidAssetPixelSize(SionSize)
  case invalidDisplayAsset(AssetID)
  case missingAsset(AssetID)
}

public enum SionArchiveConstants {
  public static let mediaType = "application/vnd.lkmc.sion+zip"
  public static let formatIdentifier = "sion-document"
  public static let sceneFormatIdentifier = "sion-scene"
  public static let historyFormatIdentifier = "sion-history"
  public static let formatVersion = 1
  public static let sceneSchemaVersion = 1
  public static let historyVersion = 1
  public static let assetIDPrefix = "sha256:"
  public static let maximumEntryByteCount = 256 * 1_024 * 1_024
  public static let maximumAssetExtensionLength = 12
  public static let maximumPixelDimension = 1_000_000.0

  static let mimetypePath = "mimetype"
  static let manifestPath = "manifest.json"
  static let scenePath = "scene.json"
  static let svgPath = "exports/diagram.svg"
  static let mermaidPath = "exports/diagram.mmd"
  static let previewPath = "previews/preview.png"
  static let historyIndexPath = "history/index.json"
  static let readmePath = "README.txt"
}
