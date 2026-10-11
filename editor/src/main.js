import { Crepe } from '@milkdown/crepe'
import { replaceAll } from '@milkdown/utils'
import { EditorView } from '@codemirror/view'
import { HighlightStyle, syntaxHighlighting } from '@codemirror/language'
import { tags } from '@lezer/highlight'
import { renderPreview, startPreviews } from './preview.js'
import '@milkdown/crepe/theme/common/style.css'
import '@milkdown/crepe/theme/frame.css'

// NM design system fonts, bundled offline via esbuild dataurl loader
import '@fontsource/dm-sans/400.css'
import '@fontsource/dm-sans/400-italic.css'
import '@fontsource/dm-sans/500.css'
import '@fontsource/dm-sans/600.css'
import '@fontsource/dm-sans/700.css'
import '@fontsource/dm-sans/700-italic.css'
import '@fontsource/geist-mono/400.css'
import '@fontsource/geist-mono/600.css'

// Grayscale code block theme on NM tokens — replaces Crepe's default oneDark,
// which is a dark palette rendered on our light surface.
const codeTheme = [
  EditorView.theme({
    '&': { color: 'var(--color-foreground)', backgroundColor: 'transparent' },
    '.cm-content': { caretColor: 'var(--color-foreground)' },
    '.cm-cursor': { borderLeftColor: 'var(--color-foreground)' },
    '.cm-gutters': { color: 'var(--color-muted-foreground)', backgroundColor: 'transparent', border: 'none' },
    '.cm-activeLine, .cm-activeLineGutter': { backgroundColor: 'transparent' },
    '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection': {
      backgroundColor: 'color-mix(in srgb, var(--color-primary) 22%, transparent)',
    },
  }),
  syntaxHighlighting(HighlightStyle.define([
    { tag: [tags.keyword, tags.operatorKeyword, tags.controlKeyword, tags.definitionKeyword, tags.moduleKeyword], fontWeight: '600' },
    { tag: [tags.string, tags.special(tags.string), tags.regexp], color: 'var(--color-secondary-foreground)' },
    { tag: [tags.comment, tags.meta], color: 'var(--color-muted-foreground)' },
    { tag: tags.heading, fontWeight: '600' },
  ])),
]

let crepe = null
let suppress = false
let ready = false

// Called from Swift once the page has loaded.
window.initEditor = async (markdown, baseHref) => {
  // Make relative image paths resolve against the document's folder (served via mdfile:// scheme).
  if (baseHref) {
    const base = document.createElement('base')
    base.href = baseHref
    document.head.appendChild(base)
  }

  crepe = new Crepe({
    root: document.getElementById('editor'),
    defaultValue: markdown,
    featureConfigs: {
      [Crepe.Feature.CodeMirror]: {
        theme: codeTheme,
        // ```html and ```mermaid blocks show rendered; the toggle reveals the source.
        renderPreview,
        previewOnlyByDefault: true,
        previewToggleText: (previewOnly) => (previewOnly ? 'Redigér' : 'Skjul kode'),
        previewLabel: 'Visning',
      },
    },
  })

  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, md, prev) => {
      retagPathCode()
      // Ignore Crepe's initial parse/normalize pass — opening a file must not dirty it.
      if (!ready || suppress || md === prev) return
      window.webkit.messageHandlers.contentChanged.postMessage(md)
    })
  })

  startPreviews(document.getElementById('editor'))
  await crepe.create()
  ready = true
  retagPathCode()
  // Swift keeps this web view hidden until the editor has rendered.
  window.webkit.messageHandlers.editorReady.postMessage(true)
}

// Called from Swift when the document changes outside the editor (e.g. Revert).
window.setMarkdown = (markdown) => {
  if (!crepe) return
  suppress = true
  try {
    crepe.editor.action(replaceAll(markdown))
  } finally {
    suppress = false
  }
}

// Cmd+click on a link or a path-like inline code span opens it externally (handled by Swift).
const PATH_RE = /^(~\/|\.\.?\/|\/)/

// Tag path-like inline code spans so CSS can show the Cmd-held affordance on them only.
// Code blocks render via CodeMirror (no <code> element), so this matches inline code only.
function retagPathCode() {
  for (const code of document.querySelectorAll('#editor code')) {
    code.classList.toggle('path-code', PATH_RE.test(code.textContent.trim()))
  }
}

// Capture phase: run before ProseMirror's own click handling so we can hijack Cmd+clicks.
document.addEventListener('click', (e) => {
  if (!e.metaKey) return

  const link = e.target.closest('a[href]')
  const code = link ? null : e.target.closest('code')
  let target = null
  if (link) {
    // Raw attribute, not .href — the <base> tag would mangle ~/ paths.
    target = link.getAttribute('href')
  } else if (code && PATH_RE.test(code.textContent.trim())) {
    target = code.textContent.trim()
  }
  if (!target) return

  e.preventDefault()
  e.stopPropagation()
  window.webkit.messageHandlers.openLink.postMessage(target)
}, true)

const setCmdHeld = (held) => document.body.classList.toggle('cmd-held', held)
window.addEventListener('keydown', (e) => { if (e.key === 'Meta') setCmdHeld(true) })
window.addEventListener('keyup', (e) => { if (e.key === 'Meta') setCmdHeld(false) })
window.addEventListener('blur', () => setCmdHeld(false))
