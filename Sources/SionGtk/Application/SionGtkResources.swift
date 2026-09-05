import Foundation
import SionCore
import SionKit

/// Locates the files the packaged application installs beside itself.
///
/// The Debian package puts them under `/usr/share/sion`; a development build
/// finds them in the repository through `SION_RESOURCE_ROOT`, or by walking up
/// from the executable to the checkout that built it.
package enum SionGtkResources {
  package static let environmentVariable = "SION_RESOURCE_ROOT"

  /// The directory holding `Info.plist` and `help/index.html`.
  package static var rootURL: URL {
    if let override = ProcessInfo.processInfo.environment[environmentVariable], !override.isEmpty {
      return URL(fileURLWithPath: override, isDirectory: true)
    }

    let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "/usr/bin/sion")
      .resolvingSymlinksInPath()
    let installed = executable.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("share/sion", isDirectory: true)
    if FileManager.default.fileExists(atPath: installed.appendingPathComponent("Info.plist").path) {
      return installed
    }

    // A build in .build/<configuration>/ sits inside the repository.
    var candidate = executable.deletingLastPathComponent()
    for _ in 0..<6 {
      let resources = candidate.appendingPathComponent("Resources", isDirectory: true)
      if FileManager.default.fileExists(atPath: resources.appendingPathComponent("Info.plist").path)
      {
        return resources
      }
      candidate = candidate.deletingLastPathComponent()
    }

    return installed
  }

  package static var infoPlistURL: URL {
    rootURL.appendingPathComponent("Info.plist")
  }

  /// The user guide: the packaged Linux copy, else the macOS help book source.
  package static var helpIndexURL: URL {
    let packaged = rootURL.appendingPathComponent("help/index.html")
    if FileManager.default.fileExists(atPath: packaged.path) {
      return packaged
    }
    return rootURL.appendingPathComponent(
      "Sion.help/Contents/Resources/en.lproj/index.html")
  }

  /// The version stamped into archives; `Bundle` reads a flat `Info.plist`.
  package static var archiveGenerator: SionArchiveGenerator {
    let bundle = Bundle(path: rootURL.path) ?? .main
    return ApplicationArchiveMetadata(bundle: bundle).archiveGenerator
  }

  package static var versionString: String {
    archiveGenerator.version
  }
}
