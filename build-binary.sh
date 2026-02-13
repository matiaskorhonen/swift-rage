#!/bin/bash
set -e

# Build script for creating distributable binaries
# This script builds the SwiftRage library for multiple platforms

FRAMEWORK_NAME="SwiftRage"
OUTPUT_DIR="./build"

echo "Building ${FRAMEWORK_NAME} binaries for distribution..."

# Clean previous builds
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Generate Swift bindings first
echo "Generating Swift bindings..."
cargo run --manifest-path bindings-gen/Cargo.toml
mkdir -p Sources/SwiftRage
cp generated/swift_rage.swift Sources/SwiftRage/
cp generated/swift_rageFFI.h swift-rage-ffi/
cp generated/swift_rageFFI.modulemap swift-rage-ffi/module.modulemap

# Build the Rust library for different architectures
echo "Building Rust library for different architectures..."

# Build for macOS x86_64
echo "Building for macOS x86_64..."
rustup target add x86_64-apple-darwin
cargo build --release --manifest-path swift-rage-ffi/Cargo.toml --target x86_64-apple-darwin
mkdir -p "${OUTPUT_DIR}/macos-x86_64"
cp target/x86_64-apple-darwin/release/libswift_rage_ffi.a "${OUTPUT_DIR}/macos-x86_64/"

# Build for macOS arm64
echo "Building for macOS arm64..."
rustup target add aarch64-apple-darwin
cargo build --release --manifest-path swift-rage-ffi/Cargo.toml --target aarch64-apple-darwin
mkdir -p "${OUTPUT_DIR}/macos-arm64"
cp target/aarch64-apple-darwin/release/libswift_rage_ffi.a "${OUTPUT_DIR}/macos-arm64/"

# Build for iOS arm64
echo "Building for iOS arm64..."
rustup target add aarch64-apple-ios
cargo build --release --manifest-path swift-rage-ffi/Cargo.toml --target aarch64-apple-ios
mkdir -p "${OUTPUT_DIR}/ios-arm64"
cp target/aarch64-apple-ios/release/libswift_rage_ffi.a "${OUTPUT_DIR}/ios-arm64/"

# Build for iOS Simulator x86_64
echo "Building for iOS Simulator x86_64..."
rustup target add x86_64-apple-ios
cargo build --release --manifest-path swift-rage-ffi/Cargo.toml --target x86_64-apple-ios
mkdir -p "${OUTPUT_DIR}/ios-simulator-x86_64"
cp target/x86_64-apple-ios/release/libswift_rage_ffi.a "${OUTPUT_DIR}/ios-simulator-x86_64/"

# Build for iOS Simulator arm64
echo "Building for iOS Simulator arm64..."
rustup target add aarch64-apple-ios-sim
cargo build --release --manifest-path swift-rage-ffi/Cargo.toml --target aarch64-apple-ios-sim
mkdir -p "${OUTPUT_DIR}/ios-simulator-arm64"
cp target/aarch64-apple-ios-sim/release/libswift_rage_ffi.a "${OUTPUT_DIR}/ios-simulator-arm64/"

# Create universal libraries for macOS
echo "Creating universal library for macOS..."
mkdir -p "${OUTPUT_DIR}/macos-universal"
lipo -create \
  target/x86_64-apple-darwin/release/libswift_rage_ffi.a \
  target/aarch64-apple-darwin/release/libswift_rage_ffi.a \
  -output "${OUTPUT_DIR}/macos-universal/libswift_rage_ffi.a"

# Create universal libraries for iOS Simulator
echo "Creating universal library for iOS Simulator..."
mkdir -p "${OUTPUT_DIR}/ios-simulator-universal"
lipo -create \
  target/x86_64-apple-ios/release/libswift_rage_ffi.a \
  target/aarch64-apple-ios-sim/release/libswift_rage_ffi.a \
  -output "${OUTPUT_DIR}/ios-simulator-universal/libswift_rage_ffi.a"

# Copy Swift source files
echo "Copying Swift source files..."
cp -r Sources "${OUTPUT_DIR}/"
cp -r swift-rage-ffi "${OUTPUT_DIR}/"
cp Package.swift "${OUTPUT_DIR}/"

# Create distribution zip
echo "Creating distribution archive..."
cd "${OUTPUT_DIR}"
zip -r "${FRAMEWORK_NAME}-binaries.zip" \
  macos-universal \
  ios-arm64 \
  ios-simulator-universal \
  Sources \
  swift-rage-ffi \
  Package.swift
cd ..

echo "Build complete!"
echo "Distribution archive: ${OUTPUT_DIR}/${FRAMEWORK_NAME}-binaries.zip"
echo ""
echo "The following platform binaries are available:"
echo "  - macOS Universal (x86_64 + arm64): ${OUTPUT_DIR}/macos-universal/libswift_rage_ffi.a"
echo "  - iOS (arm64): ${OUTPUT_DIR}/ios-arm64/libswift_rage_ffi.a"
echo "  - iOS Simulator Universal (x86_64 + arm64): ${OUTPUT_DIR}/ios-simulator-universal/libswift_rage_ffi.a"
