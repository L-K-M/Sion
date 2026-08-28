#if canImport(AppKit)
  import CoreGraphics
  import Foundation
  import ImageIO
  import SionCore
  import UniformTypeIdentifiers

  struct SafeImageRendition: Sendable {
    let data: Data
    let sourcePixelSize: SionSize
    let pixelSize: SionSize
  }

  /// Runs decoding off the main actor and cooperatively cancels between stages.
  /// An active ImageIO or Core Graphics call cannot be interrupted.
  struct SafeImageRenditionService: Sendable {
    typealias Build = @Sendable (Data) async -> SafeImageRendition?

    private let build: Build

    init() {
      build = { data in
        SafeImageRenditionBuilder.make(from: data)
      }
    }

    init(build: @escaping Build) {
      self.build = build
    }

    func make(from data: Data) async -> SafeImageRendition? {
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

  /// Downsamples imports through ImageIO before AppKit sees their pixels.
  /// Returns nil if the current task is cancelled between decoding stages.
  enum SafeImageRenditionBuilder {
    static func make(from data: Data) -> SafeImageRendition? {
      guard !Task.isCancelled,
        data.count <= SionArchiveConstants.maximumEntryByteCount
      else {
        return nil
      }

      if let source = CGImageSourceCreateWithData(
        data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ) {
        guard !Task.isCancelled else { return nil }

        return make(from: source)
      }

      guard !Task.isCancelled else { return nil }

      return makeFromPDF(data)
    }

    private static func make(from source: CGImageSource) -> SafeImageRendition? {
      guard CGImageSourceGetCount(source) > 0,
        let properties = CGImageSourceCopyPropertiesAtIndex(
          source,
          0,
          [kCGImageSourceShouldCache: false] as CFDictionary
        ) as? [CFString: Any],
        let width = dimension(properties[kCGImagePropertyPixelWidth]),
        let height = dimension(properties[kCGImagePropertyPixelHeight])
      else {
        return nil
      }

      let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
      let sourceSize = orientedSize(width: width, height: height, orientation: orientation)
      guard validSourceSize(sourceSize) else { return nil }

      let targetMaximumDimension = targetMaximumPixelDimension(for: sourceSize)
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: targetMaximumDimension,
      ]
      guard
        let image = CGImageSourceCreateThumbnailAtIndex(
          source,
          0,
          options as CFDictionary
        )
      else {
        return nil
      }

      guard !Task.isCancelled else { return nil }

      return rendition(from: image, sourceSize: sourceSize)
    }

    private static func makeFromPDF(_ data: Data) -> SafeImageRendition? {
      guard let provider = CGDataProvider(data: data as CFData),
        let document = CGPDFDocument(provider),
        let page = document.page(at: 1)
      else {
        return nil
      }

      let pageBounds = page.getBoxRect(.mediaBox).standardized
      let sourceSize = SionSize(width: pageBounds.width, height: pageBounds.height)
      guard validSourceSize(sourceSize) else { return nil }

      let maximumDimension = targetMaximumPixelDimension(for: sourceSize)
      let scale = min(
        1,
        Double(maximumDimension) / max(sourceSize.width, sourceSize.height)
      )
      let width = max(1, Int(floor(sourceSize.width * scale)))
      let height = max(1, Int(floor(sourceSize.height * scale)))
      guard let context = bitmapContext(width: width, height: height) else { return nil }

      context.setFillColor(CGColor(gray: 0, alpha: 0))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      let transform = page.getDrawingTransform(
        .mediaBox,
        rect: CGRect(x: 0, y: 0, width: width, height: height),
        rotate: 0,
        preserveAspectRatio: true
      )
      context.concatenate(transform)
      context.drawPDFPage(page)
      guard !Task.isCancelled, let image = context.makeImage() else { return nil }

      return rendition(from: image, sourceSize: sourceSize)
    }

    private static func rendition(
      from image: CGImage,
      sourceSize: SionSize
    ) -> SafeImageRendition? {
      let output = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          output,
          UTType.png.identifier as CFString,
          1,
          nil
        )
      else {
        return nil
      }

      CGImageDestinationAddImage(destination, image, nil)
      guard !Task.isCancelled, CGImageDestinationFinalize(destination) else { return nil }

      let data = output as Data
      guard data.count <= SionArchiveConstants.maximumEntryByteCount else { return nil }

      return SafeImageRendition(
        data: data,
        sourcePixelSize: sourceSize,
        pixelSize: SionSize(width: Double(image.width), height: Double(image.height))
      )
    }

    private static func dimension(_ value: Any?) -> Double? {
      guard let number = value as? NSNumber else { return nil }

      let value = number.doubleValue
      return value.isFinite && value > 0 ? value : nil
    }

    private static func orientedSize(
      width: Double,
      height: Double,
      orientation: Int
    ) -> SionSize {
      ImageOrientation.swappedDimensions.contains(orientation)
        ? SionSize(width: height, height: width)
        : SionSize(width: width, height: height)
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
        SionAsset.maximumSafeDisplayPixelDimension
        / max(sourceSize.width, sourceSize.height)
      let areaScale = sqrt(
        Double(SionAsset.maximumSafeDisplayPixelCount)
          / (sourceSize.width * sourceSize.height)
      )
      let scale = min(1, min(dimensionScale, areaScale))
      return max(1, Int(floor(max(sourceSize.width, sourceSize.height) * scale)))
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    }
  }

  private enum ImageImportLimits {
    static let maximumSourcePixelDimension = 65_536.0
    static let maximumSourcePixelCount = 100_000_000.0
  }

  private enum ImageOrientation {
    static let swappedDimensions: Set<Int> = [5, 6, 7, 8]
  }
#endif
