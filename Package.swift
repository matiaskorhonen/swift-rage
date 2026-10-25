// swift-tools-version: 6.2
import PackageDescription

// The Rust FFI library ships as a prebuilt XCFramework, built by
// scripts/build-xcframework.sh and attached to each GitHub release.
// The release workflow updates these and checks the checksum.
let ffiReleaseURL = "https://github.com/matiaskorhonen/swift-rage/releases/download/0.1.1/SwiftRageFFI.xcframework.zip"
let ffiReleaseChecksum = "85b4d015f28f53ba6f9b415bba68d016d941b996419b8c44d92633d3dc816edc"

// Set SWIFT_RAGE_LOCAL_FFI=1 to use the XCFramework that scripts/build-xcframework.sh
// builds in build/, e.g. after changing the Rust code.
let ffiTarget: Target = if Context.environment["SWIFT_RAGE_LOCAL_FFI"] != nil {
    .binaryTarget(name: "SwiftRageFFI", path: "build/SwiftRageFFI.xcframework")
} else {
    .binaryTarget(name: "SwiftRageFFI", url: ffiReleaseURL, checksum: ffiReleaseChecksum)
}

let package = Package(
    name: "SwiftRage",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "SwiftRage",
            targets: ["SwiftRage"]),
    ],
    targets: [
        ffiTarget,
        .target(
            name: "SwiftRage",
            dependencies: ["SwiftRageFFI"],
            path: "Sources/SwiftRage",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "SwiftRageTests",
            dependencies: ["SwiftRage"],
            path: "Tests/SwiftRageTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
    ]
)
