import AppKit
import XCTest

@testable import SionCore
@testable import SionKit

@MainActor
final class InspectorPaletteTests: XCTestCase {
  func testLockedSelectionDisablesAndCanUnlockInspector() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    var shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    shape.name = "Process"
    shape.lockState = .locked
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(shape.id)
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
    let descendants = try XCTUnwrap(panel.contentView).inspectorTestDescendants
    let lockButton = try XCTUnwrap(
      descendants.compactMap { $0 as? NSButton }.first { $0.title == "Locked" }
    )
    let colorWells = descendants.compactMap { $0 as? NSColorWell }
    let widthSlider = try XCTUnwrap(descendants.compactMap { $0 as? NSSlider }.first)
    let nameField = try XCTUnwrap(
      descendants.compactMap { $0 as? NSTextField }.first {
        $0.accessibilityLabel() == "Element name"
      }
    )
    let anchorPopup = try XCTUnwrap(
      descendants.compactMap { $0 as? NSPopUpButton }.first {
        $0.toolTip == "Choose where connectors attach to the selected object."
      }
    )

    XCTAssertEqual(lockButton.state, .on)
    XCTAssertTrue(colorWells.allSatisfy { !$0.isEnabled })
    XCTAssertFalse(widthSlider.isEnabled)
    XCTAssertFalse(nameField.isEnabled)
    XCTAssertEqual(nameField.stringValue, "Process")
    XCTAssertFalse(anchorPopup.isEnabled)

    lockButton.performClick(nil)

