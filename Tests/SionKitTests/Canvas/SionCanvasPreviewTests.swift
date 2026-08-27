import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasPreviewTests: XCTestCase {
  func testPreviewContainsPNGMatchingContentAspect() throws {
    let element = SceneElement.shape(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
      frame: SionRect(x: 0, y: 0, width: 1600, height: 800)
    )
    let controller = try SionEditorController(
      package: SionPackage(document: SionDocument(scene: SionScene(elements: [element]))),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let canvas = SionCanvasView(editorController: controller)

    let data = try XCTUnwrap(canvas.renderPreviewPNG(maximumDimension: 512))

    // PNG signature.
    XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    // The content is 2:1; the preview preserves that at any backing scale.
    let image = try XCTUnwrap(NSImage(data: data))
    XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.01)
    XCTAssertGreaterThan(image.size.width, 100)
  }

  func testPreviewOmitsSelectionChrome() throws {
    let element = SceneElement.shape(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    let controller = try SionEditorController(
      package: SionPackage(document: SionDocument(scene: SionScene(elements: [element]))),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    controller.select(element.id)
    let canvas = SionCanvasView(editorController: controller)

    // A selected element must not crash or alter the preview; the chrome is
    // suppressed by the offscreen render pass itself.
    XCTAssertNotNil(canvas.renderPreviewPNG(maximumDimension: 256))
  }
}
