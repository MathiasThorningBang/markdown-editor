---
name: md-editor
description: Brug når du skriver .md- eller .html-filer, som brugeren skal læse i MarkdownEditor-appen, især planer, briefs og rapporter med diagrammer, charts, KPI'er eller tidsplaner. Beskriver hvornår du bruger markdown, ```mermaid, ```html med Chart.js eller en selvstændig .html-fil, og hvilke regler der gælder.
---

# Skriv til MarkdownEditor

MarkdownEditor viser .md-filer som et dokument (WYSIWYG). Den renderer også
```mermaid- og ```html-kodeblokke og kan åbne .html-filer som læsevisning.
Alt kører offline.

## Hvad skal du bruge?

- Tekst, lister, beslutninger og tabeller → almindelig markdown.
- Flow, proces, tidsplan eller struktur → ```mermaid.
- Tal og data (bar, line, doughnut), KPI-kort, styrede grids → ```html.
- Et helt visuelt dashboard, der skal stå alene → .html-fil.
- Prototyper, wireframes, skærmflows eller varianter side om side → et `.canvas`.
  Se skill'en `md-canvas`.

Prosaen skal altid stå i markdown, så filen også kan læses af andre modeller og
på GitHub. Diagrammer og HTML-blokke supplerer teksten. Skriv konklusionen i
markdown og lad blokken vise tallene bag.

## Mermaid

Førstevalget til diagrammer, fordi det er tekst og nemt at rette. Mermaid 11:
flowchart, sequenceDiagram, gantt, timeline, mindmap, stateDiagram, erDiagram,
pie osv. Farver og skrift sættes af appens tema, så du skal ikke style dem.

````markdown
```mermaid
gantt
    title Kampagneplan
    dateFormat YYYY-MM-DD
    section Analyse
    Brief og interviews    :a1, 2026-10-12, 5d
    section Koncept
    Idéudvikling           :a2, after a1, 7d
    Præsentation for kunde :milestone, after a2, 0d
```
````

En syntaksfejl vises som fejltekst i dokumentet. Hold labels korte, og sæt
tekst med specialtegn i anførselstegn: `A["Brief (v2)"]`.

## HTML-blokke

Hver ```html-blok kører i sin egen sandkassede iframe. Renderede blokke og
tabeller er bredere end teksten (op til ca. 1040 px, smallere i små vinduer), så
lav indholdet responsivt med procent, grid eller flex og ikke faste bredder.
Højden følger indholdet automatisk.

- Skriv kun et fragment. `<html>`, `<head>` og `<body>` skal ikke med. Inline
  `<style>` og `<script>` er fint, og id'er kan ikke støde sammen med andre blokke.
- Intet netværk: CDN-scripts, eksterne fonte, billeder og `fetch` blokeres.
- Chart.js 4.5.1 er indbygget som global `Chart`. Tekstfarve, gitter, font og
  seriefarver sættes automatisk, så de første serier får brugerens accentfarve
  og derefter en fast palet. Animation er slået fra.
- Brug CSS-variablerne til alt, du selv styler. De følger lyst/mørkt tema og
  brugerens accentfarve: `--color-background`, `--color-foreground`,
  `--color-card`, `--color-muted`, `--color-muted-foreground`,
  `--color-secondary-foreground`, `--color-border`, `--color-primary`
  (accent), `--color-nm-blue`, `--font-body`, `--font-mono`.
- I scripts findes de samme farver som værdier i `mdTheme`, fx `mdTheme.primary`,
  `mdTheme.border` og `mdTheme.palette[1]`. Du behøver ikke `getComputedStyle`.
- Brødtekst er 16px. Små labels må ned til 12px, men ikke under.

### Chart: læg altid lærredet i en div med fast højde

Et `<canvas>` direkte i et grid- eller flex-felt bliver ved med at vokse. Brug
denne opskrift hver gang:

````markdown
```html
<div style="position:relative;height:260px">
  <canvas id="timer"></canvas>
</div>
<script>
  new Chart(timer, {
    type: 'bar',
    data: {
      labels: ['Uge 41', 'Uge 42', 'Uge 43', 'Uge 44'],
      datasets: [
        { label: 'Brugt', data: [32, 41, 38, 45] },
        { label: 'Budget', data: [40, 40, 40, 40], type: 'line' }
      ]
    },
    options: { maintainAspectRatio: false }
  })
</script>
```
````

Til flere charts side om side bruger du
`grid-template-columns: repeat(2, minmax(0, 1fr))`, og hvert lærred får sin egen
div med fast højde. Bruger du `1fr` uden `minmax(0, …)`, vokser de.

### KPI-kort

````markdown
```html
<style>
  .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; }
  .kpi { background: var(--color-card); border: 1px solid var(--color-border); border-radius: 10px; padding: 14px 16px; }
  .kpi small { display: block; color: var(--color-secondary-foreground); font-size: 13px; }
  .kpi strong { font-size: 28px; }
  .kpi .up { color: var(--color-primary); font-size: 14px; }
</style>
<div class="kpis">
  <div class="kpi"><small>Timer brugt</small><strong>124</strong> <span class="up">82 %</span></div>
  <div class="kpi"><small>Faser</small><strong>3</strong></div>
  <div class="kpi"><small>Deadline</small><strong>14. nov.</strong></div>
</div>
```
````

## Selvstændige .html-filer

Appen viser .html-filer read-only og genindlæser dem, når filen ændres. Du kan
altså skrive videre i filen, mens brugeren kigger med. De samme regler gælder:
intet netværk, global `Chart`, `mdTheme` og CSS-variablerne på `:root`.

Forskellen fra blokke er, at siden selv styrer sit layout. Sæt derfor
`body { margin: 0; padding: 32px; background: var(--color-background);
color: var(--color-foreground); font-family: var(--font-body); }`.

## Vis filen i editoren

Når du er færdig med et dokument, som brugeren skal læse, så åbn det i appen:

```sh
open -a MarkdownEditor "/sti/til/rapport.md"
```

Appen kommer frem med filen valgt. Gør det kun, når dokumentet er færdigt, ikke
ved hver rettelse, for appen genindlæser selv filer, der allerede er åbne. Fejler
kommandoen, fordi appen ikke er installeret, så skriv bare stien.

Brugeren kan sende dig en reference fra appen (højreklik → Copy as Reference):
`sti:linjer` og derefter det markerede som citat. Linjenumrene er et bedste bud,
fordi editoren viser teksten uden markdown-tegn. Find stedet ud fra citatet, hvis
de ikke passer.

## Undgå

- CDN-links og eksterne ressourcer. De bliver blokeret, og blokken bliver tom.
- Hårdkodede hex-farver til tekst, baggrund og kanter. De knækker i mørkt tema.
- Vigtig tekst, der kun står inde i HTML. Den kan ikke læses uden renderer.
- Én kæmpe HTML-blok med hele dokumentet. Brug flere små blokke med markdown imellem.
- ``` inde i en html-blok, fordi det afslutter kodeblokken.
