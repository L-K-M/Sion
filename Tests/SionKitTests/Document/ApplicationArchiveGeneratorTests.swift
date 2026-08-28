import Foundation
import XCTest

@testable import SionCore
@testable import SionKit

final class ApplicationArchiveGeneratorTests: XCTestCase {
  func testUsesBundleShortVersion() throws {
    try withTemporaryBundle(shortVersion: BundleFixture.version) { bundle in
      XCTAssertEqual(
        ApplicationArchiveMetadata(bundle: bundle).archiveGenerator,
        SionArchiveGenerator(
          name: BundleFixture.applicationName,
          version: BundleFixture.version
        )
      )
    }
  }

  func testUsesUnknownVersionForMissingOrEmptyMetadata() throws {
    for version in [nil, ""] as [String?] {
      try withTemporaryBundle(shortVersion: version) { bundle in
        XCTAssertEqual(
          ApplicationArchiveMetadata(bundle: bundle).archiveGenerator,
          SionArchiveGenerator(
            name: BundleFixture.applicationName,
            version: BundleFixture.unknownVersion
          )
        )
      }
    }
  }

  private func withTemporaryBundle(
    shortVersion: String?,
    body: (Bundle) throws -> Void
  ) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let contents =
      root
      .appendingPathComponent(BundleFixture.bundleName, isDirectory: true)
      .appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

    var info: [String: Any] = [
      "CFBundleIdentifier": "ch.lkmc.sion.tests.archive-generator",
      "CFBundleName": "ArchiveGeneratorFixture",
      "CFBundlePackageType": "BNDL",
      "CFBundleVersion": "1",
    ]
    info[BundleFixture.shortVersionKey] = shortVersion
    let data = try PropertyListSerialization.data(
      fromPropertyList: info,
      format: .xml,
      options: 0
    )
    try data.write(to: contents.appendingPathComponent("Info.plist"))

    let bundleURL = contents.deletingLastPathComponent()
    let bundle = try XCTUnwrap(Bundle(url: bundleURL))
    try body(bundle)
  }
}

private enum BundleFixture {
  static let applicationName = "Sion"
  static let bundleName = "ArchiveGenerator.bundle"
  static let shortVersionKey = "CFBundleShortVersionString"
  static let unknownVersion = "unknown"
  static let version = "9.8.7"
}
