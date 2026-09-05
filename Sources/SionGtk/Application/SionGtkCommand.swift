import Foundation

/// Every command Sion's menus send, named in one place so the menu bar, the
/// canvas's context menu, keyboard accelerators, and the code that enables
/// or performs a command all agree, exactly as `AppAction` does on macOS.
///
/// Command shortcuts mirror the macOS menu with Control for Command and Alt
/// for Option; the two toolkit conventions that differ (full screen and help)
/// carry the Linux keys.
package enum SionGtkCommand: String, CaseIterable, Sendable {
  case about
  case actualSize
  case addSelectionToDocumentLibrary
  case addSelectionToGlobalLibrary
  case alignBottom
  case alignCenterHorizontally
  case alignCenterVertically
  case alignLeading
  case alignTop
  case alignTrailing
  case bringForward
  case bringToFront
  case clearRecentDocuments
  case close
  case copy
  case cut
  case delete
  case distributeHorizontally
  case distributeVertically
  case duplicate
  case exportImage
  case exportMermaid
  case exportSVG
  case help
  case hideSelection
  case importMermaid
  case lockSelection
  case minimize
  case newDocument
  case newDocumentFromMermaid
  case open
  case pageSetup
  case paste
  case printDocument
  case quit
  case redo
  case revealHiddenElements
  case revertToSaved
  case save
  case saveAs
  case selectAll
  case sendBackward
  case sendToBack
  case showHistory
  case showInspector
  case showLibrary
  case toggleFullScreen
  case toggleGridVisibility
  case toggleObjectSnapping
  case undo
  case unlockSelection
  case zoomIn
  case zoomOut
  case zoomToFit

  /// Where the `GAction` lives: `app.` actions work with no window open.
  package enum Scope: Sendable {
    case application
    case window
  }

  package var scope: Scope {
    switch self {
    case .about, .clearRecentDocuments, .help, .newDocument, .newDocumentFromMermaid, .open,
      .quit:
      .application
    default:
      .window
    }
  }

  /// The detailed action name a menu item or accelerator activates.
  package var actionName: String {
    switch scope {
    case .application: "app.\(rawValue)"
    case .window: "win.\(rawValue)"
    }
  }

  package var title: String {
    switch self {
    case .about: "About Sion"
    case .actualSize: "Actual Size"
    case .addSelectionToDocumentLibrary: "This Document"
    case .addSelectionToGlobalLibrary: "All Documents"
    case .alignBottom: "Align Bottom"
    case .alignCenterHorizontally: "Align Center Horizontally"
    case .alignCenterVertically: "Align Center Vertically"
    case .alignLeading: "Align Left"
    case .alignTop: "Align Top"
    case .alignTrailing: "Align Right"
    case .bringForward: "Bring Forward"
    case .bringToFront: "Bring to Front"
    case .clearRecentDocuments: "Clear Menu"
    case .close: "Close"
    case .copy: "Copy"
    case .cut: "Cut"
    case .delete: "Delete"
    case .distributeHorizontally: "Distribute Horizontally"
    case .distributeVertically: "Distribute Vertically"
    case .duplicate: "Duplicate"
    case .exportImage: "Export Image…"
    case .exportMermaid: "Export Mermaid…"
    case .exportSVG: "Export SVG…"
    case .help: "Sion Help"
    case .hideSelection: "Hide Selection"
    case .importMermaid: "Import Mermaid…"
    case .lockSelection: "Lock"
    case .minimize: "Minimize"
    case .newDocument: "New"
    case .newDocumentFromMermaid: "New from Mermaid…"
    case .open: "Open…"
    case .pageSetup: "Page Setup…"
    case .paste: "Paste"
    case .printDocument: "Print…"
    case .quit: "Quit Sion"
    case .redo: "Redo"
    case .revealHiddenElements: "Reveal All Hidden"
    case .revertToSaved: "Revert to Saved…"
    case .save: "Save"
    case .saveAs: "Save As…"
    case .selectAll: "Select All"
    case .sendBackward: "Send Backward"
    case .sendToBack: "Send to Back"
    case .showHistory: "History"
    case .showInspector: "Inspector"
    case .showLibrary: "Library"
    case .toggleFullScreen: "Enter Full Screen"
    case .toggleGridVisibility: "Show Grid"
    case .toggleObjectSnapping: "Snap to Objects"
    case .undo: "Undo"
    case .unlockSelection: "Unlock"
    case .zoomIn: "Zoom In"
    case .zoomOut: "Zoom Out"
    case .zoomToFit: "Zoom to Fit"
    }
  }

  /// GTK accelerator strings, in `gtk_accelerator_parse` syntax.
  package var accelerators: [String] {
    switch self {
    case .actualSize: ["<Control>0", "<Control>KP_0"]
    case .bringForward: ["<Control>bracketright"]
    case .bringToFront: ["<Control><Alt>bracketright"]
    case .close: ["<Control>w"]
    case .copy: ["<Control>c"]
    case .cut: ["<Control>x"]
    case .delete: ["Delete", "BackSpace"]
    case .duplicate: ["<Control>d"]
    case .exportSVG: ["<Control><Shift>e"]
    case .help: ["F1", "<Control>question"]
    case .lockSelection: ["<Control><Shift>l"]
    case .minimize: ["<Control>m"]
    case .newDocument: ["<Control>n"]
    case .open: ["<Control>o"]
    case .pageSetup: ["<Control><Shift>p"]
    case .paste: ["<Control>v"]
    case .printDocument: ["<Control>p"]
    case .quit: ["<Control>q"]
    case .redo: ["<Control><Shift>z", "<Control>y"]
    case .save: ["<Control>s"]
    case .saveAs: ["<Control><Shift>s"]
    case .selectAll: ["<Control>a"]
    case .sendBackward: ["<Control>bracketleft"]
    case .sendToBack: ["<Control><Alt>bracketleft"]
    case .showHistory: ["<Control><Alt>y"]
    case .showInspector: ["<Control><Alt>i"]
    case .showLibrary: ["<Control><Alt>l"]
    case .toggleFullScreen: ["F11", "<Control><Alt>f"]
    case .undo: ["<Control>z"]
    case .zoomIn: ["<Control>plus", "<Control>equal", "<Control>KP_Add"]
    case .zoomOut: ["<Control>minus", "<Control>KP_Subtract"]
    case .zoomToFit: ["<Control>1", "<Control>KP_1"]
    default: []
    }
  }

  /// Commands whose menu item shows a check mark for the current state.
  package var isToggle: Bool {
    switch self {
    case .toggleGridVisibility, .toggleObjectSnapping: true
    default: false
    }
  }

  /// The commands the canvas answers for, in both the main and context menus.
  package var isCanvasCommand: Bool {
    switch self {
    case .actualSize, .addSelectionToDocumentLibrary, .addSelectionToGlobalLibrary, .alignBottom,
      .alignCenterHorizontally, .alignCenterVertically, .alignLeading, .alignTop, .alignTrailing,
      .bringForward, .bringToFront, .copy, .cut, .delete, .distributeHorizontally,
      .distributeVertically, .duplicate, .hideSelection, .lockSelection, .paste,
      .revealHiddenElements, .selectAll, .sendBackward, .sendToBack, .toggleGridVisibility,
      .toggleObjectSnapping, .unlockSelection, .zoomIn, .zoomOut, .zoomToFit:
      true
    default:
      false
    }
  }
}

