import Foundation

/// One bounded scene query plus deterministic work instrumentation.
package struct SceneRenderQuery {
  package let elements: [SceneElement]
  package let examinedElementCount: Int
}

/// Reuses spatial and routing work for one mutable editor scene state.
package struct SceneRenderContext {
  package typealias ConnectorRouteResolver = (SceneElement, SionScene) -> ConnectorRoute?

  private var scene: SionScene
  private var spatialIndex: SceneSpatialIndex
  private var visibleConnectorIndices: Set<Int>
  private let indicesByID: [ElementID: Int]
  private var connectorRoutes: [ElementID: CachedConnectorRoute]
  private let connectorRouteResolver: ConnectorRouteResolver

  package init(
    scene: SionScene,
    connectorRouteResolver: @escaping ConnectorRouteResolver = {
      SceneRenderGeometry.connectorRoute(for: $0, in: $1)
    }
  ) {
    self.scene = scene
    self.connectorRouteResolver = connectorRouteResolver
    indicesByID = Dictionary(
      uniqueKeysWithValues: scene.elements.enumerated().map { ($0.element.id, $0.offset) }
    )
    connectorRoutes = [:]

    var spatialIndex = SceneSpatialIndex()
    var visibleConnectorIndices = Set<Int>()

    for (index, element) in scene.elements.enumerated() where element.visibility == .visible {
      guard element.content.connector == nil else {
        visibleConnectorIndices.insert(index)
        continue
      }

      spatialIndex.update(
        entry: index,
        bounds: SceneRenderGeometry.paintedBounds(of: element)
      )
    }

    self.spatialIndex = spatialIndex
    self.visibleConnectorIndices = visibleConnectorIndices
  }

  /// Connectors remain candidates until P0.3 adds conservative route corridors.
  package func elements(
    intersecting bounds: SionRect,
    including includedIDs: Set<ElementID> = []
  ) -> SceneRenderQuery {
    let spatialQuery = spatialIndex.entries(intersecting: bounds)
    var indices = Set(spatialQuery.entries)
    indices.formUnion(visibleConnectorIndices)

    for id in includedIDs {
      guard let index = indicesByID[id] else { continue }

      indices.insert(index)
    }

    let elements = indices.sorted().compactMap { index -> SceneElement? in
      let element = scene.elements[index]
      return element.visibility == .visible ? element : nil
    }
    let forcedCount = indices.count - spatialQuery.entries.count

    return SceneRenderQuery(
      elements: elements,
      examinedElementCount: spatialQuery.examinedEntryCount + forcedCount
    )
  }

  /// Updates in-place gesture changes without rebuilding the scene-wide index.
  /// Structural commands must rebuild because element order is the z-order key.
  package mutating func update(
    scene updatedScene: SionScene,
    changedElementIDs: Set<ElementID>
  ) {
    guard updatedScene.elements.count == scene.elements.count else {
      rebuild(for: updatedScene)
      return
    }

    for id in changedElementIDs {
      guard let index = indicesByID[id], updatedScene.elements[index].id == id else {
        rebuild(for: updatedScene)
        return
      }
    }

    let previousScene = scene
    scene = updatedScene
    invalidateConnectorRoutes(previousScene: previousScene, changedElementIDs: changedElementIDs)

    for id in changedElementIDs {
      guard let index = indicesByID[id] else { continue }

      updateEntry(at: index)
    }
  }

  /// Drops only the cached routes the change can actually affect (chonk finding
  /// 24): a connector whose own element or either endpoint changed, or whose
  /// cached path crosses the corridor the changed elements moved through. Routes
  /// elsewhere in the scene stay cached instead of the whole map being wiped on
  /// every gesture sample.
  private mutating func invalidateConnectorRoutes(
    previousScene: SionScene,
    changedElementIDs: Set<ElementID>
  ) {
    guard !connectorRoutes.isEmpty, !changedElementIDs.isEmpty else { return }

    var corridor: SionRect?
    for id in changedElementIDs {
      guard let index = indicesByID[id] else { continue }
      guard index < previousScene.elements.count else { continue }
      guard previousScene.elements[index].id == id else { continue }
      guard index < scene.elements.count else { continue }

      let previous = SceneRenderGeometry.paintedBounds(of: previousScene.elements[index])
      let current = SceneRenderGeometry.paintedBounds(of: scene.elements[index])
      let change = previous.union(current)
      corridor = corridor.map { $0.union(change) } ?? change
    }
    guard let corridor else {
      connectorRoutes.removeAll(keepingCapacity: true)
      return
    }

    connectorRoutes = connectorRoutes.filter { id, cached in
      guard let index = indicesByID[id] else { return false }
      guard index < scene.elements.count else { return false }
      guard let connector = scene.elements[index].content.connector else { return false }
      if changedElementIDs.contains(id) { return false }

      let endpoints = [connector.source.elementID, connector.target.elementID]
      let endpointChanged = endpoints.contains { endpointID in
        endpointID.map(changedElementIDs.contains) ?? false
      }
      if endpointChanged { return false }

      guard let route = cached.route else { return true }
      return !route.polylineSegments.contains { segment in
        let bounds = SionRect(
          x: min(segment.start.x, segment.end.x),
          y: min(segment.start.y, segment.end.y),
          width: abs(segment.end.x - segment.start.x),
          height: abs(segment.end.y - segment.start.y)
        )
        return bounds.intersects(corridor)
      }
    }
  }

  package mutating func connectorRoute(for element: SceneElement) -> ConnectorRoute? {
    if let cached = connectorRoutes[element.id] {
      return cached.route
    }

    guard let index = indicesByID[element.id] else { return nil }

    let currentElement = scene.elements[index]
    guard currentElement.content.connector != nil else { return nil }

    let route = connectorRouteResolver(currentElement, scene)
    connectorRoutes[element.id] = route.map(CachedConnectorRoute.available) ?? .unavailable
    return route
  }

  private mutating func updateEntry(at index: Int) {
    let element = scene.elements[index]
    guard element.visibility == .visible else {
      visibleConnectorIndices.remove(index)
      spatialIndex.remove(entry: index)
      return
    }

    guard element.content.connector == nil else {
      visibleConnectorIndices.insert(index)
      spatialIndex.remove(entry: index)
      return
    }

    visibleConnectorIndices.remove(index)
    spatialIndex.update(
      entry: index,
      bounds: SceneRenderGeometry.paintedBounds(of: element)
    )
  }

  private mutating func rebuild(for scene: SionScene) {
    self = SceneRenderContext(
      scene: scene,
      connectorRouteResolver: connectorRouteResolver
    )
  }
}

