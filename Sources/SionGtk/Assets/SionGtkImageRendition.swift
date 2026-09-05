import CGtk
import CPoppler
import CSionGtkShim
import Foundation
import SionCore

package struct SafeImageRendition: Sendable {
  package let data: Data
  package let sourcePixelSize: SionSize
  package let pixelSize: SionSize

  package init(data: Data, sourcePixelSize: SionSize, pixelSize: SionSize) {
    self.data = data
    self.sourcePixelSize = sourcePixelSize
    self.pixelSize = pixelSize
  }
}

/// Downsamples imports before the canvas sees their pixels: bitmaps and SVG
/// through GdkPixbuf (which decodes straight to the bounded size), PDF through
/// poppler. Returns nil for anything it will not import or if the current
/// task is cancelled between decoding stages.
package enum SafeImageRenditionBuilder {
  package static func make(from data: Data) -> SafeImageRendition? {
    guard !Task.isCancelled, data.count <= SionArchiveConstants.maximumEntryByteCount else {
      return nil
    }

    if let rendition = makeWithPixbuf(data) {
      return rendition
    }

    guard !Task.isCancelled else { return nil }

    return makeFromPDF(data)
  }

  private static func makeWithPixbuf(_ data: Data) -> SafeImageRendition? {
    guard let loader = gdk_pixbuf_loader_new() else { return nil }
    defer { g_object_unref(loader.gobject) }

    // The loader reports the source size before decoding pixels, which is
    // where the thumbnail-style downsampling is requested.
    let sizing = SizingBox()
    let trampoline: @convention(c) (gpointer?, gint, gint, gpointer?) -> Void = {
      loader, width, height, data in
      guard let data, let loader else { return }
      let box = Unmanaged<SizingBox>.fromOpaque(data).takeUnretainedValue()
      let source = SionSize(width: Double(width), height: Double(height))
      box.sourceSize = source
      guard SafeImageRenditionBuilder.validSourceSize(source) else {
        box.rejected = true
        return
      }
      let target = SafeImageRenditionBuilder.targetMaximumPixelDimension(for: source)
      let scale = min(1, Double(target) / max(source.width, source.height))
      gdk_pixbuf_loader_set_size(
        loader.cast(),
        max(1, Int32((source.width * scale).rounded(.down))),
        max(1, Int32((source.height * scale).rounded(.down))))
    }
    _ = sion_signal_connect(
      loader.gobject, "size-prepared", unsafeBitCast(trampoline, to: GCallback.self),
      Unmanaged.passUnretained(sizing).toOpaque(), nil, 0)

    let written = data.withUnsafeBytes { buffer -> Bool in
      guard let base = buffer.baseAddress else { return false }
      return gdk_pixbuf_loader_write(
        loader, base.assumingMemoryBound(to: guchar.self), gsize(buffer.count), nil) != 0
    }
    let closed = gdk_pixbuf_loader_close(loader, nil) != 0
    guard written, closed, !sizing.rejected, !Task.isCancelled,
      let loaded = gdk_pixbuf_loader_get_pixbuf(loader)
    else {
      return nil
    }

    // EXIF orientation is applied the way ImageIO's thumbnail transform does.
    guard let oriented = gdk_pixbuf_apply_embedded_orientation(loaded) else { return nil }
    defer { g_object_unref(oriented.gobject) }
    var sourceSize = sizing.sourceSize
    if gdk_pixbuf_get_width(oriented) != gdk_pixbuf_get_width(loaded) {
      sourceSize = SionSize(width: sourceSize.height, height: sourceSize.width)
    }
    guard validSourceSize(sourceSize) else { return nil }

    return rendition(from: oriented, sourceSize: sourceSize)
  }

  private final class SizingBox: @unchecked Sendable {
    var sourceSize = SionSize(width: 0, height: 0)
    var rejected = false
  }

  private static func makeFromPDF(_ data: Data) -> SafeImageRendition? {
    let bytes = data.withUnsafeBytes { buffer in
      g_bytes_new(buffer.baseAddress, gsize(buffer.count))
    }
    defer { g_bytes_unref(bytes) }
    guard let document = poppler_document_new_from_bytes(bytes, nil, nil),
      poppler_document_get_n_pages(document) > 0,
      let page = poppler_document_get_page(document, 0)
    else {
      return nil
    }
    defer {
      g_object_unref(page.gobject)
      g_object_unref(document.gobject)
    }

    var pageWidth = 0.0
    var pageHeight = 0.0
    poppler_page_get_size(page, &pageWidth, &pageHeight)
    let sourceSize = SionSize(width: pageWidth, height: pageHeight)
    guard validSourceSize(sourceSize) else { return nil }

    let maximumDimension = targetMaximumPixelDimension(for: sourceSize)
    let scale = min(1, Double(maximumDimension) / max(sourceSize.width, sourceSize.height))
    let width = max(1, Int32((sourceSize.width * scale).rounded(.down)))
    let height = max(1, Int32((sourceSize.height * scale).rounded(.down)))
    guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height),
      let context = cairo_create(surface)
    else {
      return nil
    }
    defer {
      cairo_destroy(context)
      cairo_surface_destroy(surface)
    }
    cairo_scale(context, Double(width) / sourceSize.width, Double(height) / sourceSize.height)
    poppler_page_render(page, context)
    cairo_surface_flush(surface)
    guard !Task.isCancelled, let png = try? pngData(surface) else { return nil }
    guard png.count <= SionArchiveConstants.maximumEntryByteCount else { return nil }

    return SafeImageRendition(
      data: png,
      sourcePixelSize: sourceSize,
      pixelSize: SionSize(width: Double(width), height: Double(height))
    )
  }

  private static func rendition(from pixbuf: OpaquePointer, sourceSize: SionSize)
    -> SafeImageRendition?
  {
    var buffer: UnsafeMutablePointer<gchar>?
    var size: gsize = 0
    var noKeys: [UnsafeMutablePointer<CChar>?] = [nil]
    var noValues: [UnsafeMutablePointer<CChar>?] = [nil]
    let saved = noKeys.withUnsafeMutableBufferPointer { keys in
      noValues.withUnsafeMutableBufferPointer { values in
        gdk_pixbuf_save_to_bufferv(
          pixbuf, &buffer, &size, "png", keys.baseAddress, values.baseAddress, nil)
      }
    }
    guard saved != 0, let buffer, size > 0, !Task.isCancelled else { return nil }
    defer { g_free(buffer) }
    let data = Data(bytes: buffer, count: Int(size))
    guard data.count <= SionArchiveConstants.maximumEntryByteCount else { return nil }

    return SafeImageRendition(
      data: data,
      sourcePixelSize: sourceSize,
      pixelSize: SionSize(
        width: Double(gdk_pixbuf_get_width(pixbuf)), height: Double(gdk_pixbuf_get_height(pixbuf)))
    )
  }

  /// PNG bytes from a Cairo image surface, off the main actor.
  private static func pngData(_ surface: OpaquePointer) throws -> Data {
    let sink = CairoDataSink()
    let status = sink.withWriter { writer, closure in
      cairo_surface_write_to_png_stream(surface, writer, closure)
    }
    guard status == CAIRO_STATUS_SUCCESS, !sink.data.isEmpty else {
      throw SionExportError.encodingFailed
    }
    return sink.data
  }

  private static func validSourceSize(_ size: SionSize) -> Bool {
    size.isFinite
      && size.width > 0
      && size.height > 0
      && size.width <= ImageImportLimits.maximumSourcePixelDimension
      && size.height <= ImageImportLimits.maximumSourcePixelDimension
      && size.width * size.height <= ImageImportLimits.maximumSourcePixelCount
  }

  private static func targetMaximumPixelDimension(for sourceSize: SionSize) -> Int {
    let dimensionScale =
      SionAsset.maximumSafeDisplayPixelDimension / max(sourceSize.width, sourceSize.height)
    let areaScale = sqrt(
      Double(SionAsset.maximumSafeDisplayPixelCount) / (sourceSize.width * sourceSize.height))
    let scale = min(1, min(dimensionScale, areaScale))
    return max(1, Int((max(sourceSize.width, sourceSize.height) * scale).rounded(.down)))
  }

  private enum ImageImportLimits {
    static let maximumSourcePixelDimension = 65_536.0
    static let maximumSourcePixelCount = 100_000_000.0
  }
}

/// Runs decoding off the main actor and cooperatively cancels between stages.
package struct SafeImageRenditionService: Sendable {
  package typealias Build = @Sendable (Data) async -> SafeImageRendition?

  private let build: Build

  package init() {
    build = { data in
      SafeImageRenditionBuilder.make(from: data)
    }
  }

  package init(build: @escaping Build) {
    self.build = build
  }

  package func make(from data: Data) async -> SafeImageRendition? {
    guard !Task.isCancelled else { return nil }

    let task = Task.detached(priority: .userInitiated) {
      await build(data)
    }
    let rendition = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    guard !Task.isCancelled else { return nil }

    return rendition
  }
}
