# MarkdownEditor

## Design system

NM design system, applied in `Sources/MarkdownEditor/Web/editor.html`.

* Colors only from the tokens in `:root` (light) and its `prefers-color-scheme: dark`
  block (Codex-style dark). Mirror changes in `UI/NMColors.swift`.

* `--color-primary` (accent) and `--font-heading/-body/-mono` are user settings:
  Swift sets them on every web view from `ThemeSettings`. Never hardcode them.
  Defaults: NM red, DM Sans, Geist Mono (bundled via `@fontsource` in `editor/src/main.js`).

* Body text minimum 16px, nothing below 12px.

* Theme Crepe through its `--crepe-*` variables, not by fighting selectors.

## Architecture notes

* ```html/```mermaid previews: `editor/src/preview.js`. Crepe sanitizes previews
  (strips iframes), so it returns an empty slot that a MutationObserver fills.
  HTML runs in `sandbox="allow-scripts"` iframes with a no-network CSP.
* `Web/preview-runtime.js` (tokens, Chart.js defaults, `mdTheme`) is shared by
  those iframes and by `.html` files (`HTMLViewerController`). It holds a third
  copy of the color tokens.
* Swift only accepts script messages from the main frame.

* Settings is a page in the editor canvas (`SettingsView`, `session.showSettings`),
  not a separate window.

* Crepe's image component sets an inline `height` on `<img>`; full-width images
  need `height: auto !important`.

* Changes to `editor/src/` need a bundle rebuild in `editor/`: `node build.mjs`
  (npm isn't installed here; install deps with `pnpm dlx npm@10 ci`). Then `./build.sh`.

* Changes only to `editor.html` or Swift just need `./build.sh`. Restart the app afterwards.

