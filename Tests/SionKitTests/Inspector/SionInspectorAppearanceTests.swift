import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionInspectorAppearanceTests: XCTestCase {
  func testAnImageOffersAStrokeButNoFill() throws {
    let image = SceneElement.image(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90),
      assetID: AssetID(rawValue: "asset"),
      displayAssetID: AssetID(rawValue: "display")
    )

    try withInspector(elements: [image], selecting: image.id) { fixture in
      XCTAssertFalse(try colorWell(labelled: "Fill color", in: fixture).isEnabled)
      XCTAssertTrue(try colorWell(labelled: "Stroke color", in: fixture).isEnabled)
      XCTAssertTrue(try slider(labelled: "Stroke width", in: fixture).isEnabled)
    }
  }

  func testTextOffersNeitherStrokeNorFill() throws {
    let text = SceneElement.text(
      frame: SionRect(x: 40, y: 40, width: 160, height: 40),
      text: "Label"
    )

    try withInspector(elements: [text], selecting: text.id) { fixture in
      XCTAssertFalse(try colorWell(labelled: "Fill color", in: fixture).isEnabled)
      XCTAssertFalse(try colorWell(labelled: "Stroke color", in: fixture).isEnabled)
    }
  }

  func testTurningOffTheDropShadowRemovesItFromTheDocument() throws {
    let shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90),
      kind: .rectangle
    )

    try withInspector(elements: [shape], selecting: shape.id) { fixture in
      let button = try shadowButton(in: fixture)

      // A shape ships with an elevation shadow, so the control starts on.
      XCTAssertTrue(button.isEnabled)
      XCTAssertEqual(button.state, .on)
      XCTAssertTrue(try colorWell(labelled: "Drop shadow color", in: fixture).isEnabled)

      button.state = .off
      button.performClick(nil)

      let edited = try XCTUnwrap(fixture.editor.document.scene.element(withID: shape.id))
      XCTAssertTrue(edited.style.shadows.isEmpty)
      XCTAssertFalse(try colorWell(labelled: "Drop shadow color", in: fixture).isEnabled)
    }
  }

  func testAGroupCastsNoShadow() throws {
    let group = SceneElement.group(frame: SionRect(x: 0, y: 0, width: 200, height: 200))

    try withInspector(elements: [group], selecting: group.id) { fixture in
      XCTAssertFalse(try shadowButton(in: fixture).isEnabled)
    }
  }

  private struct Fixture {
    let editor: SionEditorController
    let descendants: [NSView]
  }

  /// The inspector palette is app global, so every caller tears it down.
  private func withInspector(
    elements: [SceneElement],
    selecting id: ElementID,
    _ body: (Fixture) throws -> Void
  ) throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: elements))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(id)
    let documentController = SionDocumentWindowController(editorController: editor)
    defer { documentController.close() }

    let documentWindow = try XCTUnwrap(documentController.window)
    documentWindow.orderFrontRegardless()
    let inspector = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.inspector.paletteKind)
    )
    defer { inspector.close() }
    inspector.showPanel()

    let panel = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Inspector" && $0.isVisible }
    )

    try body(
      Fixture(
        editor: editor,
        descendants: try XCTUnwrap(panel.contentView).appearanceTestDescendants
      )
    )
  }

  private func colorWell(labelled label: String, in fixture: Fixture) throws -> NSColorWell {
    try XCTUnwrap(
      fixture.descendants.compactMap { $0 as? NSColorWell }.first {
        $0.accessibilityLabel() == label
      }
    )
  }

  private func slider(labelled label: String, in fixture: Fixture) throws -> NSSlider {
    try XCTUnwrap(
      fixture.descendants.compactMap { $0 as? NSSlider }.first {
        $0.accessibilityLabel() == label
      }
    )
  }

  private func shadowButton(in fixture: Fixture) throws -> NSButton {
    try XCTUnwrap(
      fixture.descendants.compactMap { $0 as? NSButton }.first { $0.title == "Drop Shadow" }
    )
  }
}

extension NSView {
  fileprivate var appearanceTestDescendants: [NSView] {
    subviews + subviews.flatMap(\.appearanceTestDescendants)
  }
}
