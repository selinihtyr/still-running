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
        // Info.plist is consumed by scripts/bundle.sh, not by SwiftPM.
        .executableTarget(name: "StillRunning", dependencies: ["StillRunningCore"],
                          exclude: ["Info.plist"]),
        .testTarget(name: "ProcessKitTests", dependencies: ["ProcessKit"]),
        .testTarget(name: "DockerClientTests", dependencies: ["DockerClient"]),
        .testTarget(name: "SimulatorSourceTests", dependencies: ["SimulatorSource"]),
        .testTarget(name: "DetectorsTests", dependencies: ["Detectors"]),
        .testTarget(name: "ActionsTests", dependencies: ["Actions"]),
        .testTarget(name: "StillRunningCoreTests", dependencies: ["StillRunningCore"]),
    ]
)
