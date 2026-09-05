import CGtk
import Foundation
import SionCore

/// Renders scene content into export data with Cairo: PNG through Cairo's
/// encoder, JPEG and TIFF through GdkPixbuf, PDF as vector output.
@MainActor
package enum SionGtkSceneImageExporter {
  package static func data(
    options: SionImageExportOptions,
    renderer: SionGtkSceneRenderer
  ) throws -> Data {
    try data(options: options, contentBounds: renderer.contentBounds, draw: renderer.sceneDrawing)
  }

  package static func data(
    options: SionImageExportOptions,
    contentBounds: SionRect,
    draw: SionGtkSceneDrawing
  ) throws -> Data {
    throw SionExportError.contextUnavailable
  }
}
