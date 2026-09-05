import Foundation
import XCTest

@testable import SionGtk

final class SionGtkResourcesTests: XCTestCase {
  func testResourcesResolveToTheRepositoryDuringDevelopment() {
    let root = SionGtkResources.rootURL
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("Info.plist").path),
      "no Info.plist under \(root.path)")
    XCTAssertNotEqual(SionGtkResources.versionString, "unknown")
    XCTAssertTrue(FileManager.default.fileExists(atPath: SionGtkResources.helpIndexURL.path))
  }

  func testEnvironmentOverrideWins() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("sion-resources-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    setenv(SionGtkResources.environmentVariable, directory.path, 1)
    defer { unsetenv(SionGtkResources.environmentVariable) }

    XCTAssertEqual(
      SionGtkResources.rootURL.standardizedFileURL.path, directory.standardizedFileURL.path)
  }
}
