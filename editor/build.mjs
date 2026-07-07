import * as esbuild from 'esbuild'

await esbuild.build({
  entryPoints: ['src/main.js'],
  bundle: true,
  minify: true,
  format: 'iife',
  outfile: '../Sources/MarkdownEditor/Web/editor.bundle.js',
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
