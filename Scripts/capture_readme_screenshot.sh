#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LLimit"
DEST="$ROOT/Resources/screenshot.png"

"$BIN" --readme-snapshot "$DEST"
cp "$DEST" "$ROOT/website/screenshot.png"

echo "Wrote $DEST"
echo "Wrote $ROOT/website/screenshot.png"
