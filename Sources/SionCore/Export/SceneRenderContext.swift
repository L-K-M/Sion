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

    scene = updatedScene
    connectorRoutes.removeAll(keepingCapacity: true)

    for id in changedElementIDs {
      guard let index = indicesByID[id] else { continue }

      updateEntry(at: index)
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
