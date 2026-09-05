# Feature parity: macOS and Linux

Sion ships one application per platform over one shared editing model. This
table is the contract that keeps them functionally identical: every
user-visible feature lists the file that implements it on each platform, and
every deliberate difference is recorded with its reason. A change to a row on
one side is not finished until the other side and this file follow.

Shared code (compiled into both applications): `Sources/SionCore` and the
unguarded files of `Sources/SionKit` — `Editing/SionEditorController.swift`
(commands, selection, tools, transactions, undo registration, assets, routes),
`Editing/SionEditorFeedback.swift`, `Editing/SionMermaidInsertion.swift`,
`Editing/SceneElementNaming.swift`, `Library/SionGlobalLibrary.swift`,
`Document/SionMermaidFile.swift` (source reading and errors),
`Rendering/SionColorBridge.swift` (`SionPaperColor`), and on Linux
`Editing/SionUndoManager.swift`, which carries Foundation's undo-manager
contract that swift-corelibs-foundation lacks.

## Application

| Feature | macOS (`Sources/SionKit`, `Sources/Sion`) | Linux (`Sources/SionGtk`) |
| --- | --- | --- |
| Entry point, activation, untitled document on launch, reopen | `Application/SionApplicationDelegate.swift`, `Sion/SionMain.swift` | `Application/SionGtkApplication.swift` (`SionGtkApplicationCoordinator`) |
| Command names shared by menus, shortcuts, and the context menu | `Application/AppAction.swift` | `Application/SionGtkCommand.swift` (`SionGtkCommand`, `SionGtkMenuTree`) |
| Main menu: File, Edit, Arrange, View, Window, Help | `SionMainMenu` in `SionApplicationDelegate.swift` | `SionGtkMenuTree.menuBar`, built into a `GtkPopoverMenuBar` in each window |
| Keyboard shortcuts | Command-based key equivalents | Control-based accelerators (`SionGtkCommand.accelerators`): ⌘ → Ctrl, ⌥ → Alt |
| Open Recent with Clear Menu | `Application/SionRecentDocumentsMenuController.swift` | `Application/SionGtkRecentDocuments.swift` over `GtkRecentManager` |
| About | AppKit standard about panel | `AdwAboutDialog` with the shared version metadata |
| Help | Help Book `Resources/Sion.help` | The same `index.html`, installed to `/usr/share/sion/help` and opened with the default browser |
| Version metadata stamped into archives | `Application/ApplicationArchiveMetadata.swift` reading the bundle | Same type reading `Info.plist` from `/usr/share/sion` (`Application/SionGtkResources.swift`) |
| Quit with unsaved changes | AppKit document termination | `SionGtkDocumentController.terminate` runs each document's close check |

## Document and window

| Feature | macOS | Linux |
| --- | --- | --- |
| Document lifecycle: new, open, save, save as, revert, close | `Document/SionDrawingDocument.swift`, `Document/SionDocumentController.swift` | `Document/SionGtkDocument.swift`, `Document/SionGtkDocumentController.swift` |
| Autosave in place; untitled documents ask before closing | `NSDocument.autosavesInPlace` | Debounced autosave after edits and on close; the same Save / Delete / Cancel question for untitled documents |
| Archive read and write, preview PNG, committed history | `data(ofType:)`, `write(to:…)` | `SionGtkDocument.archive(intent:savedTitle:)`, `write(to:intent:)` |
| Import Mermaid, New from Mermaid | `importMermaid(_:)`, `SionMermaidFile.makeOpenPanel()` | `SionGtkDocument.importMermaid()`, `SionGtkDialogs.open` with the same copy |
| Export SVG, Export Mermaid with coverage warning | `exportSVG(_:)`, `exportMermaid(_:)`, `MermaidExportWarning` | Same methods and copy in `SionGtkDocument.swift` |
| Export Image (PNG, JPEG, TIFF, PDF; 1x–3x; transparency) | `Export/SionSceneImageExporter.swift`, save-panel accessory `Export/SionImageExportAccessoryView.swift` | `Export/SionGtkSceneImageExporter.swift`; options are asked in `Export/SionGtkImageExportOptionsDialog.swift` before the GTK file chooser, which has no accessory view |
| Print scaled to one page, Page Setup | `Printing/SionScenePrintView.swift`, `printOperation(withSettings:)` | `Printing/SionGtkPrintOperation.swift` over `GtkPrintOperation` |
| Window: toolbar tools, zoom controls, palette buttons, title | `Document/SionDocumentWindowController.swift` | `Document/SionGtkDocumentWindow.swift` (header bar), `Document/SionGtkToolGlyph.swift` |
| One click arms a tool once; double click keeps it | `selectTool(_:clickCount:)` | Same rule with GTK's double-click time |
| Zoom: 0.1–8.0, step 1.2, fit at 0.88 | Window controller over `NSScrollView.magnification` | Canvas owns the zoom (`SionGtkCanvasView`); the window shows the percentage |
| Error presentation | `NSDocument.presentError` | `SionGtkDialogs.presentError` (`AdwAlertDialog`) |

