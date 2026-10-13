import { marked } from 'marked'
import DOMPurify from 'dompurify'

// NM design system fonts, bundled offline via esbuild dataurl loader
import '@fontsource/dm-sans/400.css'
import '@fontsource/dm-sans/500.css'
import '@fontsource/dm-sans/600.css'
import '@fontsource/dm-sans/700.css'
import '@fontsource/geist-mono/400.css'

// A JSON Canvas (jsoncanvas.org) on a pan/zoom surface. Swift owns the file:
// it sends the text with setCanvas and gets the new JSON back (contentChanged)
// when a node is moved or resized. Unknown fields survive, since the parsed
// object is edited in place.

const viewport = document.getElementById('viewport')
const world = document.getElementById('world')
const edgeLayer = document.getElementById('edges')
const zoomLabel = document.getElementById('zoom')
const errorBar = document.getElementById('error')
const emptyHint = document.getElementById('empty')
const marquee = document.getElementById('marquee')
const help = document.getElementById('help')
const helpButton = document.getElementById('help-button')

const post = (name, body = null) => window.webkit?.messageHandlers[name]?.postMessage(body)

let canvas = { nodes: [], edges: [] }
let text = '' // the file as last received or sent, so nothing is echoed back
let path = ''
let folder = ''
let files = {} // absolute path -> { version, text? }
let view = null // { x, y, z }: screen = world * z + (x, y)
let selection = new Set() // node ids; a single selected node is live (frames take clicks)
let gesture = null
let broken = false // the file on disk isn't valid JSON: never write over it
// Undo/redo: earlier versions of the file text. An outside change clears them,
// so undo never writes an old version over an agent's edit.
const undoStack = []
const redoStack = []
const elements = new Map() // node id -> { el, key }

const IMAGE = /\.(png|jpe?g|gif|webp|svg|avif)$/i
const GRID = 24
const LABEL = 28 // room above frames for their label

// MARK: Paths

function resolve(file, base = folder) {
  const parts = (file.startsWith('/') ? file : `${base}/${file}`).split('/')
  const out = []
  for (const part of parts) {
    if (part === '..') out.pop()
    else if (part && part !== '.') out.push(part)
  }
  return '/' + out.join('/')
}

const dirname = (p) => p.slice(0, p.lastIndexOf('/')) || '/'
const basename = (p) => p.slice(p.lastIndexOf('/') + 1)

function fileURL(abs) {
  const version = files[abs]?.version ?? 0
  return 'mdfile://' + abs.split('/').map(encodeURIComponent).join('/') + `?v=${version}`
}

// MARK: Swift API

window.setCanvas = ({ text: newText, path: newPath, folder: newFolder, files: newFiles }) => {
  cancelGesture() // a drag must never write its stale copy over the new file
  let parsed
  try {
    parsed = newText.trim() ? JSON.parse(newText) : {}
  } catch (error) {
    // Half-written by an agent, or broken: keep showing the last good version.
    errorBar.textContent = `This canvas isn't valid JSON: ${error.message}`
    errorBar.hidden = false
    broken = true
    return
  }
  errorBar.hidden = true
  broken = false
  if (newText !== text) undoStack.length = redoStack.length = 0
  canvas = parsed
  canvas.nodes ??= []
  canvas.edges ??= []
  text = newText
  path = newPath
  folder = newFolder
  files = newFiles
  render()
  if (!view) {
    view = restoreView() ?? fitView()
    applyView()
  }
}

window.reloadFile = (abs, info) => {
  files[abs] = info
  for (const node of canvas.nodes) {
    if (node.type === 'file' && resolve(node.file) === abs) {
      elements.get(node.id)?.el.remove()
      elements.delete(node.id)
    }
  }
  render()
}

