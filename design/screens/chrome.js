// Draws the window chrome shared by every screen: sidebar and toolbar.
// A screen describes its state on <body>:
//   data-active    file shown in the detail column ("" = none)
//   data-open      comma-separated open files (gray dot), data-dirty (accent dot)
//   data-subtitle  word/token count (markdown files only)
//   data-settings  settings page is showing
// and puts its own view in <div class="content">.
// Sidebar rows link to the screen that shows that file, so the canvas frames click through.

// Projects and files as in the real sidebar (real folders). Rows link to the screen for their file type.
const PROJECTS = [
  { path: '~/Desktop/personal/markdown-editor/design', files: ['app.canvas'] },
  { path: '~/Desktop/work/Intern/Prod/MCP', files: ['CLAUDE.md', 'handoff.md'] },
  { path: '~/Desktop/personal/markdown-editor/examples/canvas', files: ['demo.canvas', 'noter.md'] },
  { path: '~/Desktop/personal/markdown-editor/examples/canvas/screens', files: ['checkout-1-cart.html', 'login-a.html', 'login-b.html'] },
  { path: '~/Desktop/personal/markdown-editor/examples', files: ['markdown-in-numbers.html', 'why-markdown.md'] },
  { path: '~/Desktop/work/Intern/Prod/MCP/best-practices', files: ['README.md', 'status.md'] },
  { path: '~/Desktop/personal/nsk-ordreagent/docs', files: ['ai-pipeline.md', 'architecture.md'] },
  { path: '~/Desktop/work/Intern/Prod/nm-checkliste/docs', files: ['azure-sso.md'] },
  { path: '~/Desktop/NM_Arbejde/Intern/nm-pets', files: ['AGENTS.md', 'DESIGN.md'] },
  { path: '~/Downloads', files: ['cvr-test-batch-1.md', 'workshop-top3-status.md'] },
].map((p) => ({ ...p, name: p.path.split('/').pop() }))

// Project headers, under design (data-header on <body>):
//   name    today: folder name only
//   tail    the last three folders inline: …/Intern/Prod/MCP
//   twoline folder name, the two nearest parent folders below in gray (…/Intern/Prod); chosen, the default
//   smart   folder name, plus as many parent folders as it takes to tell two projects apart
function header(p) {
  const headerMode = state.header || 'twoline'
  const parts = p.path.split('/')
  // Parent folder path, cut at whole folders: the two nearest, or all of it when short
  const up = parts.slice(0, -1)
  const parent = up.length > 3 ? '…/' + up.slice(-2).join('/') : up.join('/')
  const count = `<span class="count">${p.files.length}</span>`
  // Head truncation: rtl box, with &lrm; so the leading ~ or … stays in place
  const cut = (text) => `<span class="cut">&lrm;${text}</span>`
  if (headerMode === 'tail') {
    const tail = parts.length > 4 ? '…/' + parts.slice(-3).join('/') : p.path
    return `<div class="section-header" title="${p.path}"><span class="title-path">${tail}</span>${count}</div>`
  }
  if (headerMode === 'twoline') {
    return `<div class="section-header two" title="${p.path}"><span><span>${p.name}</span>${cut(parent)}</span>${count}</div>`
  }
  if (headerMode === 'smart') {
    let depth = 1
    const label = (q, d) => q.path.split('/').slice(-d - 1, -1).reverse().join(' › ')
    while (PROJECTS.some((q) => q !== p && q.name === p.name && label(q, depth) === label(p, depth))) depth++
    const twin = PROJECTS.some((q) => q !== p && q.name === p.name)
    return `<div class="section-header" title="${p.path}"><span>${p.name}${twin ? ` <span class="hint">${label(p, depth)}</span>` : ''}</span>${count}</div>`
  }
  return `<div class="section-header" title="${p.path}"><span>${p.name}</span>${count}</div>`
}
const SCREENS = { md: 'doc-md.html', html: 'doc-html.html', canvas: 'doc-canvas.html' }

