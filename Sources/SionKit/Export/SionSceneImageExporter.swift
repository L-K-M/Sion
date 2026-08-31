#if canImport(AppKit)
  import AppKit
  import SionCore
  import UniformTypeIdentifiers

  /// The image formats "Export Image…" writes.
  enum SionImageExportFormat: Int, CaseIterable {
    case png
    case jpeg
    case tiff
    case pdf

    var title: String {
      switch self {
      case .png: "PNG"
      case .jpeg: "JPEG"
      case .tiff: "TIFF"
      case .pdf: "PDF"
      }
    }

    var fileExtension: String {
      switch self {
      case .png: "png"
      case .jpeg: "jpg"
      case .tiff: "tiff"
      case .pdf: "pdf"
      }
    }

    var contentType: UTType {
      switch self {
      case .png: .png
      case .jpeg: .jpeg
      case .tiff: .tiff
      case .pdf: .pdf
      }
    }

    /// JPEG has no alpha channel, so its background is always opaque.
    var supportsTransparency: Bool {
      self != .jpeg
    }

    /// PDF output is vector, so a pixel scale factor does not apply.
    var supportsScale: Bool {
      self != .pdf
    }
  }

  /// Pixel scale for raster output.
  enum SionImageExportScale: Int, CaseIterable {
    case oneX
    case twoX
    case threeX

    var title: String {
      switch self {
      case .oneX: "1x"
      case .twoX: "2x"
      case .threeX: "3x"
      }
    }

    var factor: Double {
      switch self {
      case .oneX: 1
      case .twoX: 2
      case .threeX: 3
      }
    }
  }

  /// What is painted under the drawing before its elements.
  enum SionExportBackdrop: Equatable {
    /// Nothing, so the exported image keeps a transparent background.
    case clear
    /// The scene's own canvas color, which may itself be translucent.
    case canvas
    /// Opaque white beneath the scene's canvas color.
    case opaqueCanvas
  }

  struct SionImageExportOptions: Equatable {
    var format = SionImageExportFormat.png
    var scale = SionImageExportScale.oneX
    var hasTransparentBackground = false

    /// A format without an alpha channel always renders onto opaque paper.
    var backdrop: SionExportBackdrop {
      guard format.supportsTransparency, hasTransparentBackground else {
        return .opaqueCanvas
      }

      return .clear
    }

    /// Vector output ignores the pixel scale factor.
    var renderScale: Double {
      format.supportsScale ? scale.factor : 1
    }
  }

  enum SionExportError: LocalizedError, Equatable {
    case emptyContent
    case dimensionsUnsupported
    case contextUnavailable
    case encodingFailed

    var errorDescription: String? {
      switch self {
      case .emptyContent: "This drawing has no content to export."
      case .dimensionsUnsupported: "The drawing is too large to export at this scale."
      case .contextUnavailable: "The image could not be prepared for export."
      case .encodingFailed: "The image could not be encoded."
      }
    }
  }

  /// Renders scene content into export data. Raster output reuses the archive
  /// preview's context math; PDF output stays vector.
  @MainActor
  enum SionSceneImageExporter {
    static func data(
      options: SionImageExportOptions,
      renderer: SionSceneRenderer
    ) throws -> Data {
      try data(
        options: options,
        contentBounds: renderer.contentBounds,
        draw: renderer.sceneDrawing
      )
    }

    static func data(
      options: SionImageExportOptions,
      contentBounds: SionRect,
      draw: SionSceneDrawing
    ) throws -> Data {
      let content = contentBounds.standardized
      guard content.isFinite, content.width > 0, content.height > 0 else {
        throw SionExportError.emptyContent
      }

      switch options.format {
      case .pdf:
        return try pdfData(content: content, backdrop: options.backdrop, draw: draw)
      case .png, .jpeg, .tiff:
        let rendered = try renderBitmap(
          content: content,
          scale: options.renderScale,
          backdrop: options.backdrop,
          draw: draw
        )
        return try encode(rendered, as: options.format)
      }
    }

    /// Draws content into an sRGB bitmap. The explicit flipped context keeps
    /// text upright without inheriting a display's backing scale.
    static func renderBitmap(
      content: SionRect,
      scale: Double,
      backdrop: SionExportBackdrop,
      draw: SionSceneDrawing
    ) throws -> NSBitmapImageRep {
      guard let pixelWidth = pixelCount(content.width * scale),
        let pixelHeight = pixelCount(content.height * scale),
        // Each edge can pass its own cap and still ask for a gigabyte.
        Double(pixelWidth) * Double(pixelHeight) <= Double(ExportMetrics.maximumPixelCount)
      else {
        throw SionExportError.dimensionsUnsupported
      }

      guard
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: pixelWidth,
          pixelsHigh: pixelHeight,
          bitsPerSample: ExportMetrics.bitsPerSample,
          samplesPerPixel: ExportMetrics.samplesPerPixel,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .calibratedRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ),
        let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap)
      else {
        throw SionExportError.contextUnavailable
      }

      let previousContext = NSGraphicsContext.current
      defer { NSGraphicsContext.current = previousContext }

      // Map the y-down model into the bitmap's y-up pixel coordinates.
      let cgContext = bitmapContext.cgContext
      cgContext.translateBy(x: 0, y: CGFloat(pixelHeight))
      cgContext.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
      cgContext.translateBy(x: CGFloat(-content.minX), y: CGFloat(-content.minY))
      let drawingContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
      NSGraphicsContext.current = drawingContext

      paintBackdrop(backdrop, in: content)
      draw(content, backdrop != .clear)
      drawingContext.flushGraphics()

      return bitmap.converting(
        to: NSColorSpace.sRGB,
        renderingIntent: NSColorRenderingIntent.default
      ) ?? bitmap
    }

    /// A PDF context records the same drawing commands, so shapes and text stay
    /// resolution independent instead of wrapping a rasterized page.
    private static func pdfData(
      content: SionRect,
      backdrop: SionExportBackdrop,
      draw: SionSceneDrawing
    ) throws -> Data {
      let page = exportRect(content)
      let pageData = NSMutableData()
      var mediaBox = CGRect(origin: .zero, size: page.size)
      guard let consumer = CGDataConsumer(data: pageData),
        let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
      else {
        throw SionExportError.contextUnavailable
      }

      let previousContext = NSGraphicsContext.current
      defer { NSGraphicsContext.current = previousContext }

      cgContext.beginPDFPage(nil)
      // Map the y-down model into the page's y-up points.
      cgContext.translateBy(x: 0, y: page.height)
      cgContext.scaleBy(x: 1, y: -1)
      cgContext.translateBy(x: -page.minX, y: -page.minY)
      let drawingContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
      NSGraphicsContext.current = drawingContext

      paintBackdrop(backdrop, in: content)
      draw(content, backdrop != .clear)
      drawingContext.flushGraphics()
      cgContext.endPDFPage()
      cgContext.closePDF()

      guard pageData.length > 0 else {
        throw SionExportError.encodingFailed
      }

      return pageData as Data
    }

    private static func encode(
      _ bitmap: NSBitmapImageRep,
      as format: SionImageExportFormat
    ) throws -> Data {
      let fileType: NSBitmapImageRep.FileType
      let properties: [NSBitmapImageRep.PropertyKey: Any]
      switch format {
      case .jpeg:
        fileType = .jpeg
        properties = [.compressionFactor: ExportMetrics.jpegCompressionFactor]
      case .tiff:
        fileType = .tiff
        properties = [:]
      case .png, .pdf:
        fileType = .png
        properties = [:]
      }

      guard let data = bitmap.representation(using: fileType, properties: properties) else {
        throw SionExportError.encodingFailed
      }

      return data
    }

    private static func paintBackdrop(_ backdrop: SionExportBackdrop, in content: SionRect) {
      guard backdrop == .opaqueCanvas else { return }

      NSColor.white.setFill()
      NSBezierPath(rect: exportRect(content)).fill()
    }

    /// Bounds a requested pixel count so an oversized drawing fails cleanly
    /// instead of trapping on the conversion or exhausting memory.
    private static func pixelCount(_ value: Double) -> Int? {
      let rounded = value.rounded()
      guard rounded.isFinite,
        rounded <= Double(ExportMetrics.maximumPixelDimension)
      else {
        return nil
      }

      return max(1, Int(rounded))
    }
  }

  private func exportRect(_ rect: SionRect) -> NSRect {
    let standardized = rect.standardized
    return NSRect(
      x: standardized.minX,
      y: standardized.minY,
      width: standardized.width,
      height: standardized.height
    )
  }

  private enum ExportMetrics {
    static let bitsPerSample = 8
    static let samplesPerPixel = 4
    static let jpegCompressionFactor = 0.9
    static let maximumPixelDimension = 16_384
    /// 16384 x 8192 at four bytes a pixel is already half a gigabyte, and PNG
    /// encoding needs its own buffer on top.
    static let maximumPixelCount = 134_217_728
  }
#endif
