// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RichTextKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "RichTextKit",
            targets: ["RichTextKit"]
        )
    ],
    dependencies: [
        // MockingKit 仅在测试中使用，暂时移除以避免网络依赖问题
        // .package(
        //     url: "https://github.com/danielsaidi/MockingKit.git",
        //     .upToNextMajor(from: "1.5.0")
        // )
    ],
    targets: [
        .target(
            name: "RichTextKit",
            dependencies: [],
            resources: [.process("Resources")],
            swiftSettings: [
                .define("macOS", .when(platforms: [.macOS])),
                .define("iOS", .when(platforms: [.iOS, .macCatalyst]))
            ]
        ),
        .testTarget(
            name: "RichTextKitTests",
            dependencies: ["RichTextKit"], // MockingKit 暂时移除
            swiftSettings: [
                .define("macOS", .when(platforms: [.macOS])),
                .define("iOS", .when(platforms: [.iOS, .macCatalyst]))
            ]
        )
    ]
)
