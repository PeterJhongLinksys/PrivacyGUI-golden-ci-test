#!/bin/bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <SRC_DIR> <PAGES_WORKTREE> <SUBPATH>" >&2
  exit 1
fi

SRC_DIR="$1"
PAGES_WORKTREE="$2"
SUBPATH="$3"

if [ ! -d "$SRC_DIR" ]; then
  echo "Error: Source directory does not exist: $SRC_DIR" >&2
  exit 1
fi

TARGET_DIR="$PAGES_WORKTREE/$SUBPATH"

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp -r "$SRC_DIR/"* "$TARGET_DIR/"

echo "Published $SRC_DIR to $TARGET_DIR"
