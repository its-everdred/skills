#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🤖 Starting Android Play Store upload process...${NC}"

# Check if we're in the right directory
if [ ! -f "app.json" ]; then
    echo -e "${RED}❌ Error: app.json not found. Are you in the project root (mobile/)?${NC}"
    exit 1
fi

# App identifiers derived from app.json (no hardcoded app name/slug). The slug
# names the release files AND the per-app upload keystore; the display name is
# only used for a freshly generated keystore's certificate DN.
APP_SLUG=$(grep -o '"slug": "[^"]*' app.json | grep -o '[^"]*$' | head -1)
APP_SLUG="${APP_SLUG:-app}"
APP_NAME=$(grep -o '"name": "[^"]*' app.json | grep -o '[^"]*$' | head -1)
APP_NAME="${APP_NAME:-App}"

# Check if this is first time setup
echo -e "${YELLOW}📋 Pre-flight check...${NC}"
echo ""
echo "Have you created your app in Google Play Console?"
echo "This includes:"
echo "  • Creating your app in Play Console"
echo "  • Setting up at least one release track"
echo ""
echo -e "${GREEN}y${NC} = Yes, I've set up Google Play Console"
echo -e "${YELLOW}n${NC} = No, this is my first time"
echo ""
read -p "Continue with upload? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}👉 Starting first-time setup...${NC}"
    echo ""

    # Run the setup script
    ./scripts/setup-android-upload.sh

    echo ""
    echo -e "${YELLOW}Setup complete! Run this command again to upload.${NC}"
    exit 0
fi

# Load environment variables from .env file FIRST (line-by-line, so values with
# spaces or shell metacharacters are preserved verbatim — no xargs word-splitting)
if [ -f ".env" ]; then
    echo -e "${GREEN}✓ Loading environment variables from .env${NC}"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|\#*) continue ;; esac
        [ "${line#*=}" = "$line" ] && continue
        key="${line%%=*}"; value="${line#*=}"; value="${value%$'\r'}"; export "$key=$value"
    done < .env
else
    echo -e "${YELLOW}⚠️  No .env file found${NC}"
fi

# Bump version (only now that the user has committed to an actual build+upload,
# so an aborted first-time-setup run never leaves a stranded version bump)
echo -e "${YELLOW}📱 Preparing new release...${NC}"
echo ""
./scripts/bump-version.sh
echo ""

# Set Android SDK path
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools"

# Clean and rebuild. EXPO_NO_GIT_STATUS skips expo's interactive "continue with
# uncommitted changes?" prompt — the only dirty files are the version bump we just
# made on purpose, and that prompt defaults to "yes" on Ctrl+C (so it can't be
# cancelled cleanly). Our own y/n gate above is the intended stopping point.
echo -e "${YELLOW}🧹 Cleaning and rebuilding native project...${NC}"
EXPO_NO_GIT_STATUS=1 npx expo prebuild --platform android --clean

# Create local.properties file with SDK location
echo "sdk.dir=$ANDROID_HOME" > android/local.properties

# Navigate to Android directory
cd android || exit 1

# Secure keystore location (only location used). The default filename is derived
# from the app slug so two apps never collide on one shared keystore.
# Expand ~ to home directory if present
KEYSTORE_PATH="${ANDROID_KEYSTORE_PATH:-$HOME/.private_keys/android/${APP_SLUG}-upload-keystore.jks}"
KEYSTORE_PATH="${KEYSTORE_PATH/#\~/$HOME}"
KEYSTORE_DIR=$(dirname "$KEYSTORE_PATH")

echo -e "${GREEN}✓ Using keystore path: $KEYSTORE_PATH${NC}"

# Create secure directory if it doesn't exist
mkdir -p "$KEYSTORE_DIR"

# Check if keystore exists - NEVER overwrite existing keystore
if [ -f "$KEYSTORE_PATH" ]; then
    echo -e "${GREEN}✓ Using existing keystore: $KEYSTORE_PATH${NC}"

    # Verify environment variables are set
    if [ -z "$ANDROID_UPLOAD_STORE_PASSWORD" ] || [ -z "$ANDROID_UPLOAD_KEY_PASSWORD" ]; then
        echo -e "${RED}❌ Error: Keystore exists but passwords not found in environment${NC}"
        echo -e "${YELLOW}Please check your .env file for:${NC}"
        echo "  ANDROID_UPLOAD_STORE_PASSWORD"
        echo "  ANDROID_UPLOAD_KEY_PASSWORD"
        exit 1
    fi

