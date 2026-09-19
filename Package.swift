// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MechKeys",
    // macOS 26 is the floor: the interface is built on Liquid Glass, which
    // does not exist before it. Built and run against the 26 and 27 SDKs.
    platforms: [.macOS(.v26)],
    targets: [
        // All application logic lives in the library target so it can be unit
        // tested. The executable is a thin @main shim, because SwiftPM test
        // targets cannot cleanly @testable import an executable target.
        .target(
            name: "MechKeysCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "MechKeys",
            dependencies: ["MechKeysCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MechKeysCoreTests",
            dependencies: ["MechKeysCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
