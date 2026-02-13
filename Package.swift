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
        .target(
            name: "SwiftRageFFI",
            dependencies: [],
            path: "swift-rage-ffi",
            exclude: ["src"],
            sources: [],
            publicHeadersPath: "."
        ),
        .target(
            name: "SwiftRage",
            dependencies: ["SwiftRageFFI"],
            path: "Sources/SwiftRage",
            swiftSettings: [
                .unsafeFlags(["-enable-upcoming-feature", "ExistentialAny"])
            ]
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
