#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to increment version
increment_version() {
    local version=$1
    local part=$2

    # Split version into parts
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    local major=${VERSION_PARTS[0]}
    local minor=${VERSION_PARTS[1]}
    local patch=${VERSION_PARTS[2]}

    # Increment based on part
    case $part in
        "major")
            ((major++))
            minor=0
            patch=0
            ;;
        "minor")
            ((minor++))
            patch=0
            ;;
        "patch")
            ((patch++))
            ;;
    esac

    echo "$major.$minor.$patch"
}

# Function to calculate versionCode from version string
calculate_version_code() {
    local version=$1

    # Split version into parts
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    local major=${VERSION_PARTS[0]}
    local minor=${VERSION_PARTS[1]}
    local patch=${VERSION_PARTS[2]}

    # Calculate versionCode: major*10000 + minor*100 + patch
    # This ensures proper ordering and allows up to 99 minor versions and 99 patches
    echo $((major * 10000 + minor * 100 + patch))
}

# Parse arguments or ask interactively
if [ -n "$1" ]; then
    VERSION_TYPE=$1
else
    # Interactive mode
    echo -e "${BLUE}🔢 Version Bump Tool${NC}"
    echo ""
    echo "What type of changes are you releasing?"
    echo ""
    echo -e "${RED}Major${NC} - Breaking changes, incompatible API changes"
    echo -e "${YELLOW}Minor${NC} - New features, backwards compatible"
    echo -e "${GREEN}Patch${NC} - Bug fixes, small improvements"
    echo -e "${BLUE}Overwrite${NC} - Keep same version, rebuild existing release"
    echo ""
    echo "Enter your choice:"
    echo "  1) Major"
    echo "  2) Minor"
    echo "  3) Patch (default)"
    echo "  4) Overwrite (same version)"
    echo ""
    read -p "Selection [1-4]: " choice

    case $choice in
        1)
            VERSION_TYPE="major"
            ;;
        2)
            VERSION_TYPE="minor"
            ;;
        3|"")
            VERSION_TYPE="patch"
            ;;
        4)
            VERSION_TYPE="overwrite"
            ;;
        *)
            echo -e "${RED}❌ Invalid selection${NC}"
            exit 1
            ;;
    esac
fi

# Validate version type
if [[ ! "$VERSION_TYPE" =~ ^(major|minor|patch|overwrite)$ ]]; then
    echo -e "${RED}❌ Invalid version type: $VERSION_TYPE${NC}"
    echo "Usage: $0 [major|minor|patch|overwrite]"
    exit 1
fi

echo ""

# Read current version from app.json
CURRENT_VERSION=$(grep -o '"version": "[^"]*' app.json | grep -o '[^"]*$')

# Read current versionCode from app.json (falls back to calculating from version)
CURRENT_VERSION_CODE=$(python3 -c "import json; d=json.load(open('app.json')); print(d.get('expo',{}).get('android',{}).get('versionCode', 0))" 2>/dev/null || echo "0")

if [ "$VERSION_TYPE" = "overwrite" ]; then
    echo -e "${BLUE}🔄 Keeping current version for rebuild...${NC}"
    echo -e "Current version: ${YELLOW}$CURRENT_VERSION${NC}"
    echo -e "New version: ${GREEN}$CURRENT_VERSION${NC} (no change)"

    NEW_VERSION=$CURRENT_VERSION
    NEW_VERSION_CODE=$((CURRENT_VERSION_CODE + 1))
    echo -e "New versionCode: ${GREEN}$NEW_VERSION_CODE${NC} (incremented for rebuild)"
else
    echo -e "${BLUE}🔢 Bumping $VERSION_TYPE version...${NC}"
    echo -e "Current version: ${YELLOW}$CURRENT_VERSION${NC}"

    # Calculate new version
    NEW_VERSION=$(increment_version $CURRENT_VERSION $VERSION_TYPE)
    echo -e "New version: ${GREEN}$NEW_VERSION${NC}"

    # Calculate versionCode based on semantic version
    NEW_VERSION_CODE=$(calculate_version_code $NEW_VERSION)
    echo -e "New versionCode: ${GREEN}$NEW_VERSION_CODE${NC} (calculated from version)"
fi

# Update app.json (version + android.versionCode) using python for reliable JSON editing
python3 -c "
import json
with open('app.json', 'r') as f:
    data = json.load(f)
data['expo']['version'] = '$NEW_VERSION'
data['expo'].setdefault('android', {})['versionCode'] = $NEW_VERSION_CODE
# Keep the iOS build number in lockstep with versionCode so every build — including
# an 'overwrite' rebuild of the same marketing version — uploads a unique
# CFBundleVersion. TestFlight rejects a reused (version, build number) pair.
data['expo'].setdefault('ios', {})['buildNumber'] = str($NEW_VERSION_CODE)
with open('app.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

# Update package.json (portable in-place edit: -i.bak works on both BSD/macOS
# and GNU sed; remove the backup afterwards)
sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" package.json && rm -f package.json.bak

if [ "$VERSION_TYPE" = "overwrite" ]; then
    echo -e "${GREEN}✅ Version maintained for rebuild!${NC}"
    echo ""
    echo -e "${YELLOW}Updated files:${NC}"
    echo "  • app.json: $NEW_VERSION, versionCode $NEW_VERSION_CODE, buildNumber $NEW_VERSION_CODE"
    echo "  • package.json: $NEW_VERSION"
else
    echo -e "${GREEN}✅ Version bumped successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Updated files:${NC}"
    echo "  • app.json: $NEW_VERSION, versionCode $NEW_VERSION_CODE, buildNumber $NEW_VERSION_CODE"
    echo "  • package.json: $NEW_VERSION"
fi