/// A menu tree entry, shared by the menu bar and the canvas's context menu so
/// neither can offer a command the other does not.
package indirect enum SionGtkMenuEntry: Equatable, Sendable {
  case command(SionGtkCommand)
  case separator
  case submenu(title: String, entries: [SionGtkMenuEntry])
  /// A section the application fills in at display time.
  case dynamicSection(SionGtkDynamicMenuSection)
}

package enum SionGtkDynamicMenuSection: Equatable, Sendable {
  case recentDocuments
  case windows
}

package enum SionGtkMenuTree {
  package static let addToLibrary = SionGtkMenuEntry.submenu(
    title: "Add to Library",
    entries: [
      .command(.addSelectionToDocumentLibrary),
      .command(.addSelectionToGlobalLibrary),
    ]
  )

  package static let arrange: [SionGtkMenuEntry] = [
    .command(.bringToFront),
    .command(.bringForward),
    .command(.sendBackward),
    .command(.sendToBack),
    .separator,
    .command(.alignLeading),
    .command(.alignCenterHorizontally),
    .command(.alignTrailing),
    .command(.alignTop),
    .command(.alignCenterVertically),
    .command(.alignBottom),
    .separator,
    .command(.distributeHorizontally),
    .command(.distributeVertically),
  ]

  package static let menuBar: [SionGtkMenuEntry] = [
    .submenu(
      title: "File",
      entries: [
        .command(.newDocument),
        .command(.newDocumentFromMermaid),
        .command(.open),
        .submenu(
          title: "Open Recent",
          entries: [
            .dynamicSection(.recentDocuments),
            .separator,
            .command(.clearRecentDocuments),
          ]
        ),
        .separator,
        .command(.close),
        .command(.save),
        .command(.saveAs),
        .command(.revertToSaved),
        .separator,
        .command(.importMermaid),
        .command(.exportImage),
        .command(.exportSVG),
        .command(.exportMermaid),
        .separator,
        .command(.pageSetup),
        .command(.printDocument),
        .separator,
        .command(.quit),
      ]
    ),
    .submenu(
      title: "Edit",
      entries: [
        .command(.undo),
        .command(.redo),
        .separator,
        .command(.cut),
        .command(.copy),
        .command(.paste),
        .command(.duplicate),
        .command(.delete),
        .separator,
        addToLibrary,
        .separator,
        .command(.selectAll),
      ]
    ),
    .submenu(
      title: "Arrange",
      entries: arrange + [
        .separator,
        .command(.lockSelection),
        .command(.unlockSelection),
        .command(.hideSelection),
        .command(.revealHiddenElements),
      ]
    ),
    .submenu(
      title: "View",
      entries: [
        .command(.zoomIn),
        .command(.zoomOut),
        .command(.actualSize),
        .command(.zoomToFit),
        .separator,
        .command(.toggleGridVisibility),
        .command(.toggleObjectSnapping),
        .separator,
        .command(.showInspector),
        .command(.showLibrary),
        .command(.showHistory),
        .separator,
        .command(.toggleFullScreen),
      ]
    ),
    .submenu(
      title: "Window",
      entries: [
        .command(.minimize),
        .separator,
        .dynamicSection(.windows),
      ]
    ),
    .submenu(
      title: "Help",
      entries: [
        .command(.help),
        .command(.about),
      ]
    ),
  ]

  /// The canvas's right-click menu: the same commands as the main menu.
  package static let canvasContextMenu: [SionGtkMenuEntry] = [
    .command(.cut),
    .command(.copy),
    .command(.paste),
    .command(.duplicate),
    .command(.delete),
    .separator,
    addToLibrary,
    .separator,
    .submenu(title: "Arrange", entries: arrange),
    .command(.lockSelection),
    .command(.unlockSelection),
    .command(.hideSelection),
    .command(.revealHiddenElements),
    .separator,
    .command(.selectAll),
    .command(.toggleGridVisibility),
    .command(.toggleObjectSnapping),
    .command(.zoomToFit),
  ]
}
