// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MiNoteMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MiNoteMac", targets: ["MiNoteMacApp"]) // 最终产物
    ],
    targets: [
        // 1. 这里放你所有的 SwiftUI 视图和业务逻辑 (普通 Target)
        .target(
            name: "MiNoteLibrary",
            path: "Sources/MiNoteLibrary"
        ),
        // 2. 这里只放一个 App 入口文件 (可执行 Target)
        .executableTarget(
            name: "MiNoteMacApp",
            dependencies: ["MiNoteLibrary"],
            path: "Sources/MiNoteMac"
        ),
    ]
)
