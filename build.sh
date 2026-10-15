#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# KOKORO=1 ./build.sh adds the Kokoro read-aloud voices (see Package.swift).
swift build -c release ${KOKORO:+--traits Kokoro}

APP=build/MarkdownEditor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MarkdownEditor "$APP/Contents/MacOS/"
cp -R .build/release/MarkdownEditor_MarkdownEditor.bundle "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/"

# Kokoro and Plapre voices: espeak-ng turns text into phonemes and llama.cpp runs
# Plapre's language model (brew install espeak-ng llama.cpp). Bundle the libraries,
# llama.cpp's Metal and CPU backends and espeak's English and Danish data so the app
# runs without Homebrew.
if [ -n "${KOKORO:-}" ]; then
ESPEAK=/opt/homebrew/opt/espeak-ng
PCAUDIO=/opt/homebrew/opt/pcaudiolib
FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS" "$APP/Contents/Resources/espeak-ng-data"
cp "$ESPEAK/lib/libespeak-ng.1.dylib" "$PCAUDIO/lib/libpcaudio.0.dylib" "$FRAMEWORKS/"
chmod u+w "$FRAMEWORKS/"*.dylib
install_name_tool -id @rpath/libespeak-ng.1.dylib "$FRAMEWORKS/libespeak-ng.1.dylib"
install_name_tool -id @rpath/libpcaudio.0.dylib "$FRAMEWORKS/libpcaudio.0.dylib"
install_name_tool -change "$PCAUDIO/lib/libpcaudio.0.dylib" @rpath/libpcaudio.0.dylib "$FRAMEWORKS/libespeak-ng.1.dylib"
install_name_tool -change "$ESPEAK/lib/libespeak-ng.1.dylib" @rpath/libespeak-ng.1.dylib "$APP/Contents/MacOS/MarkdownEditor"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/MarkdownEditor"
(cd "$ESPEAK/share/espeak-ng-data" && cp -R phontab phonindex phondata intonations en_dict da_dict lang "$OLDPWD/$APP/Contents/Resources/espeak-ng-data/")

LLAMA=/opt/homebrew/opt/llama.cpp
GGML=/opt/homebrew/opt/ggml
OMP=/opt/homebrew/opt/libomp
cp "$LLAMA/lib/libllama.0.dylib" "$GGML/lib/libggml.0.dylib" "$GGML/lib/libggml-base.0.dylib" "$OMP/lib/libomp.dylib" \
    "$GGML"/libexec/*.so "$FRAMEWORKS/"
chmod u+w "$FRAMEWORKS/"*
for lib in "$FRAMEWORKS"/libllama.0.dylib "$FRAMEWORKS"/libggml*.dylib "$FRAMEWORKS"/libomp.dylib "$FRAMEWORKS"/*.so; do
    name=$(basename "$lib")
    case "$name" in *.dylib) install_name_tool -id "@rpath/$name" "$lib" 2>/dev/null ;; esac
    install_name_tool -add_rpath @loader_path "$lib" 2>/dev/null || true
    # Point every Homebrew path at the bundled copy.
    for dep in $(otool -L "$lib" | awk '/\/opt\/homebrew\//{print $1}'); do
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$lib"
    done
done
for dep in $(otool -L "$APP/Contents/MacOS/MarkdownEditor" | awk '/\/opt\/homebrew\/opt\/(llama.cpp|ggml)\//{print $1}'); do
    install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$APP/Contents/MacOS/MarkdownEditor"
done
# The edits above break the libraries' signatures; loose plugins aren't covered by --deep.
codesign --force --sign - "$FRAMEWORKS"/*
fi

codesign --force --deep --sign - "$APP"

rm -rf /Applications/MarkdownEditor.app
cp -R "$APP" /Applications/

# Refresh LaunchServices so Finder picks up the document types
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MarkdownEditor.app

echo "✅ Installed /Applications/MarkdownEditor.app"
