#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <APP_DIR> <BASELINE_DIR>" >&2
  exit 1
fi

APP_DIR="$1"
BASELINE_DIR="$2"

if [[ ! -d "$APP_DIR/test/golden_test" ]]; then
  echo "Error: $APP_DIR/test/golden_test does not exist" >&2
  exit 1
fi

rm -rf "$BASELINE_DIR/test"

count=0
while IFS= read -r -d '' png_file; do
  rel_path="${png_file#"$APP_DIR/"}"
  target_dir="$BASELINE_DIR/$(dirname "$rel_path")"
  mkdir -p "$target_dir"
  cp "$png_file" "$target_dir/"
  ((count++))
done < <(find "$APP_DIR/test/golden_test" -type f -name "*.png" -path "*/goldens/*.png" -print0)

if [[ $count -eq 0 ]]; then
  echo "Error: No golden PNGs found in $APP_DIR/test/golden_test/**/goldens/" >&2
  exit 1
fi

echo "Successfully collected $count golden PNG(s) into $BASELINE_DIR"
