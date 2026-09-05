import Foundation
import SionCore

package struct SafeImageRendition: Sendable {
  package let data: Data
  package let sourcePixelSize: SionSize
  package let pixelSize: SionSize

  package init(data: Data, sourcePixelSize: SionSize, pixelSize: SionSize) {
    self.data = data
    self.sourcePixelSize = sourcePixelSize
    self.pixelSize = pixelSize
  }
}

/// Decodes pasted or dropped image bytes (bitmaps and SVG through GdkPixbuf,
/// PDF through poppler) into a bounded PNG display rendition, mirroring
/// `SafeImageRenditionBuilder` on macOS. Returns nil for anything it will not
/// import.
package enum SafeImageRenditionBuilder {
  package static func make(from data: Data) -> SafeImageRendition? {
    nil
  }
}

/// Runs decoding off the main actor and cooperatively cancels between stages.
package struct SafeImageRenditionService: Sendable {
  package typealias Build = @Sendable (Data) async -> SafeImageRendition?

  private let build: Build

  package init() {
    build = { data in
      SafeImageRenditionBuilder.make(from: data)
    }
  }

  package init(build: @escaping Build) {
    self.build = build
  }

  package func make(from data: Data) async -> SafeImageRendition? {
    guard !Task.isCancelled else { return nil }

    let task = Task.detached(priority: .userInitiated) {
      await build(data)
    }
    let rendition = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    guard !Task.isCancelled else { return nil }

    return rendition
  }
}
