#!/bin/bash
# Compile AVDB115.dylib for iOS arm64 with the host's iPhoneOS SDK.
# Intended for macOS (local or GitHub Actions). Does not sign.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-"$ROOT/dist/AVDB115.dylib"}"
mkdir -p "$(dirname "$OUT")"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found; this script must run on macOS with Xcode / iOS SDK" >&2
  exit 1
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
MIN="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

# shellcheck disable=SC2206
SRCS=("$ROOT"/src/*.m)

echo "clang: $CLANG"
echo "sdk:   $SDK"
xcrun --sdk iphoneos clang --version | head -1
echo "sources:" "${SRCS[@]}"

"$CLANG" -dynamiclib \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min="$MIN" \
  -fobjc-arc \
  -fmodules \
  -fvisibility=hidden \
  -Wall -Werror=implicit-function-declaration \
  -install_name @executable_path/Frameworks/AVDB115.dylib \
  -framework Foundation \
  -framework UIKit \
  -framework AVFoundation \
  -framework AVKit \
  -framework Security \
  -framework QuartzCore \
  -o "$OUT" \
  "${SRCS[@]}"

echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
python3 "$ROOT/scripts/verify-dylib.py" "$OUT"
