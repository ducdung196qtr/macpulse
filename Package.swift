// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacPulse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacPulseCore", targets: ["MacPulseCore"]),
        .executable(name: "MacPulse", targets: ["MacPulseApp"]),
        .executable(name: "MacPulseTests", targets: ["MacPulseTests"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacPulseCore",
            dependencies: []
        ),
        .executableTarget(
            name: "MacPulseApp",
            dependencies: ["MacPulseCore"]
        ),
        .executableTarget(
            name: "MacPulseTests",
            dependencies: ["MacPulseCore"],
            path: "Tests/MacPulseTests"
        )
    ]
)
