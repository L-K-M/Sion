import CGtk
import Foundation
import SionCore
import SionKit

/// A stable, application-wide palette identity.
package enum SionGtkPaletteKind: String, CaseIterable, Sendable {
  case inspector
  case library
  case history

  package var title: String {
    switch self {
    case .inspector: "Inspector"
    case .library: "Library"
    case .history: "History"
    }
  }
}

/// What a palette targets: the front document window and its editor.
@MainActor
package protocol SionGtkPaletteHost: AnyObject {
  var paletteEditorController: SionEditorController { get }
  var canvasVisibleCenter: SionPoint { get }
  var toplevel: UnsafeMutablePointer<GtkWindow>? { get }
  func presentEditorFeedback(_ request: SionEditorFeedbackRequest)
  func beginTextEditing(_ id: ElementID)
}

/// Owns exactly one palette per kind across the application. Each palette
/// shows as a transient popover anchored to its toolbar button, or as a
/// floating window once detached, and retargets to the front document.
@MainActor
package final class SionGtkPaletteCenter {
  package static let shared = SionGtkPaletteCenter()

  /// Resolves the front document window whenever a palette needs its target.
  package var frontHost: @MainActor () -> SionGtkPaletteHost? = { nil }

  private init() {}

  /// Shows the palette attached to `anchor`, or raises its floating window.
  package func present(
    _ kind: SionGtkPaletteKind,
    relativeTo anchor: UnsafeMutablePointer<GtkWidget>?
  ) {}

  /// Call after the front document or its selection changes.
  package func frontDocumentDidChange() {}

  package func closeAll() {}
}