// Files dropped from Finder, already copied next to the canvas by Swift:
// [{ file, width?, height? }] at a point in page coordinates.
window.addFiles = (dropped, px, py) => {
  if (broken || !view) return
  let x = Math.round((px - view.x) / view.z)
  const y = Math.round((py - view.y) / view.z)
  for (const { file, width, height } of dropped) {
    let size = [440, 340] // notes
    if (/\.html?$/i.test(file)) size = [390, 844] // a mobile frame
    else if (width && height) {
      const scale = Math.min(1, 480 / width) // images: natural size, at most 480 wide
      size = [Math.round(width * scale), Math.round(height * scale)]
    }
    const id = crypto.randomUUID().replaceAll('-', '').slice(0, 16)
    canvas.nodes.push({ id, type: 'file', file, x, y, width: size[0], height: size[1] })
    x += size[0] + 40
  }
  render()
  commit()
}

// For "Copy as Reference".
window.selectedNode = () => {
  const node = canvas.nodes.find((n) => selection.has(n.id))
  return node ? { id: node.id, file: node.file, text: node.text ?? node.label } : null
}

// MARK: Rendering

// Presets or hex only: the value ends up in markup.
const colorVar = (color) =>
  /^[1-6]$/.test(color) ? `var(--canvas-${color})` : /^#[0-9a-f]{3,8}$/i.test(color) ? color : null

function nodeKey(node) {
  const file = node.type === 'file' ? resolve(node.file) : null
  return JSON.stringify([node.type, file, file && files[file]?.version, node.text, node.url,
    node.label, node.color, node.subpath])
}

function render() {
  const ids = new Set(canvas.nodes.map((n) => n.id))
  for (const [id, { el }] of elements) {
    if (!ids.has(id)) { el.remove(); elements.delete(id) }
  }
  for (const node of canvas.nodes) {
    const key = nodeKey(node)
    let entry = elements.get(node.id)
    if (entry?.key !== key) {
      entry?.el.remove()
      entry = { el: createNode(node), key }
      elements.set(node.id, entry)
    }
    world.appendChild(entry.el) // keeps the file's order: later nodes on top
    place(node)
  }
  emptyHint.hidden = canvas.nodes.length > 0
  renderEdges()
  updateSelection()
}

function place(node) {
  const el = elements.get(node.id)?.el
  if (!el) return
  Object.assign(el.style, {
    left: `${node.x}px`, top: `${node.y}px`,
    width: `${node.width}px`, height: `${node.height}px`,
  })
  const size = el.querySelector('.size')
  if (size) size.textContent = ` · ${Math.round(node.width)}`
}

function createNode(node) {
  const el = document.createElement('div')
  el.className = `node node-${node.type}`
  el.dataset.id = node.id
  const color = colorVar(node.color)
  if (color) el.style.setProperty('--node-color', color)

  const body = document.createElement('div')
  body.className = 'body'
  el.append(body)

  if (node.type === 'group') {
    el.classList.add('has-label')
    el.append(label(node.label || 'Group'), palette())
  } else if (node.type === 'file') {
    const abs = resolve(node.file)
    if (/\.html?$/i.test(abs)) {
      el.classList.add('frame', 'has-label')
      const frame = document.createElement('iframe')
      // No allow-same-origin: a prototype can't reach the canvas page or Swift.
      frame.setAttribute('sandbox', 'allow-scripts allow-forms')
      frame.src = fileURL(abs)
      const shield = document.createElement('div')
      shield.className = 'shield'
      body.append(frame, shield)
      el.append(label(basename(abs), true))
    } else if (IMAGE.test(abs)) {
      el.classList.add('card', 'image')
      const img = document.createElement('img')
      img.src = fileURL(abs)
      img.alt = basename(abs)
      img.draggable = false
      body.append(img)
    } else if (/\.md$/i.test(abs)) {
      el.classList.add('card', 'has-label')
      body.append(markdown(files[abs]?.text ?? '', dirname(abs), abs))
      el.append(label(basename(abs)))
    } else {
      el.classList.add('card', 'has-label')
      body.textContent = basename(abs)
      el.append(label(basename(abs)))
    }
  } else if (node.type === 'link') {
    el.classList.add('card')
    const host = (() => { try { return new URL(node.url).host } catch { return node.url } })()
    body.innerHTML = '<div class="link-host"></div><div class="link-url"></div>'
    body.firstChild.textContent = host
    body.lastChild.textContent = node.url
  } else {
    el.classList.add('card')
    body.append(markdown(node.text ?? '', folder))
  }

  const handle = document.createElement('div')
  handle.className = 'resize'
  el.append(handle)
  return el
}

