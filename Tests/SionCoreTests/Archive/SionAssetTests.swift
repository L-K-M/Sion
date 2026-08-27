import Foundation
import XCTest

@testable import SionCore

final class SionAssetTests: XCTestCase {
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
