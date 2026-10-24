// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NeuroTrace",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NeuroTraceCore", targets: ["NeuroTraceCore"]),
    ],
    targets: [
        .target(name: "NeuroTraceCore", path: "NeuroTrace/Core"),
        .testTarget(name: "NeuroTraceTests", dependencies: ["NeuroTraceCore"], path: "NeuroTraceTests"),
    ]
)
