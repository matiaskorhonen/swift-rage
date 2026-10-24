#!/bin/bash
# Builds the Rust FFI library into build/SwiftRageFFI.xcframework (and a zip of it
# for releases), and regenerates the vendored UniFFI Swift bindings in
# Sources/SwiftRage/Generated.
#
# Usage: scripts/build-xcframework.sh
#
# Needs Rust (rustup) and Xcode. Missing Rust targets are installed with rustup.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
CARGO_TARGET_DIR="$ROOT/target"
LIB_NAME="libswift_rage_ffi.a"
FRAMEWORK_NAME="SwiftRageFFI"
MODULE_NAME="swift_rageFFI"

TARGETS=(
    aarch64-apple-darwin
    x86_64-apple-darwin
    aarch64-apple-ios
    aarch64-apple-ios-sim
    x86_64-apple-ios
)

# Run cargo with a minimal environment: build settings exported by Xcode or SwiftPM
# (e.g. MACOSX_DEPLOYMENT_TARGET) break rustc's loading of proc-macro crates.
run_cargo() {
    env -i PATH="$PATH" HOME="$HOME" \
        ${CARGO_HOME:+CARGO_HOME="$CARGO_HOME"} \
        ${RUSTUP_HOME:+RUSTUP_HOME="$RUSTUP_HOME"} \
        ${RUSTUP_TOOLCHAIN:+RUSTUP_TOOLCHAIN="$RUSTUP_TOOLCHAIN"} \
        CARGO_TARGET_DIR="$CARGO_TARGET_DIR" \
        cargo "$@"
}

installed_targets="$(rustup target list --installed)"
for target in "${TARGETS[@]}"; do
    if ! grep -qx "$target" <<<"$installed_targets"; then
        rustup target add "$target"
    fi
done

for target in "${TARGETS[@]}"; do
    echo "==> Building swift-rage-ffi for $target"
    run_cargo build --release --locked -p swift-rage-ffi --target "$target"
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/macos" "$BUILD_DIR/ios" "$BUILD_DIR/ios-simulator" "$BUILD_DIR/bindings"

echo "==> Generating Swift bindings"
run_cargo run --release --locked -p bindings-gen -- \
    "$ROOT/swift-rage-ffi/src/swift_rage.udl" "$BUILD_DIR/bindings"

# Keep the generated FFI layer out of SwiftRage's public API
mkdir -p "$ROOT/Sources/SwiftRage/Generated"
sed -E 's/^public /internal /' "$BUILD_DIR/bindings/swift_rage.swift" \
    > "$ROOT/Sources/SwiftRage/Generated/swift_rage.swift"

# The headers go in a subdirectory named after the module, so that the modulemap
# doesn't clash with other XCFrameworks' modulemaps in an Xcode build.
HEADERS_DIR="$BUILD_DIR/headers"
mkdir -p "$HEADERS_DIR/$MODULE_NAME"
cp "$BUILD_DIR/bindings/$MODULE_NAME.h" "$HEADERS_DIR/$MODULE_NAME/"
cp "$BUILD_DIR/bindings/$MODULE_NAME.modulemap" "$HEADERS_DIR/$MODULE_NAME/module.modulemap"

echo "==> Creating universal libraries"
cp "$CARGO_TARGET_DIR/aarch64-apple-ios/release/$LIB_NAME" "$BUILD_DIR/ios/$LIB_NAME"
lipo -create \
    "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/$LIB_NAME" \
    "$CARGO_TARGET_DIR/x86_64-apple-darwin/release/$LIB_NAME" \
    -output "$BUILD_DIR/macos/$LIB_NAME"
lipo -create \
    "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/$LIB_NAME" \
    "$CARGO_TARGET_DIR/x86_64-apple-ios/release/$LIB_NAME" \
    -output "$BUILD_DIR/ios-simulator/$LIB_NAME"

# Debug info (mostly from Rust's standard library) is over half of the libraries' size
for platform in macos ios ios-simulator; do
    strip -S "$BUILD_DIR/$platform/$LIB_NAME"
done

echo "==> Creating $FRAMEWORK_NAME.xcframework"
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/macos/$LIB_NAME" -headers "$HEADERS_DIR" \
    -library "$BUILD_DIR/ios/$LIB_NAME" -headers "$HEADERS_DIR" \
    -library "$BUILD_DIR/ios-simulator/$LIB_NAME" -headers "$HEADERS_DIR" \
    -output "$BUILD_DIR/$FRAMEWORK_NAME.xcframework"

(cd "$BUILD_DIR" && zip -qry "$FRAMEWORK_NAME.xcframework.zip" "$FRAMEWORK_NAME.xcframework")

checksum="$(cd "$ROOT" && swift package compute-checksum "$BUILD_DIR/$FRAMEWORK_NAME.xcframework.zip")"
echo
echo "XCFramework: $BUILD_DIR/$FRAMEWORK_NAME.xcframework"
echo "Zip:         $BUILD_DIR/$FRAMEWORK_NAME.xcframework.zip"
echo "Checksum:    $checksum"
