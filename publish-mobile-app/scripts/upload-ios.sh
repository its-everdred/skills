#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step-by-step for setting the signing team in the Xcode GUI. Printed whenever a
# signing failure means the CLI can't finish and the user has to fix it by hand.
xcode_signing_walkthrough() {
    local ws scheme
    ws=$(ls -d ios/*.xcworkspace 2>/dev/null | head -1)
    scheme=$(basename "${ws%.xcworkspace}" 2>/dev/null)
    [ -z "$scheme" ] && scheme="your app"
    echo ""
    echo -e "${BLUE}🛠  Fix signing in Xcode (one-time):${NC}"
    if [ -n "$ws" ]; then
        echo -e "   1. Open the workspace:  ${GREEN}open ${ws}${NC}"
    else
        echo    "   1. Run 'npm run upload:ios' once to generate ios/, then open the .xcworkspace it creates."
    fi
    echo    "   2. In the left Project Navigator, click the blue ${GREEN}${scheme}${NC} project icon at the top."
    echo    "   3. In the editor, under ${GREEN}TARGETS${NC} (not PROJECT) select ${GREEN}${scheme}${NC}."
    echo    "   4. Click the ${GREEN}Signing & Capabilities${NC} tab across the top of the editor"
    echo    "      (widen the window if the tab is hidden)."
    echo    "   5. Check ${GREEN}Automatically manage signing${NC} and set ${GREEN}Team${NC} to your Apple"
    echo    "      Developer account (NOT \"Unknown Name (REPLACE_ME)\")."
    echo    "   6. Repeat steps 3–5 for any other targets (e.g. a ${GREEN}${scheme}Watch${NC} watch companion), if present."
    echo    "   7. Add your Apple ID first if the Team dropdown is empty:"
    echo    "      Xcode ▸ Settings… ▸ Accounts ▸ + ▸ Apple ID."
    echo -e "   ${YELLOW}Tip:${NC} put your Team ID in .env as APPLE_TEAM_ID and this script sets it"
    echo    "        automatically on the next run — no manual step needed."
}

# Step-by-step for archiving + uploading by hand in Xcode. Printed when the CLI
# export can't produce a distributable build (e.g. Xcode + injected-watch quirks)
# and the user needs to fall back to the Organizer GUI.
xcode_manual_upload_walkthrough() {
    local ws
    ws=$(ls -d ios/*.xcworkspace 2>/dev/null | head -1)
    echo ""
    echo -e "${BLUE}🛠  Upload manually from Xcode (Organizer):${NC}"
    [ -n "$ws" ] && echo -e "   1. Open the workspace:  ${GREEN}open ${ws}${NC}"
    echo    "   2. Toolbar (next to the scheme): set the destination to ${GREEN}Any iOS Device (arm64)${NC}"
    echo    "      — it's at the top of that menu, above the simulators. You can't archive to a sim."
    echo    "   3. Menu bar: ${GREEN}Product ▸ Archive${NC}. Wait for the build; the Organizer opens when done."
    echo    "   4. In the Organizer, select the new archive and click ${GREEN}Distribute App${NC}"
    echo    "      (NOT \"Distribute Content\" — that only exports a copy, it won't upload)."
    echo    "   5. Choose ${GREEN}App Store Connect${NC} ▸ ${GREEN}Upload${NC}, keep the defaults"
    echo    "      (automatically manage signing), then ${GREEN}Upload${NC} again to finish."
    echo    "   6. Wait 5–30 min for processing, then submit the build from App Store Connect:"
    echo -e "      ${BLUE}https://appstoreconnect.apple.com/apps${NC}"
}

# Walk the user through registering the app record in App Store Connect. Uploads
# fail ("No suitable application records were found") until the app exists there.
appstore_connect_app_walkthrough() {
    local bundle_id
    bundle_id=$(grep -o '"bundleIdentifier": "[^"]*' app.json 2>/dev/null | grep -o '[^"]*$' | head -1)
    echo ""
    echo -e "${BLUE}🌐 Create the app in App Store Connect (one-time, before first upload):${NC}"
    echo    "   1. Register the bundle ID: developer.apple.com/account ▸ Identifiers ▸ + ▸ App."
    echo    "   2. appstoreconnect.apple.com/apps ▸ + ▸ New App ▸ iOS."
    echo -e "   3. Pick Bundle ID ${GREEN}${bundle_id:-<expo.ios.bundleIdentifier>}${NC}, any unique SKU ▸ Create."
}

# Print actionable guidance for the common Apple signing / agreement failures
# that abort an archive or export. Reads the captured xcodebuild log.
explain_signing_failure() {
    local log="$1"
    if grep -qiE "Program License Agreement|PLA Update available|agree to the latest|don't have access to this membership" "$log" 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}👉 Apple needs you to accept an updated agreement before it can sign the build.${NC}"
        echo    "   1. Open https://developer.apple.com/account  (and https://appstoreconnect.apple.com )"
        echo    "   2. Accept the latest Program License Agreement — the Account Holder must do this."
        echo    "   3. Re-run:  npm run upload:ios"
        echo -e "   ${YELLOW}Until it's accepted, Xcode can't create provisioning profiles (incl. the watch app).${NC}"
    elif grep -qiE "No profiles for|requires a provisioning profile|Failed to (create|register)|no signing certificate" "$log" 2>/dev/null; then
        local badid
        badid=$(grep -oE "No profiles for '[^']+'" "$log" 2>/dev/null | head -1 | sed "s/No profiles for '//; s/'$//")
        echo ""
        echo -e "${YELLOW}👉 A provisioning profile could not be created${badid:+ for ${badid}}.${NC}"
        echo    "   • Most often this is an unaccepted Program License Agreement — accept it at"
        echo    "     https://developer.apple.com/account and re-run."
        echo    "   • If it's already accepted, register the App ID once at developer.apple.com →"
        echo    "     Certificates, Identifiers & Profiles → Identifiers → +"
        [ -n "$badid" ] && echo "     App ID to register: ${badid}"
        xcode_signing_walkthrough
    elif grep -qiE "does not have an associated developer team|no development team|requires a development team|REPLACE_ME|Signing for .* requires a development team" "$log" 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}👉 No development team is assigned to the app's targets.${NC}"
        xcode_signing_walkthrough
    fi
}

echo -e "${YELLOW}📱 Starting iOS TestFlight upload process...${NC}"

# Check if we're in the right directory
if [ ! -f "app.json" ]; then
    echo -e "${RED}❌ Error: app.json not found. Are you in the project root (mobile/)?${NC}"
    exit 1
fi

# Load environment variables from .env file (line-by-line, so values with
# spaces or shell metacharacters are preserved verbatim — no xargs word-splitting)
if [ -f ".env" ]; then
    echo -e "${GREEN}✓ Loading environment variables from .env${NC}"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|\#*) continue ;; esac
        [ "${line#*=}" = "$line" ] && continue
        key="${line%%=*}"; value="${line#*=}"; value="${value%$'\r'}"; export "$key=$value"
    done < .env
else
    echo -e "${RED}❌ Error: .env file not found. Run 'npm run setup:env' first.${NC}"
    exit 1
fi

# Validate required environment variables
if [ -z "$APPLE_API_KEY_ID" ] || [ -z "$APPLE_API_ISSUER_ID" ] || [ -z "$APPLE_TEAM_ID" ]; then
    echo -e "${RED}❌ Error: Missing required environment variables in .env${NC}"
    echo "Please ensure APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, and APPLE_TEAM_ID are set."
    exit 1
fi

# Check if this is first time setup
echo -e "${YELLOW}📋 Pre-flight check...${NC}"
echo ""
echo "Have you configured Xcode with your Apple Developer account?"
echo "This includes:"
echo "  • Adding your Apple ID to Xcode"
echo "  • Selecting your development team"
echo "  • Creating provisioning profiles for this app"
echo ""
echo -e "${GREEN}y${NC} = Yes, I've set up Xcode"
echo -e "${YELLOW}n${NC} = No, this is my first time"
echo ""
echo ""
echo -e "${YELLOW}Also: the app must already exist in App Store Connect, or the upload fails${NC}"
echo    "with \"No suitable application records were found.\" If you haven't created it:"
appstore_connect_app_walkthrough
echo ""
read -p "Continue with upload? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}👉 Starting first-time setup...${NC}"
    echo ""

    # Run the setup script
    ./scripts/setup-ios.sh

    echo ""
    echo -e "${YELLOW}Setup complete! Run this command again to upload.${NC}"
    exit 0
fi

# Bump version (only now that the user has committed to an actual build+upload,
# so an aborted first-time-setup run never leaves a stranded version bump)
echo -e "${YELLOW}📱 Preparing new release...${NC}"
echo ""
./scripts/bump-version.sh
echo ""

# Sync the Apple Team ID from .env into app.json BEFORE prebuild. Expo writes
# expo.ios.appleTeamId into the generated Xcode project's DEVELOPMENT_TEAM; if it's
# left as "REPLACE_ME" the targets show Team = "Unknown Name (REPLACE_ME)" with no
# signing certificate, which breaks both the CLI archive and a manual Xcode archive.
echo -e "${YELLOW}🔏 Setting Apple Team ID in app.json (${APPLE_TEAM_ID})...${NC}"
node -e '
  const fs = require("fs");
  const p = "app.json";
  const cfg = JSON.parse(fs.readFileSync(p, "utf8"));
  cfg.expo.ios = cfg.expo.ios || {};
  cfg.expo.ios.appleTeamId = process.env.APPLE_TEAM_ID;
  fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + "\n");
' || { echo -e "${RED}❌ Failed to set appleTeamId in app.json${NC}"; exit 1; }

# Clean and rebuild. EXPO_NO_GIT_STATUS skips expo's interactive "continue with
# uncommitted changes?" prompt — the only dirty files are the version bump we just
# made on purpose, and that prompt defaults to "yes" on Ctrl+C.
echo -e "${YELLOW}🧹 Cleaning and rebuilding native project...${NC}"
EXPO_NO_GIT_STATUS=1 npx expo prebuild --platform ios --clean

# Generate ExportOptions.plist with current team ID
./scripts/generate-export-options.sh

# Navigate to iOS directory
cd ios || exit 1

# Detect the workspace + scheme generated by prebuild (derived from the app name;
# do not hardcode a project name here).
WORKSPACE=$(ls -d *.xcworkspace 2>/dev/null | head -1)
if [ -z "$WORKSPACE" ]; then
    echo -e "${RED}❌ Error: no .xcworkspace found in ios/. Did prebuild succeed?${NC}"
    exit 1
fi
SCHEME="${WORKSPACE%.xcworkspace}"
ARCHIVE_PATH="./build/${SCHEME}.xcarchive"
echo -e "${GREEN}✓ Using workspace: ${WORKSPACE} (scheme: ${SCHEME})${NC}"

# Remove any stale build output so a failed archive/export can never leave a
# previous run's .xcarchive or .ipa behind for the upload step to pick up.
rm -rf ./build

# Build the app. Capture the output (still shown live via tee) so a failure can
# be explained with actionable next steps.
echo -e "${YELLOW}🔨 Building iOS app for release...${NC}"
ARCHIVE_LOG=$(mktemp)
run_archive() {
    rm -rf "$ARCHIVE_PATH"
    xcodebuild -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM=$APPLE_TEAM_ID \
        archive 2>&1 | tee "$ARCHIVE_LOG"
    return ${PIPESTATUS[0]}
}

run_archive
ARCHIVE_STATUS=$?

# Retry once on a transient failure. React Native's codegen script phases can
# race on the first clean archive (the "will run during every build" notes) and
# abort compilation of the generated Pods sources; a warm-DerivedData retry
# almost always succeeds. Do NOT retry signing/agreement failures — a retry
# can't fix those, so fall straight through to the explanation.
if { [ "$ARCHIVE_STATUS" -ne 0 ] || [ ! -d "$ARCHIVE_PATH" ]; } \
   && ! grep -qiE "Program License Agreement|PLA Update available|No profiles for|requires a provisioning profile|no signing certificate" "$ARCHIVE_LOG"; then
    echo ""
    echo -e "${YELLOW}⚠️  Archive failed — retrying once (RN codegen can race on the first build)...${NC}"
    run_archive
    ARCHIVE_STATUS=$?
fi

# Check if archive was created
if [ "$ARCHIVE_STATUS" -ne 0 ] || [ ! -d "$ARCHIVE_PATH" ]; then
    echo ""
    echo -e "${RED}❌ Error: Archive creation failed${NC}"
    explain_signing_failure "$ARCHIVE_LOG"
    rm -f "$ARCHIVE_LOG"
    exit 1
fi
rm -f "$ARCHIVE_LOG"

# Export the archive
echo -e "${YELLOW}📦 Exporting archive...${NC}"
EXPORT_LOG=$(mktemp)
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath ./build \
    -exportOptionsPlist ./ExportOptions.plist \
    -allowProvisioningUpdates 2>&1 | tee "$EXPORT_LOG"

# Locate the exported IPA (named after the app's product name)
IPA_PATH=$(ls ./build/*.ipa 2>/dev/null | head -1)
if [ -z "$IPA_PATH" ]; then
    echo ""
    echo -e "${RED}❌ Error: no .ipa produced by export${NC}"
    explain_signing_failure "$EXPORT_LOG"
    echo ""
    echo -e "${YELLOW}The archive succeeded but the automated export didn't produce an .ipa.${NC}"
    echo    "You can finish the upload by hand from Xcode:"
    xcode_manual_upload_walkthrough
    rm -f "$EXPORT_LOG"
    exit 1
fi
rm -f "$EXPORT_LOG"

# Upload to TestFlight
echo -e "${YELLOW}🚀 Uploading to TestFlight...${NC}"

# Ensure the API key (.p8) is discoverable by altool in a standard location.
# altool searches ./private_keys, ~/private_keys, ~/.private_keys and
# ~/.appstoreconnect/private_keys for AuthKey_<APPLE_API_KEY_ID>.p8.
if [ -n "$APPLE_API_KEY_PATH" ]; then
    EXPANDED_KEY_PATH="${APPLE_API_KEY_PATH/#\~/$HOME}"
    if [ -f "$EXPANDED_KEY_PATH" ]; then
        mkdir -p "$HOME/.private_keys"
        cp -f "$EXPANDED_KEY_PATH" "$HOME/.private_keys/AuthKey_${APPLE_API_KEY_ID}.p8" 2>/dev/null || true
    fi
fi

UPLOAD_LOG=$(mktemp)
xcrun altool --upload-app \
    -f "$IPA_PATH" \
    -t ios \
    --apiKey $APPLE_API_KEY_ID \
    --apiIssuer $APPLE_API_ISSUER_ID \
    --verbose 2>&1 | tee "$UPLOAD_LOG"
UPLOAD_STATUS=${PIPESTATUS[0]}

if [ "$UPLOAD_STATUS" -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Upload failed (altool exit ${UPLOAD_STATUS}).${NC}"
    # "Cannot determine the Apple ID from Bundle ID" means no App Store Connect
    # app record exists for the bundle ID in this .ipa (or the .ipa was built
    # with a different bundle ID than the one you registered).
    if grep -qiE "Cannot determine the Apple ID|No suitable application records|bundle.?id" "$UPLOAD_LOG"; then
        IPA_BUNDLE_ID=$(grep -oE "Bundle ID '[^']+'" "$UPLOAD_LOG" | head -1 | sed "s/Bundle ID '//; s/'$//")
        echo -e "${YELLOW}👉 No App Store Connect app matches this build's bundle ID${IPA_BUNDLE_ID:+ (${IPA_BUNDLE_ID})}.${NC}"
        echo    "   • Make sure app.json's expo.ios.bundleIdentifier matches the app you created."
        echo    "   • If you just changed the bundle ID, the .ipa is stale — re-run to rebuild it."
        appstore_connect_app_walkthrough
    fi
    rm -f "$UPLOAD_LOG"
    exit 1
fi
rm -f "$UPLOAD_LOG"

BUILD_NUMBER=$(grep -o '"buildNumber": "[^"]*' app.json 2>/dev/null | grep -o '[^"]*$' | head -1)

echo -e "${GREEN}✅ Upload complete!${NC}  Build ${GREEN}${BUILD_NUMBER:-?}${NC}"
echo ""
echo -e "${YELLOW}Next (manual) at ${BLUE}https://appstoreconnect.apple.com/apps${NC}${YELLOW}:${NC}"
echo    "   1. TestFlight ▸ iOS builds — wait 5-30 min until it stops \"Processing\"."
echo    "   2. App Store version ▸ Build ▸ + ▸ pick this build (clears \"must choose a build\")."
echo    "   3. Submit for Review. It won't go live until you do."
