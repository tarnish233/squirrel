#!/usr/bin/env bash
# Scroll-mode integration harness: builds the real Squirrel sources (without Main.swift)
# together with tests/scroll_mode/main.swift, runs them against a real librime session in an
# isolated temporary user directory, and writes panel snapshots to $work/out.
# Requires a prior `make release` (for librime, Sparkle and the bundled data).
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
# Not /tmp: endpoint security may kill freshly built binaries run from there.
work=${HARNESS_WORK:-$root/build/scroll-harness}
shared="$root/build/Build/Products/Release/Squirrel.app/Contents/SharedSupport"
[ -d "$shared" ] || { echo "Build Squirrel first: make release" >&2; exit 1; }

rm -rf "$work"
mkdir -p "$work/user" "$work/log" "$work/out"
cat > "$work/user/default.custom.yaml" <<'YAML'
patch:
  schema_list:
    - schema: luna_pinyin_simp
YAML
cat > "$work/user/squirrel.custom.yaml" <<'YAML'
patch:
  status_icon/show: false
  style/candidate_list_layout: linear
  style/scroll_mode/enable: true
  style/scroll_mode/max_rows: 4
  # keep the test panel invisible on screen; snapshots are rendered offscreen
  style/alpha: 0
YAML

bash tests/scroll_mode/build-harness.sh "$work/harness"

HARNESS_USER_DIR="$work/user" HARNESS_LOG_DIR="$work/log" HARNESS_OUT_DIR="$work/out" \
HARNESS_APP_DIR="$work" HARNESS_SHARED_DIR="$shared" "$work/harness"

# Visual variant: preedit inside the panel, paging arrows, long candidates.
mkdir -p "$work/visual/user" "$work/visual/log" "$work/visual/out"
cp "$work/user/default.custom.yaml" "$work/visual/user/"
cat > "$work/visual/user/squirrel.custom.yaml" <<'YAML'
patch:
  status_icon/show: false
  style/candidate_list_layout: linear
  style/scroll_mode/enable: true
  style/inline_preedit: false
  style/show_paging: true
  style/alpha: 0
YAML
HARNESS_VARIANT=visual HARNESS_USER_DIR="$work/visual/user" HARNESS_LOG_DIR="$work/visual/log" HARNESS_OUT_DIR="$work/visual/out" \
HARNESS_APP_DIR="$work" HARNESS_SHARED_DIR="$shared" "$work/harness"
