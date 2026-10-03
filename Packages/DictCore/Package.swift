// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
  name: "DictCore",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "DictCore", targets: ["DictCore"])
  ],
  targets: [
    .target(name: "DictCore"),
    .testTarget(name: "DictCoreTests", dependencies: ["DictCore"]),
  ]
)
