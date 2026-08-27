import Foundation

/// A self-contained, versioned transfer of scene elements and their assets.
public struct SceneSelectionPayload: Equatable, Sendable {
  public static let formatIdentifier = "sion-selection"
  public static let formatVersion = 1

  public let elements: [SceneElement]
  public let assets: [AssetID: SionAsset]

  public init(
    package: SionPackage,
    selectedElementIDs: Set<ElementID>
  ) throws {
    guard !selectedElementIDs.isEmpty else {
      throw SceneSelectionPayloadError.emptySelection
    }

    try package.document.validate()

    for id in selectedElementIDs.sorted(by: { $0.description < $1.description })
    where package.document.scene.element(withID: id) == nil {
      throw SceneSelectionPayloadError.elementNotFound(id)
    }

    let includedIDs = Self.includedElementIDs(
      selectedElementIDs,
      in: package.document.scene
    )
    let elements: [SceneElement] = package.document.scene.elements.compactMap { element in
      guard includedIDs.contains(element.id) else { return nil }

      let renderedRoute = SceneRenderGeometry.connectorRoute(
        for: element,
        in: package.document.scene
      )
      return Self.detachedCopy(
        of: element,
        includedIDs: includedIDs,
        renderedRoute: renderedRoute
      )
    }
    let referencedAssetIDs = Self.referencedAssetIDs(in: elements)
    var assets = [AssetID: SionAsset]()

    for id in referencedAssetIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let asset = package.assets[id] else {
        throw SceneSelectionPayloadError.missingAsset(id)
      }

      assets[id] = asset
    }

