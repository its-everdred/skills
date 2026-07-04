#!/bin/bash
# run-ios.sh — dev entrypoint for the iOS Simulator (`npm run ios`).
#
# First run on a machine performs one-time onboarding (setup:ios). Every run
# does a fast toolchain preflight — which auto-installs the iOS platform if it
# went missing (e.g. after an Xcode upgrade) — then hands off to Expo. Extra
# args are forwarded, e.g.  npm run ios -- --device "iPhone 17 Pro".

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

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

echo -e "${GREEN}🚀 Launching iOS app on the Simulator...${NC}"
exec npx expo run:ios "$@"
