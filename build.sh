#!/bin/bash
set -e

# Build script for SwiftRage
# This script builds the Rust library and generates Swift bindings

echo "Building Rust library..."
cargo build --release --manifest-path swift-rage-ffi/Cargo.toml

echo "Generating Swift bindings..."
cargo run --manifest-path bindings-gen/Cargo.toml

echo "Copying generated files to Swift package..."
mkdir -p Sources/SwiftRage
cp generated/swift_rage.swift Sources/SwiftRage/
cp generated/swift_rageFFI.h swift-rage-ffi/
cp generated/swift_rageFFI.modulemap swift-rage-ffi/module.modulemap

echo "Build complete!"
echo "Library location: target/release/libswift_rage_ffi.a"
