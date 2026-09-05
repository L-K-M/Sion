import CGtk
import Foundation
import SionCore
import SionKit

/// Draws visible scene content into a Cairo context the caller has already
/// mapped to the model's y-down space.
package typealias SionGtkSceneDrawing =
  @MainActor (_ context: OpaquePointer, _ bounds: SionRect, _ fillsBackground: Bool) -> Void

/// Owns an unparented canvas so a document can render its scene without a
/// window; drawing itself stays in the canvas. Mirrors `SionSceneRenderer`.
@MainActor
package final class SionGtkSceneRenderer {
  package let editorController: SionEditorController

  private var canvasStorage: SionGtkCanvasView?

  package init(editorController: SionEditorController) {
    self.editorController = editorController
  }

  /// The drawing's bounds, not the scrolled viewport.
  package var contentBounds: SionRect {
    editorController.contentBounds()
  }

  /// A drawing seam bound to this renderer's canvas; the canvas is captured so
  /// a print operation outlives the renderer that produced the seam.
  package var sceneDrawing: SionGtkSceneDrawing {
    let sceneCanvas = canvas
    return { context, bounds, fillsBackground in
      sceneCanvas.drawSceneContent(context, in: bounds, fillsBackground: fillsBackground)
    }
  }

  package func invalidate() {
    canvasStorage?.invalidate()
    canvasStorage = nil
  }

  private var canvas: SionGtkCanvasView {
    if let canvasStorage {
      return canvasStorage
    }

    let canvas = SionGtkCanvasView(editorController: editorController, editorFeedback: { _ in })
    canvasStorage = canvas
    return canvas
  }
}
