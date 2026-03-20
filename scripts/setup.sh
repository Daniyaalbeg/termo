#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "=== termo setup ==="

require_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' is required but was not found." >&2
        exit 1
    fi
}

require_command git
require_command npm

ZIG_BIN="${ZIG_BIN:-zig}"
if [ -x "$ROOT/.tooling/zig-aarch64-macos-0.15.2/zig" ]; then
    ZIG_BIN="$ROOT/.tooling/zig-aarch64-macos-0.15.2/zig"
fi

if [ -z "${TOOLCHAINS:-}" ] && command -v xcodebuild &>/dev/null; then
    METAL_TOOLCHAIN_JSON="$(xcodebuild -showComponent MetalToolchain -json 2>/dev/null || true)"
    METAL_TOOLCHAIN_ID="$(
        printf '%s\n' "$METAL_TOOLCHAIN_JSON" \
            | sed -n 's/.*"toolchainIdentifier" : "\(.*\)".*/\1/p' \
            | head -n 1
    )"
    if [ -n "$METAL_TOOLCHAIN_ID" ]; then
        export TOOLCHAINS="$METAL_TOOLCHAIN_ID"
        echo "Using Metal toolchain: $TOOLCHAINS"
    fi
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
    echo "Preparing web shell..."
    cd "$ROOT/electrobun"
    if [ ! -d node_modules ]; then
        if [ -f package-lock.json ]; then
            npm ci
        else
            npm install
        fi
    else
        echo "Web dependencies already installed."
    fi
    echo "Building web shell..."
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
if [ ! -d "$ROOT/termo.xcodeproj" ] && ! command -v xcodegen &>/dev/null; then
    echo ""
    echo "ERROR: termo.xcodeproj is missing and xcodegen is not installed." >&2
    echo "Install it with: brew install xcodegen" >&2
    exit 1
elif command -v xcodegen &>/dev/null; then
    echo "Generating Xcode project..."
    xcodegen generate
    echo "termo.xcodeproj generated."
else
    echo ""
    echo "xcodegen not found. Using the checked-in termo.xcodeproj."
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "To build and run:"
echo "  npm run build"
echo "  npm start"
