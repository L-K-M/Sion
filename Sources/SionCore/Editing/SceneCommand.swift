import Foundation

public enum SceneCommand: Equatable, Sendable {
  /// Recovery replaces locked content as one validated, undoable intent.
  case replaceScene(SionScene)
  case insert(elements: [SceneElement], at: Int?)
  case remove(elementIDs: Set<ElementID>)
  case replace(elements: [SceneElement])
  case translate(elementIDs: Set<ElementID>, by: SionVector)
  /// The destination is measured after the selected elements are removed.
  case reorder(elementIDs: [ElementID], destinationIndex: Int)
  case setFrame(elementID: ElementID, frame: SionRect)
  case setParent(elementID: ElementID, parentID: ElementID?)
  case setText(elementID: ElementID, text: String)
  case setStyle(elementID: ElementID, style: ElementStyle)
  case setMagnetConfiguration(elementID: ElementID, configuration: MagnetConfiguration)
  case setConnectorRouting(
    elementID: ElementID,
    style: ConnectorRoutingStyle,
    manualRoute: ManualConnectorRoute?
  )
  case setConnectorResolvedRoute(elementID: ElementID, route: ConnectorRoute?)
  case setVisibility(elementID: ElementID, visibility: ElementVisibility)
  case setLockState(elementID: ElementID, lockState: ElementLockState)
  case rename(elementID: ElementID, name: String?)
  case setCanvas(SionCanvas)
}

public struct SceneTransaction: Equatable, Sendable {
  public var name: String
  public var commands: [SceneCommand]

  public init(name: String, commands: [SceneCommand]) {
    self.name = name
    self.commands = commands
  }

  public init(name: String, command: SceneCommand) {
    self.init(name: name, commands: [command])
  }
}

extension SceneCommand {
  func apply(to scene: inout SionScene) throws {
    switch self {
    case .replaceScene(let replacement):
      scene = replacement
    case .insert(let elements, let index):
      try insert(elements, at: index, into: &scene)
    case .remove(let elementIDs):
      try remove(elementIDs, from: &scene)
    case .replace(let elements):
      try replace(elements, in: &scene)
    case .translate(let elementIDs, let offset):
      try translate(elementIDs, by: offset, in: &scene)
    case .reorder(let elementIDs, let destinationIndex):
      try reorder(elementIDs, to: destinationIndex, in: &scene)
    case .setFrame(let elementID, let frame):
      let element = try editableElement(elementID, in: scene)
      let previousFrame = element.geometry.frame
      try updateEditableElement(elementID, in: &scene) { element in
        element.geometry.frame = frame
      }
      let offset = frame.origin - previousFrame.origin
      adjustAttachedConnectors(
        to: [elementID],
        by: offset,
        excluding: [],
        in: &scene
      )

      if element.content.connector == nil, frame != previousFrame {
        invalidateResolvedConnectorRoutes(in: &scene)
      }
    case .setParent(let elementID, let parentID):
      try updateEditableElement(elementID, in: &scene) { element in
        element.parentID = parentID
      }
    case .setText(let elementID, let text):
      try setText(text, on: elementID, in: &scene)
    case .setStyle(let elementID, let style):
      try updateEditableElement(elementID, in: &scene) { element in
        element.style = style
      }
    case .setMagnetConfiguration(let elementID, let configuration):
      try updateEditableElement(elementID, in: &scene) { element in
        element.magnetConfiguration = configuration
      }
      invalidateAttachedConnectorRoutes(to: [elementID], in: &scene)
    case .setConnectorRouting(let elementID, let style, let manualRoute):
      try setConnectorRouting(
        style,
        manualRoute: manualRoute,
        on: elementID,
        in: &scene
      )
    case .setConnectorResolvedRoute(let elementID, let route):
      try setConnectorResolvedRoute(route, on: elementID, in: &scene)
    case .setVisibility(let elementID, let visibility):
      let element = try editableElement(elementID, in: scene)
      try updateEditableElement(elementID, in: &scene) { element in
        element.visibility = visibility
      }

      if element.content.connector == nil, visibility != element.visibility {
        invalidateResolvedConnectorRoutes(in: &scene)
      }
    case .setLockState(let elementID, let lockState):
      try updateElement(elementID, in: &scene) { element in
        element.lockState = lockState
      }
    case .rename(let elementID, let name):
      try updateEditableElement(elementID, in: &scene) { element in
        element.name = name
      }
    case .setCanvas(let canvas):
      scene.canvas = canvas
    }
  }

