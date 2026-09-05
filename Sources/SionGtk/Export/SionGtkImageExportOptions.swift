import Foundation

/// The image formats "Export Image…" writes.
package enum SionImageExportFormat: Int, CaseIterable, Sendable {
  case png
  case jpeg
  case tiff
  case pdf

  package var title: String {
    switch self {
    case .png: "PNG"
    case .jpeg: "JPEG"
    case .tiff: "TIFF"
    case .pdf: "PDF"
    }
  }

  package var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .tiff: "tiff"
    case .pdf: "pdf"
    }
  }

  package var mimeType: String {
    switch self {
    case .png: "image/png"
    case .jpeg: "image/jpeg"
    case .tiff: "image/tiff"
    case .pdf: "application/pdf"
    }
  }

  /// JPEG has no alpha channel, so its background is always opaque.
  package var supportsTransparency: Bool {
    self != .jpeg
  }

  /// PDF output is vector, so a pixel scale factor does not apply.
  package var supportsScale: Bool {
    self != .pdf
  }
}

/// Pixel scale for raster output.
package enum SionImageExportScale: Int, CaseIterable, Sendable {
  case oneX
  case twoX
  case threeX

  package var title: String {
    switch self {
    case .oneX: "1x"
    case .twoX: "2x"
    case .threeX: "3x"
    }
  }

  package var factor: Double {
    switch self {
    case .oneX: 1
    case .twoX: 2
    case .threeX: 3
    }
  }
}

/// What is painted under the drawing before its elements.
package enum SionExportBackdrop: Equatable, Sendable {
  /// Nothing, so the exported image keeps a transparent background.
  case clear
  /// The scene's own canvas color, which may itself be translucent.
  case canvas
  /// Opaque white beneath the scene's canvas color.
  case opaqueCanvas
}

package struct SionImageExportOptions: Equatable, Sendable {
  package var format = SionImageExportFormat.png
  package var scale = SionImageExportScale.oneX
  package var hasTransparentBackground = false

  package init(
    format: SionImageExportFormat = .png,
    scale: SionImageExportScale = .oneX,
    hasTransparentBackground: Bool = false
  ) {
    self.format = format
    self.scale = scale
    self.hasTransparentBackground = hasTransparentBackground
  }

  /// A format without an alpha channel always renders onto opaque paper.
  package var backdrop: SionExportBackdrop {
    guard format.supportsTransparency, hasTransparentBackground else {
      return .opaqueCanvas
    }

    return .clear
  }

  /// Vector output ignores the pixel scale factor.
  package var renderScale: Double {
    format.supportsScale ? scale.factor : 1
  }
}

package enum SionExportError: LocalizedError, Equatable {
  case emptyContent
  case dimensionsUnsupported
  case contextUnavailable
  case encodingFailed

  package var errorDescription: String? {
    switch self {
    case .emptyContent: "This drawing has no content to export."
    case .dimensionsUnsupported: "The drawing is too large to export at this scale."
    case .contextUnavailable: "The image could not be prepared for export."
    case .encodingFailed: "The image could not be encoded."
    }
  }
}
