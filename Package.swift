// swift-tools-version: 6.2
import Foundation
import PackageDescription

// RustBuildPlugin builds the Rust static library into its plugin work directory.
// SwiftPM gives plugins no way to pass libraries to the linker, so point the
// linker at that directory here. Set SWIFT_RAGE_LIB_DIR to override it, e.g.
// when building with a custom --scratch-path.
let packageIdentity = URL(fileURLWithPath: Context.packageDirectory).lastPathComponent.lowercased()
let rustLibraryDirectory = Context.environment["SWIFT_RAGE_LIB_DIR"]
    ?? "\(Context.packageDirectory)/.build/plugins/outputs/\(packageIdentity)/SwiftRage/destination/RustBuildPlugin/cargo/release"

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
        .plugin(
            name: "RustBuildPlugin",
            capability: .buildTool()
        ),
        .systemLibrary(
            name: "SwiftRageFFI",
            path: "swift-rage-ffi",
            pkgConfig: nil,
            providers: nil
        ),
        .target(
            name: "SwiftRage",
            dependencies: ["SwiftRageFFI"],
            path: "Sources/SwiftRage",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", rustLibraryDirectory]),
                .linkedLibrary("swift_rage_ffi"),
            ],
            plugins: ["RustBuildPlugin"]
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
