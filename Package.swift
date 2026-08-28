// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
  .library(name: "SionCore", targets: ["SionCore"])
]

var targets: [Target] = [
  .target(
    name: "SionCore",
    swiftSettings: [.swiftLanguageMode(.v6)]
  ),
  .testTarget(
    name: "SionCoreTests",
    dependencies: ["SionCore"],
    resources: [.copy("Fixtures")],
    swiftSettings: [.swiftLanguageMode(.v6)]
  ),
]

#if os(macOS)
  products += [
    .library(name: "SionKit", targets: ["SionKit"]),
    .executable(name: "Sion", targets: ["Sion"]),
  ]

  targets += [
    .target(name: "SionKit", dependencies: ["SionCore"]),
    .executableTarget(name: "Sion", dependencies: ["SionKit"]),
    .testTarget(
      name: "SionKitTests",
      dependencies: ["SionKit", "SionCore"]
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