  private func insert(
    _ insertedElements: [SceneElement],
    at requestedIndex: Int?,
    into scene: inout SionScene
  ) throws {
    let existingIDs = Set(scene.elements.map(\.id))
    var insertedIDs = Set<ElementID>()

    for element in insertedElements {
      guard !existingIDs.contains(element.id), insertedIDs.insert(element.id).inserted else {
        throw SceneEditingError.duplicateElementID(element.id)
      }
    }

    let index = requestedIndex ?? scene.elements.endIndex
    guard scene.elements.indices.contains(index) || index == scene.elements.endIndex else {
      throw SceneEditingError.invalidDestinationIndex(index)
    }

    scene.elements.insert(contentsOf: insertedElements, at: index)

    if insertedElements.contains(where: { $0.content.connector == nil }) {
      invalidateResolvedConnectorRoutes(in: &scene)
    }
  }

  private func remove(_ requestedIDs: Set<ElementID>, from scene: inout SionScene) throws {
    try requireElements(requestedIDs, in: scene)

    let removesObstacle = scene.elements.contains { element in
      requestedIDs.contains(element.id) && element.content.connector == nil
    }

    var removedIDs = requestedIDs
    removedIDs.formUnion(descendants(of: requestedIDs, in: scene))

    for element in scene.elements where removedIDs.contains(element.id) {
      guard element.lockState == .editable else {
        throw SceneEditingError.elementLocked(element.id)
      }
    }

    // Connections are owned by their endpoints and leave with either endpoint.
    for element in scene.elements {
      guard let connector = element.content.connector else {
        continue
      }

      let endpointIDs = [connector.source.elementID, connector.target.elementID]
      if endpointIDs.contains(where: { $0.map(removedIDs.contains) ?? false }) {
        removedIDs.insert(element.id)
      }
    }

    scene.elements.removeAll { removedIDs.contains($0.id) }

    if removesObstacle {
      invalidateResolvedConnectorRoutes(in: &scene)
    }
  }

  private func replace(_ replacements: [SceneElement], in scene: inout SionScene) throws {
    var replacementIDs = Set<ElementID>()
    var changesObstacle = false

    for replacement in replacements {
      guard replacementIDs.insert(replacement.id).inserted else {
        throw SceneEditingError.duplicateElementID(replacement.id)
      }

      guard let index = scene.index(of: replacement.id) else {
        throw SceneEditingError.elementNotFound(replacement.id)
      }

      guard scene.elements[index].lockState == .editable else {
        throw SceneEditingError.elementLocked(replacement.id)
      }

      let existing = scene.elements[index]
      let replacesObstacle =
        existing.content.connector == nil
        || replacement.content.connector == nil
      changesObstacle = changesObstacle || (replacesObstacle && existing != replacement)
      scene.elements[index] = replacement
    }

    if changesObstacle {
      invalidateResolvedConnectorRoutes(in: &scene)
    }
  }

  private func translate(
    _ requestedIDs: Set<ElementID>,
    by offset: SionVector,
    in scene: inout SionScene
  ) throws {
    try requireElements(requestedIDs, in: scene)

    // In a validated scene only groups own children, so one descendant walk
    // over every requested ID replaces a per-group traversal.
    var translatedIDs = requestedIDs
    translatedIDs.formUnion(descendants(of: requestedIDs, in: scene))

    // Validate the full move before mutating any element.
    for element in scene.elements where translatedIDs.contains(element.id) {
      guard element.lockState == .editable else {
        throw SceneEditingError.elementLocked(element.id)
      }
    }

    for index in scene.elements.indices {
      guard translatedIDs.contains(scene.elements[index].id) else { continue }

      try updateEditableElement(at: index, in: &scene) { element in
        element.geometry.frame.origin = translated(element.geometry.frame.origin, by: offset)
        element.content = translatedConnectorContent(
          element.content,
          by: offset,
          movedElementIDs: translatedIDs
        )
      }
    }

    adjustAttachedConnectors(
      to: translatedIDs,
      by: offset,
      excluding: translatedIDs,
      in: &scene
    )

    let movesObstacle =
      offset != .zero
      && scene.elements.contains { element in
        translatedIDs.contains(element.id) && element.content.connector == nil
      }
    if movesObstacle {
      invalidateResolvedConnectorRoutes(in: &scene)
    }
  }

