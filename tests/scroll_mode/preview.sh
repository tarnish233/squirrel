#!/usr/bin/env bash
# Renders the real candidate panel on screen, glass background included, over a synthetic
# backdrop window, and captures that region (light and dark appearance) with screencapture.
# Uses a copy of a Rime user directory (schemas and dictionaries, without user dictionaries),
# with the given squirrel.custom.yaml. A window shows on screen for a few seconds.
#   tests/scroll_mode/preview.sh [squirrel.custom.yaml] [output dir]
# Defaults: ~/Library/Rime/squirrel.custom.yaml, build/preview/out.
set -euo pipefail
custom=${1:-$HOME/Library/Rime/squirrel.custom.yaml}
custom="$(cd "$(dirname "$custom")" && pwd)/$(basename "$custom")"
out=${2:-}
[ -z "$out" ] || out="$(mkdir -p "$out" && cd "$out" && pwd)"
cd "$(dirname "$0")/../.."
root=$PWD
source_dir=${PREVIEW_RIME_DIR:-$HOME/Library/Rime}
# Not /tmp: endpoint security may kill freshly built binaries run from there.
work=${HARNESS_WORK:-$root/build/preview}
out=${out:-$work/out}
shared="$root/build/Build/Products/Release/Squirrel.app/Contents/SharedSupport"
[ -d "$shared" ] || { echo "Build Squirrel first: make release" >&2; exit 1; }

rm -rf "$work/user" "$work/log"
mkdir -p "$work/user" "$work/log" "$out"
rsync -a --exclude '*.userdb/' --exclude '*.userdb.txt' --exclude 'sync/' --exclude 'installation.yaml' \
  "$source_dir/" "$work/user/"
# the given customization, without the menu bar icon
awk '{ print } /^patch:/ { print "  status_icon/show: false" }' "$custom" > "$work/user/squirrel.custom.yaml"

bash tests/scroll_mode/build-harness.sh "$work/harness"
for attempt in 1 2 3; do
  status=0
  HARNESS_VARIANT=preview HARNESS_USER_DIR="$work/user" HARNESS_LOG_DIR="$work/log" HARNESS_OUT_DIR="$out" \
  HARNESS_APP_DIR="$work" HARNESS_SHARED_DIR="$shared" "$work/harness" || status=$?
  # endpoint security sometimes kills a freshly built binary on its first run
  [ $status = 137 ] || break
  echo "harness killed (attempt $attempt), retrying" >&2
  sleep 3
done
exit $status
