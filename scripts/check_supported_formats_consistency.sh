#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "[check_supported_formats_consistency] ripgrep (rg) is required." >&2
  exit 2
fi

forbidden_mobi_matches="$(
  rg -n 'mobi|MOBI' \
    "$PROJECT_ROOT/JamReader" \
    "$PROJECT_ROOT/README.md" \
    "$PROJECT_ROOT/docs/maintenance-pitfalls.md" \
    "$PROJECT_ROOT/scripts/build_ios.sh" \
    --glob '!**/Resources/EPUBReader/epub.min.js' \
    || true
)"

if [[ -n "$forbidden_mobi_matches" ]]; then
  echo "[check_supported_formats_consistency] MOBI is not a supported format. Remove runtime or user-facing MOBI references." >&2
  echo "$forbidden_mobi_matches" >&2
  exit 1
fi

echo "[check_supported_formats_consistency] OK: no runtime or user-facing MOBI support references found."
