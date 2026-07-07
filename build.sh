#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/MarkdownEditor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MarkdownEditor "$APP/Contents/MacOS/"
cp -R .build/release/MarkdownEditor_MarkdownEditor.bundle "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"

rm -rf /Applications/MarkdownEditor.app
cp -R "$APP" /Applications/

# Refresh LaunchServices so Finder picks up the document types
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MarkdownEditor.app

echo "✅ Installed /Applications/MarkdownEditor.app"
