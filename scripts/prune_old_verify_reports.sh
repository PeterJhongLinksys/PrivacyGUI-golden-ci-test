#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <VERIFY_DIR> <KEEP_DAYS>" >&2
  exit 1
fi

VERIFY_DIR="$1"
KEEP_DAYS="$2"

if [ ! -d "$VERIFY_DIR" ]; then
  exit 0
fi

TODAY=$(date +%s)
CUTOFF_SECONDS=$((KEEP_DAYS * 86400))

for entry in "$VERIFY_DIR"/*; do
  if [ ! -d "$entry" ]; then
    continue
  fi

  basename=$(basename "$entry")

  if [[ ! "$basename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    continue
  fi

  entry_date=$(date -d "$basename" +%s 2>/dev/null || continue)
  age_seconds=$((TODAY - entry_date))

  if [ "$age_seconds" -gt "$CUTOFF_SECONDS" ]; then
    rm -rf "$entry"
    echo "Pruned old report: $basename"
  fi
done