    XCTAssertEqual(editor.document.scene.element(withID: shape.id)?.lockState, .editable)
    XCTAssertTrue(colorWells.allSatisfy { $0.isEnabled })
    XCTAssertTrue(widthSlider.isEnabled)
    XCTAssertTrue(nameField.isEnabled)
    XCTAssertTrue(anchorPopup.isEnabled)
  }

  func testMultipleSelectionExposesNoInspectorMutation() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    var lockedShape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    lockedShape.lockState = .locked
    let editableShape = SceneElement.shape(
      frame: SionRect(x: 240, y: 40, width: 160, height: 90)
    )
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [lockedShape, editableShape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(lockedShape.id)
    editor.select(editableShape.id, mode: .extend)
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
    let descendants = try XCTUnwrap(panel.contentView).inspectorTestDescendants
    let lockButton = try XCTUnwrap(
      descendants.compactMap { $0 as? NSButton }.first { $0.title == "Locked" }
    )

    XCTAssertFalse(lockButton.isEnabled)
    XCTAssertTrue(descendants.compactMap { $0 as? NSColorWell }.allSatisfy { !$0.isEnabled })
    XCTAssertTrue(descendants.compactMap { $0 as? NSSlider }.allSatisfy { !$0.isEnabled })
    XCTAssertTrue(descendants.compactMap { $0 as? NSPopUpButton }.allSatisfy { !$0.isEnabled })
  }

  func testMixedNamesEditAsOneUndoStep() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    var first = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    first.name = "First"
    var second = SceneElement.shape(
      frame: SionRect(x: 240, y: 40, width: 160, height: 90)
    )
    second.name = "Second"
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [first, second]))
      ),
      undoManagerProvider: { undoManager },
      didChange: { _ in }
    )
    editor.select([first.id, second.id])
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
    let nameField = try XCTUnwrap(
      try XCTUnwrap(panel.contentView).inspectorTestDescendants
        .compactMap { $0 as? NSTextField }
        .first { $0.accessibilityLabel() == "Element name" }
    )

    XCTAssertTrue(nameField.isEnabled)
    XCTAssertEqual(nameField.stringValue, "")
    XCTAssertEqual(nameField.placeholderString, "Mixed")

    let sentUntouchedAction = NSApp.sendAction(
      try XCTUnwrap(nameField.action),
      to: nameField.target,
      from: nameField
    )

    XCTAssertTrue(sentUntouchedAction)
    XCTAssertEqual(editor.document.scene.element(withID: first.id)?.name, "First")
    XCTAssertEqual(editor.document.scene.element(withID: second.id)?.name, "Second")
    XCTAssertFalse(undoManager.canUndo)

    nameField.stringValue = "Shared"
    undoManager.beginUndoGrouping()
    let sentAction = NSApp.sendAction(
      try XCTUnwrap(nameField.action),
      to: nameField.target,
      from: nameField
    )
    undoManager.endUndoGrouping()

    XCTAssertTrue(sentAction)

    XCTAssertEqual(editor.document.scene.element(withID: first.id)?.name, "Shared")
    XCTAssertEqual(editor.document.scene.element(withID: second.id)?.name, "Shared")
    XCTAssertEqual(undoManager.undoActionName, "Rename Elements")
    XCTAssertEqual(nameField.stringValue, "Shared")
    XCTAssertNil(nameField.placeholderString)

    undoManager.undo()

    XCTAssertEqual(editor.document.scene.element(withID: first.id)?.name, "First")
    XCTAssertEqual(editor.document.scene.element(withID: second.id)?.name, "Second")
  }

  func testEscapeCancelsMixedNameEdit() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    var first = SceneElement.shape(frame: SionRect(x: 40, y: 40, width: 160, height: 90))
    first.name = "First"
    var second = SceneElement.shape(frame: SionRect(x: 60, y: 60, width: 160, height: 90))
    second.name = "Second"
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [first, second]))
      ),
      undoManagerProvider: { undoManager },
      didChange: { _ in }
    )
    editor.select([first.id, second.id])
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
    let nameField = try XCTUnwrap(
      try XCTUnwrap(panel.contentView).inspectorTestDescendants
        .compactMap { $0 as? NSTextField }
        .first { $0.accessibilityLabel() == "Element name" }
    )

    XCTAssertTrue(panel.makeFirstResponder(nameField))
    let fieldEditor = try XCTUnwrap(nameField.currentEditor() as? NSTextView)
    fieldEditor.selectAll(nil)
    fieldEditor.insertText("Shared", replacementRange: fieldEditor.selectedRange())

    // Escape cancels the edit: the field reverts and editing ends.
    fieldEditor.doCommandBy(#selector(NSResponder.cancelOperation(_:)))
    XCTAssertTrue(panel.makeFirstResponder(nil))

    XCTAssertEqual(editor.document.scene.element(withID: first.id)?.name, "First")
    XCTAssertEqual(editor.document.scene.element(withID: second.id)?.name, "Second")
    XCTAssertFalse(undoManager.canUndo)
    XCTAssertEqual(nameField.stringValue, "")
    XCTAssertEqual(nameField.placeholderString, "Mixed")
  }

  func testSingleNameClearsAndCommitsOnFocusLoss() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    var shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    shape.name = "First"
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { undoManager },
      didChange: { _ in }
    )
    editor.select(shape.id)
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
    let descendants = try XCTUnwrap(panel.contentView).inspectorTestDescendants
    let nameField = try XCTUnwrap(
      descendants.compactMap { $0 as? NSTextField }.first {
        $0.accessibilityLabel() == "Element name"
      }
    )
    let lockButton = try XCTUnwrap(
      descendants.compactMap { $0 as? NSButton }.first { $0.title == "Locked" }
    )

    nameField.stringValue = ""
    undoManager.beginUndoGrouping()
    XCTAssertTrue(
      NSApp.sendAction(try XCTUnwrap(nameField.action), to: nameField.target, from: nameField)
    )
    undoManager.endUndoGrouping()

    XCTAssertNil(editor.document.scene.element(withID: shape.id)?.name)

    undoManager.undo()

    XCTAssertEqual(editor.document.scene.element(withID: shape.id)?.name, "First")

    undoManager.beginUndoGrouping()
    XCTAssertTrue(panel.makeFirstResponder(nameField))
    let fieldEditor = try XCTUnwrap(nameField.currentEditor() as? NSTextView)
    fieldEditor.selectAll(nil)
    fieldEditor.insertText("Tabbed", replacementRange: fieldEditor.selectedRange())
    XCTAssertTrue(panel.makeFirstResponder(lockButton))
    undoManager.endUndoGrouping()

    XCTAssertEqual(editor.document.scene.element(withID: shape.id)?.name, "Tabbed")
    XCTAssertEqual(undoManager.undoActionName, "Rename Element")
  }

  func testRejectedInspectorEditRestoresDisplayedValue() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    let connector = SceneElement.connector(
      source: .free(SionPoint(x: 40, y: 80)),
      target: .free(SionPoint(x: 240, y: 80)),
      routingStyle: .orthogonal
    )
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [connector]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(connector.id)
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
    let routePopup = try XCTUnwrap(
      panel.contentView?.inspectorTestDescendants.compactMap { $0 as? NSPopUpButton }
        .first { $0.accessibilityLabel() == "Connector route" }
    )
    let documentBefore = editor.document
    try editor.beginMove()
    defer { editor.cancelActiveGesture() }

    let straightItem = try XCTUnwrap(
      routePopup.itemArray.first {
        $0.representedObject as? String == ConnectorRoutingStyle.straight.rawValue
      }
    )
    routePopup.select(straightItem)
    let action = try XCTUnwrap(routePopup.action)

    XCTAssertTrue(
      NSApp.sendAction(action, to: try XCTUnwrap(routePopup.target), from: routePopup)
    )
    XCTAssertEqual(editor.document, documentBefore)
    XCTAssertTrue(editor.hasPendingEditorGesture)
    XCTAssertEqual(
      routePopup.selectedItem?.representedObject as? String,
      ConnectorRoutingStyle.orthogonal.rawValue
    )
  }

  func testFloatingInspectorObservesDocumentSelection() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    var shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    shape.name = "Process"
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    let documentController = SionDocumentWindowController(editorController: editor)
    defer { documentController.close() }

    let documentWindow = try XCTUnwrap(documentController.window)
    documentWindow.orderFrontRegardless()
    let inspector = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.inspector.paletteKind)
    )
    defer { inspector.close() }

    inspector.showPanel()

    editor.select(shape.id)

    let panel = try XCTUnwrap(
      NSApp.windows.first { $0.title == "Inspector" && $0.isVisible }
    )
    let labels = try XCTUnwrap(panel.contentView).inspectorTestDescendants.compactMap {
      ($0 as? NSTextField)?.stringValue
    }
    XCTAssertTrue(labels.contains("Process"))
  }

  func testCustomAnchorModeEndsWithDoneOrPanelClose() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    let shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(shape.id)
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
    let descendants = try XCTUnwrap(panel.contentView).inspectorTestDescendants
    let anchorPopup = try XCTUnwrap(
      descendants.compactMap { $0 as? NSPopUpButton }.first {
        $0.toolTip == "Choose where connectors attach to the selected object."
      }
    )
    anchorPopup.selectItem(withTitle: "Custom points…")
    let action = try XCTUnwrap(anchorPopup.action)

    XCTAssertTrue(NSApp.sendAction(action, to: anchorPopup.target, from: anchorPopup))
    XCTAssertEqual(editor.anchorEditingState, .editing(shape.id))

    let instruction = descendants.compactMap { $0 as? NSTextField }.first {
      $0.stringValue == "Click the object to add an anchor; click an anchor to remove it."
    }
    let done = descendants.compactMap { $0 as? NSButton }.first { $0.title == "Done" }
    XCTAssertFalse(try XCTUnwrap(instruction).isHidden)
    XCTAssertFalse(try XCTUnwrap(done).isHidden)

    done?.performClick(nil)

    XCTAssertEqual(editor.anchorEditingState, .inactive)

    anchorPopup.selectItem(withTitle: "Custom points…")
    XCTAssertTrue(NSApp.sendAction(action, to: anchorPopup.target, from: anchorPopup))
    XCTAssertEqual(editor.anchorEditingState, .editing(shape.id))

    inspector.close()

    XCTAssertEqual(editor.anchorEditingState, .inactive)
  }

  func testCustomAnchorOptionPromotesPopoverToPanel() throws {
    _ = NSApplication.shared
    let previousServicesMenu = NSApp.servicesMenu
    defer { NSApp.servicesMenu = previousServicesMenu }

    let shape = SceneElement.shape(
      frame: SionRect(x: 40, y: 40, width: 160, height: 90)
    )
    let editor = try SionEditorController(
      package: SionPackage(
        document: SionDocument(scene: SionScene(elements: [shape]))
      ),
      undoManagerProvider: { nil },
      didChange: { _ in }
    )
    editor.select(shape.id)
    let documentController = SionDocumentWindowController(editorController: editor)
    defer { documentController.close() }

    let documentWindow = try XCTUnwrap(documentController.window)
    let contentView = try XCTUnwrap(documentWindow.contentView)
    let anchor = NSButton(frame: NSRect(x: 20, y: 20, width: 24, height: 24))
    contentView.addSubview(anchor)
    documentWindow.orderFrontRegardless()

    let inspector = try XCTUnwrap(
      PaletteCenter.shared.registeredPalette(for: SionPaletteKind.inspector.paletteKind)
    )
    defer { inspector.close() }
    inspector.present(from: anchor)

    let anchorPopup = try XCTUnwrap(
      NSApp.windows.lazy.filter(\.isVisible).compactMap(\.contentView)
        .flatMap(\.inspectorTestDescendants)
        .compactMap { $0 as? NSPopUpButton }
        .first { $0.toolTip == "Choose where connectors attach to the selected object." }
    )
    anchorPopup.selectItem(withTitle: "Custom points…")
    let action = try XCTUnwrap(anchorPopup.action)

    XCTAssertTrue(NSApp.sendAction(action, to: anchorPopup.target, from: anchorPopup))
    runMainLoop(until: { inspector.isFloating })

    XCTAssertTrue(inspector.isFloating)
    XCTAssertEqual(editor.anchorEditingState, .editing(shape.id))
  }

  private func runMainLoop(until condition: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: TestTiming.presentationTimeout)
    while !condition(), Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: TestTiming.pollInterval))
    }
  }
}

private enum TestTiming {
  static let presentationTimeout = 2.0
  static let pollInterval = 0.01
}

extension NSView {
  fileprivate var inspectorTestDescendants: [NSView] {
    subviews + subviews.flatMap(\.inspectorTestDescendants)
  }
}
