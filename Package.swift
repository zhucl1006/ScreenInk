// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenInk",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ScreenInkCore",
            targets: ["ScreenInkCore"]
        ),
        .executable(
            name: "ScreenInk",
            targets: ["ScreenInkApp"]
        )
    ],
    targets: [
        .target(
            name: "ScreenInkCore",
            path: "Sources/ScreenInkCore"
        ),
        .executableTarget(
            name: "ScreenInkApp",
            dependencies: ["ScreenInkCore"],
            path: "Sources/ScreenInkApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "ScreenInkCoreTests",
            dependencies: ["ScreenInkCore"],
            path: "Tests/ScreenInkCoreTests"
        )
    ]
)
