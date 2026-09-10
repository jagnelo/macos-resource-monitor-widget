// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResourceMonitorWidget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ResourceMonitorWidget", targets: ["ResourceMonitorWidget"])
    ],
    targets: [
        .executableTarget(
            name: "ResourceMonitorWidget",
            path: "Sources/ResourceMonitorWidget"
        ),
        .testTarget(
            name: "ResourceMonitorWidgetTests",
            dependencies: ["ResourceMonitorWidget"],
            path: "Tests/ResourceMonitorWidgetTests"
        )
    ]
)
