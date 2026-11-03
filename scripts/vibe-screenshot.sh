#!/bin/bash
# Vibe map screenshot harness. Boots one simulator, installs the current build,
# opens the vibe map (real data on the signed-in simulator), takes a screenshot, shuts down.
#
# Usage: scripts/vibe-screenshot.sh <name> <sim-udid> [extra launch args...]
#   scripts/vibe-screenshot.sh home <sim-udid>
#   scripts/vibe-screenshot.sh zoomed <sim-udid> -kima-vibe-locate -kima-vibe-zoom 0.15
#   scripts/vibe-screenshot.sh bare <sim-udid> -kima-vibe-bare -kima-vibe-still
#
# Output: build/vibe-shots/<name>-<timestamp>.png
# Debug flags (release builds ignore them): -kima-vibe-still (frozen time, finished reveal),
# -kima-vibe-bare (no overlay), -kima-vibe-locate (fly to the playing star),
# -kima-vibe-zoom <f> (pin the camera at f x home distance), -kima-vibe-fake-playing <i>.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: vibe-screenshot.sh <name> <sim-udid> [extra launch args...]}"; shift
UDID="${1:?usage: vibe-screenshot.sh <name> <sim-udid> [extra launch args...]}"; shift
EXTRA_ARGS=("$@")

BUNDLE_ID="com.chevron7locked.kima"
OUT_DIR="build/vibe-shots"
STAMP="$(date +%H%M%S)"
OUT="$OUT_DIR/$NAME-$STAMP.png"
mkdir -p "$OUT_DIR"

# One build at a time, throttled (same discipline as xcodebuild runs by hand).
lockf -k /tmp/kima-build.lock taskpolicy -b nice -n 19 \
    xcodebuild -project Kima.xcodeproj -scheme Kima -destination "platform=iOS Simulator,id=$UDID" \
    -configuration Debug -quiet build

APP="$(xcodebuild -project Kima.xcodeproj -scheme Kima -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/BUILD_DIR =/ {print $2; exit}')/Debug-iphonesimulator/Kima.app"
[[ -d "$APP" ]] || { echo "app not found at $APP" >&2; exit 1; }

xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -kima-open-vibe "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
sleep 14   # map load, reveal, any fly-to
xcrun simctl io "$UDID" screenshot "$OUT"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true
echo "wrote $OUT"
