// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetNewsWireSimplified",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "NetNewsWireSimplified",
            targets: ["NetNewsWireSimplified"]),
    ],
    targets: [
        .executableTarget(
            name: "NetNewsWireSimplified",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
