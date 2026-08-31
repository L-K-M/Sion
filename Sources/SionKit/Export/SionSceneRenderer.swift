#if canImport(AppKit)
  import AppKit
  import SionCore

  /// Draws visible scene content into the current graphics context, which the
  /// caller has already mapped to the model's y-down space.
  typealias SionSceneDrawing = @MainActor (_ bounds: SionRect, _ fillsBackground: Bool) -> Void

  /// Owns an unparented canvas so a document can render its scene without a
  /// window. Drawing itself stays in the canvas; this type only manages the
  /// canvas's lifetime and hands out the drawing seam.
  @MainActor
  final class SionSceneRenderer {
    private let editorController: SionEditorController
    private var canvasStorage: SionCanvasView?

    init(editorController: SionEditorController) {
      self.editorController = editorController
    }

    /// The drawing's bounds, not the scrolled viewport.
    var contentBounds: SionRect {
      editorController.contentBounds()
    }

    /// A drawing seam bound to this renderer's canvas. The canvas is captured
    /// so a print operation outlives the renderer that produced the seam.
    var sceneDrawing: SionSceneDrawing {
      let sceneCanvas = canvas
      return { bounds, fillsBackground in
        sceneCanvas.drawSceneContent(in: bounds, fillsBackground: fillsBackground)
      }
    }

    /// Releases the canvas's observer registration on the editor controller.
    func invalidate() {
      canvasStorage?.invalidate()
      canvasStorage = nil
    }

    private var canvas: SionCanvasView {
      if let canvasStorage {
        return canvasStorage
      }

      let canvas = SionCanvasView(editorController: editorController)
      canvasStorage = canvas
      return canvas
    }
  }
#endif
