import mermaid from 'mermaid'

// Inlined at build time (build.mjs): Chart.js and the shared theme runtime.
/* global CHART_SRC, RUNTIME_SRC */

// No network from previews: inline scripts/styles and data: URLs only.
const CSP = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; ` +
  `script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:">`

// Crepe passes every preview through DOMPurify, which strips iframes. So
// renderPreview returns an empty slot, and mountSlots fills it afterwards.
const pending = new Map()
let nextId = 0

export function renderPreview(language, content) {
  const kind = language.toLowerCase()
  if ((kind !== 'html' && kind !== 'mermaid') || !content.trim()) return null
  const id = String(++nextId)
  pending.set(id, { kind, content })
  return `<div class="md-preview-slot md-preview-${kind}" data-preview-id="${id}"></div>`
}

const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

function mount(slot) {
  const entry = slot.mdPreview
  slot.replaceChildren()
  if (entry.kind === 'html') mountHTML(slot, entry.content)
  else mountMermaid(slot, entry.content)
}

function mountHTML(slot, html) {
  const theme = {
    primary: cssVar('--color-primary'),
    fontBody: cssVar('--font-body'),
    fontMono: cssVar('--font-mono'),
    fragment: true,
  }
  const themeJSON = JSON.stringify(theme).replace(/</g, '\\u003c')
  const iframe = document.createElement('iframe')
  // allow-scripts without allow-same-origin: no access to the editor or its message handlers.
  iframe.setAttribute('sandbox', 'allow-scripts')
  iframe.srcdoc = `<!doctype html><html><head><meta charset="utf-8">${CSP}` +
    `<script>window.__mdTheme=${themeJSON}<\/script>` +
    `<script>${CHART_SRC}<\/script><script>${RUNTIME_SRC}<\/script>` +
    `</head><body>${html}</body></html>`
  slot.append(iframe)
}

let mermaidCount = 0

async function mountMermaid(slot, source) {
  const dark = matchMedia('(prefers-color-scheme: dark)').matches
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: 'base',
    fontFamily: cssVar('--font-body'),
    // SVG text labels: HTML labels would pick up the editor's paragraph styles.
    htmlLabels: false,
    flowchart: { htmlLabels: false },
    gantt: { fontSize: 14, sectionFontSize: 14, barHeight: 24 },
    themeVariables: {
      fontSize: '15px',
      todayLineColor: cssVar('--color-muted-foreground'),
      darkMode: dark,
      background: cssVar('--color-background'),
      primaryColor: cssVar('--color-card'),
      primaryTextColor: cssVar('--color-foreground'),
      primaryBorderColor: cssVar('--color-border'),
      secondaryColor: cssVar('--color-muted'),
      tertiaryColor: cssVar('--color-background'),
      lineColor: cssVar('--color-muted-foreground'),
      textColor: cssVar('--color-foreground'),
      // Accent marks the active/critical items (gantt bars, highlights).
      taskBkgColor: cssVar('--color-primary'),
      activeTaskBkgColor: cssVar('--color-primary'),
      critBkgColor: cssVar('--color-primary'),
      taskTextColor: '#ffffff',
      taskTextLightColor: '#ffffff',
      taskTextOutsideColor: cssVar('--color-foreground'),
    },
  })
  const id = `md-mermaid-${++mermaidCount}`
  try {
    const { svg } = await mermaid.render(id, source)
    if (slot.isConnected) slot.innerHTML = svg
  } catch (err) {
    document.getElementById(id)?.remove()
    document.getElementById(`d${id}`)?.remove()
    const error = document.createElement('pre')
    error.className = 'md-preview-error'
    error.textContent = String(err?.message || err)
    if (slot.isConnected) slot.replaceChildren(error)
  }
}

// Fill new slots as Crepe inserts them.
export function startPreviews(root) {
  new MutationObserver(() => {
    for (const slot of root.querySelectorAll('.md-preview-slot:not([data-mounted])')) {
      const entry = pending.get(slot.dataset.previewId)
      if (!entry) continue
      pending.delete(slot.dataset.previewId)
      slot.dataset.mounted = ''
      slot.mdPreview = entry
      mount(slot)
    }
  }).observe(root, { childList: true, subtree: true })

  // Sized by the iframe itself (preview-runtime.js); only trust our own frames.
  window.addEventListener('message', (e) => {
    const height = e.data?.mdPreviewHeight
    if (typeof height !== 'number') return
    for (const iframe of root.querySelectorAll('.md-preview-html iframe')) {
      if (iframe.contentWindow === e.source) iframe.style.height = `${Math.ceil(height)}px`
    }
  })

  // Accent, fonts or light/dark changed: redraw every preview with the new tokens.
  let timer = null
  window.themeChanged = () => {
    clearTimeout(timer)
    timer = setTimeout(() => {
      for (const slot of root.querySelectorAll('.md-preview-slot[data-mounted]')) mount(slot)
    }, 100)
  }
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => window.themeChanged())
}
