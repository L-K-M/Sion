import Foundation
import XCTest

@testable import SionCore
@testable import SionKit

final class ApplicationArchiveMetadataTests: XCTestCase {
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

  func testReadsTheSameVersionFromAnInfoDictionary() {
    XCTAssertEqual(
      ApplicationArchiveMetadata(
        infoDictionary: ["CFBundleShortVersionString": BundleFixture.version]
      ).archiveGenerator,
      SionArchiveGenerator(name: BundleFixture.applicationName, version: BundleFixture.version)
    )
    for dictionary in [[:], ["CFBundleShortVersionString": ""]] as [[String: Any]] {
      XCTAssertEqual(
        ApplicationArchiveMetadata(infoDictionary: dictionary).archiveGenerator,
        SionArchiveGenerator(
          name: BundleFixture.applicationName,
          version: BundleFixture.unknownVersion
        )
      )
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
      .appendingPathComponent(BundleFixture.contentsName, isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

    var info: [String: Any] = [
      BundleFixture.identifierKey: BundleFixture.identifier,
      BundleFixture.nameKey: BundleFixture.name,
      BundleFixture.packageTypeKey: BundleFixture.packageType,
      BundleFixture.versionKey: BundleFixture.bundleVersion,
    ]
    info[BundleFixture.shortVersionKey] = shortVersion
    let data = try PropertyListSerialization.data(
      fromPropertyList: info,
      format: .xml,
      options: 0
    )
    try data.write(to: contents.appendingPathComponent(BundleFixture.infoPlistName))

    let bundleURL = contents.deletingLastPathComponent()
    let bundle = try XCTUnwrap(Bundle(url: bundleURL))
    try body(bundle)
  }
}

private enum BundleFixture {
  static let applicationName = "Sion"
  static let bundleVersion = "1"
  static let bundleName = "ArchiveGenerator.bundle"
  static let contentsName = "Contents"
  static let identifier = "ch.lkmc.sion.tests.archive-generator"
  static let identifierKey = "CFBundleIdentifier"
  static let infoPlistName = "Info.plist"
  static let name = "ArchiveGeneratorFixture"
  static let nameKey = "CFBundleName"
  static let packageType = "BNDL"
  static let packageTypeKey = "CFBundlePackageType"
  static let shortVersionKey = "CFBundleShortVersionString"
  static let unknownVersion = "unknown"
  static let version = "9.8.7"
  static let versionKey = "CFBundleVersion"
}