  private func reorder(
    _ requestedIDs: [ElementID],
    to destinationIndex: Int,
    in scene: inout SionScene
  ) throws {
    let requestedIDSet = Set(requestedIDs)
    guard requestedIDSet.count == requestedIDs.count else {
      throw SceneEditingError.duplicateReorderID
    }

    try requireElements(requestedIDSet, in: scene)

    let indicesByID = self.indicesByID(in: scene)
    let movedElements = try requestedIDs.map { id -> SceneElement in
      guard let index = indicesByID[id] else {
        throw SceneEditingError.elementNotFound(id)
      }

      let element = scene.elements[index]

      guard element.lockState == .editable else {
        throw SceneEditingError.elementLocked(id)
      }

      return element
    }

    let retainedElements = scene.elements.filter { !requestedIDSet.contains($0.id) }
    guard
      retainedElements.indices.contains(destinationIndex)
        || destinationIndex == retainedElements.endIndex
    else {
      throw SceneEditingError.invalidDestinationIndex(destinationIndex)
    }

    var reorderedElements = retainedElements
    reorderedElements.insert(contentsOf: movedElements, at: destinationIndex)
    scene.elements = reorderedElements
  }

  private func setText(
    _ text: String,
    on elementID: ElementID,
    in scene: inout SionScene
  ) throws {
    try updateEditableElement(elementID, in: &scene) { element in
      switch element.content {
      case .shape(var shape):
        let style = shape.label?.style ?? .shapeLabelDefault
        shape.label = TextContent(string: text, style: style)
        element.content = .shape(shape)
      case .text(var content):
        content.string = text
        element.content = .text(content)
      case .connector(var connector):
        let style = connector.label?.style ?? .shapeLabelDefault
        connector.label = TextContent(string: text, style: style)
        element.content = .connector(connector)
      case .path, .image, .group:
        throw SceneEditingError.elementDoesNotContainText(elementID)
      }
    }
  }

  private func setConnectorRouting(
    _ style: ConnectorRoutingStyle,
    manualRoute: ManualConnectorRoute?,
    on elementID: ElementID,
    in scene: inout SionScene
  ) throws {
    try updateEditableElement(elementID, in: &scene) { element in
      guard var connector = element.content.connector else {
        throw SceneEditingError.elementIsNotConnector(elementID)
      }

      connector.routingStyle = style
      connector.manualRoute = manualRoute
      connector.resolvedRoute = nil
      element.content = .connector(connector)
    }
  }

  private func setConnectorResolvedRoute(
    _ route: ConnectorRoute?,
    on elementID: ElementID,
    in scene: inout SionScene
  ) throws {
    try updateElement(elementID, in: &scene) { element in
      guard var connector = element.content.connector else {
        throw SceneEditingError.elementIsNotConnector(elementID)
      }

      connector.resolvedRoute = route
      element.content = .connector(connector)
    }
  }

  private func requireElements(_ ids: Set<ElementID>, in scene: SionScene) throws {
    let existingIDs = Set(scene.elements.map(\.id))
    let missingIDs = ids.subtracting(existingIDs).sorted { $0.description < $1.description }

    if let firstMissing = missingIDs.first {
      throw SceneEditingError.elementNotFound(firstMissing)
    }
  }

  private func editableElement(_ id: ElementID, in scene: SionScene) throws -> SceneElement {
    guard let element = scene.element(withID: id) else {
      throw SceneEditingError.elementNotFound(id)
    }

    guard element.lockState == .editable else {
      throw SceneEditingError.elementLocked(id)
    }

    return element
  }

  private func updateEditableElement(
    _ id: ElementID,
    in scene: inout SionScene,
    update: (inout SceneElement) throws -> Void
  ) throws {
    guard let index = scene.index(of: id) else {
      throw SceneEditingError.elementNotFound(id)
    }

    try updateEditableElement(at: index, in: &scene, update: update)
  }

  /// Indices stay valid while a command mutates elements only in place.
  private func updateEditableElement(
    at index: Int,
    in scene: inout SionScene,
    update: (inout SceneElement) throws -> Void
  ) throws {
    try updateElement(at: index, in: &scene) { element in
      guard element.lockState == .editable else {
        throw SceneEditingError.elementLocked(element.id)
      }

      try update(&element)
    }
  }

