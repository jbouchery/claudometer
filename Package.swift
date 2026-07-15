// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Claudometer",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudometerCore", path: "Sources/ClaudometerCore"),
        .executableTarget(name: "Claudometer", dependencies: ["ClaudometerCore"], path: "Sources/Claudometer"),
        .executableTarget(name: "EvaluateCheck", dependencies: ["ClaudometerCore"], path: "Checks/EvaluateCheck")
    ]
)
