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
    let pasteboard = testPasteboard()
    let canvas = SionCanvasView(editorController: controller, pasteboard: pasteboard)

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

  func testPasteValidationRejectsEmptySupportedFile() throws {
    _ = NSApplication.shared
    let controller = try makeController(elements: [])
    let pasteboard = testPasteboard()
    let canvas = SionCanvasView(editorController: controller, pasteboard: pasteboard)
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(TestPasteboard.imageFileExtension)
    try Data().write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }
    XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))

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
    let pasteboard = testPasteboard()
    let canvas = SionCanvasView(editorController: controller, pasteboard: pasteboard)
    let document = controller.document
    pasteboard.setString(TestPasteboard.existingText, forType: .string)
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
    let pasteboard = testPasteboard()
    let canvas = SionCanvasView(editorController: controller, pasteboard: pasteboard)
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
    let previousServicesMenu = application.servicesMenu
    let previousWindowsMenu = application.windowsMenu
    defer {
      application.mainMenu = previousMainMenu
      application.servicesMenu = previousServicesMenu
      application.windowsMenu = previousWindowsMenu
    }

    let delegate: NSApplicationDelegate = SionApplicationDelegate()
    delegate.applicationWillFinishLaunching?(
      Notification(name: NSApplication.willFinishLaunchingNotification)
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

  func testShowGridMenuTogglesCanvasAndTracksUndoState() throws {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    let previousServicesMenu = application.servicesMenu
    let previousWindowsMenu = application.windowsMenu
    defer {
      application.mainMenu = previousMainMenu
      application.servicesMenu = previousServicesMenu
      application.windowsMenu = previousWindowsMenu
    }

    let delegate: NSApplicationDelegate = SionApplicationDelegate()
    delegate.applicationWillFinishLaunching?(
      Notification(name: NSApplication.willFinishLaunchingNotification)
    )

    let originalCanvas = SionCanvas(
      extent: .fixed(SionSize(width: 640, height: 480)),
      background: SionColor(red: 0.2, green: 0.3, blue: 0.4),
      grid: CanvasGrid(visibility: .hidden, spacing: 37, subdivisions: 7)
    )
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    var changes: [SionEditorController.DocumentChange] = []
    let controller = try makeController(
      elements: [],
      canvas: originalCanvas,
      undoManager: undoManager,
      didChange: { changes.append($0) }
    )
    let canvas = SionCanvasView(editorController: controller)
    let viewMenu = try XCTUnwrap(
      application.mainMenu?.item(withTitle: TestMenu.view)?.submenu
    )
    let showGrid = try XCTUnwrap(viewMenu.item(withTitle: TestMenu.showGrid))

    XCTAssertEqual(showGrid.action, TestAction.toggleGridVisibility)
    XCTAssertTrue(canvas.validateMenuItem(showGrid))
    XCTAssertEqual(showGrid.state, .off)

    undoManager.beginUndoGrouping()
    XCTAssertTrue(
      application.sendAction(
        TestAction.toggleGridVisibility,
        to: canvas,
        from: showGrid
      )
    )
    undoManager.endUndoGrouping()

    var visibleCanvas = originalCanvas
    visibleCanvas.grid.visibility = .visible
    XCTAssertEqual(controller.document.scene.canvas, visibleCanvas)
    XCTAssertEqual(changes.count, 1)
    guard case .done? = changes.last else {
      return XCTFail("Show Grid must report a completed document change")
    }
    XCTAssertEqual(undoManager.undoActionName, TestAction.showGridUndoName)
    XCTAssertTrue(canvas.validateMenuItem(showGrid))
    XCTAssertEqual(showGrid.state, .on)

    undoManager.undo()

    XCTAssertEqual(controller.document.scene.canvas, originalCanvas)
    XCTAssertEqual(changes.count, 2)
    guard case .undone? = changes.last else {
      return XCTFail("Undo must report an undone document change")
    }
    XCTAssertTrue(canvas.validateMenuItem(showGrid))
    XCTAssertEqual(showGrid.state, .off)

    undoManager.redo()

    XCTAssertEqual(controller.document.scene.canvas, visibleCanvas)
    XCTAssertEqual(changes.count, 3)
    guard case .redone? = changes.last else {
      return XCTFail("Redo must report a redone document change")
    }
    XCTAssertTrue(canvas.validateMenuItem(showGrid))
    XCTAssertEqual(showGrid.state, .on)

    undoManager.beginUndoGrouping()
    XCTAssertTrue(
      application.sendAction(
        TestAction.toggleGridVisibility,
        to: canvas,
        from: showGrid
      )
    )
    undoManager.endUndoGrouping()

    XCTAssertEqual(controller.document.scene.canvas, originalCanvas)
    XCTAssertEqual(changes.count, 4)
    guard case .done? = changes.last else {
      return XCTFail("Hide Grid must report a completed document change")
    }
    XCTAssertEqual(undoManager.undoActionName, TestAction.hideGridUndoName)
    XCTAssertTrue(canvas.validateMenuItem(showGrid))
    XCTAssertEqual(showGrid.state, .off)
  }

  func testShowGridMenuIsDisabledDuringInlineTextEditing() throws {
    _ = NSApplication.shared
    let text = SceneElement.text(
      frame: SionRect(x: 40, y: 40, width: 180, height: 80),
      text: "Draft"
    )
    let controller = try makeController(elements: [text])
    let canvas = SionCanvasView(editorController: controller)
    let showGrid = NSMenuItem()
    showGrid.action = TestAction.toggleGridVisibility

    canvas.beginTextEditing(text.id)
    defer { canvas.discardPendingEdits() }

    XCTAssertFalse(canvas.validateMenuItem(showGrid))
    XCTAssertEqual(showGrid.state, .off)
  }

  private func makeController(
    elements: [SceneElement],
    canvas: SionCanvas = SionCanvas(),
    undoManager: UndoManager? = nil,
    didChange: @escaping (SionEditorController.DocumentChange) -> Void = { _ in }
  ) throws -> SionEditorController {
    try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(canvas: canvas, elements: elements))
      ),
      undoManagerProvider: { undoManager },
      didChange: didChange
    )
  }

  private func shape(id: String) -> SceneElement {
    SceneElement.shape(
      id: ElementID(rawValue: UUID(uuidString: id)!),
      frame: SionRect(x: 0, y: 0, width: 50, height: 40)
    )
  }

  private func testPasteboard() -> NSPasteboard {
    NSPasteboard(
      name: NSPasteboard.Name(
        rawValue: "ch.lkmc.sion.tests.\(UUID().uuidString)"
      )
    )
  }
}

private enum TestMenu {
  static let arrange = "Arrange"
  static let bringToFront = "Bring to Front"
  static let bringForward = "Bring Forward"
  static let sendBackward = "Send Backward"
  static let sendToBack = "Send to Back"
  static let showGrid = "Show Grid"
  static let view = "View"
}

private enum TestAction {
  static let hideGridUndoName = "Hide Grid"
  static let showGridUndoName = "Show Grid"
  static let toggleGridVisibility = NSSelectorFromString("toggleGridVisibility:")
}

private enum TestPasteboard {
  static let existingText = "Existing clipboard"
  static let imageFileExtension = "png"
  static let selection = NSPasteboard.PasteboardType("ch.lkmc.sion.selection")
  static let unsupported = NSPasteboard.PasteboardType("example.unsupported")
}

extension SionCanvasView {
  fileprivate func editMenuItemIsEnabled(action: Selector) -> Bool {
    validateMenuItem(NSMenuItem(title: "Test", action: action, keyEquivalent: ""))
  }
}
