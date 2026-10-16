# MarkdownEditor

WYSIWYG editor for `.md` files on macOS, in the spirit of Typora. The sidebar collects your folders as projects, files save automatically as you type and reload when an agent changes them on disk, and Cmd+click opens links — including local file paths. Everything runs locally, with no network apart from an optional voice download and the update check.

Under the hood it's a SwiftUI app with a bundled [Milkdown Crepe](https://milkdown.dev/docs/guide/using-crepe) editor in a WKWebView. Styling follows the NM design system (DM Sans + Geist Mono) by default.

## Working with agents

- **Copy Path** (toolbar or right-click) puts the file's absolute path on the clipboard.
- **Copy as Reference** (right-click a selection) copies `path:lines` plus the selected text as a quote, ready to paste into Claude Code or Codex. Line numbers are a best guess, since the editor shows the text without markdown syntax.
- Under the file name you see its word count and an estimate of how many tokens an agent spends reading it (about four characters per token).
- Agents can open a file for you with `open -a MarkdownEditor path/to/file.md`.

## Appearance

Open settings with the gear in the toolbar or ⌘, — they open as a page in the editor, not a separate window.

- **Mode:** System, Light or Dark. The sun/moon button in the toolbar switches directly between light and dark.
- **Accent color:** six presets or any color via the macOS color picker. It drives selection, the caret, checked tasks and the active file in the sidebar.
- **Fonts:** separate choices for headings, body text and code — a short curated list first, then every font installed on your Mac.

## Diagrams, charts and HTML

