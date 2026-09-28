#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/轻读.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -X "$BIN_DIR/Reader" "$APP/Contents/MacOS/Reader.next"
mv -f "$APP/Contents/MacOS/Reader.next" "$APP/Contents/MacOS/Reader"
cp -X Resources/Info.plist "$APP/Contents/Info.plist"
cp -X Resources/appearance.js "$APP/Contents/Resources/appearance.js"
cp -X Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Documents may be managed by File Provider, which adds Finder metadata to new bundles.
# Remove only that generated bundle metadata before signing; source files are untouched.
SIGNED=false
for ATTEMPT in 1 2 3; do
    # File Provider may attach metadata asynchronously just after the bundle changes.
    sleep 1
    if xattr -p com.apple.FinderInfo "$APP" >/dev/null 2>&1; then
        xattr -d com.apple.FinderInfo "$APP"
    fi
    if codesign --force --sign - "$APP" && codesign --verify --strict "$APP"; then
        SIGNED=true
        break
    fi
    printf 'Signing attempt %s failed; retrying after checking generated Finder metadata.\n' "$ATTEMPT" >&2
done
if [ "$SIGNED" != true ]; then
    printf 'App signing or verification failed.\n' >&2
    exit 1
fi
printf 'Built: %s/%s\n' "$PWD" "$APP"
