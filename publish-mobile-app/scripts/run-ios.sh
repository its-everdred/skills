#!/bin/bash
# run-ios.sh — dev entrypoint for the iOS Simulator (`npm run ios`).
#
# First run on a machine performs one-time onboarding (setup:ios). Every run
# does a fast toolchain preflight — which auto-installs the iOS platform if it
# went missing (e.g. after an Xcode upgrade) — then hands off to Expo. Extra
# args are forwarded, e.g.  npm run ios -- --device "iPhone 17 Pro".

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTINEL=".expo/.ios-setup-complete"

# First-time onboarding gate.
if [ ! -f "$SENTINEL" ]; then
    echo -e "${YELLOW}👋 First iOS run on this machine — running one-time setup...${NC}"
    if ! "${SCRIPT_DIR}/setup-ios.sh"; then
        echo -e "${RED}❌ iOS setup failed. Fix the above and try again.${NC}"
        exit 1
    fi
else
    # Fast health guard on subsequent runs (setup-ios.sh already ran it above).
    if ! "${SCRIPT_DIR}/doctor-ios.sh"; then
        echo -e "${RED}❌ iOS preflight failed. Fix the above and try again.${NC}"
        exit 1
    fi
fi

# Sync the watch companion sources into the generated Xcode project before the
# build. An Expo withWatchApp-style config plugin only copies watchos/ -> the
# embedded watch target during `expo prebuild`, which `expo run:ios` skips once
# the native project exists — so edits to watchos/ would otherwise silently never
# ship in the embedded watch app. App-agnostic: the watch target dir is found by
# globbing ios/*Watch, so this is a no-op for apps without a watch companion.
WATCH_SRC_DIR="${PROJECT_ROOT}/../watchos"
WATCH_DEST_DIR=$(ls -d "${PROJECT_ROOT}"/ios/*Watch 2>/dev/null | head -1)
if [ -d "$WATCH_SRC_DIR" ] && [ -n "$WATCH_DEST_DIR" ] && [ -d "$WATCH_DEST_DIR" ]; then
    echo -e "${YELLOW}🔄 Syncing watch sources (watchos/ → ios/$(basename "$WATCH_DEST_DIR")/)...${NC}"
    cp "$WATCH_SRC_DIR"/*.swift "$WATCH_SRC_DIR"/Info.plist "$WATCH_DEST_DIR"/ 2>/dev/null || true
    cp -R "$WATCH_SRC_DIR"/Assets.xcassets "$WATCH_DEST_DIR"/ 2>/dev/null || true
fi

# Optionally bring up the Apple Watch companion alongside the phone app.
# Generalized: only chains if a watch runner exists in this repo, so the same
# script is a no-op elsewhere. We wait until the phone app is installed before
# building the watch — that way the phone's Xcode build finishes first and the
# two xcodebuilds don't contend over the shared build database. It runs in the
# background so Metro stays in the foreground here.
WATCH_SCRIPT="${SCRIPT_DIR}/run-watch.sh"
if [ -x "$WATCH_SCRIPT" ]; then
    echo -e "${BLUE}⌚ Watch companion detected — it will launch after the phone build finishes.${NC}"
    (
        # The phone (expo run:ios) and watch (xcodebuild) builds share one
        # DerivedData tree, whose build.db is locked for a single build at a
        # time. Wait for the phone's xcodebuild to appear and then finish before
        # starting the watch build — otherwise the second build dies with
        # "database is locked". Gating on "app installed" is not enough: the app
        # is often already installed from a previous run, so that check passes
        # instantly while this build is still compiling.
        started=0
        for _ in $(seq 1 120); do            # wait up to ~2 min for it to appear
            if pgrep -x xcodebuild >/dev/null 2>&1; then started=1; break; fi
            sleep 1
        done
        if [ "$started" = 1 ]; then
            while pgrep -x xcodebuild >/dev/null 2>&1; do sleep 2; done
        fi
        sleep 2                              # small settle after the lock releases
        "$WATCH_SCRIPT"
    ) &
fi

echo -e "${GREEN}🚀 Launching iOS app on the Simulator...${NC}"
exec npx expo run:ios "$@"
