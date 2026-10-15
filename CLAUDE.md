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

* No SwiftUI macros (`@State`, `@Observable`, `#Preview`): with only the Command Line
  Tools installed, `swift build` has no SwiftUI macro plugin. State lives in
  `ObservableObject`s with `@Published`, as the code already does.

* Settings is a page in the editor canvas (`SettingsView`, `session.showSettings`),
  not a separate window.

* Crepe's image component sets an inline `height` on `<img>`; full-width images
  need `height: auto !important`.

* Changes to `editor/src/` need a bundle rebuild in `editor/`: `node build.mjs`
  (npm isn't installed here; install deps with `pnpm dlx npm@10 ci`). Then `./build.sh`.

* Changes only to `editor.html` or Swift just need `./build.sh`. Restart the app afterwards.

* Read aloud (`Speech/`) reads one sentence at a time and highlights it in the
  editor (`window.readAloudHighlight` in `editor.html`, overlay divs, so the
  document is never touched). The voice follows the document's language: English reads
  with Kokoro-82M (Daniel by default, or George), Danish with Plapre Turbo (Mic or Nic,
  syv.ai, MIT: keep the credit in Settings), each when built in and downloaded from
  Settings to Application Support (326 MB and 790 MB, pinned Hugging Face revisions).
  Otherwise the system's Daniel or Sara. Apps can't use the Siri voices:
  `AVSpeechSynthesisVoice.speechVoices()` hides them outside Apple's own binaries.

* `VoicePlayer` trims the silence the models put around each sentence and adds its own
  pauses (0.2 s between sentences, 0.45 s after a block), and generates until 8 s of
  audio are queued.

* Plapre (`Speech/Plapre.swift`): Turbo's language model (GGUF q8) runs in llama.cpp on
  the GPU, fed the text, its Danish espeak phonemes (`Plapre.phonemes`, like phonemizer
  without stress marks) and Mic's or Nic's vector (`PlapreSpeakers.json`, projected
  ahead of time with Turbo's speaker_proj.pt). elgehelge's ONNX Kanade decoder and HiFT
  vocoder make the audio. The GGUF repeats one token's text, which llama.cpp refuses:
  `patchRepeatedTokens` fixes the file in place. Long sentences go in pieces of about
  150 characters, each played as soon as it's ready. The model sometimes doesn't stop:
  `<eos>` is boosted past the expected length, and speech that still runs long is
  generated once more. Kanade fails above about 500 tokens.
  Tried and dropped: Plapre Pico on ONNX (CPU only, couldn't keep up with playback),
  int8 language models (clearly worse voice), and cutting the silent mel frames before
  HiFT (it changes the whole spectrum). HiFT is the slowest step, and memory pressure
  (swap) slows everything.

* Kokoro (also building Plapre) is a package trait: `KOKORO=1 ./build.sh` (`swift build --traits Kokoro`),
  code behind `#if Kokoro`. It needs `brew install espeak-ng llama.cpp`; `build.sh` then copies
  the libraries (with ggml's Metal and CPU backend plugins and libomp), espeak's English and
  Danish data into the app and re-signs them, and the app requires macOS 27 (Homebrew's
  builds do). Homebrew's llama.cpp is newer than the one Plapre Turbo was made with. Prebuilt espeak-ng binaries (pip wheels, sherpa-onnx) can't find their
  data on macOS 27. The default build has none of this.
