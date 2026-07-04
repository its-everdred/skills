#!/bin/bash
# doctor-ios.sh — non-interactive iOS toolchain preflight.
#
# Verifies that Xcode and every simulator platform this project builds are
# installed, and auto-installs any that are missing. A missing platform is the
# #1 "works on my machine" gap right after an Xcode upgrade: the SDK ships but
# the platform support package (which includes the simulator runtime) does not,
# so `xcodebuild` reports `<platform> <ver> is not installed`, offers NO
# simulator destinations, and every `expo run:ios` fails. If the app embeds an
# Apple Watch companion (detected below), the scheme also needs the watchOS
# platform.
#
# Safe to run repeatedly; fast when the toolchain is healthy.
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Operate from the mobile/ project root regardless of the caller's cwd.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# 1. iOS builds are macOS-only.
if [ "$(uname)" != "Darwin" ]; then
    echo -e "${RED}❌ iOS builds require macOS.${NC}"
    exit 1
fi

# 2. Full Xcode must be installed and selected (Command Line Tools alone can't
#    build the app or run the Simulator).
if ! xcodebuild -version >/dev/null 2>&1; then
    echo -e "${RED}❌ Xcode not found, or the Command Line Tools are selected instead of Xcode.${NC}"
    echo    "   Install Xcode from the App Store, then point the toolchain at it:"
    echo    "     sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi

# Ensure the simulator platform matching the active SDK is installed for a given
# platform, installing it via `xcodebuild -downloadPlatform` when it is missing.
# Args: <PlatformName> <sdk-token> ; e.g. ensure_platform iOS iphonesimulator
#   - PlatformName doubles as the -downloadPlatform arg and the simctl runtime
#     label (simctl prints "iOS 26.5 (...)" / "watchOS 26.5 (...)").
ensure_platform() {
    local name="$1" sdk_token="$2" ver
    ver="$(xcodebuild -showsdks 2>/dev/null | sed -n "s/.*${sdk_token}\([0-9][0-9.]*\).*/\1/p" | head -1 || true)"

    if [ -z "$ver" ]; then
        echo -e "${YELLOW}⚠️  Could not determine the ${name} Simulator SDK version — skipping ${name} check.${NC}"
        return 0
    fi
    if xcrun simctl list runtimes 2>/dev/null | grep -q "${name} ${ver} "; then
        echo -e "${GREEN}✓ ${name} ${ver} simulator platform is installed.${NC}"
        return 0
    fi

    echo -e "${YELLOW}📥 The ${name} ${ver} platform (and its simulator runtime) is not installed.${NC}"
    echo    "   Xcode ships the SDK but not the platform support package after an upgrade,"
    echo    "   so the scheme has no ${name} simulator to target until it is downloaded."
    if [ "${SKIP_PLATFORM_DOWNLOAD:-0}" = "1" ]; then
        echo -e "${YELLOW}   SKIP_PLATFORM_DOWNLOAD=1 set — skipping the download.${NC}"
        echo    "   Install it yourself before running:  xcodebuild -downloadPlatform ${name}"
        return 1
    fi
    echo    "   Installing now via 'xcodebuild -downloadPlatform ${name}'."
    echo    "   This is a large one-time download (several GB) and may take a while."
    echo    "   (Set SKIP_PLATFORM_DOWNLOAD=1 to skip and install it yourself.)"
    if ! xcodebuild -downloadPlatform "${name}"; then
        echo -e "${RED}❌ Failed to install the ${name} platform.${NC}"
        echo    "   Retry manually, or install it from Xcode → Settings → Components:"
        echo    "     xcodebuild -downloadPlatform ${name}"
        return 1
    fi
    echo -e "${GREEN}✓ ${name} ${ver} platform installed.${NC}"
    return 0
}

status=0

# 3. iOS platform (always required).
ensure_platform "iOS" "iphonesimulator" || status=1

# 4. watchOS platform — only when the scheme embeds an Apple Watch companion.
#    Detect via app.json (works pre-prebuild) or the generated native target.
if grep -q "withWatchApp" app.json 2>/dev/null || ls -d ios/*Watch* >/dev/null 2>&1; then
    ensure_platform "watchOS" "watchsimulator" || status=1
fi

if [ "$status" -eq 0 ]; then
    echo -e "${GREEN}✓ iOS toolchain looks good.${NC}"
fi
exit "$status"
