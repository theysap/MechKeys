// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MechKeys",
    platforms: [.macOS(.v14)],
    targets: [
        // All application logic lives in the library target so it can be unit
        // tested. The executable is a thin @main shim, because SwiftPM test
        // targets cannot cleanly @testable import an executable target.
        .target(name: "MechKeysCore"),
        .executableTarget(name: "MechKeys", dependencies: ["MechKeysCore"]),
        .testTarget(name: "MechKeysCoreTests", dependencies: ["MechKeysCore"]),
    ]
)
