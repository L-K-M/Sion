// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
  .library(name: "SionCore", targets: ["SionCore"])
]

var targets: [Target] = [
  .target(name: "SionCore"),
  .testTarget(
    name: "SionCoreTests",
    dependencies: ["SionCore"],
    resources: [.copy("Fixtures")]
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
  ]
#endif

let package = Package(
  name: "Sion",
  platforms: [.macOS(.v13)],
  products: products,
  targets: targets,
  swiftLanguageModes: [.v5]
)
