import CGtk
import CSionGtkShim
import Foundation
import SionCore

/// Renders scene content into export data. Raster output goes through a Cairo
/// image surface (PNG via Cairo, JPEG and TIFF via GdkPixbuf); PDF output
/// records the same drawing commands as vectors.
@MainActor
package enum SionGtkSceneImageExporter {
  package static func data(
    options: SionImageExportOptions,
    renderer: SionGtkSceneRenderer
  ) throws -> Data {
    try data(options: options, contentBounds: renderer.contentBounds, draw: renderer.sceneDrawing)
  }

  /// `renderScaleOverride` and `backdropOverride` serve the archive preview,
  /// which renders a bounded PNG onto the canvas colour.
  package static func data(
    options: SionImageExportOptions,
    contentBounds: SionRect,
    draw: SionGtkSceneDrawing,
    renderScaleOverride: Double? = nil,
    backdropOverride: SionExportBackdrop? = nil
  ) throws -> Data {
    let content = contentBounds.standardized
    guard content.isFinite, content.width > 0, content.height > 0 else {
      throw SionExportError.emptyContent
    }
    let backdrop = backdropOverride ?? options.backdrop

    switch options.format {
    case .pdf:
      return try pdfData(content: content, backdrop: backdrop, draw: draw)
    case .png, .jpeg, .tiff:
      let surface = try renderSurface(
        content: content,
        scale: renderScaleOverride ?? options.renderScale,
        backdrop: backdrop,
        draw: draw
      )
      defer { cairo_surface_destroy(surface) }
      return try encode(surface, as: options.format)
    }
  }

  /// Draws content into an ARGB32 surface whose pixels are the content
  /// bounds at `scale`, mapping the model's y-down space one to one.
  package static func renderSurface(
    content: SionRect,
    scale: Double,
    backdrop: SionExportBackdrop,
    draw: SionGtkSceneDrawing
  ) throws -> OpaquePointer {
    guard let pixelWidth = pixelCount(content.width * scale),
      let pixelHeight = pixelCount(content.height * scale),
      // Each edge can pass its own cap and still ask for a gigabyte.
      Double(pixelWidth) * Double(pixelHeight) <= Double(ExportMetrics.maximumPixelCount)
    else {
      throw SionExportError.dimensionsUnsupported
    }

    guard
      let surface = cairo_image_surface_create(
        CAIRO_FORMAT_ARGB32, Int32(pixelWidth), Int32(pixelHeight)),
      cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS,
      let context = cairo_create(surface)
    else {
      throw SionExportError.contextUnavailable
    }
    defer { cairo_destroy(context) }

    cairo_scale(context, scale, scale)
    cairo_translate(context, -content.minX, -content.minY)
    paintBackdrop(context, backdrop, in: content)
    draw(context, content, backdrop != .clear)
    cairo_surface_flush(surface)
    guard cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else {
      cairo_surface_destroy(surface)
      throw SionExportError.contextUnavailable
    }
    return surface
  }

  /// A PDF surface records the same drawing commands, so shapes and text stay
  /// resolution independent instead of wrapping a rasterized page.
  private static func pdfData(
    content: SionRect,
    backdrop: SionExportBackdrop,
    draw: SionGtkSceneDrawing
  ) throws -> Data {
    let sink = CairoDataSink()
    let surface = sink.withWriter { writer, closure in
      cairo_pdf_surface_create_for_stream(writer, closure, content.width, content.height)
    }
    guard let surface, cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS,
      let context = cairo_create(surface)
    else {
      throw SionExportError.contextUnavailable
    }

    cairo_translate(context, -content.minX, -content.minY)
    paintBackdrop(context, backdrop, in: content)
    draw(context, content, backdrop != .clear)
    cairo_show_page(context)
    cairo_destroy(context)
    cairo_surface_finish(surface)
    let status = cairo_surface_status(surface)
    cairo_surface_destroy(surface)
    guard status == CAIRO_STATUS_SUCCESS, !sink.data.isEmpty else {
      throw SionExportError.encodingFailed
    }
    return sink.data
  }

  private static func encode(_ surface: OpaquePointer, as format: SionImageExportFormat) throws
    -> Data
  {
    switch format {
    case .png, .pdf:
      return try pngData(surface)
    case .jpeg:
      return try pixbufData(surface, type: "jpeg", options: ["quality": "90"])
    case .tiff:
      return try pixbufData(surface, type: "tiff", options: [:])
    }
  }

  package static func pngData(_ surface: OpaquePointer) throws -> Data {
    let sink = CairoDataSink()
    let status = sink.withWriter { writer, closure in
      cairo_surface_write_to_png_stream(surface, writer, closure)
    }
    guard status == CAIRO_STATUS_SUCCESS, !sink.data.isEmpty else {
      throw SionExportError.encodingFailed
    }
    return sink.data
  }

  private static func pixbufData(
    _ surface: OpaquePointer, type: String, options: [String: String]
  ) throws -> Data {
    let width = cairo_image_surface_get_width(surface)
    let height = cairo_image_surface_get_height(surface)
    guard let pixbuf = gdk_pixbuf_get_from_surface(surface, 0, 0, width, height) else {
      throw SionExportError.encodingFailed
    }
    defer { g_object_unref(pixbuf.gobject) }

    var buffer: UnsafeMutablePointer<gchar>?
    var size: gsize = 0
    let keys = options.keys.sorted()
    var cKeys: [UnsafeMutablePointer<CChar>?] = keys.map { strdup($0) } + [nil]
    var cValues: [UnsafeMutablePointer<CChar>?] = keys.map { strdup(options[$0]!) } + [nil]
    defer {
      for pointer in cKeys + cValues {
        free(pointer)
      }
    }
    let saved = try GLibError.check { error in
      cKeys.withUnsafeMutableBufferPointer { keyBuffer in
        cValues.withUnsafeMutableBufferPointer { valueBuffer in
          gdk_pixbuf_save_to_bufferv(
            pixbuf, &buffer, &size, type, keyBuffer.baseAddress, valueBuffer.baseAddress, error)
        }
      }
    }
    guard saved != 0, let buffer, size > 0 else {
      throw SionExportError.encodingFailed
    }
    defer { g_free(buffer) }
    return Data(bytes: buffer, count: Int(size))
  }

  private static func paintBackdrop(
    _ context: OpaquePointer, _ backdrop: SionExportBackdrop, in content: SionRect
  ) {
    guard backdrop == .opaqueCanvas else { return }

    cairo_set_source_rgb(context, 1, 1, 1)
    cairo_rectangle(context, content.minX, content.minY, content.width, content.height)
    cairo_fill(context)
  }

  /// Bounds a requested pixel count so an oversized drawing fails cleanly
  /// instead of trapping on the conversion or exhausting memory.
  private static func pixelCount(_ value: Double) -> Int? {
    let rounded = value.rounded()
    guard rounded.isFinite, rounded <= Double(ExportMetrics.maximumPixelDimension) else {
      return nil
    }

    return max(1, Int(rounded))
  }

  private enum ExportMetrics {
    static let maximumPixelDimension = 16_384
    /// 16384 x 8192 at four bytes a pixel is already half a gigabyte, and PNG
    /// encoding needs its own buffer on top.
    static let maximumPixelCount = 134_217_728
  }
}

/// Collects the bytes a Cairo stream surface writes.
final class CairoDataSink {
  private(set) var data = Data()

  func withWriter<Result>(
    _ body: (cairo_write_func_t, UnsafeMutableRawPointer) -> Result
  ) -> Result {
    let writer: cairo_write_func_t = { closure, bytes, length in
      guard let closure, let bytes else { return CAIRO_STATUS_WRITE_ERROR }
      let sink = Unmanaged<CairoDataSink>.fromOpaque(closure).takeUnretainedValue()
      sink.data.append(bytes, count: Int(length))
      return CAIRO_STATUS_SUCCESS
    }
    return body(writer, Unmanaged.passUnretained(self).toOpaque())
  }
}
