#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/Volumes/Ju/Projects/ios/yacreader"
PROJECT_PATH="$PROJECT_ROOT/yacreader.xcodeproj"
DERIVED_DATA_PATH="/tmp/yacreader-derived-data"

echo "[build_ios] Cleaning previous build artifacts..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme yacreader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  clean

echo "[build_ios] Building yacreader..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme yacreader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[build_ios] Build completed successfully."
