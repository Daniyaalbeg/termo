#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/DerivedData}"
PROJECT_PATH="$ROOT/termo.xcodeproj"
SCHEME="${SCHEME:-termo}"

if ! command -v xcodebuild &>/dev/null; then
    echo "ERROR: xcodebuild is required but was not found." >&2
    exit 1
fi

"$ROOT/scripts/setup.sh"

if [ ! -d "$PROJECT_PATH" ]; then
    echo "ERROR: Expected Xcode project at $PROJECT_PATH" >&2
    exit 1
fi

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/termo.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Built app not found at $APP_PATH" >&2
    exit 1
fi

echo "Built app at $APP_PATH"
