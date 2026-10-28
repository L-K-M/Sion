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
  // Keep the reviewed UI revision outside the portable core's dependency graph.
  dependencies += [
    .package(
      url: "https://github.com/L-K-M/Rigi.git",
      revision: "8b569d0bad1e2137e087428c52e22f0bed241c6d"
    )
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
