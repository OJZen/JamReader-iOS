#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "[check_project_static_guards] Running SwiftUI gesture guard..."
"$PROJECT_ROOT/scripts/check_no_swiftui_gestures.sh"

echo "[check_project_static_guards] Running supported format policy guard..."
"$PROJECT_ROOT/scripts/check_supported_formats_consistency.sh"

echo "[check_project_static_guards] Running logging hygiene guard..."
"$PROJECT_ROOT/scripts/check_logging_hygiene.sh"

echo "[check_project_static_guards] OK: all static guards passed."
