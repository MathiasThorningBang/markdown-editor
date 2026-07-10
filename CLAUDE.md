# MarkdownEditor

## Design System

This project uses the NM (Nørgaard Mikkelsen) design system, applied to the
editor web view in `Sources/MarkdownEditor/Web/editor.html`.

When touching the editor styling, follow these rules:

* Use only the NM color tokens defined in `:root` in editor.html — never invent new colors

* Fonts: DM Sans (body + headings at bold weight), Geist Mono (code) — bundled
  offline via `@fontsource` imports in `editor/src/main.js`

* Body text minimum 16px, nothing below 12px

* Crepe theming goes through its CSS variables (`--crepe-font-*`, `--crepe-color-*`)
  mapped to NM tokens in editor.html — override those rather than fighting selectors

## Architecture notes

* Crepe's image component sets an inline `height` on `<img>` after load
  (naturalHeight × resize-ratio). The full-width image CSS needs
  `height: auto !important` to beat it.

* Changes to `editor/src/` or fonts require `npm run build` in `editor/`
  (use `/opt/homebrew/bin/npm`), then `./build.sh` to reinstall the app.

* Changes only to `editor.html` or Swift just need `./build.sh`.

