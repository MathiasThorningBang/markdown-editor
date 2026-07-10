# MarkdownEditor

WYSIWYG-editor til `.md`-filer på macOS, i stil med Typora. Sidebaren samler dine mapper som projekter, filer gemmes automatisk mens du skriver, og Cmd+klik åbner links — også lokale stier. Alt kører lokalt uden netværk.

Teknisk er det en SwiftUI-app med en bundlet [Milkdown Crepe](https://milkdown.dev/docs/guide/using-crepe)-editor i en WKWebView. Styling følger NM-designsystemet (DM Sans + Geist Mono).

## Hvorfor en markdown-editor i 2026?

Fordi mere og mere af mit arbejde ender i markdown, og det er ikke et tilfælde.

Markdown er det format, AI-agenter taler bedst. De læser og skriver det direkte, og strukturen overlever turen gennem en modelkontekst. Alt det et Office-dokument gør for mennesker med layout, gør markdown for modeller med ren tekst.

Det kan også måles. Jeg har testet et bundt rigtige arbejdsfiler (PDF, PowerPoint, Word, Excel) mod den samme viden konverteret til markdown. At lade en model læse de rå filer koster cirka 6 gange så mange tokens, og for billedtunge slide-decks 15-30 gange, fordi hver side sendes som et billede. Den pris betales hver eneste gang filen læses, ikke kun én gang. Samme indhold i markdown giver hurtigere svar og et langt lavere forbrug.

Så agenterne arbejder i `.md`. Problemet er bare, at rå markdown er træls at læse for mennesker. Den her editor findes for at lukke det hul: når en agent skriver briefs eller rapporter i markdown, kan jeg læse med og rette i et pænt dokument i stedet for i kildeteksten. Det er den nemmeste måde, jeg har fundet, at være human in the loop på.

## Installation

**Krav:** macOS 14+ og Xcode Command Line Tools (`xcode-select --install`). Node/npm er *ikke* nødvendigt — web-bundlen er committet.

```sh
git clone https://github.com/MathiasThorningBang/markdown-editor.git
cd markdown-editor
./build.sh
```

Det bygger appen og installerer den i `/Applications/MarkdownEditor.app`.

## Opdatering

Har du appen installeret i forvejen, henter det her seneste version og geninstallerer den:

```sh
cd markdown-editor
git pull && ./build.sh
```

Genstart appen bagefter, hvis den kører.

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
