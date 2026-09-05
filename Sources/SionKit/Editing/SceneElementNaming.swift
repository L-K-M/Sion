import SionCore

extension SceneElement {
  /// What to call an element that has no name of its own — in the inspector's
  /// selection line, and as the opening name of a stored library item.
  package var displayName: String {
    switch content {
    case .shape: "Shape"
    case .path: "Path"
    case .text: "Text"
    case .image: "Image"
    case .group: "Group"
    case .connector: "Connector"
    }
  }
}
