// swift-tools-version: 6.2
import PackageDescription

// The Rust FFI library ships as a prebuilt XCFramework, built by
// scripts/build-xcframework.sh and attached to each GitHub release.
// The release workflow updates these and checks the checksum.
let ffiReleaseURL = "https://github.com/matiaskorhonen/swift-rage/releases/download/0.1.0/SwiftRageFFI.xcframework.zip"
let ffiReleaseChecksum = "dcdb0b306678af72c7b7146422695cf9cddfd7bb4f671d7e00256197e942585c"

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
