import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionEditorControllerTextEditingTests: XCTestCase {
  func testInlineTextIsLiveAndOneUndoableChange() throws {
    let element = SceneElement.text(
      frame: SionRect(x: 20, y: 20, width: 220, height: 56),
      text: "Original"
    )
    let package = SionPackage(
      document: SionDocument(scene: SionScene(elements: [element]))
    )
    var changes = [String]()
    let controller = try SionEditorController(
      package: package,
      undoManagerProvider: { nil },
      didChange: { change in
        changes.append(change.label)
      }
    )

    try controller.beginTextEdit(on: element.id)
    try controller.updateTextEdit("Draft", on: element.id)
    try controller.updateTextEdit("Final", on: element.id)

    XCTAssertEqual(controller.selectedText(for: element.id), "Final")
    XCTAssertEqual(changes, ["done"])

    try controller.endTextEdit()
    controller.undoSceneEdit()

    XCTAssertEqual(controller.selectedText(for: element.id), "Original")
    XCTAssertEqual(changes, ["done", "undone"])

    controller.undoSceneEdit()
    XCTAssertEqual(changes, ["done", "undone"])
  }

  func testTextCheckpointKeepsLaterUndoAtSavedState() throws {
    let element = SceneElement.text(
      frame: SionRect(x: 20, y: 20, width: 220, height: 56),
      text: "Original"
    )
    let controller = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [element]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )

    try controller.beginTextEdit(on: element.id)
    try controller.updateTextEdit("Saved", on: element.id)
    try controller.checkpointTextEdit(on: element.id)
    try controller.updateTextEdit("Later", on: element.id)
    try controller.endTextEdit()

    controller.undoSceneEdit()
    XCTAssertEqual(controller.selectedText(for: element.id), "Saved")

    controller.undoSceneEdit()
    XCTAssertEqual(controller.selectedText(for: element.id), "Original")
  }
}

extension SionEditorController.DocumentChange {
  fileprivate var label: String {
    switch self {
    case .done: "done"
    case .undone: "undone"
    case .redone: "redone"
    }
  }
}

extension SionEditorController {
  fileprivate func selectedText(for id: ElementID) -> String? {
    guard let element = document.scene.element(withID: id),
      case .text(let text) = element.content
    else {
      return nil
    }

    return text.string
  }
}