else
    echo -e "${YELLOW}🔐 Creating new release keystore with secure passwords...${NC}"
    echo -e "${RED}⚠️  This will create a NEW keystore. Existing keystore check: PASSED${NC}"

    # Double-check keystore doesn't exist (paranoid safety check)
    if [ -f "$KEYSTORE_PATH" ]; then
        echo -e "${RED}❌ ABORT: Keystore appeared during execution. Not overwriting.${NC}"
        exit 1
    fi

    # Generate secure passwords
    STORE_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    KEY_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    # Create keystore in secure location
    keytool -genkeypair -v \
        -storetype JKS \
        -keystore "$KEYSTORE_PATH" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -alias upload \
        -keypass "$KEY_PASSWORD" \
        -storepass "$STORE_PASSWORD" \
        -dname "CN=${APP_NAME}, OU=Development, O=${APP_NAME}, L=City, ST=State, C=US"

    # Verify keystore was actually created
    if [ ! -f "$KEYSTORE_PATH" ]; then
        echo -e "${RED}❌ Error: Keystore creation failed${NC}"
        exit 1
    fi

    # Export for the current run so this same invocation can sign the bundle.
    export ANDROID_UPLOAD_STORE_PASSWORD="$STORE_PASSWORD"
    export ANDROID_UPLOAD_KEY_PASSWORD="$KEY_PASSWORD"

    # Persist passwords to .env, replacing any prior (placeholder) lines so the
    # real keystore passwords are authoritative and never duplicated.
    cd ..
    if [ -f .env ]; then
        grep -vE '^(# Android Release Signing$|ANDROID_UPLOAD_STORE_PASSWORD=|ANDROID_UPLOAD_KEY_PASSWORD=)' .env > .env.tmp && mv .env.tmp .env
    fi
    {
        echo ""
        echo "# Android Release Signing"
        echo "ANDROID_UPLOAD_STORE_PASSWORD=$STORE_PASSWORD"
        echo "ANDROID_UPLOAD_KEY_PASSWORD=$KEY_PASSWORD"
    } >> .env
    cd android

    echo -e "${GREEN}✓ Keystore created with secure passwords${NC}"
    echo ""
    echo -e "${RED}🚨 CRITICAL: KEYSTORE SAVED TO SECURE LOCATION!${NC}"
    echo -e "${GREEN}✓ Location: $KEYSTORE_PATH${NC}"
    echo -e "${YELLOW}⚠️  Passwords in .env file (ANDROID_UPLOAD_*)${NC}"
    echo ""
    echo -e "${GREEN}✅ Keystore survives cache cleaning and prebuild operations${NC}"
    echo -e "${RED}🔒 This keystore will NEVER be overwritten by this script${NC}"
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
fi

# Add signing config to gradle.properties (only file path and alias, no passwords)
if ! grep -q "MYAPP_UPLOAD_STORE_FILE" gradle.properties 2>/dev/null; then
    echo "" >> gradle.properties
    echo "# Upload key configuration (passwords come from environment)" >> gradle.properties
    echo "MYAPP_UPLOAD_STORE_FILE=$KEYSTORE_PATH" >> gradle.properties
    echo "MYAPP_UPLOAD_KEY_ALIAS=upload" >> gradle.properties
fi

# Fix build.gradle to use release signing
cd ..
node scripts/fix-android-signing.js
cd android

# Build the release bundle
echo -e "${YELLOW}🔨 Building Android release bundle...${NC}"
ANDROID_UPLOAD_STORE_PASSWORD="$ANDROID_UPLOAD_STORE_PASSWORD" \
ANDROID_UPLOAD_KEY_PASSWORD="$ANDROID_UPLOAD_KEY_PASSWORD" \
./gradlew bundleRelease

# Check if bundle was created
if [ ! -f "app/build/outputs/bundle/release/app-release.aab" ]; then
    echo -e "${RED}❌ Error: Bundle creation failed${NC}"
    exit 1
fi

# Get version from app.json and rename the bundle
cd ..
APP_VERSION=$(grep -o '"version": "[^"]*' app.json | grep -o '[^"]*$')
cd android

# Create releases directory if it doesn't exist
mkdir -p "../releases"