// Stand-ins for the SF Symbols in MainWindowView: moon/sun.max, gearshape, speaker.wave.2, doc.on.clipboard
const ICONS = {
  moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  sidebar: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16M5.5 8h1.5M5.5 11h1.5"/>',
  speaker: '<path d="M11 5 6 9H3v6h3l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9 9 0 0 1 0 13"/>',
  clipboard: '<rect x="8" y="3" width="8" height="4" rx="1"/><path d="M16 5h2a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2"/>',
}
const icon = (name) => `<svg viewBox="0 0 24 24">${ICONS[name]}</svg>`

const state = document.body.dataset
const list = (value) => (value || '').split(',').filter(Boolean)
const open = list(state.open)
const dirty = list(state.dirty)
const settings = 'settings' in state
const active = settings ? '' : state.active || ''
const dark = matchMedia('(prefers-color-scheme: dark)').matches

// File-type tags in the sidebar, under design (data-sidebar on <body>):
//   left  name without extension, fixed-width tag before it (chosen, the default)
//   none  before: full file name
//   pill  name without extension, tinted tag on the right
//   quiet like pill, but .md (most files) gets no tag
const variant = state.sidebar === 'none' ? '' : state.sidebar || 'left'
function row(name) {
  const ext = name.split('.').pop().toLowerCase()
  const base = name.slice(0, -(ext.length + 1))
  const tag = `<span class="tag tag-${ext}">${ext}</span>`
  // Open: with tags the dot takes the file type's color (unsaved only lasts until autosave)
  const dot = dirty.includes(name) ? `<span class="dot dirty${variant ? ` dot-${ext}` : ''}" title="Unsaved"></span>`
    : open.includes(name) ? `<span class="dot${variant ? ` dot-${ext}` : ''}" title="Open"></span>`
    // Variants keep the dot's slot, so the tags line up
    : variant ? '<span class="dot" style="visibility:hidden"></span>' : ''
  const label = variant ? base : name
  const parts = {
    '': `<span class="name">${label}</span>${dot}`,
    pill: `<span class="name">${label}</span>${tag}${dot}`,
    left: `${tag}<span class="name">${label}</span>${dot}`,
    quiet: `<span class="name">${label}</span>${ext === 'md' ? '' : tag}${dot}`,
  }[variant]
  return `<a class="row${variant ? ` v-${variant}` : ''}${name === active ? ' active' : ''}" href="${SCREENS[ext]}" title="${name}">${parts}</a>`
}

const sidebar = `
  <nav class="sidebar">
    <div class="traffic"><span></span><span></span><span></span><span class="toggle" title="Hide sidebar">${icon('sidebar')}</span></div>
    ${PROJECTS.map((p) => `
      <div class="section">
        ${header(p)}
        ${p.files.map((name) => row(name)).join('')}
      </div>`).join('')}
  </nav>`

const toolbar = `
  <header class="toolbar">
    <div class="title">
      <strong>Markdown Editor</strong>
      ${state.subtitle && !settings ? `<small>${state.subtitle}</small>` : ''}
    </div>
    <div class="tools">
      <a title="${dark ? 'Switch to light mode' : 'Switch to dark mode'}">${icon(dark ? 'sun' : 'moon')}</a>
      <a class="${settings ? 'on' : ''}" href="${settings ? 'doc-md.html' : 'settings.html'}" title="Settings (⌘,)">${icon('gear')}</a>
      ${active.endsWith('.md') ? `<a title="Read the file aloud">${icon('speaker')}</a>` : ''}
      ${active ? `<a title="Copy the file's path to the clipboard">${icon('clipboard')}</a>` : ''}
    </div>
  </header>`

const content = document.querySelector('.content')
const detail = document.createElement('main')
detail.className = 'detail'
detail.innerHTML = toolbar
detail.append(content)
const win = document.createElement('div')
win.className = 'window'
win.innerHTML = sidebar
win.append(detail)
document.body.prepend(win)
if ('sidebarOnly' in state) document.body.classList.add('sidebar-only')
