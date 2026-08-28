import Foundation
import SionCore

/// Resolves app provenance at the platform boundary, outside portable Core.
package struct ApplicationArchiveMetadata {
  package let archiveGenerator: SionArchiveGenerator

  package init(bundle: Bundle) {
    guard
      let version = bundle.object(forInfoDictionaryKey: Defaults.bundleVersionKey) as? String,
      !version.isEmpty
    else {
      archiveGenerator = SionArchiveGenerator(
        name: Defaults.applicationName,
        version: Defaults.unknownVersion
      )
      return
    }

    archiveGenerator = SionArchiveGenerator(
      name: Defaults.applicationName,
      version: version
    )
  }

  private enum Defaults {
    static let applicationName = "Sion"
    static let bundleVersionKey = "CFBundleShortVersionString"
    static let unknownVersion = "unknown"
  }
}
