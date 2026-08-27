import Foundation
import XCTest

@testable import SionCore

final class SionAssetTests: XCTestCase {
  func testBuildsOnlyStructurallyValidDisplayPNGs() throws {
    let display = try SionAsset.safeDisplayPNG(data: testPNGData())

    XCTAssertEqual(display.mediaType, "image/png")
    XCTAssertEqual(display.fileExtension, "png")
    XCTAssertNil(display.pixelSize)

    XCTAssertThrowsError(
      try SionAsset.safeDisplayPNG(data: Data("not a PNG".utf8))
    ) { error in
      guard case .invalidDisplayAsset = error as? SionPackageError else {
        XCTFail("Expected invalid display asset")
        return
      }
    }
  }

  func testRejectsDisplayPNGWithMismatchedPixelSize() {
    XCTAssertNoThrow(
      try SionAsset.safeDisplayPNG(
        data: testPNGData(width: 1, height: 1),
        pixelSize: SionSize(width: 1, height: 1)
      )
    )

    XCTAssertThrowsError(
      try SionAsset.safeDisplayPNG(
        data: testPNGData(width: 1, height: 1),
        pixelSize: SionSize(width: 2, height: 1)
      )
    ) { error in
      guard case .invalidDisplayAsset = error as? SionPackageError else {
        XCTFail("Expected invalidDisplayAsset, got \(error)")
        return
      }
    }

    XCTAssertThrowsError(
      try SionAsset.safeDisplayPNG(
        data: testPNGData(width: 1, height: 1),
        pixelSize: SionSize(width: 1, height: 2)
      )
    ) { error in
      guard case .invalidDisplayAsset = error as? SionPackageError else {
        XCTFail("Expected invalidDisplayAsset, got \(error)")
        return
      }
    }
  }

  func testPackageRejectsDisplayPNGWithMismatchedPixelSize() throws {
    let display = try SionAsset(
      data: testPNGData(width: 1, height: 1),
      mediaType: "image/png",
      fileExtension: "png",
      pixelSize: SionSize(width: 2, height: 1)
    )
    let image = SceneElement.image(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      assetID: display.id,
      displayAssetID: display.id
    )
    let package = SionPackage(
      document: SionDocument(scene: SionScene(elements: [image])),
      assets: [display.id: display]
    )

    XCTAssertThrowsError(try package.validate()) { error in
      XCTAssertEqual(error as? SionPackageError, .invalidDisplayAsset(display.id))
    }
  }

  func testRejectsDisplayPNGDecompressionBombDimensions() {
    let excessiveDimension = UInt32(SionAsset.maximumSafeDisplayPixelDimension) + 1

    XCTAssertThrowsError(
      try SionAsset.safeDisplayPNG(data: testPNGData(width: excessiveDimension))
    )
    XCTAssertThrowsError(
      try SionAsset.safeDisplayPNG(data: testPNGData(width: 4_096, height: 4_097))
    )
  }

  func testRejectsDisplayPNGWithInvalidCompressedPixels() {
    XCTAssertThrowsError(
      try SionAsset.safeDisplayPNG(data: testPNGDataWithInvalidCompressedPixels())
    )
  }

  func testAcceptsDisplayPNGWithDynamicHuffmanPixels() {
    XCTAssertNoThrow(
      try SionAsset.safeDisplayPNG(
        data: testDynamicPNGData(),
        pixelSize: SionSize(width: 17, height: 17)
      )
    )
  }

  func testPackageRejectsSpoofedDisplayPNG() throws {
    let spoofed = try SionAsset(
      data: Data("not a PNG".utf8),
      mediaType: "image/png",
      fileExtension: "png"
    )
    let image = SceneElement.image(
      frame: SionRect(x: 0, y: 0, width: 100, height: 100),
      assetID: spoofed.id,
      displayAssetID: spoofed.id
    )
    let package = SionPackage(
      document: SionDocument(scene: SionScene(elements: [image])),
      assets: [spoofed.id: spoofed]
    )

    XCTAssertThrowsError(try package.validate()) { error in
      XCTAssertEqual(error as? SionPackageError, .invalidDisplayAsset(spoofed.id))
    }
  }

  func testRejectsEmptyMediaType() {
    XCTAssertThrowsError(
      try SionAsset(
        data: Data([0x89, 0x50, 0x4e, 0x47]),
        mediaType: "",
        fileExtension: "png"
      )
    ) { error in
      XCTAssertEqual(error as? SionPackageError, .invalidAssetMediaType(""))
    }
  }

  func testRejectsInvalidPixelSize() {
    XCTAssertThrowsError(
      try SionAsset(
        data: Data([0x89, 0x50, 0x4e, 0x47]),
        mediaType: "image/png",
        fileExtension: "png",
        pixelSize: SionSize(width: .nan, height: 24)
      )
    ) { error in
      guard case .invalidAssetPixelSize(let size) = error as? SionPackageError else {
        XCTFail("Expected invalid pixel size")
        return
      }

      XCTAssertTrue(size.width.isNaN)
      XCTAssertEqual(size.height, 24)
    }

    XCTAssertThrowsError(
      try SionAsset(
        data: Data([0x89, 0x50, 0x4e, 0x47]),
        mediaType: "image/png",
        fileExtension: "png",
        pixelSize: SionSize(width: 0, height: 24)
      )
    )
  }
}
