import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasImageDropTests: XCTestCase {
  func testTheCanvasAcceptsEveryDroppedTypeAPasteAccepts() throws {
    _ = NSApplication.shared
    let canvas = SionCanvasView(editorController: try makeController())
    defer { canvas.invalidate() }

    let registered = Set(canvas.registeredDraggedTypes)

    XCTAssertTrue(registered.contains(.fileURL))
    XCTAssertTrue(registered.contains(.png))
    XCTAssertTrue(registered.contains(.tiff))
    XCTAssertTrue(registered.contains(.pdf))
    // Sion's own selection payload is pasted, never dropped.
    XCTAssertFalse(
      registered.contains(NSPasteboard.PasteboardType("ch.lkmc.sion.selection"))
    )
  }

  func testOnlyPasteboardsCarryingArtworkAreAccepted() throws {
    _ = NSApplication.shared
    let canvas = SionCanvasView(editorController: try makeController())
    defer { canvas.invalidate() }

    let empty = makePasteboard()
    empty.declareTypes([.string], owner: nil)
    empty.setString("just words", forType: .string)

    let artwork = makePasteboard()
    artwork.declareTypes([.tiff], owner: nil)
    XCTAssertTrue(artwork.setData(try makeImageData(), forType: .tiff))

    let vector = makePasteboard()
    vector.declareTypes([.string], owner: nil)
    vector.setString("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>", forType: .string)

    XCTAssertFalse(canvas.acceptsImageDrop(from: empty))
    XCTAssertTrue(canvas.acceptsImageDrop(from: artwork))
    XCTAssertTrue(canvas.acceptsImageDrop(from: vector))
  }

  func testADroppedImageIsInsertedWhereItLanded() async throws {
    _ = NSApplication.shared
    let sourceData = try makeImageData()
    let rendition = try XCTUnwrap(SafeImageRenditionBuilder.make(from: sourceData))
    let service = SafeImageRenditionService(build: { _ in rendition })
    let inserted = expectation(description: "The drop reached the document")
    let controller = try makeController { _ in inserted.fulfill() }
    let canvas = SionCanvasView(
      editorController: controller,
      imageRenditionService: service
    )
    defer { canvas.invalidate() }

    let pasteboard = makePasteboard()
    pasteboard.declareTypes([.tiff], owner: nil)
    XCTAssertTrue(pasteboard.setData(sourceData, forType: .tiff))
    let location = NSPoint(x: 220, y: 140)

    XCTAssertTrue(canvas.performImageDrop(from: pasteboard, atWindowLocation: location))
    await fulfillment(of: [inserted], timeout: DropTestTiming.insertion)

    let element = try XCTUnwrap(controller.document.scene.elements.first)
    guard case .image = element.content else {
      return XCTFail("Expected the drop to insert an image")
    }

    // The drop lands under the pointer, not at the viewport center.
    let dropped = canvas.convert(location, from: nil)
    let landed = canvas.viewPoint(for: element.geometry.frame.center)
    XCTAssertEqual(landed.x, dropped.x, accuracy: 0.001)
    XCTAssertEqual(landed.y, dropped.y, accuracy: 0.001)
  }

  func testADroppedImageStretchesToItsFrame() async throws {
    _ = NSApplication.shared
    let sourceData = try makeImageData()
    let rendition = try XCTUnwrap(SafeImageRenditionBuilder.make(from: sourceData))
    let service = SafeImageRenditionService(build: { _ in rendition })
    let inserted = expectation(description: "The drop reached the document")
    let controller = try makeController { _ in inserted.fulfill() }
    let canvas = SionCanvasView(
      editorController: controller,
      imageRenditionService: service
    )
    defer { canvas.invalidate() }

    let pasteboard = makePasteboard()
    pasteboard.declareTypes([.tiff], owner: nil)
    XCTAssertTrue(pasteboard.setData(sourceData, forType: .tiff))

    canvas.performImageDrop(from: pasteboard, atWindowLocation: NSPoint(x: 100, y: 100))
    await fulfillment(of: [inserted], timeout: DropTestTiming.insertion)

    let element = try XCTUnwrap(controller.document.scene.elements.first)
    guard case .image(let content) = element.content else {
      return XCTFail("Expected the drop to insert an image")
    }

    // A resized image fills its frame rather than sitting inside it.
    XCTAssertEqual(content.scalingMode, .stretch)
  }

  private func makeController(
    didChange: @escaping (SionEditorController.DocumentChange) -> Void = { _ in }
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

  private func makePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name(rawValue: "ch.lkmc.sion.tests.\(UUID().uuidString)"))
  }
}

private enum DropTestTiming {
  static let insertion: TimeInterval = 5
}