// Color swatches beside a selected group's label: none, then presets 1-6.
function palette() {
  const el = document.createElement('div')
  el.className = 'palette'
  for (const color of ['', '1', '2', '3', '4', '5', '6']) {
    const swatch = document.createElement('span')
    swatch.dataset.color = color
    if (color) swatch.style.background = `var(--canvas-${color})`
    el.append(swatch)
  }
  return el
}

function label(textContent, withSize = false) {
  const el = document.createElement('div')
  el.className = 'label'
  const name = document.createElement('span')
  name.textContent = textContent
  el.append(name)
  if (withSize) {
    const size = document.createElement('span')
    size.className = 'size'
    el.append(size)
  }
  return el
}

// The canvas page can message Swift, so note HTML is always sanitized.
// Task boxes on a .md card can be ticked: Swift writes the change to `file`.
function markdown(source, base, file = null) {
  const el = document.createElement('div')
  el.className = 'markdown'
  el.innerHTML = DOMPurify.sanitize(marked.parse(source))
  if (file) {
    el.dataset.file = file
    el.querySelectorAll('input[type="checkbox"]').forEach((box, index) => {
      box.disabled = false
      box.dataset.task = index
    })
  }
  for (const img of el.querySelectorAll('img[src]')) {
    const src = img.getAttribute('src')
    if (!/^[a-z]+:/i.test(src)) img.src = fileURL(resolve(decodeURI(src), base))
  }
  for (const a of el.querySelectorAll('a[href]')) a.dataset.base = base
  return el
}

// MARK: Edges

const SIDES = {
  top: [0.5, 0, 0, -1], bottom: [0.5, 1, 0, 1],
  left: [0, 0.5, -1, 0], right: [1, 0.5, 1, 0],
}

function anchor(node, side) {
  const [fx, fy, dx, dy] = SIDES[side]
  return { x: node.x + node.width * fx, y: node.y + node.height * fy, dx, dy }
}

// Facing sides when the file doesn't say.
function guessSides(a, b) {
  const ax = a.x + a.width / 2, ay = a.y + a.height / 2
  const bx = b.x + b.width / 2, by = b.y + b.height / 2
  return Math.abs(bx - ax) >= Math.abs(by - ay)
    ? (bx > ax ? ['right', 'left'] : ['left', 'right'])
    : (by > ay ? ['bottom', 'top'] : ['top', 'bottom'])
}

function renderEdges() {
  const byId = new Map(canvas.nodes.map((n) => [n.id, n]))
  const parts = []
  world.querySelectorAll('.edge-label').forEach((el) => el.remove())
  for (const edge of canvas.edges) {
    const from = byId.get(edge.fromNode), to = byId.get(edge.toNode)
    if (!from || !to) continue
    const [gf, gt] = guessSides(from, to)
    const a = anchor(from, Object.hasOwn(SIDES, edge.fromSide) ? edge.fromSide : gf)
    const b = anchor(to, Object.hasOwn(SIDES, edge.toSide) ? edge.toSide : gt)
    const bend = Math.max(40, Math.hypot(b.x - a.x, b.y - a.y) / 3)
    const c1 = { x: a.x + a.dx * bend, y: a.y + a.dy * bend }
    const c2 = { x: b.x + b.dx * bend, y: b.y + b.dy * bend }
    const color = colorVar(edge.color) ?? 'var(--color-muted-foreground)'
    const start = edge.fromEnd === 'arrow' ? 'marker-start="url(#arrow)"' : ''
    const end = (edge.toEnd ?? 'arrow') === 'arrow' ? 'marker-end="url(#arrow)"' : ''
    parts.push(`<path d="M${a.x},${a.y} C${c1.x},${c1.y} ${c2.x},${c2.y} ${b.x},${b.y}" ` +
      `style="stroke:${color};color:${color}" ${start} ${end}/>`)
    if (edge.label) {
      // The curve's midpoint (t = 0.5).
      const el = document.createElement('div')
      el.className = 'edge-label'
      el.textContent = edge.label
      el.style.left = `${(a.x + 3 * c1.x + 3 * c2.x + b.x) / 8}px`
      el.style.top = `${(a.y + 3 * c1.y + 3 * c2.y + b.y) / 8}px`
      world.append(el)
    }
  }
  edgeLayer.innerHTML = '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" ' +
    'markerWidth="8" markerHeight="8" orient="auto-start-reverse">' +
    '<path d="M0,0 L10,5 L0,10 z" fill="context-stroke"/></marker></defs>' + parts.join('')
}

