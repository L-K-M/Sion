import CGtk
import Foundation
import SionCore
import SionKit
import XCTest

@testable import SionGtk

@MainActor
final class SionGtkCanvasRenderingTests: XCTestCase {
  func testSceneContentPaintsFillInsideAndNothingOutside() throws {
    try GtkTestSupport.requireDisplay()
    let canvas = try CanvasFixture.makeCanvas(elements: [
      CanvasFixture.rectangle(x: 100, y: 100)
    ])
    let bounds = SionRect(x: 0, y: 0, width: 400, height: 300)

    let inside = try CanvasFixture.renderedPixel(
      canvas, at: SionPoint(x: 180, y: 148), bounds: bounds)
    let outside = try CanvasFixture.renderedPixel(
      canvas, at: SionPoint(x: 20, y: 20), bounds: bounds)

    XCTAssertEqual(inside.alpha, 255)
    XCTAssertGreaterThan(inside.blue, inside.red)
    XCTAssertEqual(outside.alpha, 0)
  }

  func testFilledBackgroundUsesTheCanvasColour() throws {
    try GtkTestSupport.requireDisplay()
    let canvas = try CanvasFixture.makeCanvas(elements: [])
    let bounds = SionRect(x: 0, y: 0, width: 100, height: 100)

    let pixel = try CanvasFixture.renderedPixel(
      canvas, at: SionPoint(x: 50, y: 50), bounds: bounds, backdrop: .canvas)

    XCTAssertEqual(pixel.alpha, 255)
  }

  func testPreviewPNGIsBoundedAndDecodable() throws {
    try GtkTestSupport.requireDisplay()
    let canvas = try CanvasFixture.makeCanvas(elements: [
      CanvasFixture.rectangle(x: 0, y: 0, width: 3_000, height: 1_500)
    ])

    let png = try XCTUnwrap(canvas.renderPreviewPNG())
    let pixbuf = try XCTUnwrap(SionGtkPixbuf.load(png))
    defer { g_object_unref(pixbuf.gobject) }

    XCTAssertLessThanOrEqual(
      Int(gdk_pixbuf_get_width(pixbuf)), Int(PreviewMetrics.maximumDimension))
    XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
  }

  func testHiddenElementsAreNotPainted() throws {
    try GtkTestSupport.requireDisplay()
    var hidden = CanvasFixture.rectangle(x: 100, y: 100)
    hidden.visibility = .hidden
    let canvas = try CanvasFixture.makeCanvas(elements: [hidden])
    let bounds = SionRect(x: 0, y: 0, width: 400, height: 300)

    let pixel = try CanvasFixture.renderedPixel(
      canvas, at: SionPoint(x: 180, y: 148), bounds: bounds)

    XCTAssertEqual(pixel.alpha, 0)
  }

  func testTextRenderCacheEvictsPartially() throws {
    try GtkTestSupport.requireDisplay()
    let canvas = try CanvasFixture.makeCanvas(elements: [])
    guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 10, 10),
      let context = cairo_create(surface)
    else {
      return XCTFail("no surface")
    }
    defer {
      cairo_destroy(context)
      cairo_surface_destroy(surface)
    }

    for index in 0...CanvasMetrics.textRenderCacheLimit {
      let content = TextContent(string: "Item \(index)", style: .standaloneDefault)
      _ = canvas.cachedTextRender(for: content, width: 200, context: context)
    }

