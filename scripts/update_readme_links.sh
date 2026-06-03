#!/usr/bin/env bash
set -euo pipefail

# Usage: update_readme_links.sh <PAGES_WORKTREE> <README_PATH> <BASE_URL>
# Scans the gh-pages worktree for reports and updates the README between markers.

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <PAGES_WORKTREE> <README_PATH> <BASE_URL>" >&2
  exit 1
fi

PAGES_DIR="$1"
README="$2"
BASE_URL="${3%/}"

LINKS=""

# Showcase gallery
if [[ -f "$PAGES_DIR/golden/usp/golden_gallery_report.html" ]]; then
  LINKS+="### Showcase (USP)\n"
  LINKS+="\n"
  LINKS+="- [Gallery Report](${BASE_URL}/golden/usp/golden_gallery_report.html)\n"
  LINKS+="\n"
fi

# Dev baseline gallery
if [[ -f "$PAGES_DIR/golden/dev/golden_gallery_report.html" ]]; then
  LINKS+="### Dev Baseline\n"
  LINKS+="\n"
  LINKS+="- [Gallery Report](${BASE_URL}/golden/dev/golden_gallery_report.html)\n"
  LINKS+="\n"
fi

# Daily verify reports (sorted newest first, max 7 days)
if [[ -d "$PAGES_DIR/verify/dev" ]]; then
  DATES=$(find "$PAGES_DIR/verify/dev" -maxdepth 1 -type d -name "????-??-??" | sort -r)
  if [[ -n "$DATES" ]]; then
    LINKS+="### Daily Verify\n"
    LINKS+="\n"
    LINKS+="| Date | Report |\n"
    LINKS+="|------|--------|\n"
    while IFS= read -r dir; do
      date=$(basename "$dir")
      LINKS+="| ${date} | [Verify Report](${BASE_URL}/verify/dev/${date}/golden_verify_report.html) |\n"
    done <<< "$DATES"
    LINKS+="\n"
  fi
fi

if [[ -z "$LINKS" ]]; then
  LINKS="_No reports yet. Run the workflows to generate links here._\n"
fi

# Replace content between markers
awk -v links="$LINKS" '
  /<!-- REPORTS:START -->/ { print; printf links; skip=1; next }
  /<!-- REPORTS:END -->/ { skip=0 }
  !skip { print }
' "$README" > "${README}.tmp"

mv "${README}.tmp" "$README"
echo "README updated with report links"
