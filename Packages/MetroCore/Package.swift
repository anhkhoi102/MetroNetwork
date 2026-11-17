// swift-tools-version: 6.0
//
// MetroCore: Metro Network's gameplay logic in pure Swift (Foundation only).
// No SpriteKit, SwiftUI, AppKit or UIKit — the same code runs on macOS and iOS.
//
// Run the tests from the command line:  swift test --package-path Packages/MetroCore

import PackageDescription

let package = Package(
    name: "MetroCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "MetroCore", targets: ["MetroCore"])
    ],
    targets: [
        .target(name: "MetroCore"),
        .testTarget(name: "MetroCoreTests", dependencies: ["MetroCore"])
    ]
)
