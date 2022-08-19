// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AsyncSwiftGit",
  platforms: [.iOS(.v13), .macOS(.v11)],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .library(
      name: "AsyncSwiftGit",
      targets: ["AsyncSwiftGit", "Initializer"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/bdewey/static-libgit2", from: "0.4.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.1.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages this package depends on.
    .target(
      name: "AsyncSwiftGit",
      dependencies: [
        "static-libgit2",
        "Initializer",
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: [
        //        .unsafeFlags(["-warnings-as-errors"]),
      ]
    ),
    .target(name: "Initializer", dependencies: ["static-libgit2"]),
    .testTarget(
      name: "AsyncSwiftGitTests",
      dependencies: ["AsyncSwiftGit"],
      swiftSettings: [
        //        .unsafeFlags(["-warnings-as-errors"]),
      ]
    ),
  ]
)
