import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerShadowTests: XCTestCase {
  func testDisablingAShadowRemovesIt() throws {
    let (controller, id) = try makeShape()
    XCTAssertFalse(try style(of: id, in: controller).shadows.isEmpty)

    try controller.setShadowEnabled(false, on: id)

    XCTAssertTrue(try style(of: id, in: controller).shadows.isEmpty)
  }

  func testEnablingAShadowStartsFromTheSharedDefault() throws {
    let (controller, id) = try makeShape()
    try controller.setShadowEnabled(false, on: id)

    try controller.setShadowEnabled(true, on: id)

    XCTAssertEqual(try style(of: id, in: controller).shadows, [SionShadowDefaults.style])
  }

  func testColorAndBlurEditTheShadowInPlace() throws {
    let (controller, id) = try makeShape()
    let color = SionColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)

    try controller.setShadowColor(color, on: id)
    try controller.setShadowBlurRadius(18, on: id)

    let shadow = try XCTUnwrap(try style(of: id, in: controller).shadows.first)
    XCTAssertEqual(shadow.color, color)
    XCTAssertEqual(shadow.blurRadius, 18)
  }

  func testEditingAShadowOnAnElementWithoutOneCreatesIt() throws {
    let (controller, id) = try makeText()
    XCTAssertTrue(try style(of: id, in: controller).shadows.isEmpty)

    try controller.setShadowBlurRadius(12, on: id)

    let shadow = try XCTUnwrap(try style(of: id, in: controller).shadows.first)
    XCTAssertEqual(shadow.blurRadius, 12)
    XCTAssertEqual(shadow.color, SionShadowDefaults.style.color)
  }

  func testAnUnchangedShadowIsNotRecordedAsAnEdit() throws {
    let (controller, id) = try makeShape()
    var changes = 0
    controller.observeChanges { changes += 1 }
    let existing = try XCTUnwrap(try style(of: id, in: controller).shadows.first)

    // Prove the observer fires at all before asserting that it stays quiet.
    try controller.setShadowEnabled(false, on: id)
    XCTAssertEqual(changes, 1)
    try controller.setShadow(existing, on: id)
    XCTAssertEqual(changes, 2)

    try controller.setShadow(existing, on: id)

    XCTAssertEqual(changes, 2)
  }

  func testAGroupNeverTakesAShadowEvenThroughTheCommand() throws {
    let group = SceneElement.group(frame: SionRect(x: 0, y: 0, width: 120, height: 80))
    let controller = try makeController(elements: [group])

    try controller.setShadowEnabled(true, on: group.id)
    try controller.setShadowBlurRadius(12, on: group.id)

    XCTAssertTrue(try style(of: group.id, in: controller).shadows.isEmpty)
  }

  /// A document written by another build can carry a shadow on content this
  /// build refuses to shadow. Rendering still draws it, so removal has to work.
  func testAShadowAlreadyOnAGroupCanStillBeCleared() throws {
    var group = SceneElement.group(frame: SionRect(x: 0, y: 0, width: 120, height: 80))
    group.style.shadows = [SionShadowDefaults.style]
    let controller = try makeController(elements: [group])
    XCTAssertFalse(try style(of: group.id, in: controller).shadows.isEmpty)

    try controller.setShadowEnabled(false, on: group.id)

    XCTAssertTrue(try style(of: group.id, in: controller).shadows.isEmpty)
  }

  /// The clearing path stays open to content that cannot take a shadow, so it
  /// has to stay quiet when there is nothing there to clear.
  func testClearingAShadowThatIsNotThereRecordsNoEdit() throws {
    let group = SceneElement.group(frame: SionRect(x: 0, y: 0, width: 120, height: 80))
    let controller = try makeController(elements: [group])
    var changes = 0
    controller.observeChanges { changes += 1 }

    try controller.setShadow(nil, on: group.id)
    try controller.setShadowEnabled(false, on: group.id)

    XCTAssertEqual(changes, 0)
  }

  func testANegativeOrInfiniteBlurIsRefused() throws {
    let (controller, id) = try makeShape()
    let before = try style(of: id, in: controller).shadows

    try controller.setShadowBlurRadius(-4, on: id)
    try controller.setShadowBlurRadius(.infinity, on: id)

    XCTAssertEqual(try style(of: id, in: controller).shadows, before)
  }

  private func makeShape() throws -> (SionEditorController, ElementID) {
    let element = SceneElement.shape(
      frame: SionRect(x: 0, y: 0, width: 120, height: 80),
      kind: .rectangle
    )
    return (try makeController(elements: [element]), element.id)
  }

  private func makeText() throws -> (SionEditorController, ElementID) {
    let element = SceneElement.text(
      frame: SionRect(x: 0, y: 0, width: 120, height: 40),
      text: "Text"
    )
    return (try makeController(elements: [element]), element.id)
  }

  private func makeController(elements: [SceneElement]) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: elements))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
  }

  private func style(
    of id: ElementID,
    in controller: SionEditorController
  ) throws -> ElementStyle {
    try XCTUnwrap(controller.document.scene.element(withID: id)).style
  }
}
