// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
  .library(name: "SionCore", targets: ["SionCore"])
]

var dependencies: [Package.Dependency] = []

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
  // The shared Lucerne chrome lives in Rigi. macOS-only so the Linux core
  // never resolves a UI package; the branch pin is temporary until the
  // shared-ui work lands on main and a merged revision can be pinned instead.
  dependencies += [
    .package(url: "https://github.com/L-K-M/Rigi.git", branch: "feat/shared-ui")
  ]

  products += [
    .library(name: "SionKit", targets: ["SionKit"]),
    .executable(name: "Sion", targets: ["Sion"]),
  ]

  targets += [
    .target(
      name: "SionKit",
      dependencies: [
        "SionCore",
        .product(name: "RigiUI", package: "rigi"),
      ]
    ),
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
  dependencies: dependencies,
  targets: targets,
  swiftLanguageModes: [.v5]
)
