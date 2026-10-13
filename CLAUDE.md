# MarkdownEditor

## Design system

NM design system, applied in `Sources/MarkdownEditor/Web/editor.html`.

* Colors only from the tokens in `:root` (light) and its `prefers-color-scheme: dark`
  block (Codex-style dark). Mirror changes in `UI/NMColors.swift`.

* `--color-primary` (accent) and `--font-heading/-body/-mono` are user settings:
  Swift sets them on every web view from `ThemeSettings`. Never hardcode them.
  Defaults: NM red, DM Sans, Geist Mono (bundled via `@fontsource` in `editor/src/main.js`).

* Body text minimum 16px, nothing below 12px.

* All UI text is English: menus, toolbar, settings, alerts, toasts, a11y labels and
  the editor's own labels in `editor/src/`. This overrides the global Danish preference.

* Theme Crepe through its `--crepe-*` variables, not by fighting selectors.

## Architecture notes

* ```html/```mermaid previews: `editor/src/preview.js`. Crepe sanitizes previews
  (strips iframes), so it returns an empty slot that a MutationObserver fills.
  HTML runs in `sandbox="allow-scripts"` iframes with a no-network CSP.

* `Web/preview-runtime.js` (tokens, Chart.js defaults, `mdTheme`) is shared by
  those iframes and by `.html` files (`HTMLViewerController`). It holds a third
  copy of the color tokens.

* Swift only accepts script messages from the main frame.

* `.canvas` (JSON Canvas): `CanvasController` + `Web/canvas.html` + `editor/src/canvas.js`
  (bundled to `canvas.bundle.js/.css`). The canvas JSON is the document's text, so
  autosave/reload/conflicts are `OpenDocument`'s. The page posts the whole JSON on
  move/resize and must never post on load. Frames are `mdfile://` iframes with
  `sandbox="allow-scripts allow-forms"`; tokens come from the injected runtime
  (`canvas: true` keeps the canvas page from reloading on dark mode). Files the nodes
  point at are checked via `OpenDocument.onDiskCheck` on the session's 1 s loop.

* `skills/md-editor/SKILL.md` tells agents what the app renders and how to
  open files in it; `skills/md-canvas/SKILL.md` does the same for canvases. Update
  them when previews, canvas or agent features change.

* `design/app.canvas` is the app itself as HTML screens, for trying UI changes
  before building them. The window chrome lives once in `design/screens/chrome.js`
  and `app.css`. Keep it in step when the UI changes.

* Open files sync with disk: `SessionModel` checks each file's modification date
  once a second. Clean docs reload (`window.setMarkdown`), dirty ones ask.
  `OpenDocument.flush()` never writes over a file that changed or vanished.

* At most 8 live web views (`liveEditorLimit`); evicted docs keep their text.

* Swift 6 language mode. WebKit delegate methods must copy the SDK's `@MainActor`
  on closure parameters, or they silently stop matching the protocol.

* Settings is a page in the editor canvas (`SettingsView`, `session.showSettings`),
  not a separate window.

* Crepe's image component sets an inline `height` on `<img>`; full-width images
  need `height: auto !important`.

* Changes to `editor/src/` need a bundle rebuild in `editor/`: `node build.mjs`
  (npm isn't installed here; install deps with `pnpm dlx npm@10 ci`). Then `./build.sh`.

* Changes only to `editor.html` or Swift just need `./build.sh`. Restart the app afterwards.

