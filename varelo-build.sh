#!/usr/bin/env bash
# Builds the signed arm64 RustDesk APK of this fork on a Mac, the way RustDesk's CI does
# (.github/workflows/bridge.yml and flutter-build.yml, job build-rustdesk-android):
# the Dart/Rust bridge with Flutter 3.22.3, the Rust library with Rust 1.75 and cargo-ndk,
# the video and audio libraries with vcpkg, the APK with Flutter 3.24.5 (patched as CI does).
#
# Tools and caches go to .varelo-build/ next to this script; the first run downloads and
# compiles a lot, later runs reuse it. The APK is signed with the key from
# varelo-signing.sh (~/.rustdesk-varelo-signing); its password is read, never printed.
#
# Usage: ./varelo-build.sh        -> .varelo-build/out/rustdesk-<version>-aarch64-varelo.apk
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
C="$ROOT/.varelo-build"
mkdir -p "$C/out"
cd "$ROOT"

VERSION=$(grep -m1 '^  VERSION:' .github/workflows/flutter-build.yml | sed 's/.*"\(.*\)".*/\1/')
RUST=1.75
SDK="$HOME/Library/Android/sdk"
NDK="$SDK/ndk/28.2.13676358" # r28c, NDK_VERSION in flutter-build.yml
SIGN="$HOME/.rustdesk-varelo-signing"
export ANDROID_NDK_HOME="$NDK" ANDROID_NDK_ROOT="$NDK" ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export CARGO_TARGET_DIR="$ROOT/target"

step() { printf '\n=== %s\n' "$*"; }

[ -d "$NDK" ] || { echo "NDK r28c missing: install 28.2.13676358 in Android Studio's SDK manager"; exit 1; }
[ -f "$SIGN/release.p12" ] || { echo "No signing key: run ./varelo-signing.sh first"; exit 1; }

# Files the build edits temporarily, put back however it ends.
restore() {
    git -C "$ROOT" checkout -- flutter/pubspec.yaml flutter/android/app/build.gradle 2>/dev/null || true
}
trap restore EXIT

step "Submodules"
git submodule update --init --depth 1

step "Rust $RUST, Android target, build tools"
rustup toolchain install "$RUST" --profile minimal -c rustfmt >/dev/null
rustup target add aarch64-linux-android --toolchain "$RUST" >/dev/null
export RUSTUP_TOOLCHAIN="$RUST"
# rustup's cargo and rustc, not a Homebrew Rust that ignores RUSTUP_TOOLCHAIN and has no Android std.
export PATH="$C/cargo/bin:$HOME/.cargo/bin:$PATH"
need() { [ -x "$C/cargo/bin/$1" ] || cargo install "$2" --version "$3" --locked --root "$C/cargo" ${4:-}; }
need cargo-ndk cargo-ndk 3.1.2
need cargo-expand cargo-expand 1.0.95
need flutter_rust_bridge_codegen flutter_rust_bridge_codegen 1.80.1 "--features uuid"

step "Flutter SDKs"
flutter_sdk() {
    local v=$1 d="$C/flutter-$1"
    [ -x "$d/bin/flutter" ] || git clone -q --depth 1 -b "$v" https://github.com/flutter/flutter.git "$d"
    "$d/bin/flutter" --disable-analytics >/dev/null 2>&1 || true
    echo "$d/bin/flutter"
}
FLUTTER_BRIDGE=$(flutter_sdk 3.22.3)
FLUTTER_APK=$(flutter_sdk 3.24.5)
if [ ! -f "$C/flutter-3.24.5/.varelo-patched" ]; then
    git -C "$C/flutter-3.24.5" apply "$ROOT/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff"
    touch "$C/flutter-3.24.5/.varelo-patched"
fi

step "vcpkg libraries for arm64-v8a"
VCPKG_COMMIT=$(grep -m1 'VCPKG_COMMIT_ID:' .github/workflows/flutter-build.yml | sed 's/.*"\(.*\)".*/\1/')
export VCPKG_ROOT="$C/vcpkg"
if [ ! -x "$VCPKG_ROOT/vcpkg" ]; then
    git clone -q https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
    git -C "$VCPKG_ROOT" checkout -q "$VCPKG_COMMIT"
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
fi
./flutter/build_android_deps.sh arm64-v8a

step "Dart/Rust bridge (Flutter 3.22.3)"
# The same downgrade CI makes for 3.22.3: extended_text 14 needs a newer Dart.
sed -i '' -e 's/extended_text: 14.0.0/extended_text: 13.0.0/g' flutter/pubspec.yaml
(cd flutter && "$FLUTTER_BRIDGE" pub get)
PATH="$(dirname "$FLUTTER_BRIDGE"):$PATH" flutter_rust_bridge_codegen \
    --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart \
    --c-output ./flutter/macos/Runner/bridge_generated.h
cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h
git checkout -- flutter/pubspec.yaml

step "Rust library"
# bindgen with the NDK's clang and Android headers: Xcode's has no Android sysroot and fails
# on stdlib.h (RustDesk's Linux CI gets this implicitly).
NDK_LLVM="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
export LIBCLANG_PATH="$NDK_LLVM/lib"
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--target=aarch64-linux-android21 --sysroot=$NDK_LLVM/sysroot"
./flutter/ndk_arm64.sh
JNI=flutter/android/app/src/main/jniLibs/arm64-v8a
mkdir -p "$JNI"
cp "$NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$JNI/"
cp "$CARGO_TARGET_DIR/aarch64-linux-android/release/liblibrustdesk.so" "$JNI/librustdesk.so"

step "APK (Flutter 3.24.5)"
sed -i '' -e 's/signingConfigs.release/signingConfigs.debug/g' flutter/android/app/build.gradle
(cd flutter && "$FLUTTER_APK" pub get && "$FLUTTER_APK" build apk --release --target-platform android-arm64 --split-per-abi)
git checkout -- flutter/android/app/build.gradle

step "Signing"
APKSIGNER=$(ls -d "$SDK"/build-tools/*/apksigner | sort -V | tail -1)
OUT="$C/out/rustdesk-$VERSION-aarch64-varelo.apk"
VARELO_KS_PASS=$(cat "$SIGN/password") "$APKSIGNER" sign \
    --ks "$SIGN/release.p12" --ks-key-alias varelo --ks-pass env:VARELO_KS_PASS \
    --out "$OUT" flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
"$APKSIGNER" verify "$OUT"
step "Done: $OUT"
