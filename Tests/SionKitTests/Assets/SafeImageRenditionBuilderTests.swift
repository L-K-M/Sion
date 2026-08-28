import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SafeImageRenditionBuilderTests: XCTestCase {
  func testRasterizesAnImageIntoAValidatedPNG() throws {
    let image = NSImage(size: NSSize(width: 12, height: 8), flipped: false) { bounds in
      NSColor.systemBlue.setFill()
      bounds.fill()
      return true
    }
    let sourceData = try XCTUnwrap(image.tiffRepresentation)

    let rendition = try XCTUnwrap(SafeImageRenditionBuilder.make(from: sourceData))

    XCTAssertEqual(rendition.sourcePixelSize, SionSize(width: 12, height: 8))
    XCTAssertEqual(rendition.pixelSize, SionSize(width: 12, height: 8))
    XCTAssertNoThrow(
      try SionAsset.safeDisplayPNG(
        data: rendition.data,
        pixelSize: rendition.pixelSize
      )
    )
  }

  func testServiceRasterizesAnImage() async throws {
    let image = NSImage(size: NSSize(width: 12, height: 8), flipped: false) { bounds in
      NSColor.systemBlue.setFill()
      bounds.fill()
      return true
    }
    let sourceData = try XCTUnwrap(image.tiffRepresentation)

    let rendition = await SafeImageRenditionService().make(from: sourceData)

    XCTAssertNotNil(rendition)
  }
}