// MARK: View

function applyView() {
  world.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.z})`
  world.style.setProperty('--z', view.z) // labels keep their screen size
  viewport.style.backgroundSize = `${GRID * view.z}px ${GRID * view.z}px`
  viewport.style.backgroundPosition = `${view.x}px ${view.y}px`
  zoomLabel.textContent = `${Math.round(view.z * 100)}%`
  saveView()
}

let saveQueued = false
function saveView() {
  if (saveQueued) return
  saveQueued = true
  requestAnimationFrame(() => {
    saveQueued = false
    try { sessionStorage.setItem(`view:${path}`, JSON.stringify(view)) } catch {}
  })
}

function restoreView() {
  try { return JSON.parse(sessionStorage.getItem(`view:${path}`)) } catch { return null }
}

function fitView() {
  const nodes = canvas.nodes
  if (!nodes.length) return { x: 0, y: 0, z: 1 }
  const minX = Math.min(...nodes.map((n) => n.x)), minY = Math.min(...nodes.map((n) => n.y)) - LABEL
  const maxX = Math.max(...nodes.map((n) => n.x + n.width)), maxY = Math.max(...nodes.map((n) => n.y + n.height))
  const pad = 64
  const z = clampZoom(Math.min(1, (innerWidth - pad * 2) / (maxX - minX), (innerHeight - pad * 2) / (maxY - minY)))
  return {
    z,
    x: (innerWidth - (maxX - minX) * z) / 2 - minX * z,
    y: (innerHeight - (maxY - minY) * z) / 2 - minY * z,
  }
}

const clampZoom = (z) => Math.min(4, Math.max(0.05, z))

function zoomAt(z, cx, cy) {
  z = clampZoom(z)
  view = { z, x: cx - (cx - view.x) * (z / view.z), y: cy - (cy - view.y) * (z / view.z) }
  applyView()
}

// Scrolling pans, pinch (ctrl+wheel) zooms. A live frame or a selected card
// that can scroll keeps its own scrolling.
viewport.addEventListener('wheel', (e) => {
  if (!view) return
  const scroller = e.target.closest?.('.node.live .body')
  if (!e.ctrlKey && scroller && scroller.scrollHeight > scroller.clientHeight) return
  e.preventDefault()
  if (e.ctrlKey) {
    zoomAt(view.z * Math.exp(-e.deltaY * 0.01), e.clientX, e.clientY)
  } else {
    view.x -= e.deltaX
    view.y -= e.deltaY
    applyView()
  }
}, { passive: false })

// WebKit's own trackpad pinch.
let pinchStart = 1
addEventListener('gesturestart', (e) => { e.preventDefault(); pinchStart = view?.z ?? 1 })
addEventListener('gesturechange', (e) => {
  e.preventDefault()
  if (view) zoomAt(pinchStart * e.scale, e.clientX, e.clientY)
})

zoomLabel.addEventListener('click', () => { view = fitView(); applyView() })
helpButton.addEventListener('click', () => { help.hidden = !help.hidden })
addEventListener('pointerdown', (e) => {
  if (!e.target.closest('#help, #help-button')) help.hidden = true
}, true)

let spaceHeld = false
const editing = () => document.activeElement?.isContentEditable

addEventListener('keydown', (e) => {
  if (!view || editing()) return
  if (e.key === ' ') { spaceHeld = true; e.preventDefault(); return }
  if (e.key === 'Escape') { help.hidden = true; select([]) }
  if (e.key === '?') { help.hidden = !help.hidden; return }
  if ((e.key === 'Backspace' || e.key === 'Delete') && !e.metaKey) {
    if (removeGroups()) e.preventDefault()
    return
  }
  if (!e.metaKey) return
  const cx = innerWidth / 2, cy = innerHeight / 2
  const key = e.key.toLowerCase()
  if (key === 'z' && e.shiftKey) redo()
  else if (key === 'z') undo()
  else if (key === 'g' && e.shiftKey) removeGroups()
  else if (key === 'g') groupSelection()
  else if (key === '0') { view = fitView(); applyView() }
  else if (key === '=' || key === '+') zoomAt(view.z * 1.25, cx, cy)
  else if (key === '-') zoomAt(view.z / 1.25, cx, cy)
  else return
  e.preventDefault()
})
addEventListener('keyup', (e) => { if (e.key === ' ') spaceHeld = false })
addEventListener('blur', () => { spaceHeld = false })

// Esc inside a live frame (forwarded by preview-runtime.js) lets go of it.
addEventListener('message', (e) => {
  if (!e.data?.mdCanvasEscape) return
  for (const frame of world.querySelectorAll('iframe')) {
    if (frame.contentWindow === e.source) select([])
  }
})

// MARK: Selection

function select(ids) {
  selection = new Set(ids)
  updateSelection()
}

function updateSelection() {
  for (const [id, { el }] of elements) {
    el.classList.toggle('selected', selection.has(id))
    el.classList.toggle('live', selection.size === 1 && selection.has(id))
  }
}

const nodeById = (id) => canvas.nodes.find((n) => n.id === id)

// Groups take the nodes inside them along.
function contained(group) {
  return canvas.nodes.filter((n) => n !== group &&
    n.x >= group.x && n.y >= group.y &&
    n.x + n.width <= group.x + group.width && n.y + n.height <= group.y + group.height)
}

const toWorld = (cx, cy) => ({ x: (cx - view.x) / view.z, y: (cy - view.y) / view.z })

function rectFrom(a, b) {
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y)
  return { x: Math.round(x), y: Math.round(y), width: Math.round(Math.abs(b.x - a.x)), height: Math.round(Math.abs(b.y - a.y)) }
}

// Marquee: nodes it touches, but groups only when they're fully inside.
function inRect(r) {
  return canvas.nodes.filter((n) => n.type === 'group'
    ? n.x >= r.x && n.y >= r.y && n.x + n.width <= r.x + r.width && n.y + n.height <= r.y + r.height
    : n.x < r.x + r.width && n.x + n.width > r.x && n.y < r.y + r.height && n.y + n.height > r.y)
}

// MARK: Groups

const newId = () => crypto.randomUUID().replaceAll('-', '').slice(0, 16)
const GROUP_PAD = 40

// ⌘G: a group around the selection.
function groupSelection() {
  const nodes = canvas.nodes.filter((n) => selection.has(n.id))
  if (!nodes.length || broken) return
  const x = Math.min(...nodes.map((n) => n.x)) - GROUP_PAD
  const y = Math.min(...nodes.map((n) => n.y)) - GROUP_PAD
  const width = Math.max(...nodes.map((n) => n.x + n.width)) + GROUP_PAD - x
  const height = Math.max(...nodes.map((n) => n.y + n.height)) + GROUP_PAD - y
  addGroup({ x, y, width, height })
}

function addGroup(rect) {
  const group = { id: newId(), type: 'group', label: 'Group', ...rect }
  canvas.nodes.unshift(group) // first in the file: behind everything
  render()
  select([group.id])
  commit()
  rename(group)
}

// Delete / ⌘⇧G: removes the selected groups' frames, never what's inside.
function removeGroups() {
  const ids = new Set(canvas.nodes.filter((n) => n.type === 'group' && selection.has(n.id)).map((n) => n.id))
  if (!ids.size || broken) return false
  canvas.nodes = canvas.nodes.filter((n) => !ids.has(n.id))
  canvas.edges = canvas.edges.filter((e) => !ids.has(e.fromNode) && !ids.has(e.toNode))
  select([])
  render()
  commit()
  return true
}

function rename(group) {
  const name = elements.get(group.id)?.el.querySelector('.label span')
  if (!name) return
  name.contentEditable = 'plaintext-only'
  name.focus()
  getSelection()?.selectAllChildren(name)
  const finish = (save) => {
    name.removeEventListener('blur', onBlur)
    name.removeEventListener('keydown', onKey)
    name.contentEditable = 'false'
    const value = name.textContent.trim()
    if (save && value && value !== group.label) {
      group.label = value
      render()
      commit()
    } else {
      name.textContent = group.label || 'Group'
    }
  }
  const onBlur = () => finish(true)
  const onKey = (e) => {
    e.stopPropagation()
    if (e.key === 'Enter') { e.preventDefault(); name.blur() }
    if (e.key === 'Escape') { finish(false); name.blur() }
  }
  name.addEventListener('blur', onBlur)
  name.addEventListener('keydown', onKey)
}

function setColor(group, color) {
  if (color) group.color = color
  else delete group.color
  render()
  commit()
}

// MARK: Moving, resizing, marquee

viewport.addEventListener('pointerdown', (e) => {
  if (!view || (e.button !== 0 && e.button !== 2) || e.target.isContentEditable) return
  if (e.button === 0 && spaceHeld) {
    startGesture(e, { type: 'pan', x: view.x, y: view.y })
    return
  }
  const swatch = e.target.closest('.palette [data-color]')
  if (swatch) {
    e.preventDefault()
    const group = nodeById(swatch.closest('.node').dataset.id)
    if (group) setColor(group, swatch.dataset.color)
    return
  }
  let el = e.target.closest('.node')
  // A group is grabbed by its label; its inside is canvas.
  if (el?.classList.contains('node-group') && !e.target.closest('.label, .resize')) el = null
  const node = el && nodeById(el.dataset.id)
  if (!node) {
    if (e.button !== 0) return select([])
    const start = toWorld(e.clientX, e.clientY)
    if (e.altKey) {
      select([])
      startGesture(e, { type: 'draw', start })
    } else {
      const keep = e.shiftKey ? [...selection] : []
      if (!e.shiftKey) select([])
      startGesture(e, { type: 'marquee', start, keep })
    }
    return
  }
  if (e.shiftKey && e.button === 0) {
    // Shift-click adds to or takes from the selection.
    const ids = new Set(selection)
    ids.has(node.id) ? ids.delete(node.id) : ids.add(node.id)
    select(ids)
    return
  }
  if (!selection.has(node.id)) select([node.id])
  if (e.button !== 0) return // right-click selects, for Copy as Reference
  if (e.target.closest('.resize')) {
    startGesture(e, { type: 'resize', node, width: node.width, height: node.height })
    return
  }
  // Frames move by their label; clicking a resting frame only brings it to life.
  // Cards move by any part that isn't a link.
  if (e.target.closest('.shield, a, .markdown input')) return
  if (e.target.closest('.label') || !el.classList.contains('frame')) {
    // The whole selection moves, groups with what's inside them.
    const moving = new Set()
    for (const n of canvas.nodes.filter((n) => selection.has(n.id))) {
      moving.add(n)
      if (n.type === 'group') contained(n).forEach((c) => moving.add(c))
    }
    startGesture(e, { type: 'move', nodes: [...moving].map((n) => ({ n, x: n.x, y: n.y })) })
  }
})

function startGesture(e, g) {
  e.preventDefault() // no native selection or image drag alongside ours
  getSelection()?.removeAllRanges()
  gesture = { ...g, startX: e.clientX, startY: e.clientY, moved: false, target: e.target, id: e.pointerId }
  try { e.target.setPointerCapture(e.pointerId) } catch {}
  document.body.classList.add('dragging')
}

function showMarquee(r) {
  Object.assign(marquee.style, {
    left: `${r.x * view.z + view.x}px`, top: `${r.y * view.z + view.y}px`,
    width: `${r.width * view.z}px`, height: `${r.height * view.z}px`,
  })
  marquee.hidden = false
}

viewport.addEventListener('pointermove', (e) => {
  if (!gesture) return
  const sx = e.clientX - gesture.startX, sy = e.clientY - gesture.startY
  if (!gesture.moved && Math.hypot(sx, sy) < 3) return
  gesture.moved = true
  if (gesture.type === 'pan') {
    view.x = gesture.x + sx
    view.y = gesture.y + sy
    applyView()
    return
  }
  if (gesture.type === 'marquee' || gesture.type === 'draw') {
    gesture.rect = rectFrom(gesture.start, toWorld(e.clientX, e.clientY))
    showMarquee(gesture.rect)
    marquee.classList.toggle('draw', gesture.type === 'draw')
    if (gesture.type === 'marquee') select([...gesture.keep, ...inRect(gesture.rect).map((n) => n.id)])
    return
  }
  const dx = Math.round(sx / view.z), dy = Math.round(sy / view.z)
  if (gesture.type === 'move') {
    for (const { n, x, y } of gesture.nodes) {
      n.x = x + dx
      n.y = y + dy
      place(n)
    }
  } else {
    gesture.node.width = Math.max(80, gesture.width + dx)
    gesture.node.height = Math.max(60, gesture.height + dy)
    place(gesture.node)
  }
  renderEdges()
})

function endGesture() {
  if (!gesture) return
  const done = gesture
  cancelGesture()
  if (!done.moved) return
  if (done.type === 'move' || done.type === 'resize') commit()
  else if (done.type === 'draw' && done.rect.width >= 40 && done.rect.height >= 40) addGroup(done.rect)
}

viewport.addEventListener('pointerup', endGesture)
viewport.addEventListener('pointercancel', endGesture)

function cancelGesture() {
  if (!gesture) return
  try { gesture.target.releasePointerCapture(gesture.id) } catch {}
  gesture = null
  marquee.hidden = true
  document.body.classList.remove('dragging')
}

function commit() {
  if (broken) return
  const newText = JSON.stringify(canvas, null, '\t') + '\n'
  if (newText === text) return
  undoStack.push(text)
  if (undoStack.length > 200) undoStack.shift()
  redoStack.length = 0
  text = newText
  post('contentChanged', newText)
}

function restore(from, to) {
  if (broken || !from.length) return
  cancelGesture()
  to.push(text)
  text = from.pop()
  canvas = JSON.parse(text)
  canvas.nodes ??= []
  canvas.edges ??= []
  select([...selection].filter((id) => nodeById(id)))
  render()
  post('contentChanged', text)
}
const undo = () => restore(undoStack, redoStack)
const redo = () => restore(redoStack, undoStack)

// MARK: Opening

viewport.addEventListener('dblclick', (e) => {
  const el = e.target.closest('.node')
  const node = el && canvas.nodes.find((n) => n.id === el.dataset.id)
  if (!node || e.target.closest('.resize, .palette')) return
  if (node.type === 'group' && e.target.closest('.label')) rename(node)
  else if (node.type === 'file') post('openFile', resolve(node.file))
  else if (node.type === 'link') post('openLink', node.url)
})

// Links in notes: web links in the browser, local paths in the app.
viewport.addEventListener('click', (e) => {
  const a = e.target.closest('.markdown a[href]')
  if (!a) return
  e.preventDefault()
  const href = a.getAttribute('href')
  if (/^(https?|mailto):/i.test(href)) post('openLink', href)
  else if (!/^[a-z]+:/i.test(href) && !href.startsWith('#')) {
    post('openFile', resolve(decodeURI(href.split('#')[0]), a.dataset.base))
  }
})

// The nth task box in a .md card is the nth task item in the file.
viewport.addEventListener('change', (e) => {
  const box = e.target.closest('.markdown input[data-task]')
  if (!box) return
  const file = box.closest('.markdown').dataset.file
  post('toggleTask', { path: file, index: Number(box.dataset.task), checked: box.checked })
})

addEventListener('resize', () => view && applyView())

post('canvasReady')
