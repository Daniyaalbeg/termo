#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
APP_PATH="${APP_PATH:-$ROOT/DerivedData/Build/Products/$CONFIGURATION/termo.app}"

"$ROOT/scripts/build.sh"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Built app not found at $APP_PATH" >&2
    exit 1
fi

echo "Opening $APP_PATH"
open "$APP_PATH"
