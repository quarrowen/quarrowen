#!/usr/bin/env bash
# Builds the Rust extension and installs it where quarrowen_native.gdextension expects it:
#   native/bin/<platform>/(lib)quarrowen_native.(dylib|so|dll)
#
#   tools/build_native.sh              # host platform
#   tools/build_native.sh macos        # universal (arm64 + x86_64) macOS library
#   tools/build_native.sh linux-arm64  # cross target (needs the Rust target + linker)
#   tools/build_native.sh ios          # device .framework (needs Xcode + the Rust iOS target)
#   tools/build_native.sh ios-sim      # simulator .framework
#   tools/build_native.sh android      # all three ABIs (needs the NDK and cargo-ndk)
set -euo pipefail
cd "$(dirname "$0")/../native"

# Android minimum API. 24 is what Godot 4 targets; raising it drops older tablets.
ANDROID_API="${ANDROID_API:-24}"

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

# **iOS wants a framework, not a bare dylib**, and the dylib has to be linked against clang's iOS
# builtins or QuickJS fails to link: `___chkstk_darwin` is a stack-probe helper the C compiler emits
# and Rust does not pull in for this target. Found the hard way on 2026-09-23.
ios_framework() { # target rt_lib dest_dir
  local rt
  rt="$(dirname "$(find "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang" -name "libclang_rt.$2.a" | head -1)")"
  [ -n "$rt" ] || { echo "no libclang_rt.$2.a under Xcode; is Xcode installed?" >&2; exit 1; }
  RUSTFLAGS="-C link-arg=-L$rt -C link-arg=-lclang_rt.$2" cargo build --release --target "$1"
  local out="../native/bin/$3/quarrowen_native.framework"
  rm -rf "$out"
  mkdir -p "$out"
  cp "target/$1/release/libquarrowen_native.dylib" "$out/quarrowen_native"
  # The id has to match the framework's own path or dyld will not find it inside the app bundle.
  install_name_tool -id "@rpath/quarrowen_native.framework/quarrowen_native" "$out/quarrowen_native"
  cat > "$out/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>quarrowen_native</string>
	<key>CFBundleIdentifier</key><string>org.quarrowen.native</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>quarrowen_native</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>MinimumOSVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
  echo "installed native/bin/$3/quarrowen_native.framework"
}

# Android goes through the NDK's own clang, which cargo-ndk wires up. `ANDROID_NDK_HOME` has to point
# at an installed NDK; `sdkmanager "ndk;<version>"` puts one under the SDK root.
android_abi() { # abi rust_triple dest_dir
  cargo ndk -t "$1" -P "$ANDROID_API" build --release
  install_lib "target/$2/release/libquarrowen_native.so" "$3" libquarrowen_native.so
}

case "$platform" in
  macos-host)
    cargo build --release
    install_lib target/release/libquarrowen_native.dylib macos libquarrowen_native.dylib ;;
  ios)
    rustup target add aarch64-apple-ios >/dev/null
    ios_framework aarch64-apple-ios ios ios ;;
  ios-sim)
    rustup target add aarch64-apple-ios-sim >/dev/null
    ios_framework aarch64-apple-ios-sim iossim ios-sim ;;
  android)
    : "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an installed NDK (sdkmanager \"ndk;<version>\")}"
    command -v cargo-ndk >/dev/null || { echo "cargo-ndk missing: cargo install cargo-ndk" >&2; exit 1; }
    rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android >/dev/null
    android_abi arm64-v8a   aarch64-linux-android   android-arm64
    android_abi armeabi-v7a armv7-linux-androideabi android-arm32
    android_abi x86_64      x86_64-linux-android    android-x86_64 ;;
  macos)
    rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
    cargo build --release --target aarch64-apple-darwin
    cargo build --release --target x86_64-apple-darwin
    mkdir -p ../native/bin/macos
    lipo -create -output ../native/bin/macos/libquarrowen_native.dylib \
      target/aarch64-apple-darwin/release/libquarrowen_native.dylib \
      target/x86_64-apple-darwin/release/libquarrowen_native.dylib
    echo "installed native/bin/macos/libquarrowen_native.dylib (universal)" ;;
  linux-x86_64)
    cargo build --release --target x86_64-unknown-linux-gnu
    install_lib target/x86_64-unknown-linux-gnu/release/libquarrowen_native.so linux-x86_64 libquarrowen_native.so ;;
  linux-arm64)
    cargo build --release --target aarch64-unknown-linux-gnu
    install_lib target/aarch64-unknown-linux-gnu/release/libquarrowen_native.so linux-arm64 libquarrowen_native.so ;;
  windows-x86_64)
    cargo build --release --target x86_64-pc-windows-msvc
    install_lib target/x86_64-pc-windows-msvc/release/quarrowen_native.dll windows-x86_64 quarrowen_native.dll ;;
  *) echo "unknown platform $platform" >&2; exit 1 ;;
esac
