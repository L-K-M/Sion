import Foundation

/// Memoizes routed connector paths between scene edits.
///
/// Interactive layers ask for every connector's route on every frame, and
/// routing runs a visibility-grid search over all obstacles in the scene.
/// Redraws that leave the scene untouched — selection changes, zooming,
/// scrolling — replay the cached routes; every edit must call `invalidate()`.
public struct SceneRouteCache: Sendable {
  private var routes: [ElementID: ConnectorRoute?] = [:]

  public init() {}

  /// Drops every cached route. Required after any scene mutation: a route
  /// depends on all obstacles, not only on its own connector element.
  public mutating func invalidate() {
    routes.removeAll(keepingCapacity: true)
  }

  public mutating func route(
    for element: SceneElement,
    in scene: SionScene
  ) -> ConnectorRoute? {
    if let cached = routes[element.id] {
      return cached
    }

    let route = SceneRenderGeometry.connectorRoute(for: element, in: scene)
    routes[element.id] = route
    return route
  }
}
