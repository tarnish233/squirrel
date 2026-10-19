#!/usr/bin/env bash
# Builds the harness: the real Squirrel sources (without Main.swift) plus tests/scroll_mode/main.swift.
#   tests/scroll_mode/build-harness.sh <output binary>
# Requires a prior `make release` (for librime and Sparkle).
set -euo pipefail
output=$1
cd "$(dirname "$0")/../.."
root=$PWD
swiftc -swift-version 5 -Onone -enable-bare-slash-regex \
  -import-objc-header sources/Squirrel-Bridging-Header.h -I librime/src -I librime/include \
  -L lib -lrime.1 -F Frameworks -framework Sparkle \
  -framework AppKit -framework InputMethodKit -framework Carbon -framework UserNotifications \
  -Xlinker -rpath -Xlinker "$root/lib" -Xlinker -rpath -Xlinker "$root/Frameworks" \
  sources/{BridgingFunctions,InputSource,MacOSKeyCodes,ReservedProperty,SquirrelApplicationDelegate,SquirrelConfig,SquirrelInputController,SquirrelPanel,SquirrelScrollMode,SquirrelTheme,SquirrelView}.swift \
  tests/scroll_mode/main.swift -o "$output" 2>&1 | { grep -v -E "SwiftUICore|^ld: warning: Could not parse" || true; }
test -x "$output"
