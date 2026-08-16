// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexSwitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexSwitch", targets: ["CodexSwitch"]),
        .executable(name: "CodexSwitchProbe", targets: ["CodexSwitchProbe"])
    ],
    targets: [
        .target(
            name: "CodexSwitchCore",
            path: "Core"
        ),
        .executableTarget(
            name: "CodexSwitch",
            dependencies: ["CodexSwitchCore"],
            path: "App"
        ),
        .executableTarget(
            name: "CodexSwitchProbe",
            dependencies: ["CodexSwitchCore"],
            path: "Probe"
        ),
        .testTarget(
            name: "CodexSwitchCoreTests",
            dependencies: ["CodexSwitchCore", "CodexSwitch"],
            path: "Tests"
        )
    ]
)
