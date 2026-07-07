import { Crepe } from '@milkdown/crepe'
import { replaceAll } from '@milkdown/utils'
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
  })

  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, md, prev) => {
      // Ignore Crepe's initial parse/normalize pass — opening a file must not dirty it.
      if (!ready || suppress || md === prev) return
      window.webkit.messageHandlers.contentChanged.postMessage(md)
    })
  })

  await crepe.create()
  ready = true
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
