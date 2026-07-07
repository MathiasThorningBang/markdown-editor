# MarkdownEditor

Lille macOS-app til at åbne, læse og redigere `.md`-filer med WYSIWYG-formattering (Typora-agtig), billeder i fuld bredde og syntax-highlightede kodeblokke. Styling følger NM-designsystemet (DM Sans + Geist Mono).

SwiftUI document-app med en bundlet [Milkdown Crepe](https://milkdown.dev/docs/guide/using-crepe)-editor i en WKWebView. Alt kører lokalt — ingen netværk.

## Installation

**Krav:** macOS 14+ og Xcode Command Line Tools (`xcode-select --install`). Node/npm er *ikke* nødvendigt — web-bundlen er committet.

```sh
git clone https://github.com/MathiasThorningBang/markdown-editor.git
cd markdown-editor
./build.sh
```

Det bygger appen og installerer den i `/Applications/MarkdownEditor.app`.

### Sæt som default-app for .md

Finder → højreklik på en `.md`-fil → **Vis info** → **Åbn med:** MarkdownEditor → **Skift alle…**

## Udvikling

### Web-editoren (kun ved ændringer i editor/)

```sh
cd editor
npm install
npm run build   # bundler til Sources/MarkdownEditor/Web/ (committes)
```

### App-ikon

Kilden er `icon/AppIcon-1024.png` (1024×1024 PNG med alpha). Regenerér `AppIcon.icns` med:

```sh
cd icon && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o ../AppIcon.icns && rm -rf AppIcon.iconset
```

## Kendte tradeoffs

- Crepe normaliserer markdown-kilden ved første redigering + gem (lister bliver `*`, tabeller paddes). Indholdet bevares, men git-diffen kan være støjende første gang.
- Ingen App Sandbox (intern app, ikke App Store) — billeder ved siden af .md-filen læses via et custom `mdfile://`-URL-skema.
- Ad-hoc-signeret. Gatekeeper kan brokke sig første gang — men da appen bygges lokalt på egen maskine, er det normalt ikke et problem.

## Licens

MIT — fonte (DM Sans, Geist Mono) er under SIL Open Font License via @fontsource.
