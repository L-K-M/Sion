import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class SionCanvasMenuValidationTests: XCTestCase {
  func testEditValidationMatchesExecutableSelection() throws {
    _ = NSApplication.shared
    let editable = shape(id: "00000000-0000-0000-0000-000000000001")
    var locked = shape(id: "00000000-0000-0000-0000-000000000002")
    locked.lockState = .locked
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
      frame: SionRect(x: 200, y: 0, width: 100, height: 100)
    )
    var lockedChild = shape(id: "00000000-0000-0000-0000-000000000004")
    lockedChild.parentID = group.id
    lockedChild.lockState = .locked
    let controller = try makeController(elements: [editable, locked, group, lockedChild])
    let canvas = SionCanvasView(editorController: controller)

    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.copy(_:))))
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.cut(_:))))
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.delete(_:))))

    controller.select(locked.id)
    XCTAssertTrue(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.copy(_:))))
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.cut(_:))))
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.delete(_:))))

    controller.select(editable.id)
    XCTAssertTrue(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.copy(_:))))
    XCTAssertTrue(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.cut(_:))))
    XCTAssertTrue(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.delete(_:))))

    // Deleting a group also deletes its descendants, so locks below it matter.
    controller.select(group.id)
    XCTAssertTrue(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.copy(_:))))
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.cut(_:))))
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.delete(_:))))
  }

  func testPasteValidationRequiresSupportedContent() throws {
    _ = NSApplication.shared
    let controller = try makeController(elements: [])
    let canvas = SionCanvasView(editorController: controller)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    defer { pasteboard.clearContents() }

    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.paste(_:))))

    pasteboard.declareTypes([TestPasteboard.unsupported], owner: nil)
    pasteboard.setData(Data([1]), forType: TestPasteboard.unsupported)
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.paste(_:))))

    pasteboard.clearContents()
    pasteboard.setString("", forType: .string)
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.paste(_:))))

    pasteboard.clearContents()
    pasteboard.setString("Diagram label", forType: .string)
    XCTAssertTrue(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.paste(_:))))

    pasteboard.clearContents()
    pasteboard.setData(Data(), forType: .pdf)
    XCTAssertFalse(canvas.editMenuItemIsEnabled(action: #selector(SionCanvasView.paste(_:))))
  }

  func testCutDoesNotReplaceClipboardWhenDeletionCannotRun() throws {
    _ = NSApplication.shared
    let group = SceneElement.group(
      id: ElementID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
      frame: SionRect(x: 0, y: 0, width: 100, height: 100)
    )
    var lockedChild = shape(id: "00000000-0000-0000-0000-000000000002")
    lockedChild.parentID = group.id
    lockedChild.lockState = .locked
    let controller = try makeController(elements: [group, lockedChild])
    let canvas = SionCanvasView(editorController: controller)
    let document = controller.document
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(TestPasteboard.existingText, forType: .string)
    defer { pasteboard.clearContents() }
    controller.select(group.id)

    canvas.cut(nil)

    XCTAssertEqual(controller.document, document)
    XCTAssertEqual(pasteboard.string(forType: .string), TestPasteboard.existingText)
  }

  func testCutCopiesAndDeletesEditableSelection() throws {
    _ = NSApplication.shared
    let element = shape(id: "00000000-0000-0000-0000-000000000001")
    var changes = 0
    let controller = try makeController(
      elements: [element],
      didChange: { _ in changes += 1 }
    )
    let canvas = SionCanvasView(editorController: controller)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    defer { pasteboard.clearContents() }
    controller.select(element.id)

    canvas.cut(nil)

    XCTAssertTrue(controller.document.scene.elements.isEmpty)
    XCTAssertEqual(changes, 1)
    let data = try XCTUnwrap(pasteboard.data(forType: TestPasteboard.selection))
    let payload = try SceneSelectionPayload(data: data)
    XCTAssertEqual(payload.elements.map(\.id), [element.id])
  }

  func testArrangeExtremeShortcutsDoNotClaimWindowTabChords() throws {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    let previousWindowsMenu = application.windowsMenu
    let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
    defer {
      for window in application.windows
      where !existingWindows.contains(ObjectIdentifier(window)) {
        (window.windowController?.document as? NSDocument)?.close()
        window.close()
      }

      application.mainMenu = previousMainMenu
      application.windowsMenu = previousWindowsMenu
    }

    let delegate = SionApplicationDelegate()
    delegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification)
    )

    let arrangeMenu = try XCTUnwrap(
      application.mainMenu?.item(withTitle: TestMenu.arrange)?.submenu
    )
    let bringToFront = try XCTUnwrap(arrangeMenu.item(withTitle: TestMenu.bringToFront))
    let bringForward = try XCTUnwrap(arrangeMenu.item(withTitle: TestMenu.bringForward))
    let sendBackward = try XCTUnwrap(arrangeMenu.item(withTitle: TestMenu.sendBackward))
    let sendToBack = try XCTUnwrap(arrangeMenu.item(withTitle: TestMenu.sendToBack))

    XCTAssertEqual(bringToFront.keyEquivalentModifierMask, [.command, .option])
    XCTAssertEqual(sendToBack.keyEquivalentModifierMask, [.command, .option])
    XCTAssertEqual(bringForward.keyEquivalentModifierMask, [.command])
    XCTAssertEqual(sendBackward.keyEquivalentModifierMask, [.command])
  }

  private func makeController(
    elements: [SceneElement],
    didChange: @escaping (SionEditorController.DocumentChange) -> Void = { _ in }
  ) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: elements))
      ),
      undoManagerProvider: { nil },
      didChange: didChange
    )
  }

  private func shape(id: String) -> SceneElement {
    SceneElement.shape(
      id: ElementID(rawValue: UUID(uuidString: id)!),
      frame: SionRect(x: 0, y: 0, width: 50, height: 40)
    )
  }
}

private enum TestMenu {
  static let arrange = "Arrange"
  static let bringToFront = "Bring to Front"
  static let bringForward = "Bring Forward"
  static let sendBackward = "Send Backward"
  static let sendToBack = "Send to Back"
}

private enum TestPasteboard {
  static let existingText = "Existing clipboard"
  static let selection = NSPasteboard.PasteboardType("ch.lkmc.sion.selection")
  static let unsupported = NSPasteboard.PasteboardType("example.unsupported")
}

extension SionCanvasView {
  fileprivate func editMenuItemIsEnabled(action: Selector) -> Bool {
    validateMenuItem(NSMenuItem(title: "Test", action: action, keyEquivalent: ""))
  }
}
