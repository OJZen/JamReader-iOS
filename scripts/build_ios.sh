#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/JamReader.xcodeproj"
DERIVED_DATA_PATH="/tmp/jamreader-derived-data"
MUPDF_ROOT="${MUPDF_ROOT:-$PROJECT_ROOT/.mupdf/mupdf-1.27.2}"
MUPDF_LIB_DIR="$MUPDF_ROOT/build/ios-arm64"
MUPDF_XCODE_ARGS=()

echo "[build_ios] Running project static guards..."
"$PROJECT_ROOT/scripts/check_project_static_guards.sh"

if [[ -f "$MUPDF_ROOT/include/mupdf/fitz.h" \
  && -f "$MUPDF_LIB_DIR/libmupdf.a" \
  && -f "$MUPDF_LIB_DIR/libmupdf-third.a" ]]; then
  echo "[build_ios] MuPDF found at $MUPDF_ROOT; linking document engine."
  MUPDF_XCODE_ARGS=(
    "HEADER_SEARCH_PATHS=$MUPDF_ROOT/include"
    "LIBRARY_SEARCH_PATHS=$MUPDF_LIB_DIR"
    'OTHER_LDFLAGS=$(inherited) -lmupdf -lmupdf-third -lc++ -lz -lbz2 -liconv -framework CoreGraphics -framework ImageIO -framework CoreText -framework MobileCoreServices'
  )
else
  echo "[build_ios] MuPDF not found at $MUPDF_ROOT; building without PDF/EPUB MuPDF engine."
fi

echo "[build_ios] Cleaning previous build artifacts..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme JamReader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  clean

echo "[build_ios] Building JamReader..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme JamReader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  "${MUPDF_XCODE_ARGS[@]}" \
  build

echo "[build_ios] Build completed successfully."
