#!/usr/bin/env bash
# Builds the Rust extension and installs it where voxelcraft_native.gdextension expects it:
#   native/bin/<platform>/(lib)voxelcraft_native.(dylib|so|dll)
#
#   tools/build_native.sh              # host platform
#   tools/build_native.sh macos        # universal (arm64 + x86_64) macOS library
#   tools/build_native.sh linux-arm64  # cross target (needs the Rust target + linker)
set -euo pipefail
cd "$(dirname "$0")/../native"

platform="${1:-}"
if [ -z "$platform" ]; then
  case "$(uname -s)-$(uname -m)" in
    Darwin-*) platform=macos-host ;;
    Linux-x86_64) platform=linux-x86_64 ;;
    Linux-aarch64|Linux-arm64) platform=linux-arm64 ;;
    MINGW*|MSYS*|CYGWIN*) platform=windows-x86_64 ;;
    *) echo "unknown host $(uname -s)-$(uname -m); pass a platform" >&2; exit 1 ;;
  esac
fi

install_lib() { # source dest_dir name
  mkdir -p "../native/bin/$2"
  # Replace rather than overwrite: on macOS, rewriting a library a running Godot (the editor) has
  # loaded invalidates its code signature and new processes hang loading it.
  rm -f "../native/bin/$2/$3"
  cp "$1" "../native/bin/$2/$3"
  echo "installed native/bin/$2/$3"
}

case "$platform" in
  macos-host)
    cargo build --release
    install_lib target/release/libvoxelcraft_native.dylib macos libvoxelcraft_native.dylib ;;
  macos)
    rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
    cargo build --release --target aarch64-apple-darwin
    cargo build --release --target x86_64-apple-darwin
    mkdir -p ../native/bin/macos
    lipo -create -output ../native/bin/macos/libvoxelcraft_native.dylib \
      target/aarch64-apple-darwin/release/libvoxelcraft_native.dylib \
      target/x86_64-apple-darwin/release/libvoxelcraft_native.dylib
    echo "installed native/bin/macos/libvoxelcraft_native.dylib (universal)" ;;
  linux-x86_64)
    cargo build --release --target x86_64-unknown-linux-gnu
    install_lib target/x86_64-unknown-linux-gnu/release/libvoxelcraft_native.so linux-x86_64 libvoxelcraft_native.so ;;
  linux-arm64)
    cargo build --release --target aarch64-unknown-linux-gnu
    install_lib target/aarch64-unknown-linux-gnu/release/libvoxelcraft_native.so linux-arm64 libvoxelcraft_native.so ;;
  windows-x86_64)
    cargo build --release --target x86_64-pc-windows-msvc
    install_lib target/x86_64-pc-windows-msvc/release/voxelcraft_native.dll windows-x86_64 voxelcraft_native.dll ;;
  *) echo "unknown platform $platform" >&2; exit 1 ;;
esac