- ` ```mermaid ` blocks render as diagrams (flowcharts, gantt, sequence, …).
- ` ```html ` blocks render inline in a sandboxed iframe. Chart.js is built in as `Chart`, and theme colors are available as CSS variables (`--color-primary`, `--color-card`, …) and as `mdTheme` in scripts.
- `.html` files show up in the sidebar and open as a read-only view that reloads when the file changes on disk.
- `.canvas` files ([JSON Canvas](https://jsoncanvas.org), the format Obsidian uses) open as a pan/zoom board for prototypes and wireframes. HTML file nodes are live frames, and each one reloads when its file changes. Notes and `.md` nodes render as cards, groups and arrows show variants and flows. Drag a frame by its name and resize it from the corner; the new layout is saved to the file. Click a frame to use it, double-click its name to open the file. Drag on the background to select, shift-click to add; ⌘G groups the selection and ⌥-drag draws a new group. Double-click a group's name to rename it, pick its color next to the name, and press Delete (or ⌘⇧G) to remove the group but keep what's inside. Pan with two fingers or space-drag. ⌘Z and ⇧⌘Z undo and redo, and the ? button next to the zoom level lists every shortcut. Drag images, `.html` or `.md` files in from Finder to add them; they're copied to an `assets/` folder next to the canvas.

Everything stays offline: previews, HTML files and canvas frames can't reach the network. See `examples/` for a demo, and `examples/canvas/demo.canvas` for a canvas. The agent skills teach agents the format: `skills/md-editor` for documents, `skills/md-canvas` for canvases.

## Read aloud

The speaker button in the toolbar reads the open `.md` file aloud from the sentence the cursor is in, and highlights each sentence as it's spoken. Pause, resume and stop sit next to it. Markdown is read as text: links and emphasis keep only their words, code blocks are skipped, tables are read cell by cell, and ChatGPT's 【…】 citations are dropped.

The voice follows the document's language. Out of the box it's macOS' own Daniel (English) or Sara (Danish). Settings → Read aloud sets the speed and plays a sample. Apps can't use the Siri voices, so those aren't offered.

Natural-sounding voices that run on your Mac come with an optional build (see [Installation](#natural-voices-optional)): Kokoro's George and Daniel for English, and Plapre Turbo's Mic and Nic for Danish. They're downloaded from Hugging Face in Settings (326 MB and 790 MB).

## Why a markdown editor in 2026?

Because more and more of my work ends up in markdown, and that's no accident.

Markdown is the format AI agents speak best. They read and write it directly, and the structure survives the trip through a model context. Everything an Office document does for humans with layout, markdown does for models with plain text.

You can measure it, too. I tested a batch of real work files (PDF, PowerPoint, Word, Excel) against the same knowledge converted to markdown. Having a model read the raw files costs roughly 6x the tokens, and 15-30x for image-heavy slide decks, because every page gets sent as an image. You pay that price every single time the file is read, not once. The same content in markdown means faster answers and far lower usage.

So the agents work in `.md`. The problem is that raw markdown is a pain for humans to read. This editor exists to close that gap: when an agent writes briefs or reports in markdown, I can read along and make edits in a nice document instead of in the source text. It's the easiest way I've found to stay in the loop.

## Installation

**Requirements:** macOS 14+ and Xcode Command Line Tools with Swift 6 or newer (`xcode-select --install`; if you already have older tools, update them under System Settings → General → Software Update). Node/npm is *not* needed — the web bundle is committed.

```sh
git clone https://github.com/MathiasThorningBang/markdown-editor.git
cd markdown-editor
./build.sh
mkdir -p ~/.claude/skills && cp -R skills/md-editor skills/md-canvas ~/.claude/skills/
```

This builds the app and installs it to `/Applications/MarkdownEditor.app`. The last line installs the agent skills for Claude Code; other agents load skills from their own folder.

### Natural voices (optional)

The neural read-aloud voices need macOS 27 on Apple silicon and two Homebrew packages, which the build copies into the app:

```sh
brew install espeak-ng llama.cpp
KOKORO=1 ./build.sh
```

Then download the voices in Settings → Read aloud. The default `./build.sh` leaves all of this out. Licenses: Kokoro is Apache-2.0 and Plapre Turbo (syv.ai) MIT. Its Kanade decoder and HiFT vocoder come as ONNX from [elgehelge](https://huggingface.co/elgehelge/plapre-onnx-web) under CC BY 4.0, and Mic and Nic are voices from the CoRal TTS dataset (CC0). espeak-ng, which the optional build bundles, is GPL-3.0.

## Updating

In the app: **MarkdownEditor → Check for Updates…**, or Settings → Updates. The app also checks GitHub at launch and puts a dot on the Settings gear when there's something new. **Update and Restart** pulls `main` in the clone the app was built from, runs the same build (with or without the natural voices), updates the agent skills if you have them and reopens the app. It takes a few minutes, and the clone has to be on `main`.

From Terminal, this does the same:

```sh
cd markdown-editor
git pull && ./build.sh && cp -R skills/md-editor skills/md-canvas ~/.claude/skills/
```

Restart the app afterwards if it's running. The skill used to be called `md-editor-format`; if `~/.claude/skills/md-editor-format` exists, delete it so agents don't see the skill twice.

### Let your agent do it

Paste this into Claude Code, Codex or another coding agent with terminal access:

```text
Install or update my MarkdownEditor app to the latest version from
https://github.com/MathiasThorningBang/markdown-editor.

1. Check the build tools with swift --version. The app needs the Xcode Command
   Line Tools with Swift 6 or newer.
   - If they are missing, run xcode-select --install, tell me to click Install
     in the dialog that opens, and check swift --version every 30 seconds until
     it works.
   - If Swift is older than 6, run softwareupdate --list and find the newest
     "Command Line Tools" label. Installing it needs my Mac password, so give me
     the exact command to run in Terminal, sudo softwareupdate --install
     "<label>", and wait until I say it's done. If no such label is listed,
     tell me to install the update from System Settings → General → Software
     Update instead.
   Check swift --version again and continue only when it reports Swift 6 or
   newer.
2. Find my local clone: a folder named markdown-editor containing build.sh and
   Package.swift (look in ~/Desktop, ~/Developer, ~/Documents and ~/code). If
   there is none, clone the repo into ~/Developer/markdown-editor.
3. Note the current commit, then run git status. The app can reformat files it
   has opened, so if the only changes are in README.md or examples/, discard
   them with git restore. If anything else has changed, stop and show me the
   changes instead of overwriting them.
4. Switch to the main branch and run git pull.
5. Run ./build.sh from the repo root. It builds the app and installs it to
   /Applications/MarkdownEditor.app. If it fails, show me the error and stop.
6. Install the agent skills in skills/md-editor and skills/md-canvas: copy both
   folders into ~/.claude/skills/ (replacing older copies) if you are Claude Code, or into
   the folder you load skills from if you are another agent. Delete any old
   copy named md-editor-format there. If you don't support skills, skip this
   step.
7. If MarkdownEditor is running, quit it normally (it saves open files on quit)
   and open it again.
8. Tell me which commit I'm on now and summarize, in a few plain sentences,
   what changed since the commit from step 3.
```

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
