#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <BASELINE_DIR> <APP_DIR>" >&2
  exit 1
fi

BASELINE_DIR="$1"
APP_DIR="$2"

if [ ! -d "$BASELINE_DIR" ]; then
  echo "Error: Baseline directory does not exist: $BASELINE_DIR" >&2
  exit 1
fi

if [ ! -d "$APP_DIR" ]; then
  echo "Error: App directory does not exist: $APP_DIR" >&2
  exit 1
fi

PNG_COUNT=$(find "$BASELINE_DIR" -type f -name "*.png" | wc -l | tr -d ' ')

if [ "$PNG_COUNT" -eq 0 ]; then
  echo "Error: Baseline directory is empty. Run generate first." >&2
  exit 1
fi

rsync -a --include='*/' --include='*.png' --exclude='*' "$BASELINE_DIR/test/" "$APP_DIR/test/"

echo "Synced $PNG_COUNT baseline PNG(s) from $BASELINE_DIR to $APP_DIR"
