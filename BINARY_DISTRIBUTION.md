# Binary Distribution

SwiftRage can be distributed as pre-built binaries for faster integration and to avoid the need for Rust toolchain during development.

## Downloading Pre-built Binaries

Binary artifacts are automatically built in CI for every commit to the main branch and every pull request. You can download them from the GitHub Actions artifacts.

### Available Platforms

The binary distribution includes the following platform libraries:

- **macOS Universal** (x86_64 + arm64)
- **iOS** (arm64)
- **iOS Simulator Universal** (x86_64 + arm64)

## Using Pre-built Binaries

1. Download the `SwiftRage-binaries.zip` artifact from GitHub Actions
2. Extract the archive
3. Copy the appropriate library for your platform to your project:
   - macOS: `macos-universal/libswift_rage_ffi.a`
   - iOS Device: `ios-arm64/libswift_rage_ffi.a`
   - iOS Simulator: `ios-simulator-universal/libswift_rage_ffi.a`

4. Update the `LIBRARY_SEARCH_PATHS` in your Xcode project to include the directory containing the library

## Benefits of Binary Distribution

- **Faster Build Times**: No need to compile Rust code during development
- **Simpler Setup**: No Rust toolchain required for using the library
- **CI/CD Optimization**: Reduce build times in continuous integration pipelines

## Building Binaries Locally

To build binaries locally (requires macOS and Rust toolchain):

```bash
./build-binary.sh
```

This will create a `build` directory with:
- Platform-specific libraries
- Universal (fat) libraries for macOS and iOS Simulator
- A distribution archive: `SwiftRage-binaries.zip`

## Notes

- The binary distribution includes all necessary Swift source files and headers
- The `Package.swift` manifest is included for reference
- You'll still need to add SwiftRage as a dependency in your project's `Package.swift` or Xcode project settings