  private func updateElement(
    _ id: ElementID,
    in scene: inout SionScene,
    update: (inout SceneElement) throws -> Void
  ) throws {
    guard let index = scene.index(of: id) else {
      throw SceneEditingError.elementNotFound(id)
    }

    try updateElement(at: index, in: &scene, update: update)
  }

  private func updateElement(
    at index: Int,
    in scene: inout SionScene,
    update: (inout SceneElement) throws -> Void
  ) throws {
    try update(&scene.elements[index])
  }

  private func indicesByID(in scene: SionScene) -> [ElementID: Int] {
    var indices: [ElementID: Int] = [:]
    indices.reserveCapacity(scene.elements.count)

    for (index, element) in scene.elements.enumerated() {
      indices[element.id] = index
    }

    return indices
  }

  /// One adjacency pass collects descendants of every requested root.
  private func descendants(of requestedIDs: Set<ElementID>, in scene: SionScene) -> Set<ElementID> {
    var childrenByParent: [ElementID: [ElementID]] = [:]
    for element in scene.elements {
      guard let parentID = element.parentID else { continue }

      childrenByParent[parentID, default: []].append(element.id)
    }

    var descendants = Set<ElementID>()
    var pending = Array(requestedIDs)

    // The insert guard also terminates walks through mid-transaction cycles.
    while let candidate = pending.popLast() {
      for child in childrenByParent[candidate] ?? [] {
        guard descendants.insert(child).inserted else { continue }

        pending.append(child)
      }
    }

    return descendants
  }

  private func translated(_ point: SionPoint, by offset: SionVector) -> SionPoint {
    SionPoint(x: point.x + offset.dx, y: point.y + offset.dy)
  }

  private func translatedConnectorContent(
    _ content: ElementContent,
    by offset: SionVector,
    movedElementIDs: Set<ElementID>
  ) -> ElementContent {
    guard var connector = content.connector else {
      return content
    }

    connector.source = translated(
      connector.source,
      by: offset,
      movedElementIDs: movedElementIDs
    )
    connector.target = translated(
      connector.target,
      by: offset,
      movedElementIDs: movedElementIDs
    )

    switch connector.manualRoute {
    case .orthogonal(let waypoints):
      connector.manualRoute = .orthogonal(
        waypoints: waypoints.map { translated($0, by: offset) }
      )
    case .curved(let controlPoint):
      connector.manualRoute = .curved(
        controlPoint: translated(controlPoint, by: offset)
      )
    case .bezier(let sourceControl, let targetControl):
      connector.manualRoute = .bezier(
        sourceControl: translated(sourceControl, by: offset),
        targetControl: translated(targetControl, by: offset)
      )
    case nil:
      break
    }

    connector.resolvedRoute = nil

    return .connector(connector)
  }

  private func translated(
    _ endpoint: ConnectionEndpoint,
    by offset: SionVector,
    movedElementIDs: Set<ElementID>
  ) -> ConnectionEndpoint {
    switch endpoint {
    case .element(let elementID, let attachment, let fallbackPoint):
      guard movedElementIDs.contains(elementID) else {
        return endpoint
      }

      return .element(
        elementID,
        attachment: attachment,
        fallbackPoint: translated(fallbackPoint, by: offset)
      )
    case .free(let point):
      return .free(translated(point, by: offset))
    }
  }

  private func adjustAttachedConnectors(
    to movedElementIDs: Set<ElementID>,
    by offset: SionVector,
    excluding excludedConnectorIDs: Set<ElementID>,
    in scene: inout SionScene
  ) {
    for index in scene.elements.indices {
      guard !excludedConnectorIDs.contains(scene.elements[index].id),
        var connector = scene.elements[index].content.connector
      else {
        continue
      }

      let sourceMoved = connector.source.elementID.map(movedElementIDs.contains) ?? false
      let targetMoved = connector.target.elementID.map(movedElementIDs.contains) ?? false
      guard sourceMoved || targetMoved else {
        continue
      }

      connector.source = translatedAttachedEndpoint(
        connector.source,
        by: sourceMoved ? offset : .zero
      )
      connector.target = translatedAttachedEndpoint(
        connector.target,
        by: targetMoved ? offset : .zero
      )
      connector.manualRoute = adjustedManualRoute(
        connector.manualRoute,
        sourceMovement: sourceMoved ? .moved : .stationary,
        targetMovement: targetMoved ? .moved : .stationary,
        offset: offset
      )
      connector.resolvedRoute = nil
      scene.elements[index].content = .connector(connector)
    }
  }

