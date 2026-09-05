import CGtk
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

  /// The version stamped into archives, read from the shared `Info.plist`.
  package static var archiveGenerator: SionArchiveGenerator {
    ApplicationArchiveMetadata(infoDictionary: infoDictionary).archiveGenerator
  }

  package static var infoDictionary: [String: Any] {
    guard let data = try? Data(contentsOf: infoPlistURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = plist as? [String: Any]
    else {
      return [:]
    }
    return dictionary
  }

  package static var versionString: String {
    archiveGenerator.version
  }

  /// A development build runs without the installed icon theme entries; render
  /// the application icon into the cache and let the theme find it there.
  @MainActor
  package static func ensureApplicationIcon(named name: String) {
    guard let display = gdk_display_get_default(),
      let theme = gtk_icon_theme_get_for_display(display)
    else {
      return
    }
    if gtk_icon_theme_has_icon(theme, name) != 0 {
      return
    }

    let cache =
      ProcessInfo.processInfo.environment["XDG_CACHE_HOME"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
      } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
    let root = cache.appendingPathComponent("sion/icons", isDirectory: true)
    for pixels in [16, 32, 48, 64, 128, 256] {
      let directory = root.appendingPathComponent(
        "hicolor/\(pixels)x\(pixels)/apps", isDirectory: true)
      let file = directory.appendingPathComponent("\(name).png")
      if FileManager.default.fileExists(atPath: file.path) { continue }
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      guard
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(pixels), Int32(pixels)),
        let context = cairo_create(surface)
      else {
        continue
      }
      SionIconArtwork.drawAppIcon(context, size: Double(pixels))
      cairo_destroy(context)
      _ = cairo_surface_write_to_png(surface, file.path)
      cairo_surface_destroy(surface)
    }
    gtk_icon_theme_add_search_path(theme, root.path)
  }
}
