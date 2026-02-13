// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftRage",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "SwiftRage",
            targets: ["SwiftRage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
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
                .unsafeFlags(["-enable-upcoming-feature", "ExistentialAny"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "/home/runner/work/swift-rage/swift-rage/target/release"], .when(platforms: [.linux, .macOS])),
                .linkedLibrary("swift_rage_ffi", .when(platforms: [.linux, .macOS]))
            ],
            plugins: ["RustBuildPlugin"]
        ),
        .testTarget(
            name: "SwiftRageTests",
            dependencies: [
                "SwiftRage",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/SwiftRageTests"
        ),
    ]
)