  private func invalidateAttachedConnectorRoutes(
    to elementIDs: Set<ElementID>,
    in scene: inout SionScene
  ) {
    for index in scene.elements.indices {
      guard var connector = scene.elements[index].content.connector else {
        continue
      }

      let endpointIDs = [connector.source.elementID, connector.target.elementID]
      guard endpointIDs.contains(where: { $0.map(elementIDs.contains) ?? false }) else {
        continue
      }

      connector.resolvedRoute = nil
      scene.elements[index].content = .connector(connector)
    }
  }

  /// Obstacle changes affect every cached automatic path, attached or not.
  private func invalidateResolvedConnectorRoutes(in scene: inout SionScene) {
    for index in scene.elements.indices {
      guard var connector = scene.elements[index].content.connector else {
        continue
      }

      connector.resolvedRoute = nil
      scene.elements[index].content = .connector(connector)
    }
  }

  private func translatedAttachedEndpoint(
    _ endpoint: ConnectionEndpoint,
    by offset: SionVector
  ) -> ConnectionEndpoint {
    guard offset != .zero else {
      return endpoint
    }

    switch endpoint {
    case .element(let elementID, let attachment, let fallbackPoint):
      return .element(
        elementID,
        attachment: attachment,
        fallbackPoint: translated(fallbackPoint, by: offset)
      )
    case .free:
      return endpoint
    }
  }

  private func adjustedManualRoute(
    _ route: ManualConnectorRoute?,
    sourceMovement: EndpointMovement,
    targetMovement: EndpointMovement,
    offset: SionVector
  ) -> ManualConnectorRoute? {
    guard let route, offset != .zero else {
      return route
    }

    let sourceMoved = sourceMovement == .moved
    let targetMoved = targetMovement == .moved

    if sourceMoved && targetMoved {
      return translated(route, by: offset)
    }

    switch route {
    case .orthogonal(var waypoints):
      if sourceMoved, !waypoints.isEmpty {
        waypoints[waypoints.startIndex] = translated(waypoints[waypoints.startIndex], by: offset)
      }
      if targetMoved, !waypoints.isEmpty {
        let lastIndex = waypoints.index(before: waypoints.endIndex)
        waypoints[lastIndex] = translated(waypoints[lastIndex], by: offset)
      }
      return .orthogonal(waypoints: waypoints)
    case .curved(let controlPoint):
      let fraction = ConnectorEditingDefaults.singleEndpointControlMovement
      return .curved(controlPoint: translated(controlPoint, by: offset * fraction))
    case .bezier(let sourceControl, let targetControl):
      return .bezier(
        sourceControl: sourceMoved
          ? translated(sourceControl, by: offset)
          : sourceControl,
        targetControl: targetMoved
          ? translated(targetControl, by: offset)
          : targetControl
      )
    }
  }

  private func translated(
    _ route: ManualConnectorRoute,
    by offset: SionVector
  ) -> ManualConnectorRoute {
    switch route {
    case .orthogonal(let waypoints):
      return .orthogonal(waypoints: waypoints.map { translated($0, by: offset) })
    case .curved(let controlPoint):
      return .curved(controlPoint: translated(controlPoint, by: offset))
    case .bezier(let sourceControl, let targetControl):
      return .bezier(
        sourceControl: translated(sourceControl, by: offset),
        targetControl: translated(targetControl, by: offset)
      )
    }
  }
}

public enum SceneEditingError: Error, Equatable, Sendable {
  case elementNotFound(ElementID)
  case duplicateElementID(ElementID)
  case elementLocked(ElementID)
  case elementDoesNotContainText(ElementID)
  case elementIsNotConnector(ElementID)
  case invalidDestinationIndex(Int)
  case duplicateReorderID
  case invalidHistoryLimit(Int)
  case gestureAlreadyActive
  case noActiveGesture
  case commandDuringGesture
}

private enum ConnectorEditingDefaults {
  static let singleEndpointControlMovement = 0.5
}

private enum EndpointMovement {
  case stationary
  case moved
}
