// swift-tools-version: 5.9
// PACKAGE.SWIFT DESCRIBES THE NEUROTRACE SWIFT PACKAGE
// IT BUILDS THE NEUROTRACECORE LIBRARY AND ITS TESTS FOR IOS 17 AND MACOS 14

import PackageDescription

// The package, its platforms, the library it makes, and its code and test folders
let package = Package(
    name: "NeuroTrace",
    platforms: [.iOS(.v17), .macOS(.v14)],

    // The NeuroTraceCore library
    products: [
        .library(name: "NeuroTraceCore", targets: ["NeuroTraceCore"]),
    ],

    // The code in NeuroTrace/Core and the tests in NeuroTraceTests
    targets: [
        .target(name: "NeuroTraceCore", path: "NeuroTrace/Core"),
        .testTarget(name: "NeuroTraceTests", dependencies: ["NeuroTraceCore"], path: "NeuroTraceTests"),
    ]
)
