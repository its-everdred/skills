#!/bin/bash

# Load environment variables (line-by-line; preserves values verbatim)
if [ -f ".env" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|\#*) continue ;; esac
        [ "${line#*=}" = "$line" ] && continue
        key="${line%%=*}"; value="${line#*=}"; value="${value%$'\r'}"; export "$key=$value"
    done < .env
fi

# Fall back to the Apple Team ID configured in app.json when it is not in .env.
if [ -z "${APPLE_TEAM_ID:-}" ]; then
    APPLE_TEAM_ID=$(grep -o '"appleTeamId": "[^"]*' app.json | grep -o '[^"]*$' | head -1)
fi

# Read the iOS bundle identifier from app.json so the provisioning profile entry
# always matches the configured app (no hardcoded bundle id).
BUNDLE_ID=$(grep -o '"bundleIdentifier": "[^"]*' app.json | grep -o '[^"]*$')

if [ -z "$BUNDLE_ID" ]; then
    echo "❌ Error: could not read ios.bundleIdentifier from app.json"
    exit 1
fi

# Generate ExportOptions.plist with actual team ID
cat > ios/ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID}</string>
    <key>uploadBitcode</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_ID}</key>
        <string>Automatic</string>
    </dict>
</dict>
</plist>
EOF

echo "✓ Generated ExportOptions.plist with Team ID: ${APPLE_TEAM_ID} (bundle: ${BUNDLE_ID})"
