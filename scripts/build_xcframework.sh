#!/usr/bin/env bash
set -euo pipefail

# Build RCLI engine as xcframework for the macOS app.
# Usage: bash scripts/build_xcframework.sh [--debug]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build-xcframework"
OUTPUT_DIR="$ROOT_DIR/app"
BUILD_TYPE="Release"

if [[ "${1:-}" == "--debug" ]]; then
    BUILD_TYPE="Debug"
fi

echo "=== Building RCLI engine ($BUILD_TYPE) ==="

# Step 1: CMake configure + build (static libs only, no shared)
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake "$ROOT_DIR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DRCLI_BUILD_STATIC=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF

cmake --build . -j"$(sysctl -n hw.ncpu)" --target rcli

echo "=== Merging static libraries ==="

# Step 2: Collect all static libs that rcli depends on
LIBS=()

# librcli itself
[[ -f "$BUILD_DIR/librcli.a" ]] && LIBS+=("$BUILD_DIR/librcli.a")

# llama.cpp / ggml static libs (may be in bin/ or llama.cpp/ subdir)
while IFS= read -r lib; do
    LIBS+=("$lib")
done < <(find "$BUILD_DIR/llama.cpp" "$BUILD_DIR/bin" -name "*.a" -type f 2>/dev/null | grep -v CMakeLTOTest | sort -u)

# sherpa-onnx and its deps (lib/ subdir when built static)
while IFS= read -r lib; do
    LIBS+=("$lib")
done < <(find "$BUILD_DIR/lib" "$BUILD_DIR/sherpa-onnx" -name "*.a" -type f 2>/dev/null | grep -v CMakeLTOTest | sort -u)

# FetchContent deps (_deps/)
while IFS= read -r lib; do
    LIBS+=("$lib")
done < <(find "$BUILD_DIR/_deps" -name "*.a" -type f 2>/dev/null | grep -v CMakeLTOTest | sort -u)

echo "Found ${#LIBS[@]} static libraries to merge"
for lib in "${LIBS[@]}"; do
    echo "  $lib ($(du -h "$lib" | cut -f1))"
done

# Step 3: Merge into single static lib
MERGED_LIB="$BUILD_DIR/librcli_merged.a"
libtool -static -o "$MERGED_LIB" "${LIBS[@]}"
echo "Merged → $MERGED_LIB ($(du -h "$MERGED_LIB" | cut -f1))"

# Step 4: Create xcframework
FRAMEWORK_OUTPUT="$OUTPUT_DIR/RCLIEngine.xcframework"
rm -rf "$FRAMEWORK_OUTPUT"
mkdir -p "$OUTPUT_DIR"

# Collect all public headers
HEADERS_DIR="$BUILD_DIR/xcframework-headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"
cp "$ROOT_DIR/src/api/rcli_api.h" "$HEADERS_DIR/"
cp "$ROOT_DIR/src/bridge/rcli_overlay_bridge.h" "$HEADERS_DIR/"
cp "$ROOT_DIR/src/bridge/rcli_paste_bridge.h" "$HEADERS_DIR/"
cp "$ROOT_DIR/src/bridge/rcli_caret_bridge.h" "$HEADERS_DIR/"

# Create module.modulemap for Swift import
cat > "$HEADERS_DIR/module.modulemap" <<'MODULEMAP'
module CRCLIEngine {
    header "rcli_api.h"
    header "rcli_overlay_bridge.h"
    header "rcli_paste_bridge.h"
    header "rcli_caret_bridge.h"
    export *
}
MODULEMAP

xcodebuild -create-xcframework \
    -library "$MERGED_LIB" \
    -headers "$HEADERS_DIR" \
    -output "$FRAMEWORK_OUTPUT"

echo "=== xcframework created ==="
echo "$FRAMEWORK_OUTPUT"

# Step 5: Copy Metal shaders if present
METALLIB=$(find "$BUILD_DIR" -name "ggml-metal.metallib" -type f | head -1)
if [[ -n "$METALLIB" ]]; then
    RESOURCES_DIR="$OUTPUT_DIR/RCLI/Resources"
    mkdir -p "$RESOURCES_DIR"
    cp "$METALLIB" "$RESOURCES_DIR/ggml-metal.metallib"
    echo "Copied Metal shaders → $RESOURCES_DIR/ggml-metal.metallib"

    # Also copy default.metallib if it exists
    DEFAULT_METALLIB=$(find "$BUILD_DIR" -name "default.metallib" -type f | head -1)
    if [[ -n "$DEFAULT_METALLIB" ]]; then
        cp "$DEFAULT_METALLIB" "$RESOURCES_DIR/default.metallib"
        echo "Copied default.metallib → $RESOURCES_DIR/"
    fi
fi

echo "=== Done ==="
echo "xcframework: $FRAMEWORK_OUTPUT"
echo "Next: open app/RCLI.xcodeproj and add the xcframework"