## Canvas

| Feature | macOS (`Canvas/SionCanvasView.swift`) | Linux (`Canvas/`) |
| --- | --- | --- |
| Scene rendering, grid, selection chrome, previews | `SionCanvasView` drawing | `SionGtkCanvasView` drawing with Cairo and Pango |
| Tools, gestures, snapping, anchors, connectors | `SionCanvasView` event handling | `SionGtkCanvasView` gesture and key controllers |
| Inline text editing | Field editor `NSTextView` | `GtkTextView` overlay |
| Clipboard and paste precedence, drag and drop | `NSPasteboard`, dragging destination | `GdkClipboard`, `GtkDropTarget` |
| Context menu | `Canvas/SionCanvasContextMenu.swift` | `SionGtkMenuTree.canvasContextMenu` in a `GtkPopoverMenu` |
| Image import pipeline (bounded PNG rendition, original kept) | `Assets/SafeImageRenditionBuilder.swift` (ImageIO, PDF via Core Graphics) | `Assets/SionGtkImageRendition.swift` (GdkPixbuf, SVG via librsvg, PDF via poppler) |

## Palettes

| Feature | macOS | Linux |
| --- | --- | --- |
| Palette framework: popover, tear-off floating panel, retargeting | `Panels/Palette.swift`, `PaletteCenter.swift`, `PalettePanel.swift`, `PaletteTypes.swift` | `Panels/SionGtkPaletteCenter.swift` and neighbours |
| Inspector and History | `Inspector/SionPalettes.swift` | `Inspector/` |
| Library (document and global) | `Library/LibraryPaletteController.swift`, shared `SionGlobalLibrary` | `Library/`, shared `SionGlobalLibrary` (stored under `$XDG_DATA_HOME/Sion/Library`) |
| Feedback banner | `Panels/SionEditorFeedbackPresenter.swift` | `Panels/SionGtkEditorFeedbackPresenter.swift` |

## Platform differences

Each entry is deliberate; anything else that differs is a bug.

- Shortcuts use Control and Alt where macOS uses Command and Option. Full
  screen is F11 (also Ctrl+Alt+F) and Help is F1 (also Ctrl+?), the desktop's
  conventions.
- The menu bar lives inside each document window; there is no Services, Find,
  Spelling and Grammar, Hide, or Show All entry because the desktop provides
  none of those roles.
- Export Image asks for format, scale, and background in its own dialog before
  the file chooser, which cannot host an accessory view.
- The process quits when its last window closes: with no global menu bar there
  would be nothing left to act on.
- Help opens the same HTML page in the default browser instead of Help Viewer;
  the packaged copy says Ctrl where the macOS book says Command.
- Toolbar layout is fixed; macOS lets the toolbar be customised. The History
  button is therefore always present on Linux.
