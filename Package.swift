// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MiNoteMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MiNoteMac", targets: ["MiNoteMac"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "MiNoteMac",
            path: "Sources/MiNoteMac"
        ),
    ]
)
