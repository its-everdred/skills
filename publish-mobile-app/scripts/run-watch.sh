#!/bin/bash
# run-watch.sh — build, install, and launch the Apple Watch companion on a local
# watchOS Simulator, paired with the running iPhone Simulator.
#
# Everything is local: the iOS Simulator, the watchOS Simulator, and their
# pairing all run on this Mac via CoreSimulator — no physical device, no code
# signing, no cloud. The companion is phone-driven (it receives data from the
# phone over WatchConnectivity), so it only shows live data while the iPhone app
# is running and paired. Start that first, in another terminal:  npm run ios
#
# App-agnostic: the workspace and app scheme are discovered from ios/, and the
# watch scheme defaults to "<app scheme>Watch" (the Expo withWatchApp naming
# convention). Override with WATCH_SCHEME=... when your target is named
# differently.
#
# Usage:  npm run watch
#         WATCH_DEVICE="Apple Watch Ultra 3 (49mm)" npm run watch
#         WATCH_SCHEME="MyAppWatch" npm run watch

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WATCH_DEVICE="${WATCH_DEVICE:-Apple Watch Series 11 (46mm)}"

# udid of the first booted iPhone Simulator (empty if none running).
booted_iphone() {
    xcrun simctl list devices booted 2>/dev/null | grep -i "iPhone" | grep -oE "[0-9A-F]{8}-[0-9A-F-]{27}" | head -1
}
# udid of an available watch simulator matching $WATCH_DEVICE.
watch_udid() {
    xcrun simctl list devices available 2>/dev/null | grep -iF "$WATCH_DEVICE" | grep -oE "[0-9A-F]{8}-[0-9A-F-]{27}" | head -1
}

# 1. Toolchain preflight — installs the watchOS platform if it is missing.
if ! "${SCRIPT_DIR}/doctor-ios.sh"; then
    echo -e "${RED}❌ Toolchain preflight failed.${NC}"; exit 1
fi

# 2. The native project must exist (produced by 'npm run ios' / 'setup:ios').
#    Discover the workspace and derive the app + watch schemes from it.
WORKSPACE=$(ls -d ios/*.xcworkspace 2>/dev/null | head -1)
if [ -z "$WORKSPACE" ] || [ ! -f "$WORKSPACE/contents.xcworkspacedata" ]; then
    echo -e "${RED}❌ Native iOS project not found in ios/.${NC}"
    echo    "   Run 'npm run ios' (or 'npm run setup:ios') first."
    exit 1
fi
APP_SCHEME="$(basename "${WORKSPACE%.xcworkspace}")"
WATCH_SCHEME="${WATCH_SCHEME:-${APP_SCHEME}Watch}"

# 3. Resolve an iPhone to pair with — reuse a running one so we don't disturb
#    the phone app / Metro; otherwise boot one (with a heads-up).
PHONE_UDID="$(booted_iphone)"
if [ -z "$PHONE_UDID" ]; then
    echo -e "${YELLOW}ℹ️  No iPhone Simulator is running.${NC}"
    echo    "   The companion is phone-driven — for live data start the phone app first:"
    echo    "     npm run ios        (in another terminal)"
    echo    "   Booting an iPhone anyway so the watch has a pair..."
    PHONE_UDID="$(xcrun simctl list devices available 2>/dev/null | grep -iE "iPhone" | grep -oE "[0-9A-F]{8}-[0-9A-F-]{27}" | head -1)"
    [ -n "$PHONE_UDID" ] && xcrun simctl boot "$PHONE_UDID" 2>/dev/null
fi
if [ -z "$PHONE_UDID" ]; then
    echo -e "${RED}❌ Could not find an iPhone Simulator to pair with.${NC}"; exit 1
fi

# 4. Resolve the watch simulator.
WATCH_UDID="$(watch_udid)"
if [ -z "$WATCH_UDID" ]; then
    echo -e "${RED}❌ No '${WATCH_DEVICE}' simulator found.${NC}"
    echo    "   See options with:  xcrun simctl list devices | grep 'Apple Watch'"
    echo    "   Then re-run with:   WATCH_DEVICE=\"<name>\" npm run watch"
    exit 1
fi
echo -e "${BLUE}📱 Phone: ${PHONE_UDID}${NC}"
echo -e "${BLUE}⌚ Watch: ${WATCH_DEVICE} (${WATCH_UDID})${NC}"

# 5. Pair the watch to the phone (idempotent — already-paired is fine) and boot.
xcrun simctl pair "$WATCH_UDID" "$PHONE_UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$WATCH_UDID" 2>/dev/null || true
open -a Simulator

# 6. Build the watch scheme for this watch simulator (incremental after first).
echo -e "${YELLOW}🔨 Building ${WATCH_SCHEME}...${NC}"
if ! xcodebuild -workspace "$WORKSPACE" -scheme "$WATCH_SCHEME" -configuration Debug \
        -destination "id=${WATCH_UDID}" -quiet build; then
    echo -e "${RED}❌ Watch build failed. Open ${WORKSPACE} in Xcode for details.${NC}"
    echo    "   If the scheme name differs, set WATCH_SCHEME=\"<name>\" and re-run."
    exit 1
fi

# 7. Locate the built app + its bundle id straight from the build settings
#    (no hardcoded paths or ids).
SETTINGS="$(xcodebuild -workspace "$WORKSPACE" -scheme "$WATCH_SCHEME" -configuration Debug \
    -destination "id=${WATCH_UDID}" -showBuildSettings 2>/dev/null)"
BUILD_DIR="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ TARGET_BUILD_DIR =/{print $2; exit}')"
WRAPPER="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ WRAPPER_NAME =/{print $2; exit}')"
BUNDLE_ID="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER =/{print $2; exit}')"
APP_PATH="${BUILD_DIR}/${WRAPPER}"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Built watch app not found at ${APP_PATH}.${NC}"; exit 1
fi

# 8. Wait for the watch to finish booting, then install + launch.
xcrun simctl bootstatus "$WATCH_UDID" >/dev/null 2>&1
echo -e "${YELLOW}📲 Installing ${WRAPPER}...${NC}"
if ! xcrun simctl install "$WATCH_UDID" "$APP_PATH"; then
    echo -e "${RED}❌ Failed to install the watch app.${NC}"; exit 1
fi
echo -e "${GREEN}🚀 Launching ${BUNDLE_ID}...${NC}"
xcrun simctl launch "$WATCH_UDID" "$BUNDLE_ID" >/dev/null 2>&1

echo -e "${GREEN}✓ Watch companion running on ${WATCH_DEVICE}.${NC}"
echo    "  Keep the iPhone app running for live, phone-driven data:  npm run ios"
