import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasImagePasteTests: XCTestCase {
  func testInvalidationCancelsPendingImagePaste() async throws {
    _ = NSApplication.shared
    let sourceData = try makeImageData()
    let rendition = try XCTUnwrap(SafeImageRenditionBuilder.make(from: sourceData))
    let gate = ImageRenditionGate()
    let cancellation = CancellationRecord()
    let started = expectation(description: "Image rendition started")
    let resumed = expectation(description: "Image rendition resumed")
    let unexpectedChange = expectation(description: "Image paste changed the document")
    unexpectedChange.isInverted = true
    let service = SafeImageRenditionService(build: { _ in
      started.fulfill()
      await gate.wait()
      await cancellation.record(Task.isCancelled)
      resumed.fulfill()
      return rendition
    })
    let controller = try makeController {
      _ in unexpectedChange.fulfill()
    }
    let pasteboard = testPasteboard()
    pasteboard.declareTypes([.tiff], owner: nil)
    XCTAssertTrue(pasteboard.setData(sourceData, forType: .tiff))
    let canvas = SionCanvasView(
      editorController: controller,
      pasteboard: pasteboard,
      imageRenditionService: service
    )
    defer { canvas.invalidate() }

    canvas.paste(nil)
    await fulfillment(of: [started])

    canvas.invalidate()
    await gate.open()

    await fulfillment(of: [resumed])
    await fulfillment(of: [unexpectedChange], timeout: 0.1)
    let observedCancellation = await cancellation.observedCancellation

    XCTAssertTrue(observedCancellation)
    XCTAssertTrue(controller.document.scene.elements.isEmpty)
  }

  private func makeController(
    didChange: @escaping (SionEditorController.DocumentChange) -> Void
  ) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument()),
      undoManagerProvider: { nil },
      didChange: didChange
    )
  }

  private func makeImageData() throws -> Data {
    let image = NSImage(size: NSSize(width: 12, height: 8), flipped: false) { bounds in
      NSColor.systemBlue.setFill()
      bounds.fill()
      return true
    }

    return try XCTUnwrap(image.tiffRepresentation)
  }

  private func testPasteboard() -> NSPasteboard {
    NSPasteboard(
      name: NSPasteboard.Name(
        rawValue: "ch.lkmc.sion.tests.\(UUID().uuidString)"
      )
    )
  }
}

private actor CancellationRecord {
  private(set) var observedCancellation = false

  func record(_ isCancelled: Bool) {
    observedCancellation = isCancelled
  }
}

private actor ImageRenditionGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false

  func wait() async {
    guard !isOpen else { return }

    await withCheckedContinuation { continuation = $0 }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}
