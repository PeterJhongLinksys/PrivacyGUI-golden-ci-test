#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <APP_DIR>" >&2
  exit 1
fi

APP_DIR="$1"
REPORT_PATTERN="$APP_DIR/test/golden_test/localizations-test-reports-*.json"

shopt -s nullglob
REPORT_FILES=($REPORT_PATTERN)
shopt -u nullglob

if [ ${#REPORT_FILES[@]} -eq 0 ]; then
  echo "Warning: No golden test report files found matching $REPORT_PATTERN" >&2
  exit 1
fi

FAIL_COUNT=0
for report in "${REPORT_FILES[@]}"; do
  COUNT=$(jq '[.[] | select(.result == "error")] | length' "$report")
  FAIL_COUNT=$((FAIL_COUNT + COUNT))
done

echo "$FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

exit 0
