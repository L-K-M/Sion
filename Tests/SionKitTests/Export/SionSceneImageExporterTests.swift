import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionSceneImageExporterTests: XCTestCase {
  private let content = SionRect(x: 10, y: 20, width: 120, height: 80)

  func testFormatsDeclareTheirExtensionsAndCapabilities() {
    XCTAssertEqual(
      SionImageExportFormat.allCases.map(\.fileExtension),
      ["png", "jpg", "tiff", "pdf"]
    )
    XCTAssertFalse(SionImageExportFormat.jpeg.supportsTransparency)
    XCTAssertTrue(SionImageExportFormat.png.supportsTransparency)
    XCTAssertFalse(SionImageExportFormat.pdf.supportsScale)
    XCTAssertTrue(SionImageExportFormat.tiff.supportsScale)
  }

  func testPopupOrderMatchesTheRawValuesTheAccessoryViewSelectsBy() {
    // The accessory view maps a popup index straight onto a raw value, so a
    // reorder here would silently export the wrong format or scale.
    XCTAssertEqual(SionImageExportFormat.allCases.map(\.rawValue), Array(0..<4))
    XCTAssertEqual(SionImageExportScale.allCases.map(\.rawValue), Array(0..<3))
  }

  func testAnAreaBeyondTheBudgetIsRejectedEvenWhenEachEdgeFits() {
    var options = SionImageExportOptions()
    options.scale = .threeX

    // Each edge stays under the per-edge cap; together they do not.
    XCTAssertThrowsError(
      try SionSceneImageExporter.data(
        options: options,
        contentBounds: SionRect(x: 0, y: 0, width: 5000, height: 4000),
        draw: { _, _ in }
      )
    ) { error in
      XCTAssertEqual(error as? SionExportError, .dimensionsUnsupported)
    }
  }

  func testTransparencyAndScaleOptionsResolvePerFormat() {
    var options = SionImageExportOptions()
    options.hasTransparentBackground = true

    XCTAssertEqual(options.backdrop, .clear)

    options.format = .jpeg

    // JPEG has no alpha, so a transparent request still renders opaque paper.
    XCTAssertEqual(options.backdrop, .opaqueCanvas)

    options.format = .pdf
    options.scale = .threeX

    XCTAssertEqual(options.renderScale, 1)

    options.format = .png

    XCTAssertEqual(options.renderScale, 3)
  }

  func testScaleDrivesExactPixelDimensions() throws {
    for scale in SionImageExportScale.allCases {
      var options = SionImageExportOptions()
      options.scale = scale
      let data = try SionSceneImageExporter.data(
        options: options,
        contentBounds: content,
        draw: fillDrawing(.red)
      )
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))

      XCTAssertEqual(bitmap.pixelsWide, Int(content.width * scale.factor))
      XCTAssertEqual(bitmap.pixelsHigh, Int(content.height * scale.factor))
    }
  }

  func testTransparentPNGKeepsAnEmptyCornerClearWhileOpaqueDoesNot() throws {
    var transparent = SionImageExportOptions()
    transparent.hasTransparentBackground = true
    let clearData = try SionSceneImageExporter.data(
      options: transparent,
      contentBounds: content,
      draw: { _, _ in }
    )
    let opaqueData = try SionSceneImageExporter.data(
      options: SionImageExportOptions(),
      contentBounds: content,
      draw: { _, _ in }
    )

    let clearBitmap = try XCTUnwrap(NSBitmapImageRep(data: clearData))
    let opaqueBitmap = try XCTUnwrap(NSBitmapImageRep(data: opaqueData))

    XCTAssertEqual(try XCTUnwrap(clearBitmap.colorAt(x: 0, y: 0)).alphaComponent, 0)
    XCTAssertEqual(try XCTUnwrap(opaqueBitmap.colorAt(x: 0, y: 0)).alphaComponent, 1)
  }

  func testJPEGAndTIFFEncodeTheirOwnContainers() throws {
    var jpeg = SionImageExportOptions()
    jpeg.format = .jpeg
    var tiff = SionImageExportOptions()
    tiff.format = .tiff

    let jpegData = try SionSceneImageExporter.data(
      options: jpeg,
      contentBounds: content,
      draw: fillDrawing(.red)
    )
    let tiffData = try SionSceneImageExporter.data(
      options: tiff,
      contentBounds: content,
      draw: fillDrawing(.red)
    )

    XCTAssertEqual(Array(jpegData.prefix(3)), [0xFF, 0xD8, 0xFF])
    XCTAssertTrue(
      Array(tiffData.prefix(2)) == [0x49, 0x49] || Array(tiffData.prefix(2)) == [0x4D, 0x4D]
    )
  }

  func testPDFExportIsASingleVectorPageSizedInPoints() throws {
    var options = SionImageExportOptions()
    options.format = .pdf
    options.scale = .threeX

    let data = try SionSceneImageExporter.data(
      options: options,
      contentBounds: content,
      draw: fillDrawing(.red)
    )
    let document = try XCTUnwrap(PDFDocumentFixture(data: data))

    XCTAssertEqual(Array(data.prefix(4)), Array("%PDF".utf8))
    XCTAssertEqual(document.pageCount, 1)
    // The scale factor is a raster concern; the page stays in document points.
    XCTAssertEqual(document.mediaBox.width, CGFloat(content.width), accuracy: 0.5)
    XCTAssertEqual(document.mediaBox.height, CGFloat(content.height), accuracy: 0.5)
  }

  func testEmptyContentIsRejected() {
    XCTAssertThrowsError(
      try SionSceneImageExporter.data(
        options: SionImageExportOptions(),
        contentBounds: SionRect(x: 0, y: 0, width: 0, height: 40),
        draw: { _, _ in }
      )
    ) { error in
      XCTAssertEqual(error as? SionExportError, .emptyContent)
    }
  }

  func testRenderingRestoresTheCurrentGraphicsContext() throws {
    let previousContext = NSGraphicsContext.current
    defer { NSGraphicsContext.current = previousContext }

    _ = try SionSceneImageExporter.data(
      options: SionImageExportOptions(),
      contentBounds: content,
      draw: fillDrawing(.red)
    )

    XCTAssertTrue(NSGraphicsContext.current === previousContext)
  }

  private func fillDrawing(_ color: NSColor) -> SionSceneDrawing {
    { bounds, _ in
      color.setFill()
      NSBezierPath(
        rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
      ).fill()
    }
  }
}

/// Reads only what the export tests assert, so PDFKit stays out of the target.
private struct PDFDocumentFixture {
  let pageCount: Int
  let mediaBox: CGRect

  init?(data: Data) {
    guard let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider),
      let page = document.page(at: 1)
    else {
      return nil
    }

    pageCount = document.numberOfPages
    mediaBox = page.getBoxRect(.mediaBox)
  }
}
