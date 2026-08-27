import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasPreviewTests: XCTestCase {
  func testPreviewUsesExactBoundedPixelDimensions() throws {
    let element = SceneElement.shape(
      id: TestPreview.elementID,
      frame: SionRect(x: 0, y: 0, width: 1600, height: 800)
    )
    let controller = try makeController(elements: [element])
    let canvas = SionCanvasView(editorController: controller)

    let data = try XCTUnwrap(
      canvas.renderPreviewPNG(maximumDimension: TestPreview.maximumDimension)
    )
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
    let content = controller.contentBounds()
    let scale = min(
      1,
      Double(TestPreview.maximumDimension) / max(content.width, content.height)
    )

    XCTAssertEqual(
      bitmap.pixelsWide,
      max(1, Int((content.width * scale).rounded()))
    )
    XCTAssertEqual(
      bitmap.pixelsHigh,
      max(1, Int((content.height * scale).rounded()))
    )
    XCTAssertLessThanOrEqual(
      max(bitmap.pixelsWide, bitmap.pixelsHigh),
      Int(TestPreview.maximumDimension)
    )
    XCTAssertEqual(Array(data.prefix(TestPreview.pngSignature.count)), TestPreview.pngSignature)
  }

  func testPreviewRejectsNonpositiveDimension() throws {
    let element = SceneElement.shape(id: TestPreview.elementID, frame: TestPreview.defaultFrame)
    let controller = try makeController(elements: [element])
    let canvas = SionCanvasView(editorController: controller)

    XCTAssertNil(canvas.renderPreviewPNG(maximumDimension: 0))
  }

  func testPreviewMapsNonzeroContentOriginAndYAxis() throws {
    var upperLeft = SceneElement.shape(
      id: TestPreview.elementID,
      frame: SionRect(x: 1000, y: 2000, width: 200, height: 100)
    )
    upperLeft.style = ElementStyle(fill: .solid(TestPreview.red))

    var lowerRight = SceneElement.shape(
      id: TestPreview.secondElementID,
      frame: SionRect(x: 1400, y: 2300, width: 100, height: 200)
    )
    lowerRight.style = ElementStyle(fill: .solid(TestPreview.blue))

    let controller = try makeController(elements: [upperLeft, lowerRight])
    let canvas = SionCanvasView(editorController: controller)
    let content = controller.contentBounds()
    let data = try XCTUnwrap(
      canvas.renderPreviewPNG(maximumDimension: TestPreview.orientationDimension)
    )
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
    let redCenter = try XCTUnwrap(pixelCenter(in: bitmap, matching: .red))
    let blueCenter = try XCTUnwrap(pixelCenter(in: bitmap, matching: .blue))
    let scale = min(
      1,
      Double(TestPreview.orientationDimension) / max(content.width, content.height)
    )

    XCTAssertEqual(
      redCenter.x,
      (upperLeft.geometry.frame.center.x - content.minX) * scale,
      accuracy: TestPreview.pixelTolerance
    )
    XCTAssertEqual(
      blueCenter.x,
      (lowerRight.geometry.frame.center.x - content.minX) * scale,
      accuracy: TestPreview.pixelTolerance
    )
    // Bitmap rows are bottom-up; the model's smaller y-coordinate appears higher.
    XCTAssertGreaterThan(redCenter.y, blueCenter.y)
  }

  func testPreviewIsIndependentOfSelection() throws {
    let element = SceneElement.shape(id: TestPreview.elementID, frame: TestPreview.defaultFrame)
    let controller = try makeController(elements: [element])
    let canvas = SionCanvasView(editorController: controller)
    let unselected = try XCTUnwrap(
      canvas.renderPreviewPNG(maximumDimension: TestPreview.selectionDimension)
    )

    controller.select(element.id)
    let selected = try XCTUnwrap(
      canvas.renderPreviewPNG(maximumDimension: TestPreview.selectionDimension)
    )

    XCTAssertEqual(selected, unselected)
  }

  private func makeController(elements: [SceneElement]) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(document: SionDocument(scene: SionScene(elements: elements))),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func pixelCenter(
    in bitmap: NSBitmapImageRep,
    matching target: TestPreview.PixelTarget
  ) -> SionPoint? {
    var xTotal = 0.0
    var yTotal = 0.0
    var count = 0.0

    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          target.matches(color)
        else {
          continue
        }

        xTotal += Double(x)
        yTotal += Double(y)
        count += 1
      }
    }

    guard count > 0 else { return nil }

    return SionPoint(x: xTotal / count, y: yTotal / count)
  }
}

private enum TestPreview {
  enum PixelTarget {
    case red
    case blue

    func matches(_ color: NSColor) -> Bool {
      switch self {
      case .red:
        color.redComponent > TestPreview.componentHigh
          && color.greenComponent < TestPreview.componentLow
          && color.blueComponent < TestPreview.componentLow
      case .blue:
        color.redComponent < TestPreview.componentLow
          && color.greenComponent < TestPreview.componentLow
          && color.blueComponent > TestPreview.componentHigh
      }
    }
  }

  static let elementID = ElementID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  )
  static let secondElementID = ElementID(
    rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  )
  static let maximumDimension: CGFloat = 512
  static let orientationDimension: CGFloat = 282
  static let selectionDimension: CGFloat = 256
  static let pixelTolerance = 2.0
  static let componentHigh: CGFloat = 0.8
  static let componentLow: CGFloat = 0.2
  static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  static let red = SionColor(red: 1, green: 0, blue: 0)
  static let blue = SionColor(red: 0, green: 0, blue: 1)
  static let defaultFrame = SionRect(x: 0, y: 0, width: 100, height: 100)
}
