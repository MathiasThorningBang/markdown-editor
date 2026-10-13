---
name: md-canvas
description: Brug når du laver HTML-prototyper, wireframes, skærmflows, designvarianter, responsive visninger eller moodboards, som brugeren skal se i MarkdownEditor-appen. Beskriver hvordan du skriver et .canvas-board (JSON Canvas) med .html-filer som frames, hvilke mål og layoutregler der gælder, og hvordan du itererer uden at overskrive brugerens placeringer.
---

# Canvas i MarkdownEditor

MarkdownEditor viser `.canvas`-filer som en stor flade, man kan panorere og zoome
på. Hver `.html`-fil, canvasset peger på, vises som en levende frame. Det svarer
til Claudes artifact-canvas, men lokalt og offline. Formatet er
[JSON Canvas 1.0](https://jsoncanvas.org/spec/1.0/), så filen også kan åbnes i
Obsidian.

Du skriver filerne. Appen viser dem og genindlæser hver frame, når dens fil
ændres. Brugeren kan flytte og skalere frames, og appen gemmer det i `.canvas`-filen.

## Hvornår skal du bruge canvas?

- Flere skærme, varianter eller bredder, der skal ses side om side → `.canvas`.
- Én side eller et dashboard → bare en `.html`-fil (se `md-editor`).
- Tekst, beslutninger og planer → `.md` (se `md-editor`). Læg dem gerne på
  canvasset som en `.md`-node ved siden af skærmene.

## Mappestruktur

```
login-prototype/
  login.canvas
  noter.md
  screens/
    login-a.html
    login-b.html
    checkout-1-kurv.html
```

Stier i `file` er **relative til `.canvas`-filens mappe** (eller absolutte).
I Obsidian er de relative til vaultens rod. Det er det samme, når canvasset
ligger i roden.

## Formatet

````json
{
	"nodes": [
		{ "id": "note", "type": "text", "x": -520, "y": 0, "width": 440, "height": 300,
		  "text": "# Login\n\nTo varianter. **B** er uden adgangskode." },
		{ "id": "g-login", "type": "group", "label": "Login: to varianter",
		  "x": -40, "y": -40, "width": 940, "height": 924 },
		{ "id": "login-a", "type": "file", "file": "screens/login-a.html",
		  "x": 0, "y": 0, "width": 390, "height": 844 },
		{ "id": "login-b", "type": "file", "file": "screens/login-b.html",
		  "x": 470, "y": 0, "width": 390, "height": 844 },
		{ "id": "kurv", "type": "file", "file": "screens/checkout-1-kurv.html",
		  "x": 1100, "y": 0, "width": 390, "height": 844 },
		{ "id": "levering", "type": "file", "file": "screens/checkout-2-levering.html",
		  "x": 1650, "y": 0, "width": 390, "height": 844, "color": "5" }
	],
	"edges": [
		{ "id": "e1", "fromNode": "kurv", "fromSide": "right",
		  "toNode": "levering", "toSide": "left", "label": "Gå til levering" }
	]
}
````

Det viser appen:

| Node | Vises som |
|---|---|
| `file` med `.html`/`.htm` | Levende frame i nodens størrelse. Siden scroller indeni. Navnet og bredden står over den |
| `file` med `.md` | Kort med renderet markdown |
| `file` med billede (png, jpg, gif, webp, svg, avif) | Billedet, skaleret til at passe |
| `text` | Kort med renderet markdown fra `text` |
| `link` | Kort med domæne og URL. Dobbeltklik åbner browseren (frames har ikke netværk) |
| `group` | Felt med `label` over sig, bag de andre noder |

- `edges`: pile fra `fromNode` til `toNode`. `fromSide`/`toSide` er `top`,
  `right`, `bottom` eller `left`. Uden dem vælger appen de sider, der vender mod
  hinanden. `toEnd` er `arrow` som standard, `fromEnd` er `none`. `label` står midt på pilen.
- `color`: `"1"` til `"6"` (rød/accent, orange, gul, grøn, blå, lilla) eller hex.
  Brug det sparsomt, fx til at fremhæve en anbefalet variant.
- Nodernes rækkefølge er stablingsrækkefølgen: senere noder ligger øverst.
- `id`: korte, beskrivende id'er som `login-b` eller `kurv`. De står i de
  referencer, brugeren sender dig.
- Skriv JSON med tab-indrykning. Appen skriver sådan, når brugeren flytter noget,
  så diffs forbliver små.

## Mål og layout

Frames har fast størrelse, og siden scroller indeni. Brug enhedsmål:

| Enhed | width × height |
|---|---|
| Mobil | 390 × 844 |
| Tablet | 834 × 1194 |
| Desktop | 1440 × 900 |

- **Varianter** af samme skærm: på række med 80 px mellemrum, samlet i en gruppe.
- **Flow**: skærmene i rækkefølge fra venstre mod højre med **mindst 160 px**
  mellemrum og pile `right` → `left`. Ved 80 px dækker pilens label pilen.
- **Responsiv visning**: den samme `.html`-fil som tre noder i de tre bredder.
  Siden skal så selv være responsiv.
- **Grupper**: 40 px luft rundt om indholdet. Labelen står over gruppen, så hold
  mindst 80 px fri over den til næste række.
- Noter og beslutninger til venstre for skærmene, ca. 440 px brede.
- Start øverst til venstre omkring (0, 0). Appen zoomer selv, så alt kan ses.

## HTML-frames

Hver frame er en selvstændig side, der vises som en åbnet `.html`-fil. Reglerne
fra `md-editor` gælder også her:

- Komplet side med `<!doctype html>`, `<meta charset="utf-8">` og `<meta name="viewport" content="width=device-width">`.
- `body { margin: 0; min-height: 100vh; background: var(--color-background);
  color: var(--color-foreground); font-family: var(--font-body); }`.
- Intet netværk: CDN-scripts, webfonte, eksterne billeder og `fetch` blokeres.
  Billeder lægger du som filer ved siden af (`screens/img/hero.png`) eller som inline SVG.
- Farver kun via CSS-variablerne `--color-background`, `--color-foreground`,
  `--color-card`, `--color-muted`, `--color-muted-foreground`,
  `--color-secondary-foreground`, `--color-border`, `--color-primary` (accent),
  `--color-nm-blue` og skrift via `--font-body` og `--font-mono`. De følger
  lyst/mørkt tema og brugerens accentfarve. Chart.js og `mdTheme` findes også.
- Brødtekst mindst 16px, intet under 12px.
- **Klikbare prototyper**: et link til en anden lokal side
  (`<a href="checkout-2-levering.html">`) skifter siden inde i framen.
  Weblinks åbner i browseren.
- Brug ikke `alert()`, `confirm()` eller `prompt()`. De vises ikke.
- **Wireframes**: beder brugeren om wireframes, så hold dig til gråtoner
  (`--color-muted`, `--color-border`, `--color-muted-foreground`), grå bokse i
  stedet for billeder og rigtige danske overskrifter med kort pladsholdertekst.
  Ingen accentfarve, undtagen på den primære knap.

## Iteration

- **Læs `.canvas`-filen, før du skriver i den.** Brugeren kan have flyttet eller
  skaleret noder. Bevar `x`, `y`, `width` og `height` på eksisterende noder, og
  tilføj nye noder et sted med fri plads.
- Ret helst i `.html`-filerne. Appen genindlæser kun den berørte frame, inden for
  et sekund. Rør kun `.canvas`, når noder skal tilføjes, fjernes eller forbindes.
- Ny variant: ny fil (`login-c.html`) og ny node, frem for at overskrive en
  variant brugeren måske vil sammenligne med.
- Brugeren kan selv lave, omdøbe, farve og fjerne grupper i appen. Bevar dem,
  og læg nye skærme ind i den gruppe, de hører til.
- Brugeren kan trække billeder, `.html`- og `.md`-filer fra Finder ind på
  canvasset. Appen kopierer dem til `assets/` ved siden af `.canvas`-filen og
  laver en node. Brug gerne de billeder i dine frames (`../assets/foto.png` fra
  `screens/`).
- Skriv hele `.canvas`-filen på én gang. En halvskrevet fil vises som en fejl,
  indtil den er gyldig JSON igen.

## Vis canvasset

Når første version er klar, så åbn den:

```sh
open -a MarkdownEditor "/sti/til/login-prototype/login.canvas"
```

Gør det én gang, ikke ved hver rettelse. Appen følger selv med. Fejler kommandoen,
fordi appen ikke er installeret, så skriv bare stien.

Brugeren kan sende dig en reference til en node (højreklik → Copy as Reference):

```
/sti/til/login.canvas › node "login-b" (screens/login-b.html)
```

For tekstnoder følger teksten med som citat. Ret i den fil, referencen peger på.

## Undgå

- Frames i fri størrelse som 500 × 500. Brug enhedsmålene.
- Flere skærme samlet i én `.html`-fil. Én skærm pr. fil, så de kan flyttes og rettes hver for sig.
- Egne felter i `.canvas` ud over JSON Canvas-specifikationen. Obsidian kan fjerne dem.
- At flytte brugerens noder tilbage, fordi dit layout var pænere.
- Hårdkodede hex-farver i frames. De knækker i mørkt tema.