private enum CachedConnectorRoute {
  case available(ConnectorRoute)
  case unavailable

  var route: ConnectorRoute? {
    guard case .available(let route) = self else { return nil }

    return route
  }
}

private struct SceneSpatialQuery {
  let entries: [Int]
  let examinedEntryCount: Int
}

private struct SceneSpatialIndex {
  private enum Metrics {
    static let cellLength = 512.0
    static let maximumCellsPerEntry = 64
    static let maximumCellsPerQuery = 4_096
  }

  private struct Cell: Hashable {
    let x: Int
    let y: Int
  }

  private enum Membership {
    case cells([Cell])
    case overflow
  }

  private var boundsByEntry: [Int: SionRect] = [:]
  private var membershipByEntry: [Int: Membership] = [:]
  private var entriesByCell: [Cell: Set<Int>] = [:]
  private var overflowEntries = Set<Int>()

  mutating func update(entry: Int, bounds: SionRect) {
    remove(entry: entry)
    boundsByEntry[entry] = bounds

    guard let cells = cells(for: bounds, limit: Metrics.maximumCellsPerEntry) else {
      membershipByEntry[entry] = .overflow
      overflowEntries.insert(entry)
      return
    }

    membershipByEntry[entry] = .cells(cells)
    for cell in cells {
      entriesByCell[cell, default: []].insert(entry)
    }
  }

  mutating func remove(entry: Int) {
    boundsByEntry[entry] = nil
    guard let membership = membershipByEntry.removeValue(forKey: entry) else { return }

    switch membership {
    case .overflow:
      overflowEntries.remove(entry)
    case .cells(let cells):
      for cell in cells {
        entriesByCell[cell]?.remove(entry)
        if entriesByCell[cell]?.isEmpty == true {
          entriesByCell[cell] = nil
        }
      }
    }
  }

  func entries(intersecting bounds: SionRect) -> SceneSpatialQuery {
    var candidates = overflowEntries

    if let cells = cells(for: bounds, limit: Metrics.maximumCellsPerQuery) {
      for cell in cells {
        candidates.formUnion(entriesByCell[cell] ?? [])
      }
    } else {
      candidates.formUnion(boundsByEntry.keys)
    }

    let entries = candidates.filter { entry in
      boundsByEntry[entry]?.intersects(bounds) == true
    }.sorted()

    return SceneSpatialQuery(
      entries: entries,
      examinedEntryCount: candidates.count
    )
  }

  private func cells(for bounds: SionRect, limit: Int) -> [Cell]? {
    let rect = bounds.standardized
    guard rect.isFinite,
      let minimumX = cellCoordinate(rect.minX),
      let maximumX = cellCoordinate(rect.maxX),
      let minimumY = cellCoordinate(rect.minY),
      let maximumY = cellCoordinate(rect.maxY)
    else {
      return nil
    }

    let (columnSpan, columnOverflow) = maximumX.subtractingReportingOverflow(minimumX)
    let (rowSpan, rowOverflow) = maximumY.subtractingReportingOverflow(minimumY)
    guard !columnOverflow,
      !rowOverflow,
      columnSpan < limit,
      rowSpan < limit
    else {
      return nil
    }

    let columnCount = columnSpan + 1
    let rowCount = rowSpan + 1
    guard rowCount <= limit / columnCount else {
      return nil
    }

    var cells: [Cell] = []
    cells.reserveCapacity(columnCount * rowCount)

    for y in minimumY...maximumY {
      for x in minimumX...maximumX {
        cells.append(Cell(x: x, y: y))
      }
    }

    return cells
  }

  private func cellCoordinate(_ value: Double) -> Int? {
    Int(exactly: floor(value / Metrics.cellLength))
  }
}