# Create versioned filename in both locations
VERSIONED_BUNDLE="app/build/outputs/bundle/release/${APP_SLUG}-v${APP_VERSION}-release.aab"
ARCHIVED_BUNDLE="../releases/${APP_SLUG}-v${APP_VERSION}-release.aab"

# Copy the bundle with versioned name (keep in build dir for upload)
cp "app/build/outputs/bundle/release/app-release.aab" "$VERSIONED_BUNDLE"

# Check if this is an overwrite and handle existing files
if [ -f "$ARCHIVED_BUNDLE" ]; then
    echo -e "${YELLOW}⚠️  Found existing release file: releases/${APP_SLUG}-v${APP_VERSION}-release.aab${NC}"
    echo -e "${YELLOW}This will overwrite the existing release file.${NC}"
    echo ""
fi

# Archive a copy in releases directory (will overwrite if exists)
cp "app/build/outputs/bundle/release/app-release.aab" "$ARCHIVED_BUNDLE"

# Fail loudly rather than printing success for a bundle that did not copy
if [ ! -f "$VERSIONED_BUNDLE" ] || [ ! -f "$ARCHIVED_BUNDLE" ]; then
    echo -e "${RED}❌ Error: failed to copy the release bundle into releases/${NC}"
    exit 1
fi

# Copy deobfuscation mapping file if it exists
MAPPING_FILE="app/build/outputs/mapping/release/mapping.txt"
ARCHIVED_MAPPING="../releases/${APP_SLUG}-v${APP_VERSION}-mapping.txt"
if [ -f "$MAPPING_FILE" ]; then
    cp "$MAPPING_FILE" "$ARCHIVED_MAPPING"
    echo -e "${GREEN}✓ Mapping file: releases/${APP_SLUG}-v${APP_VERSION}-mapping.txt${NC}"
fi

echo -e "${GREEN}✅ Android bundle created successfully!${NC}"
echo -e "${GREEN}✓ Versioned bundle: ${APP_SLUG}-v${APP_VERSION}-release.aab${NC}"
echo -e "${GREEN}✓ Archived to: releases/${APP_SLUG}-v${APP_VERSION}-release.aab${NC}"
echo ""

# Get absolute path to the bundle for display
BUNDLE_ABSOLUTE_PATH="$(cd .. && pwd)/releases/${APP_SLUG}-v${APP_VERSION}-release.aab"

# Show manual upload instructions
echo -e "${YELLOW}📱 Manual Upload Instructions:${NC}"
echo ""
echo -e "${YELLOW}Step-by-step upload guide:${NC}"
echo ""
echo -e "1. Open your app's testing track in Google Play Console:"
echo -e "   ${BLUE}https://play.google.com/console${NC}"
echo ""
echo "2. Click 'Create new release'"
echo ""
echo "3. Upload the bundle and mapping file:"
echo "   • Drag and drop or click 'Upload' and browse to:"
echo -e "   ${GREEN}${BUNDLE_ABSOLUTE_PATH}${NC}"
echo "   • Upload the deobfuscation file under 'App bundle explorer' > 'Downloads':"
echo -e "   ${GREEN}$(cd .. && pwd)/releases/${APP_SLUG}-v${APP_VERSION}-mapping.txt${NC}"
echo ""
echo "   Open in Finder:"
echo -e "   ${BLUE}file://$(cd .. && pwd)/releases/${NC}"
echo ""
echo "4. Fill release details:"
NEW_VERSION=$(grep -o '"version": "[^"]*' ../app.json | grep -o '[^"]*$')
echo -e "   • Release name: ${GREEN}${NEW_VERSION}${NC} (or auto-generated)"
echo "   • Add release notes describing your changes"
echo ""
echo "5. Review and roll out:"
echo "   • Click 'Next' -> 'Review release'"
echo "   • Click 'Start rollout'"
echo ""
echo -e "${GREEN}✅ Follow the steps above to upload your app!${NC}"
echo ""
echo -e "${YELLOW}⚠️  ⚠️  ⚠️  Manual step required ⚠️  ⚠️  ⚠️${NC}"
echo ""
echo "After closed testing, create a Production release from the Production track"
echo "in Google Play Console:"
echo ""
echo -e "   ${BLUE}https://play.google.com/console${NC}"
echo ""
echo -e "${YELLOW}⚠️  The update will NOT go live until you create a production release.${NC}"
