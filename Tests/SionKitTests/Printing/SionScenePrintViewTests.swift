import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionScenePrintViewTests: XCTestCase {
  func testPrintableSizeSubtractsMarginsAndFallsBackToPaper() {
    let paper = NSSize(width: 612, height: 792)
    let margins = NSEdgeInsets(top: 36, left: 24, bottom: 36, right: 24)

    XCTAssertEqual(
      SionScenePrintView.printableSize(paperSize: paper, margins: margins),
      NSSize(width: 564, height: 720)
    )
    XCTAssertEqual(
      SionScenePrintView.printableSize(
        paperSize: paper,
        margins: NSEdgeInsets(top: 500, left: 400, bottom: 500, right: 400)
      ),
      paper
    )
  }

  func testPrintViewReportsExactlyOnePage() {
    let view = makeView()
    var range = NSRange(location: 0, length: 0)

    XCTAssertTrue(view.knowsPageRange(&range))
    XCTAssertEqual(range, NSRange(location: 1, length: 1))
    XCTAssertEqual(view.rectForPage(1), view.bounds)
  }

  func testPrintViewScalesContentToFitAndCentersIt() throws {
    let view = makeView()
    let bitmap = try render(view)

    // Content 100x50 on a 200x200 page fits at 2x, so the drawing spans the
    // full width and leaves an empty 50pt band above and below it.
    let centre = try XCTUnwrap(bitmap.colorAt(x: 100, y: 100))
    XCTAssertEqual(centre.alphaComponent, 1)
    XCTAssertEqual(centre.redComponent, 1, accuracy: 0.02)
    XCTAssertEqual(centre.greenComponent, 0, accuracy: 0.02)
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 4, y: 100)).alphaComponent, 1)
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 196, y: 100)).alphaComponent, 1)
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 100, y: 10)).alphaComponent, 0)
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 100, y: 190)).alphaComponent, 0)
  }

  func testPrintViewLeavesTheCanvasBackdropOffThePage() throws {
    let view = SionScenePrintView(
      contentBounds: SionRect(x: 40, y: 60, width: 100, height: 50),
      pageSize: NSSize(width: 200, height: 200),
      drawScene: { bounds, fillsBackground in
        guard fillsBackground else { return }

        NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSBezierPath(
          rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        ).fill()
      }
    )

    let bitmap = try render(view)

    // Paper is the surface already; the canvas color would print as a slab of
    // ink around the drawing, so the page stays bare where only it would be.
    XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 100, y: 100)).alphaComponent, 0)
  }

  private func makeView() -> SionScenePrintView {
    SionScenePrintView(
      contentBounds: SionRect(x: 40, y: 60, width: 100, height: 50),
      pageSize: NSSize(width: 200, height: 200),
      drawScene: { bounds, _ in
        // A device color survives the device-RGB bitmap unchanged, so the
        // sampled component is exact rather than colour-managed.
        NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSBezierPath(
          rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        ).fill()
      }
    )
  }

  private func render(_ view: SionScenePrintView) throws -> NSBitmapImageRep {
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(view.bounds.width),
        pixelsHigh: Int(view.bounds.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.current = previousContext }

    view.draw(view.bounds)
    context.flushGraphics()
    return bitmap
  }
}
