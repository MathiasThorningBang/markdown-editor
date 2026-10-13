// Theme runtime shared by ```html previews (sandboxed iframes, via the editor
// bundle) and opened .html files (WKUserScript from Swift). Runs before any
// page content; expects window.__mdTheme = { primary, fontBody, fontMono, fragment, canvas }.
(() => {
  const theme = window.__mdTheme || {}

  // Mirrors the tokens in editor.html and UI/NMColors.swift — keep in sync.
  const LIGHT = {
    background: '#ffffff', foreground: '#171717', card: '#f7f7f7', muted: '#f5f5f5',
    'muted-foreground': '#a3a3a3', 'secondary-foreground': '#525252',
    border: '#e5e5e5', 'nm-blue': '#2e7ab5',
  }
  const DARK = {
    background: '#181818', foreground: '#ffffff', card: '#212121', muted: '#2a2a2a',
    'muted-foreground': '#8a8a8a', 'secondary-foreground': '#b4b4b4',
    border: '#2e2e2e', 'nm-blue': '#5b9bd5',
  }

  const primary = theme.primary || '#df475c'
  const fontBody = theme.fontBody || 'system-ui, sans-serif'
  const fontMono = theme.fontMono || 'ui-monospace, monospace'
  const vars = (t) => Object.entries(t).map(([k, v]) => `--color-${k}:${v};`).join('')

  let css = `:root{--color-primary:${primary};--font-body:${fontBody};--font-mono:${fontMono};` +
    `${vars(LIGHT)}color-scheme:light dark}` +
    `@media (prefers-color-scheme: dark){:root{${vars(DARK)}}}`
  if (theme.fragment) {
    // Fragments sit inside the document: transparent, document type, no scrollbars.
    css += 'html,body{margin:0;padding:0;background:transparent;overflow:hidden}' +
      'body{color:var(--color-foreground);font:16px/1.6 var(--font-body);display:flow-root}'
  }
  const style = document.createElement('style')
  style.textContent = css
  // First child of <html>: the page's own styles come later and win.
  document.documentElement.prepend(style)

  const dark = matchMedia('(prefers-color-scheme: dark)')
  const tokens = dark.matches ? DARK : LIGHT

  // Series colors: the accent first, then the other accent presets.
  const palette = [...new Set([primary, tokens['nm-blue'], '#2f9e6b', '#e07a2e', '#7c5cd6',
    tokens['secondary-foreground']].map((c) => c.toLowerCase()))]

  // Resolved colors for page scripts, e.g. mdTheme.primary or mdTheme.palette[1].
  window.mdTheme = {
    primary, palette, fontBody, fontMono, dark: dark.matches,
    ...Object.fromEntries(Object.entries(tokens).map(([k, v]) =>
      [k.replace(/-(\w)/g, (_, c) => c.toUpperCase()), v])),
  }

  if (window.Chart) {
    Chart.defaults.color = tokens['secondary-foreground']
    Chart.defaults.borderColor = tokens.border
    Chart.defaults.font.family = fontBody
    Chart.defaults.font.size = 13
    // Documents, not dashboards: draw at once (offscreen iframes never finish animating).
    Chart.defaults.animation = false
    Chart.defaults.elements.arc.borderColor = tokens.background
    // Datasets without explicit colors get the theme palette.
    Chart.defaults.plugins.colors.enabled = false
    Chart.register({
      id: 'mdPalette',
      beforeUpdate(chart) {
        chart.data.datasets.forEach((ds, i) => {
          const type = ds.type || chart.config.type
          if (['pie', 'doughnut', 'polarArea'].includes(type)) {
            ds.backgroundColor ??= ds.data.map((_, j) => palette[j % palette.length])
          } else {
            // Fill and points follow the line color, so one explicit color is enough.
            ds.borderColor ??= palette[i % palette.length]
            ds.backgroundColor ??= ds.borderColor
            ds.pointBackgroundColor ??= ds.borderColor
          }
        })
      },
    })
  }
  // Charts resolved their colors at load; for .html files a fresh load is simplest.
  // (Fragments are re-mounted by the editor instead; the canvas page itself
  // follows through CSS and keeps its pan/zoom, while its frames reload.)
  const canvasPage = theme.canvas && window.top === window
  if (!theme.fragment && !canvasPage) dark.addEventListener('change', () => location.reload())
  // A live canvas frame has the keyboard: hand Esc to the canvas so it can let go.
  if (theme.canvas && !canvasPage) {
    addEventListener('keydown', (e) => {
      if (e.key === 'Escape') parent.postMessage({ mdCanvasEscape: true }, '*')
    })
  }

  if (theme.fragment && window.parent !== window) {
    // Measure the body, not the document: the document is never shorter than the
    // iframe itself, so it could grow but never shrink back.
    const report = () => parent.postMessage(
      { mdPreviewHeight: document.body.getBoundingClientRect().height }, '*')
    addEventListener('DOMContentLoaded', () => {
      new ResizeObserver(report).observe(document.body)
      report()
    })
    addEventListener('load', report)
  }
})()
