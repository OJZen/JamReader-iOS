#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$PROJECT_ROOT/JamReader"
APP_LOG_FILE="$TARGET_DIR/Core/Logging/AppLog.swift"
SUBSYSTEM="ooou.fun.jamreader"

if ! command -v rg >/dev/null 2>&1; then
  echo "[check_logging_hygiene] ripgrep (rg) is required." >&2
  exit 2
fi

failed=0

report_matches() {
  local title="$1"
  local matches="$2"
  if [[ -n "$matches" ]]; then
    echo "[check_logging_hygiene] $title" >&2
    echo "$matches" >&2
    failed=1
  fi
}

direct_output_matches="$(
  rg -n 'NSLog[[:space:]]*\(|OS_LOG_DEFAULT|\bprint[[:space:]]*\(|\bdebugPrint[[:space:]]*\(' \
    "$TARGET_DIR" \
    --glob '*.{swift,m,h,mm,c,cpp}' \
    || true
)"
report_matches "Found direct logging/output APIs. Use AppLog or project-scoped os_log instead." "$direct_output_matches"

direct_logger_matches="$(
  rg -n 'Logger[[:space:]]*\(' "$TARGET_DIR" --glob '*.swift' \
    | rg -v "^$APP_LOG_FILE:" \
    || true
)"
report_matches "Found direct Swift Logger construction outside AppLog." "$direct_logger_matches"

os_log_create_matches="$(rg -n 'os_log_create[[:space:]]*\(' "$TARGET_DIR" --glob '*.{m,mm,c,cpp,h}' || true)"
invalid_os_log_create_matches="$(
  if [[ -n "$os_log_create_matches" ]]; then
    printf '%s\n' "$os_log_create_matches" | rg -v "$SUBSYSTEM" || true
  fi
)"
report_matches "Found os_log_create without the JamReader subsystem." "$invalid_os_log_create_matches"

credential_literal_matches="$(
  rg -n '"[^"]*(referenceKey=|username=|userName=|password=|authorizationHeader=|Authorization=|token=|secret=|credential=|credentials=)' \
    "$TARGET_DIR" \
    --glob '*.{swift,m,mm,c,cpp}' \
    || true
)"
report_matches "Found log/string literals that may expose credential fields. Hash or omit these values." "$credential_literal_matches"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "[check_logging_hygiene] OK: logging entry points and obvious credential literals look safe."
