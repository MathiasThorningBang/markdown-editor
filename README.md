# MarkdownEditor

WYSIWYG editor for `.md` files on macOS, in the spirit of Typora. The sidebar collects your folders as projects, files save automatically as you type, and Cmd+click opens links — including local file paths. Everything runs locally, no network.

Under the hood it's a SwiftUI app with a bundled [Milkdown Crepe](https://milkdown.dev/docs/guide/using-crepe) editor in a WKWebView. Styling follows the NM design system (DM Sans + Geist Mono) by default.

## Appearance

Open settings with the gear in the toolbar or ⌘, — they open as a page in the editor, not a separate window.

- **Mode:** System, Light or Dark. The sun/moon button in the toolbar switches directly between light and dark.
- **Accent color:** six presets or any color via the macOS color picker. It drives selection, the caret, checked tasks and the active file in the sidebar.
- **Fonts:** separate choices for headings, body text and code — a short curated list first, then every font installed on your Mac.

## Why a markdown editor in 2026?

Because more and more of my work ends up in markdown, and that's no accident.

Markdown is the format AI agents speak best. They read and write it directly, and the structure survives the trip through a model context. Everything an Office document does for humans with layout, markdown does for models with plain text.

You can measure it, too. I tested a batch of real work files (PDF, PowerPoint, Word, Excel) against the same knowledge converted to markdown. Having a model read the raw files costs roughly 6x the tokens, and 15-30x for image-heavy slide decks, because every page gets sent as an image. You pay that price every single time the file is read, not once. The same content in markdown means faster answers and far lower usage.

So the agents work in `.md`. The problem is that raw markdown is a pain for humans to read. This editor exists to close that gap: when an agent writes briefs or reports in markdown, I can read along and make edits in a nice document instead of in the source text. It's the easiest way I've found to stay in the loop.

## Installation

**Requirements:** macOS 14+ and Xcode Command Line Tools (`xcode-select --install`). Node/npm is *not* needed — the web bundle is committed.

```sh
git clone https://github.com/MathiasThorningBang/markdown-editor.git
cd markdown-editor
./build.sh
```

This builds the app and installs it to `/Applications/MarkdownEditor.app`.

## Updating

If you already have the app installed, this pulls the latest version and reinstalls it:

```sh
cd markdown-editor
git pull && ./build.sh
```

Restart the app afterwards if it's running.

### Set as the default app for .md

Finder → right-click a `.md` file → **Get Info** → **Open with:** MarkdownEditor → **Change All…**

## Development

### The web editor (only when changing editor/)

```sh
cd editor
npm install
npm run build   # bundles into Sources/MarkdownEditor/Web/ (committed)
```

### App icon

The source is `icon/AppIcon-1024.png` (1024×1024 PNG with alpha). Regenerate `AppIcon.icns` with:

```sh
cd icon && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o ../AppIcon.icns && rm -rf AppIcon.iconset
```

## Known tradeoffs

- Crepe normalizes the markdown source on first edit + save (lists become `*`, tables get padded). Content is preserved, but the first git diff can be noisy.
- No App Sandbox (internal app, not App Store) — images next to the .md file are served through a custom `mdfile://` URL scheme.
- Ad-hoc signed. Gatekeeper may complain the first time, but since the app is built locally on your own machine, that's rarely an issue.

## License

MIT — fonts (DM Sans, Geist Mono) are under the SIL Open Font License via @fontsource.
