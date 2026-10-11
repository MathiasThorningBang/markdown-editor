import * as esbuild from 'esbuild'
import { copyFileSync, mkdirSync, readFileSync } from 'node:fs'

// Chart.js and the theme runtime are inlined into ```html preview iframes, and
// shipped as files for Swift to inject into opened .html documents.
const web = '../Sources/MarkdownEditor/Web'
mkdirSync(`${web}/vendor`, { recursive: true })
copyFileSync('node_modules/chart.js/dist/chart.umd.min.js', `${web}/vendor/chart.umd.min.js`)
const chartSrc = readFileSync('node_modules/chart.js/dist/chart.umd.min.js', 'utf8')
const runtimeSrc = readFileSync(`${web}/preview-runtime.js`, 'utf8')

await esbuild.build({
  entryPoints: ['src/main.js'],
  bundle: true,
  minify: true,
  format: 'iife',
  outfile: '../Sources/MarkdownEditor/Web/editor.bundle.js',
  define: {
    CHART_SRC: JSON.stringify(chartSrc),
    RUNTIME_SRC: JSON.stringify(runtimeSrc),
  },
  loader: {
    '.woff': 'dataurl',
    '.woff2': 'dataurl',
    '.ttf': 'dataurl',
    '.otf': 'dataurl',
    '.svg': 'dataurl',
    '.png': 'dataurl',
  },
})

console.log('Built editor.bundle.js/.css')
