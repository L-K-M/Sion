import Foundation
import XCTest

@testable import SionCore

final class SafeImageArchiveTests: XCTestCase {
  func testArchivePreservesOriginalAndDisplayRendition() throws {
    let originalData = Data("<svg><script>alert('unsafe')</script></svg>".utf8)
    let original = try SionAsset(
      data: originalData,
      mediaType: "image/svg+xml",
      fileExtension: "svg",
      originalFilename: "source.svg"
    )
    let display = try SionAsset.safeDisplayPNG(data: testPNGData())
    let image = SceneElement.image(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      assetID: original.id,
      displayAssetID: display.id
    )
    let package = SionPackage(
      document: SionDocument(scene: SionScene(elements: [image])),
      assets: [original.id: original, display.id: display]
    )

    let encoded = try SionArchive.encode(
      package: package,
      intent: .manual,
      at: Date(timeIntervalSince1970: 1_787_830_522)
    )
    let decoded = try SionArchive.decode(encoded.data)
    let entries = Dictionary(
      uniqueKeysWithValues: try StoredZIPArchive.decode(encoded.data).map { ($0.path, $0.data) }
    )
    let svg = try XCTUnwrap(
      String(data: entries[SionArchiveConstants.svgPath]!, encoding: .utf8)
    )

    XCTAssertEqual(decoded.assets[original.id]?.data, originalData)
    XCTAssertEqual(decoded.assets[display.id]?.data, display.data)
    XCTAssertTrue(svg.contains(display.data.base64EncodedString()))
    XCTAssertFalse(svg.contains(originalData.base64EncodedString()))
  }
}
