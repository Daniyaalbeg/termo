#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "=== termo setup ==="

ZIG_BIN="${ZIG_BIN:-zig}"
if [ -x "$ROOT/.tooling/zig-aarch64-macos-0.15.2/zig" ]; then
    ZIG_BIN="$ROOT/.tooling/zig-aarch64-macos-0.15.2/zig"
fi

# 1. Initialize ghostty submodule
if [ ! -f ghostty/build.zig ]; then
    echo "Initializing ghostty submodule..."
    git submodule update --init --recursive ghostty
else
    echo "Ghostty submodule already initialized."
fi

# 2. Build web shell
if [ -f "$ROOT/electrobun/package.json" ]; then
    echo "Building web shell..."
    cd "$ROOT/electrobun"
    npm run build
    cd "$ROOT"
fi

# 3. Build GhosttyKit xcframework
XCFRAMEWORK="$ROOT/ghostty/macos/GhosttyKit.xcframework"
if [ -d "$XCFRAMEWORK" ]; then
    echo "GhosttyKit.xcframework already exists, skipping build."
    echo "  (delete $XCFRAMEWORK and re-run to rebuild)"
else
    echo "Building GhosttyKit.xcframework (this takes a few minutes)..."
    echo "Using Zig: $ZIG_BIN"
    cd ghostty
    "$ZIG_BIN" build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
    cd "$ROOT"
    echo "GhosttyKit.xcframework built successfully."
fi

# 4. Generate Xcode project (requires xcodegen)
if command -v xcodegen &>/dev/null; then
    echo "Generating Xcode project..."
    xcodegen generate
    echo "termo.xcodeproj generated."
else
    echo ""
    echo "WARNING: xcodegen not found. Install it to generate the Xcode project:"
    echo "  brew install xcodegen"
    echo "  xcodegen generate"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "To build and run:"
echo "  open termo.xcodeproj"
echo "  # or: xcodebuild -project termo.xcodeproj -scheme termo -configuration Debug build"
