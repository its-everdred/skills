#!/usr/bin/env bash
set -euo pipefail

# install.sh — bootstrap the publish-mobile-app scripts into a target project.
#
# Run from the ROOT of an Expo React Native + web project. It:
#   1. copies the deploy scripts into <project>/<mobile-dir>/scripts/
#   2. copies the screenshot runner into <project>/scripts/
#   3. copies templates/.env.example into <project>/<mobile-dir>/.env.example
#      (only if one is not already present)
#   4. wires npm scripts into <project>/<mobile-dir>/package.json and
#      <project>/package.json without clobbering existing scripts
#
# Idempotent: re-running refreshes the scripts and skips any package.json script
# key that already exists.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

MOBILE_DIR="mobile"
DRY_RUN=false

usage() {
    echo "Usage: ./install.sh [--mobile-dir <dir>] [--dry-run]"
    echo ""
    echo "  --mobile-dir <dir>  Path (relative to the project root) of the Expo app."
    echo "                      Default: mobile"
    echo "  --dry-run           Print what would happen without writing anything."
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mobile-dir) shift; [[ $# -gt 0 ]] || usage; MOBILE_DIR="$1" ;;
        --mobile-dir=*) MOBILE_DIR="${1#*=}" ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Unknown argument: $1${NC}"; usage ;;
    esac
    shift
done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
MOBILE_PATH="$PROJECT_ROOT/$MOBILE_DIR"

echo -e "${BLUE}📦 Installing publish-mobile-app into: ${PROJECT_ROOT}${NC}"
echo -e "   mobile dir: ${MOBILE_DIR}"
$DRY_RUN && echo -e "${YELLOW}   (dry run — no files will be written)${NC}"
echo ""

if [ ! -d "$MOBILE_PATH" ]; then
    echo -e "${YELLOW}⚠️  '$MOBILE_DIR' does not exist under the project root.${NC}"
    echo    "   Pass --mobile-dir <dir> if your Expo app lives elsewhere."
    if ! $DRY_RUN; then
        echo -e "   Creating ${MOBILE_DIR}/ ..."
        mkdir -p "$MOBILE_PATH"
    fi
fi

# run <description> <command...> — echo in dry-run, execute otherwise.
run() {
    local desc="$1"; shift
    if $DRY_RUN; then
        echo -e "   ${YELLOW}[dry-run]${NC} $desc"
    else
        "$@"
        echo -e "   ${GREEN}✓${NC} $desc"
    fi
}

# ─────────── 1. Copy deploy scripts into <mobile>/scripts/ ───────────
echo -e "${BLUE}→ Deploy scripts → ${MOBILE_DIR}/scripts/${NC}"
run "create ${MOBILE_DIR}/scripts/" mkdir -p "$MOBILE_PATH/scripts"
for src in "$SKILL_DIR"/scripts/*; do
    base="$(basename "$src")"
    # shots.mjs belongs at the web project root, not in mobile/scripts.
    [ "$base" = "shots.mjs" ] && continue
    run "copy $base" cp "$src" "$MOBILE_PATH/scripts/$base"
done

# ─────────── 2. Copy the screenshot runner into <project>/scripts/ ───────────
echo -e "${BLUE}→ Screenshot runner → scripts/shots.mjs${NC}"
run "create scripts/" mkdir -p "$PROJECT_ROOT/scripts"
run "copy shots.mjs" cp "$SKILL_DIR/scripts/shots.mjs" "$PROJECT_ROOT/scripts/shots.mjs"

# ─────────── 3. Copy .env.example (only if absent) ───────────
echo -e "${BLUE}→ .env template → ${MOBILE_DIR}/.env.example${NC}"
if [ -f "$MOBILE_PATH/.env.example" ]; then
    echo -e "   ${YELLOW}skip${NC} ${MOBILE_DIR}/.env.example already exists"
else
    run "copy .env.example" cp "$SKILL_DIR/templates/.env.example" "$MOBILE_PATH/.env.example"
fi

# ─────────── 4. Wire npm scripts (never clobber) ───────────
# add_scripts <package.json path> <json-object-of-scripts>
# Adds each key only if it is not already present; warns and skips otherwise.
add_scripts() {
    local pkg="$1" additions="$2"
    if [ ! -f "$pkg" ]; then
        echo -e "   ${YELLOW}skip${NC} $pkg not found — cannot add npm scripts"
        return 0
    fi
    if $DRY_RUN; then
        echo -e "   ${YELLOW}[dry-run]${NC} would add scripts to $pkg: $additions"
        return 0
    fi
    ADDITIONS="$additions" node - "$pkg" <<'NODE'
const fs = require('fs');
const pkgPath = process.argv[2];
const additions = JSON.parse(process.env.ADDITIONS);
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.scripts = pkg.scripts || {};
for (const [k, v] of Object.entries(additions)) {
  if (pkg.scripts[k] !== undefined) {
    console.log(`   ⚠️  skip "${k}" — already defined in ${pkgPath}`);
    continue;
  }
  pkg.scripts[k] = v;
  console.log(`   ✓ added "${k}"`);
}
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
NODE
}

echo -e "${BLUE}→ npm scripts → ${MOBILE_DIR}/package.json${NC}"
add_scripts "$MOBILE_PATH/package.json" '{
  "setup:env": "cp -n .env.example .env 2>/dev/null; echo \"Fill in .env with your deploy credentials\"",
  "setup:ios": "bash scripts/setup-ios.sh",
  "setup:android": "bash scripts/setup-android-upload.sh",
  "ios": "bash scripts/run-ios.sh",
  "upload:ios": "bash scripts/upload-ios.sh",
  "upload:android": "bash scripts/upload-android.sh"
}'

echo -e "${BLUE}→ npm scripts → package.json (root)${NC}"
add_scripts "$PROJECT_ROOT/package.json" '{
  "shots": "node scripts/shots.mjs"
}'

# ─────────── Next steps ───────────
echo ""
echo -e "${GREEN}✅ publish-mobile-app installed.${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. cd ${MOBILE_DIR} && npm run setup:env   # create .env, then fill it in"
echo "  2. Ensure app.json has expo.name, expo.slug, expo.ios.bundleIdentifier,"
echo "     expo.android.package and (for iOS uploads) expo.ios.appleTeamId."
echo "  3. iOS:     npm run setup:ios   then   npm run upload:ios"
echo "  4. Android: npm run setup:android   then   npm run upload:android"
echo "  5. Screenshots (from the project root, with the ?shot=1 web build served):"
echo "       npm run shots"
echo "     Add a shots.config.json to describe your screens — see the skill's"
echo "     references/screenshots.md."