    try Self.validate(elements: elements, assets: assets)
    self.elements = elements
    self.assets = assets
  }

  public init(data: Data) throws {
    let file = try CanonicalJSON.decodeStrict(PayloadFile.self, from: data)
    guard file.format == Self.formatIdentifier else {
      throw SceneSelectionPayloadError.invalidFormat(file.format)
    }
    guard file.version == Self.formatVersion else {
      throw SceneSelectionPayloadError.unsupportedVersion(file.version)
    }

    var assets = [AssetID: SionAsset]()
    for encodedAsset in file.assets {
      let asset = try encodedAsset.model()
      guard assets.updateValue(asset, forKey: asset.id) == nil else {
        throw SceneSelectionPayloadError.duplicateAsset(asset.id)
      }
    }

    try Self.validate(elements: file.elements, assets: assets)
    elements = file.elements
    self.assets = assets
  }

  /// The copied content's bounds; connectors contribute their routed paths.
  public var contentBounds: SionRect {
    Self.contentBounds(of: elements)
  }

  public func dataRepresentation() throws -> Data {
    try CanonicalJSON.encode(
      PayloadFile(
        format: Self.formatIdentifier,
        version: Self.formatVersion,
        elements: elements,
        assets: assets.values.sorted { $0.id.rawValue < $1.id.rawValue }.map(PayloadAsset.init)
      )
    )
  }

  public func insertion(
    centeredAt targetCenter: SionPoint,
    excluding occupiedIDs: Set<ElementID> = []
  ) throws -> SceneSelectionInsertion {
    try insertion(
      centeredAt: targetCenter,
      excluding: occupiedIDs,
      generateElementID: ElementID.init
    )
  }

  func insertion(
    centeredAt targetCenter: SionPoint,
    excluding occupiedIDs: Set<ElementID>,
    generateElementID: () -> ElementID
  ) throws -> SceneSelectionInsertion {
    guard targetCenter.isFinite else {
      throw SceneSelectionPayloadError.invalidInsertionPoint
    }

    let sourceIDs = Set(elements.map(\.id))
    var unavailableIDs = occupiedIDs.union(sourceIDs)
    var remappedIDs = [ElementID: ElementID]()

    for element in elements {
      let newID = generateElementID()
      guard unavailableIDs.insert(newID).inserted else {
        throw SceneSelectionPayloadError.duplicateGeneratedElementID(newID)
      }

      remappedIDs[element.id] = newID
    }

    let sourceCenter = Self.contentBounds(of: elements).center
    let offset = targetCenter - sourceCenter
    let insertedElements = try elements.map { element in
      try Self.remappedCopy(of: element, ids: remappedIDs, offset: offset)
    }

    try Self.validate(elements: insertedElements, assets: assets)
    return SceneSelectionInsertion(elements: insertedElements, assets: assets)
  }

  private static func includedElementIDs(
    _ selectedIDs: Set<ElementID>,
    in scene: SionScene
  ) -> Set<ElementID> {
    var includedIDs = selectedIDs

    for id in selectedIDs {
      includedIDs.formUnion(scene.descendantIDs(of: id))
    }

    // Preserve connectors wholly owned by the copied subgraph.
    for element in scene.elements {
      guard let connector = element.content.connector else { continue }

      let endpointIDs = [connector.source.elementID, connector.target.elementID]
      guard endpointIDs.allSatisfy({ $0.map(includedIDs.contains) ?? false }) else {
        continue
      }

      includedIDs.insert(element.id)
    }

    return includedIDs
  }

  private static func detachedCopy(
    of source: SceneElement,
    includedIDs: Set<ElementID>,
    renderedRoute: ConnectorRoute?
  ) -> SceneElement {
    var element = source
    if let parentID = element.parentID, !includedIDs.contains(parentID) {
      element.parentID = nil
    }

    guard var connector = element.content.connector else { return element }

    connector.source = detachedEndpoint(
      connector.source,
      includedIDs: includedIDs,
      renderedPoint: renderedRoute?.start
    )
    connector.target = detachedEndpoint(
      connector.target,
      includedIDs: includedIDs,
      renderedPoint: renderedRoute?.end
    )
    element.content = .connector(connector)
    return element
  }

  private static func detachedEndpoint(
    _ endpoint: ConnectionEndpoint,
    includedIDs: Set<ElementID>,
    renderedPoint: SionPoint?
  ) -> ConnectionEndpoint {
    guard case .element(let id, _, let fallbackPoint) = endpoint,
      !includedIDs.contains(id)
    else {
      return endpoint
    }

    return .free(renderedPoint ?? fallbackPoint)
  }

  private static func remappedCopy(
    of source: SceneElement,
    ids: [ElementID: ElementID],
    offset: SionVector
  ) throws -> SceneElement {
    guard let newID = ids[source.id] else {
      throw SceneSelectionPayloadError.missingIDMapping(source.id)
    }

    var element = source
    element.id = newID
    element.geometry.frame = element.geometry.frame.translated(by: offset)

    if let parentID = source.parentID {
      guard let newParentID = ids[parentID] else {
        throw SceneSelectionPayloadError.missingIDMapping(parentID)
      }

      element.parentID = newParentID
    }

    guard var connector = element.content.connector else { return element }

    connector.source = try remappedEndpoint(connector.source, ids: ids, offset: offset)
    connector.target = try remappedEndpoint(connector.target, ids: ids, offset: offset)
    connector.manualRoute = translated(connector.manualRoute, by: offset)
    connector.resolvedRoute = nil
    element.content = .connector(connector)
    return element
  }

  private static func remappedEndpoint(
    _ endpoint: ConnectionEndpoint,
    ids: [ElementID: ElementID],
    offset: SionVector
  ) throws -> ConnectionEndpoint {
    switch endpoint {
    case .element(let id, let attachment, let fallbackPoint):
      guard let newID = ids[id] else {
        throw SceneSelectionPayloadError.missingIDMapping(id)
      }

      return .element(
        newID,
        attachment: attachment,
        fallbackPoint: fallbackPoint + offset
      )
    case .free(let point):
      return .free(point + offset)
    }
  }

  private static func translated(
    _ route: ManualConnectorRoute?,
    by offset: SionVector
  ) -> ManualConnectorRoute? {
    switch route {
    case .orthogonal(let waypoints):
      return .orthogonal(waypoints: waypoints.map { $0 + offset })
    case .curved(let controlPoint):
      return .curved(controlPoint: controlPoint + offset)
    case .bezier(let sourceControl, let targetControl):
      return .bezier(
        sourceControl: sourceControl + offset,
        targetControl: targetControl + offset
      )
    case nil:
      return nil
    }
  }

  private static func contentBounds(of elements: [SceneElement]) -> SionRect {
    var visibleElements = elements
    for index in visibleElements.indices {
      visibleElements[index].visibility = .visible
    }
    let scene = SionScene(elements: visibleElements)
    var bounds: SionRect?

    for element in visibleElements {
      if let route = SceneRenderGeometry.connectorRoute(for: element, in: scene) {
        for point in route.boundsPoints {
          let pointBounds = SionRect(x: point.x, y: point.y, width: 0, height: 0)
          bounds = bounds.map { $0.union(pointBounds) } ?? pointBounds
        }
        continue
      }

      guard element.content.connector == nil else { continue }

      let elementBounds = rotatedBounds(of: element.geometry)
      bounds = bounds.map { $0.union(elementBounds) } ?? elementBounds
    }

    return bounds ?? .zero
  }

  private static func rotatedBounds(of geometry: ElementGeometry) -> SionRect {
    let frame = geometry.frame.standardized
    guard geometry.rotationRadians != 0 else { return frame }

    let center = frame.center
    let cosine = cos(geometry.rotationRadians)
    let sine = sin(geometry.rotationRadians)
    let corners = [
      SionPoint(x: frame.minX, y: frame.minY),
      SionPoint(x: frame.maxX, y: frame.minY),
      SionPoint(x: frame.maxX, y: frame.maxY),
      SionPoint(x: frame.minX, y: frame.maxY),
    ].map { point in
      let dx = point.x - center.x
      let dy = point.y - center.y
      return SionPoint(
        x: center.x + (dx * cosine) - (dy * sine),
        y: center.y + (dx * sine) + (dy * cosine)
      )
    }
    let minimumX = corners.map(\.x).min() ?? frame.minX
    let maximumX = corners.map(\.x).max() ?? frame.maxX
    let minimumY = corners.map(\.y).min() ?? frame.minY
    let maximumY = corners.map(\.y).max() ?? frame.maxY
    return SionRect(
      x: minimumX,
      y: minimumY,
      width: maximumX - minimumX,
      height: maximumY - minimumY
    )
  }

  private static func referencedAssetIDs(in elements: [SceneElement]) -> Set<AssetID> {
    elements.reduce(into: Set<AssetID>()) { result, element in
      guard case .image(let image) = element.content else { return }

      result.insert(image.assetID)
      result.insert(image.displayAssetID)
    }
  }

  private static func validate(
    elements: [SceneElement],
    assets: [AssetID: SionAsset]
  ) throws {
    guard !elements.isEmpty else {
      throw SceneSelectionPayloadError.emptySelection
    }

    try SionScene(elements: elements).validate()

    let referencedAssetIDs = referencedAssetIDs(in: elements)
    for id in referencedAssetIDs where assets[id] == nil {
      throw SceneSelectionPayloadError.missingAsset(id)
    }
    for id in assets.keys where !referencedAssetIDs.contains(id) {
      throw SceneSelectionPayloadError.unreferencedAsset(id)
    }

    for element in elements {
      guard case .image(let image) = element.content,
        let displayAsset = assets[image.displayAssetID]
      else {
        continue
      }

      guard SafeDisplayImage.validates(displayAsset) else {
        throw SceneSelectionPayloadError.invalidAsset(displayAsset.id)
      }
    }
  }
}

