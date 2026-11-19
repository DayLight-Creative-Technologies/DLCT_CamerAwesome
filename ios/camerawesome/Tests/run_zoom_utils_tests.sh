#!/usr/bin/env bash
# DLCT: build and run the ZoomUtils native test as Mac Catalyst (runs on the Mac, no Simulator or device).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../Sources/camerawesome"
out="$(mktemp -d)"
xcrun --sdk macosx clang -fobjc-arc -target "$(uname -m)-apple-ios17.0-macabi" \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
  -I "$src/include" \
  "$src/Utils/Zoom/ZoomUtils.m" "$here/ZoomUtilsTests.m" \
  -framework Foundation -framework AVFoundation -framework CoreGraphics \
  -o "$out/zoom_utils_tests"
"$out/zoom_utils_tests"
