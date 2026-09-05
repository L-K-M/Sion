// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
  .library(name: "SionCore", targets: ["SionCore"]),
  .library(name: "SionKit", targets: ["SionKit"]),
]

var targets: [Target] = [
  .target(
    name: "SionCore",
    swiftSettings: [.swiftLanguageMode(.v6)]
  ),
  // The AppKit document UI lives behind `#if canImport(AppKit)`; the editor
  // controller, feedback, and library storage compile everywhere so the
  // native Linux application shares them.
  .target(name: "SionKit", dependencies: ["SionCore"]),
  .testTarget(
    name: "SionCoreTests",
    dependencies: ["SionCore"],
    resources: [.copy("Fixtures")],
    swiftSettings: [.swiftLanguageMode(.v6)]
  ),
]

#if os(macOS)
  products += [
    .executable(name: "Sion", targets: ["Sion"])
  ]

  targets += [
    .executableTarget(name: "Sion", dependencies: ["SionKit"]),
    .testTarget(
      name: "SionKitTests",
      dependencies: ["SionKit", "SionCore"]
    ),
  ]
#endif

#if os(Linux)
  products += [
    .library(name: "SionGtk", targets: ["SionGtk"]),
    .executable(name: "sion", targets: ["SionLinux"]),
    .executable(name: "sion-icon-tool", targets: ["SionIconTool"]),
  ]

  targets += [
    .systemLibrary(
      name: "CGtk",
      pkgConfig: "libadwaita-1",
      providers: [.apt(["libadwaita-1-dev", "libgtk-4-dev"])]
    ),
    .systemLibrary(
      name: "CPoppler",
      pkgConfig: "poppler-glib",
      providers: [.apt(["libpoppler-glib-dev"])]
    ),
    .target(name: "CSionGtkShim", dependencies: ["CGtk"]),
    .target(
      name: "SionGtk",
      dependencies: ["SionKit", "SionCore", "CGtk", "CPoppler", "CSionGtkShim"]
    ),
    .executableTarget(name: "SionLinux", dependencies: ["SionGtk"]),
    // Renders the icon theme at packaging time; it is not installed.
    .executableTarget(name: "SionIconTool", dependencies: ["SionGtk", "CGtk"]),
    .testTarget(
      name: "SionGtkTests",
      dependencies: ["SionGtk", "SionKit", "SionCore"]
    ),
    // The editor controller tests need no AppKit; they run against the shared
    // controller here so both applications verify the same editing rules.
    .testTarget(
      name: "SionKitPortableTests",
      dependencies: ["SionKit", "SionCore"],
      path: "Tests/SionKitTests",
      exclude: [
        "Application/SionApplicationDelegateTests.swift",
        "Application/SionFileMenuCommandTests.swift",
        "Application/SionHelpBookTests.swift",
        "Application/SionOpenRecentMenuTests.swift",
        "Application/SionRevertMenuTests.swift",
        "Assets",
        "Canvas",
        "Document",
        "Editing/SionEditorControllerArrangeTests.swift",
        "Export",
        "Inspector",
        "Library",
        "Panels",
        "Printing",
      ],
      sources: [
        "Application/ApplicationArchiveMetadataTests.swift",
        "Editing/SionEditorControllerAnchorEditingTests.swift",
        "Editing/SionEditorControllerInsertionTests.swift",
        "Editing/SionEditorControllerRenderContextTests.swift",
        "Editing/SionEditorControllerRouteCacheTests.swift",
        "Editing/SionEditorControllerSelectionTests.swift",
        "Editing/SionEditorControllerShadowTests.swift",
        "Editing/SionEditorControllerTextEditingTests.swift",
        "Editing/SionEditorControllerToolPersistenceTests.swift",
        "Editing/SionEditorControllerTransformTests.swift",
        "LinuxSupport/MainActorTestCase.swift",
      ]
    ),
  ]
#endif

let package = Package(
  name: "Sion",
  platforms: [.macOS(.v13)],
  products: products,
  targets: targets,
  swiftLanguageModes: [.v5]
)