public struct SceneSelectionInsertion: Equatable, Sendable {
  public let elements: [SceneElement]
  public let assets: [AssetID: SionAsset]

  public init(elements: [SceneElement], assets: [AssetID: SionAsset]) {
    self.elements = elements
    self.assets = assets
  }
}

public enum SceneSelectionPayloadError: Error, Equatable, Sendable {
  case emptySelection
  case elementNotFound(ElementID)
  case missingAsset(AssetID)
  case unreferencedAsset(AssetID)
  case duplicateAsset(AssetID)
  case invalidAsset(AssetID)
  case invalidFormat(String)
  case unsupportedVersion(Int)
  case invalidInsertionPoint
  case duplicateGeneratedElementID(ElementID)
  case missingIDMapping(ElementID)
}

private struct PayloadFile: Codable {
  let format: String
  let version: Int
  let elements: [SceneElement]
  let assets: [PayloadAsset]
}

private struct PayloadAsset: Codable {
  let id: AssetID
  let mediaType: String
  let fileExtension: String
  let originalFilename: String?
  let pixelSize: SionSize?
  let data: Data

  init(_ asset: SionAsset) {
    id = asset.id
    mediaType = asset.mediaType
    fileExtension = asset.fileExtension
    originalFilename = asset.originalFilename
    pixelSize = asset.pixelSize
    data = asset.data
  }

  func model() throws -> SionAsset {
    let asset = try SionAsset(
      data: data,
      mediaType: mediaType,
      fileExtension: fileExtension,
      originalFilename: originalFilename,
      pixelSize: pixelSize
    )
    guard asset.id == id else {
      throw SceneSelectionPayloadError.invalidAsset(id)
    }

    return asset
  }
}

extension ConnectorRoute {
  fileprivate var boundsPoints: [SionPoint] {
    var points = [start]
    for segment in segments {
      switch segment {
      case .line(let to):
        points.append(to)
      case .quadratic(let control, let to):
        points.append(contentsOf: [control, to])
      case .cubic(let control1, let control2, let to):
        points.append(contentsOf: [control1, control2, to])
      }
    }

    return points
  }
}
