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

