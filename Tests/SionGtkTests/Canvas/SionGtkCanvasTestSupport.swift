import CGtk
import Foundation
import SionCore
import SionKit
import XCTest

@testable import SionGtk

/// Builds controllers and canvases over small scenes for the canvas tests.
@MainActor
enum CanvasFixture {
  static func rectangle(
    x: Double, y: Double, width: Double = 160, height: Double = 96,
    fill: SionColor = SionColor(red: 0.2, green: 0.4, blue: 0.9), label: String? = nil
  ) -> SceneElement {
    var element = SceneElement.shape(
      frame: SionRect(x: x, y: y, width: width, height: height),
      kind: .roundedRectangle(radius: 8)
    )
    element.content = .shape(
      ShapeContent(
        kind: .roundedRectangle(radius: 8),
        label: label.map { TextContent(string: $0, style: .shapeLabelDefault) }))
    element.style = ElementStyle(
      fill: .solid(fill), stroke: StrokeStyle(color: .primaryInk, width: 1.5))
    return element
  }

  static func makeController(elements: [SceneElement]) throws -> SionEditorController {
    try makeController(elements: elements, undoManager: SionUndoManager())
  }

  static func makeController(
    elements: [SceneElement], undoManager: SionUndoManager
  ) throws -> SionEditorController {
    let document = SionDocument(scene: SionScene(elements: elements))
    let package = SionPackage(document: document)
    return try SionEditorController(
      package: package,
      undoManagerProvider: { undoManager },
      didChange: { _ in }
    )
  }

  static func makeCanvas(elements: [SceneElement]) throws -> SionGtkCanvasView {
    try makeCanvas(elements: elements, undoManager: SionUndoManager())
  }

  static func makeCanvas(
    elements: [SceneElement], undoManager: SionUndoManager
  ) throws -> SionGtkCanvasView {
    let controller = try makeController(elements: elements, undoManager: undoManager)
    return SionGtkCanvasView(
      editorController: controller, creationFailureFeedback: {}, editorFeedback: { _ in })
  }

  /// Renders the scene content into an ARGB32 surface and reads back a pixel.
  static func renderedPixel(
    _ canvas: SionGtkCanvasView, at point: SionPoint, bounds: SionRect,
    backdrop: SionExportBackdrop = .clear
  ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    let surface = try SionGtkSceneImageExporter.renderSurface(
      content: bounds, scale: 1, backdrop: backdrop,
      draw: { context, bounds, fills in
        canvas.drawSceneContent(context, in: bounds, fillsBackground: fills)
      })
    defer { cairo_surface_destroy(surface) }
    cairo_surface_flush(surface)
    let stride = Int(cairo_image_surface_get_stride(surface))
    let data = cairo_image_surface_get_data(surface)!
    let x = Int(point.x - bounds.minX)
    let y = Int(point.y - bounds.minY)
    let pixel = data.advanced(by: y * stride + x * 4)
    // Cairo ARGB32 is premultiplied, native-endian: B, G, R, A on little-endian.
    return (pixel[2], pixel[1], pixel[0], pixel[3])
  }
}
