// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

// Builds the instant dictionary `dict-en-zh.sqlite` from pinned public data snapshots
// (architecture 7.2). Independent of the app: no dependencies beyond the system SDK.
let package = Package(
  name: "BuildDict",
  platforms: [.macOS(.v15)],
  targets: [
    .target(name: "DictBuild", linkerSettings: [.linkedLibrary("sqlite3")]),
    .executableTarget(name: "build-dict", dependencies: ["DictBuild"]),
    .testTarget(
      name: "DictBuildTests", dependencies: ["DictBuild"], resources: [.copy("Fixtures")]),
  ]
)