    XCTAssertLessThan(canvas.textRenderCache.count, CanvasMetrics.textRenderCacheLimit + 1)
    XCTAssertGreaterThan(canvas.textRenderCache.count, CanvasMetrics.textRenderCacheLimit / 2)
  }

  func testExporterProducesPDFAndJPEGAndTIFF() throws {
    try GtkTestSupport.requireDisplay()
    let canvas = try CanvasFixture.makeCanvas(elements: [
      CanvasFixture.rectangle(x: 10, y: 10)
    ])
    let renderer = SionGtkSceneRenderer(editorController: canvas.editorController)

    let pdf = try SionGtkSceneImageExporter.data(
      options: SionImageExportOptions(format: .pdf), renderer: renderer)
    let jpeg = try SionGtkSceneImageExporter.data(
      options: SionImageExportOptions(format: .jpeg, scale: .twoX), renderer: renderer)
    let tiff = try SionGtkSceneImageExporter.data(
      options: SionImageExportOptions(format: .tiff, hasTransparentBackground: true),
      renderer: renderer)

    XCTAssertEqual(String(decoding: pdf.prefix(4), as: UTF8.self), "%PDF")
    XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
    XCTAssertTrue(tiff.starts(with: [0x49, 0x49]) || tiff.starts(with: [0x4D, 0x4D]))
  }

  func testExporterRejectsEmptyAndOversizedContent() throws {
    try GtkTestSupport.requireDisplay()
    let empty = try CanvasFixture.makeCanvas(elements: [])
    XCTAssertThrowsError(
      try SionGtkSceneImageExporter.data(
        options: SionImageExportOptions(), contentBounds: .zero,
        draw: { context, bounds, fills in
          empty.drawSceneContent(context, in: bounds, fillsBackground: fills)
        })
    ) { error in
      XCTAssertEqual(error as? SionExportError, .emptyContent)
    }

    let huge = try CanvasFixture.makeCanvas(elements: [
      CanvasFixture.rectangle(x: 0, y: 0, width: 20_000, height: 100)
    ])
    XCTAssertThrowsError(
      try SionGtkSceneImageExporter.data(
        options: SionImageExportOptions(format: .png, scale: .threeX),
        renderer: SionGtkSceneRenderer(editorController: huge.editorController))
    ) { error in
      XCTAssertEqual(error as? SionExportError, .dimensionsUnsupported)
    }
  }

  func testRenditionBuilderDownsamplesPNGAndKeepsSourceSize() throws {
    guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 64, 32),
      let context = cairo_create(surface)
    else {
      return XCTFail("no surface")
    }
    cairo_set_source_rgb(context, 1, 0, 0)
    cairo_paint(context)
    cairo_destroy(context)
    let png = try SionGtkSceneImageExporter.pngData(surface)
    cairo_surface_destroy(surface)

    let rendition = try XCTUnwrap(SafeImageRenditionBuilder.make(from: png))

    XCTAssertEqual(rendition.sourcePixelSize, SionSize(width: 64, height: 32))
    XCTAssertEqual(rendition.pixelSize, SionSize(width: 64, height: 32))
    XCTAssertEqual(Array(rendition.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    XCTAssertNil(SafeImageRenditionBuilder.make(from: Data("not an image".utf8)))
  }

  func testRenditionBuilderRendersPDFPages() throws {
    let sink = CairoDataSink()
    let surface = sink.withWriter { writer, closure in
      cairo_pdf_surface_create_for_stream(writer, closure, 200, 100)
    }
    let context = cairo_create(surface)
    cairo_set_source_rgb(context, 0, 0, 1)
    cairo_rectangle(context, 0, 0, 200, 100)
    cairo_fill(context)
    cairo_show_page(context)
    cairo_destroy(context)
    cairo_surface_finish(surface)
    cairo_surface_destroy(surface)

    let rendition = try XCTUnwrap(SafeImageRenditionBuilder.make(from: sink.data))

    XCTAssertEqual(rendition.sourcePixelSize, SionSize(width: 200, height: 100))
    XCTAssertEqual(rendition.pixelSize, SionSize(width: 200, height: 100))
  }

  func testPrintPlacementFitsAndCentres() {
    let placement = SionGtkPrintOperation.fittedPlacement(
      content: SionRect(x: 0, y: 0, width: 400, height: 200),
      pageSize: SionSize(width: 500, height: 500))

    XCTAssertEqual(placement?.scale, 1.25)
    XCTAssertEqual(placement?.origin, SionPoint(x: 0, y: 125))
    XCTAssertNil(
      SionGtkPrintOperation.fittedPlacement(
        content: .zero, pageSize: SionSize(width: 10, height: 10)))
  }
}
