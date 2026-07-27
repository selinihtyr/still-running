// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StillRunning",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "StillRunning", targets: ["StillRunning"])
    ],
    targets: [
        .target(name: "ProcessKit"),
        .target(name: "DockerClient"),
        .target(name: "SimulatorSource"),
        .target(name: "Detectors", dependencies: ["ProcessKit"]),
        .target(name: "Actions", dependencies: ["Detectors", "DockerClient", "SimulatorSource"]),
        .target(name: "StillRunningCore", dependencies: ["Actions", "ProcessKit", "DockerClient", "SimulatorSource"]),
        .executableTarget(name: "StillRunning", dependencies: ["StillRunningCore"]),
        .testTarget(name: "ProcessKitTests", dependencies: ["ProcessKit"]),
        .testTarget(name: "DockerClientTests", dependencies: ["DockerClient"]),
        .testTarget(name: "SimulatorSourceTests", dependencies: ["SimulatorSource"]),
        .testTarget(name: "DetectorsTests", dependencies: ["Detectors"]),
        .testTarget(name: "ActionsTests", dependencies: ["Actions"]),
        .testTarget(name: "StillRunningCoreTests", dependencies: ["StillRunningCore"]),
    ]
)
