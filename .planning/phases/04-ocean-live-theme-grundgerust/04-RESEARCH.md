# Phase 4: ocean-live Theme Grundgerust - Research

**Researched:** 2026-03-13
**Domain:** Vanilla HTML/CSS/JS Single-File Weather Dashboard
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| THEME-01 | ocean-live.html als einzelne Datei in webfrontend/html/ abgelegt | File location confirmed; pattern established by existing themes in webfrontend/html/ |
| THEME-02 | Theme hat 3 Tab-Buttons: Heute / Morgen / Tage | Tab pattern extracted from ocean.main.html: `.tab` + `.tab-panel` + `data-tab` attribute |
| THEME-03 | Tab-Wechsel zeigt/versteckt zugehoerige Inhalte mit CSS-Transitions | CSS `display:none`/`.active` pattern confirmed in ocean.main.html line 123; smooth fade via opacity transition |
| THEME-04 | Visuelles Design orientiert sich am bestehenden Ocean-Theme (Farbschema, Typografie, Layout) | Full CSS variable set extracted from ocean.main.html; Outfit + JetBrains Mono fonts; glass morphism card pattern |
| HERO-01 | Hero-Bereich zeigt ausgewaehlte Stunde gross an (Temperatur, Icon, Beschreibung, Wind, Feuchtigkeit) | `.hero` layout from ocean.main.html lines 131-145; static mock data replaces `<!--$var-->` placeholders |
| HERO-02 | Horizontale Stundenleiste unter dem Hero zeigt alle Stunden des Tages | `.hour-strip` horizontal scroll pattern from ocean.main.html lines 168-186 |
| HERO-03 | Klick auf Stunde in der Leiste aktualisiert den Hero-Bereich | `selectHour()` JS function from ocean.main.html lines 591-606 — reuse pattern with static mock data |
| HERO-04 | Heute-Tab zeigt Stunden des heutigen Tages | Heute-Tab maps to hourlyforecast data filtered by today date; mock: 24 static entries |
| HERO-05 | Morgen-Tab zeigt Stunden des morgigen Tages | Morgen-Tab maps to hourlyforecast data filtered by tomorrow date; mock: 24 static entries |
| HERO-06 | Aktuelle Stunde (Heute) bzw. erste Stunde (Morgen) ist bei Tab-Wechsel vorausgewahlt | Pre-select logic on tab switch: `selectHour` with index of current hour for Heute, index 0 for Morgen |
| TAGE-01 | Tage-Tab zeigt 7-Tage-Vorhersage als Uebersicht | `.daily-wrap` / `.drow` pattern from ocean.main.html; extend from 4 to 7 rows; mock data |
| TAGE-02 | Pro Tag: Wetter-Icon, Hoch/Tief-Temperatur, Niederschlagswahrscheinlichkeit | drow grid: `drow-icon`, `drow-hi`, `drow-lo`, `drow-pop` — all present in ocean.main.html |
| EXTRA-02 | Smooth CSS-Transitions bei Tab-Wechsel und Hero-Aktualisierung | Tab: opacity/transform transition on `.tab-panel`; Hero: CSS transition on temp/desc/icon DOM updates |
</phase_requirements>

## Summary

Phase 4 baut ein einzelnes HTML-Dokument (`webfrontend/html/ocean-live.html`), das das vollstaendige visuelle Design des Ocean-Themes zeigt — noch ohne Live-Daten. Alle Wetterwerte sind statisch eingebettete Mock-Daten. Das Interface zeigt die vollstaendige Interaktivitaet (Tab-Wechsel, Stunden-Auswahl, Hero-Update) schon in dieser Phase, damit in Phase 5 nur noch die Datenanbindung erganzt werden muss.

Das beste Referenz-Modell ist `templates/themes/de/ocean.main.html` — diese Datei enthaelt das fertige Ocean-Design mit CSS-Variablen, Glass-Morphism-Karten, Hero-Bereich, Stundenleiste und Daily-Tab. Der einzige strukturelle Unterschied: ocean-live braucht die Tabs "Heute / Morgen / Tage" (statt "Aktuell / Stundlich / Tage") und zeigt 7 statt 4 Tage. Das JavaScript ist ebenfalls direkt wiederverwendbar.

Das wichtigste Design-Prinzip fuer Phase 4: **keine externen Daten laden**, nur statische Inline-Mock-Werte. Dadurch laeuft die Datei direkt im Browser ohne Server, was das Entwickeln und Testen erheblich erleichtert. Phase 5 ersetzt dann die Mock-Arrays durch Fetch-Calls.

**Primary recommendation:** Kopiere das CSS- und HTML-Grundgerust von `ocean.main.html` in `webfrontend/html/ocean-live.html`, tausche `<!--$var-->` Platzhalter gegen statische Inline-Mock-Daten aus, und passe die Tab-Labels und Daily-Zeilen-Anzahl an.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vanilla HTML/CSS/JS | — | Gesamte Implementierung | Projekt-Constraint: keine Build-Tools, keine Frameworks |
| Outfit (Google Fonts) | latest | Hauptschrift | Bereits in ocean.main.html verwendet; konsistentes Design |
| JetBrains Mono (Google Fonts) | latest | Monospace fuer Zahlen/Zeit | Bereits in ocean.main.html verwendet |
| Lucide Icons | latest (unpkg CDN) | SVG-Icon-Set fuer UI-Elemente | Bereits in ocean.main.html via `<script src="https://unpkg.com/lucide@latest">` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Keine zusaetzlichen Libraries | — | — | Phase 4 braucht keine Bibliotheken ausser den bereits etablierten |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Vanilla JS Tab-Switching | Alpine.js / Vue | Kein Build-Tooling erlaubt; Vanilla ist ausreichend fuer diese Komplexitaet |
| Google Fonts CDN | Lokale Fonts | Raspberry Pi hat Internet-Zugang; CDN ist simpler; kein Offline-Requirement in Phase 4 |

**Installation:**

Keine npm-Packages. Alles wird inline oder via CDN geladen.

## Architecture Patterns

### Recommended Project Structure

```
webfrontend/html/
├── ocean-live.html          # Einzige neue Datei in Phase 4
├── icons/                   # Bestehend — {iconset}/{icon_name}_day.png etc.
├── lang-de.json             # Bestehend — noch nicht verwendet in Phase 4
└── jquery/                  # Bestehend — nicht benoetigt
```

### Pattern 1: Single-File Theme mit eingebetteten Mock-Daten

**What:** ocean-live.html enthaelt CSS, HTML und JS in einer einzigen Datei. Mock-Daten sind als inline JS-Arrays direkt im `<script>`-Block.
**When to use:** Phase 4 — vor Datenanbindung. Erlaubt vollstaendige Entwicklung ohne Server.

```html
<script>
// MOCK DATA — wird in Phase 5 durch Fetch-Responses ersetzt
var MOCK_CURRENT = {
  temperature: 12.4, feelslike: 9.1, humidity: 68,
  wind_speed: 18, wind_direction_desc: "NW",
  weather_icon: "partly-cloudy", weather_description: "Teilweise bewoelkt",
  sunrise: "06:23", sunset: "18:05"
};
var MOCK_HOURLY_TODAY = [
  { hour: "08", temp: 8.2, pop: 10, wind: 15, icon: "partly-cloudy", dn: "d", desc: "Heiter" },
  // ... 24 Eintraege
];
var MOCK_HOURLY_TOMORROW = [ /* analog */ ];
var MOCK_DAILY = [
  { day: "Mo", date: "17.03.", icon: "fair", high: 14.2, low: 5.8, pop: 5 },
  // ... 7 Eintraege
];
</script>
```

### Pattern 2: Tab-Navigation (aus ocean.main.html extrahiert)

**What:** Drei Tab-Buttons mit `data-tab` Attribut steuern Sichtbarkeit von `.tab-panel` Elementen.
**When to use:** Immer — ist das Kern-Interaktionsmuster.

```html
<!-- Tab-Buttons -->
<div class="tabs glass">
  <button class="tab active" data-tab="heute">Heute</button>
  <button class="tab" data-tab="morgen">Morgen</button>
  <button class="tab" data-tab="tage">Tage</button>
</div>

<!-- Panels -->
<div id="panel-heute" class="tab-panel active"><!-- ... --></div>
<div id="panel-morgen" class="tab-panel"><!-- ... --></div>
<div id="panel-tage" class="tab-panel"><!-- ... --></div>
```

```javascript
// Tab-Switching (aus ocean.main.html Zeilen 581-588)
document.querySelectorAll('.tab').forEach(function(btn) {
  btn.addEventListener('click', function() {
    document.querySelectorAll('.tab').forEach(function(b) { b.classList.remove('active'); });
    document.querySelectorAll('.tab-panel').forEach(function(p) { p.classList.remove('active'); });
    btn.classList.add('active');
    document.getElementById('panel-' + btn.getAttribute('data-tab')).classList.add('active');
    // Bei Heute: aktuelle Stunde vorauswaehlen; bei Morgen: erste Stunde
    preselectHour(btn.getAttribute('data-tab'));
  });
});
```

### Pattern 3: Hero-Stunden-Update (aus ocean.main.html extrahiert)

**What:** Klick auf `.hcard` aktualisiert den Hero-Bereich mit den Werten der ausgewaehlten Stunde.
**When to use:** Heute-Tab und Morgen-Tab.

```javascript
// selectHour Funktion (aus ocean.main.html Zeilen 591-606, vereinfacht fuer Mock-Daten)
function selectHour(el, dataArray) {
  document.querySelectorAll('.hcard').forEach(function(c) { c.classList.remove('selected'); });
  el.classList.add('selected');
  var idx = parseInt(el.getAttribute('data-idx'));
  var d = dataArray[idx];
  document.getElementById('heroTemp').innerHTML = Math.round(d.temp) + '<sup>°C</sup>';
  document.getElementById('heroDesc').textContent = d.desc;
  document.getElementById('heroWind').textContent = d.wind + ' km/h ' + d.wind_dir;
  document.getElementById('heroHumidity').textContent = d.humidity + '%';
  document.getElementById('heroIcon').src = ICON_BASE + d.icon + '_' + d.dn + '.png';
}
```

### Pattern 4: Icon-Pfad Konvention

Die bestehenden Icon-Sets (color, flat, dark, light etc.) verwenden das Muster:
`/plugins/{psubfolder}/icons/{iconset}/{icon_name}_{day|night}.png`

In ocean.main.html wird der Pfad als `<!--$webpath-->/icons/<!--$iconset-->/<!--$dayornight-->/<!--$icon-->.png` eingebettet, was ein Unterverzeichnis `d/` und `n/` impliziert. Die tatsaechlichen Dateien im `color/`-Verzeichnis haben jedoch das Suffix `_day.png` / `_night.png` (KEIN Unterverzeichnis).

**Wichtig fuer Phase 4:** Da keine Live-Daten verwendet werden, muss das Icon-Pfad-Muster dokumentiert sein, aber die exakte URL-Struktur ist erst in Phase 5 relevant. Fuer Mock-Daten kann ein bekannt-existierendes Icon wie `partly-cloudy_day.png` aus dem `color`-Set hardcodiert werden, oder ein konkretes Icon-Bild aus `icons/color/` gewaehlt werden.

Die Pfadstruktur aus ocean.main.html (`/d/` und `/n/` Unterverzeichnisse) stimmt nicht mit der tatsaechlichen Dateistruktur ueberein (die `_day` / `_night` Suffixe nutzt). Dies muss beim Schreiben der Bildpfade beachtet werden. Da ocean.main.html aber als SSR-Template existiert (Platzhalter werden vom CGI gefuellt), koennte die dayornight Variable entweder `d` oder `day` sein — Verifikation erforderlich.

### Pattern 5: CSS-Transitions fuer Tab-Wechsel (EXTRA-02)

```css
/* Tab-Panel: Fade-in bei Aktivierung */
.tab-panel {
  display: none;
  opacity: 0;
  transition: opacity 0.3s ease;
}
.tab-panel.active {
  display: block;
  opacity: 1;
}
```

**Hinweis:** `display: none` und CSS `transition` interagieren nicht direkt (transition wird ignoriert wenn display von none zu block wechselt). Loesung: Erst `display: block` setzen, dann in naechstem Frame `opacity: 1` via `requestAnimationFrame` oder kurzer Timeout.

```javascript
// Korrektes Fade-In Pattern
function showPanel(id) {
  var panel = document.getElementById(id);
  panel.style.display = 'block';
  requestAnimationFrame(function() { panel.style.opacity = '1'; });
}
function hidePanel(id) {
  var panel = document.getElementById(id);
  panel.style.opacity = '0';
  setTimeout(function() { panel.style.display = 'none'; }, 300); // match transition duration
}
```

Alternativ: Kein `display:none`, stattdessen `visibility: hidden` + `position: absolute` + opacity-Transition. Dies vermeidet das display-transition Problem.

### Pattern 6: CSS-Klassen fuer Ocean-Design (direkt aus ocean.main.html)

```css
/* Alle folgenden CSS-Variablen und Klassen werden 1:1 uebernommen */
:root {
  --bg-primary: #0f172a;   /* Dunkelblau Hintergrund */
  --bg-secondary: #1e293b;
  --bg-card: rgba(255,255,255,0.03);
  --border: rgba(255,255,255,0.08);
  --text-primary: #f8fafc;
  --text-secondary: #94a3b8;
  --text-muted: #64748b;
  --sky: #38bdf8;          /* Hauptakzentfarbe Blau */
  --amber: #fbbf24;        /* Temperatur-Hoch */
  --emerald: #10b981;
  --tab-from: rgba(56,189,248,0.2);
  --tab-to: rgba(139,92,246,0.2);
  --tab-border: rgba(56,189,248,0.4);
  --glow: 0 0 40px rgba(56,189,248,0.35);
}
.glass {
  background: var(--bg-card);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid var(--border);
  border-radius: 20px;
}
```

### Anti-Patterns to Avoid

- **Platzhalter `<!--$var-->` uebernehmen:** ocean.main.html hat SSR-Platzhalter — diese muessen in ocean-live.html durch statische Mock-Werte oder DOM-IDs ersetzt werden.
- **Tab-Panel mit `visibility:hidden` + normaler Flow:** Verursacht Layout-Luecken wenn Panels versteckt sind aber noch Platz belegen. `display:none` oder `position:absolute` nutzen.
- **Tage-Tab: 4 statt 7 Zeilen:** ocean.main.html hat nur dfc0-dfc3 (4 Tage). TAGE-01 verlangt 7 Tage — die Vorlage muss auf 7 Zeilen erweitert werden.
- **Morgen-Tab: Stunden aus falschem Tag:** hourlyforecast.json hat 36 Stunden ab jetzt — fuer Morgen muessen die Eintraege des morgen-Datums herausgefiltert werden (In Phase 4 mit Mock-Daten kein Problem, aber die Datenstruktur muss vorbereitet sein).
- **CSS transition auf `display` Property:** Funktioniert nicht. Immer `opacity` + `requestAnimationFrame` oder `visibility` verwenden.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Icon-Set Bilder | Eigene Wetter-Icons erstellen | Bestehende Icon-Sets in `webfrontend/html/icons/` | 11 Icon-Sets mit 20+ Symbolen pro Set bereits vorhanden |
| Glassmorphism Card-Design | Eigenes Card-CSS schreiben | CSS direkt aus ocean.main.html kopieren | Design ist bereits fertig und getestet |
| Tab-Switching-Logik | Eigene State-Machine | Pattern aus ocean.main.html Zeilen 581-588 | Bereits funktionierend, < 10 Zeilen |
| Drag-Scroll fuer Stundenleiste | Touch-Event-Handling selbst | Pattern aus ocean.main.html Zeilen 690-703 | PointerEvent-basiert, behandelt alle Edge-Cases |

**Key insight:** ocean.main.html ist de facto ein Template fuer ocean-live.html. Kein CSS oder JS muss neu geschrieben werden — nur die Datenquelle wechselt von SSR-Platzhaltern zu statischen Mock-Arrays.

## Common Pitfalls

### Pitfall 1: Icon-Pfad-Diskrepanz

**What goes wrong:** ocean.main.html verwendet `/icons/{iconset}/d/{icon}.png` (Unterverzeichnis), aber die tatsaechlichen Dateien im `icons/color/`-Verzeichnis heissen `partly-cloudy_day.png` (Suffix, kein Unterverzeichnis).
**Why it happens:** ocean.main.html wird vom CGI gerendert, das `<!--$dayornight-->` durch `d` oder `n` ersetzt — das impliziert Unterverzeichnisse. Die tatsaechlichen Icons im `color/`-Set nutzen aber `_day`/`_night` Suffixe.
**How to avoid:** Fuer Phase 4 (Mock-Daten) einen bekannt-existierenden Icon-Pfad hardcoden und visuell pruefen. Fuer Phase 5 muss die tatsaechliche URL-Struktur per `icon_mapping.json` (falls vorhanden) oder Verzeichnislisting verifiziert werden.
**Warning signs:** 404-Fehler fuer Icon-Bilder im Browser-Netzwerk-Tab.

### Pitfall 2: display:none + CSS transition

**What goes wrong:** Tab-Panels mit `display:none` und `transition: opacity 0.3s` zeigen keine Fade-Animation.
**Why it happens:** Browser triggert keine Transitions wenn `display` von `none` zu `block` wechselt — das Element ist im selben Frame bereits sichtbar.
**How to avoid:** `requestAnimationFrame` nach `display: block` nutzen, bevor `opacity: 1` gesetzt wird. Oder Panels mit `visibility: hidden` + `position: absolute/fixed` verstecken statt `display: none`.
**Warning signs:** Abrupter Panel-Wechsel ohne Uebergangsanimation.

### Pitfall 3: Heute-Tab zeigt falsche Stunden bei Morgen-Tab

**What goes wrong:** Beide Tabs teilen sich das gleiche HFC-Array und selectHour aktualisiert den falschen Hero.
**Why it happens:** Wenn beide Panels den gleichen DOM-IDs (`heroTemp` etc.) schreiben, aber jeweils unterschiedliche Stunden-Arrays brauchen, muss der aktive Tab-Kontext bekannt sein.
**How to avoid:** `selectHour` bekommt das korrekte Daten-Array als Parameter, oder der aktive Tab wird als Variable gespeichert.
**Warning signs:** Klick auf Morgen-Stunde aktualisiert Hero mit Heute-Daten.

### Pitfall 4: Keine Preselection beim Tab-Wechsel

**What goes wrong:** Nach Tab-Wechsel ist keine Stunde ausgewaehlt und der Hero zeigt leere oder veraltete Werte.
**Why it happens:** HERO-06 verlangt dass beim Oeffnen des Heute-Tabs die aktuelle Stunde vorausgewaehlt wird, beim Morgen-Tab die erste Stunde.
**How to avoid:** Im Tab-Click-Handler nach Panel-Aktivierung `preselectHour(tab)` aufrufen. Fuer Heute: `new Date().getHours()` gegen hour-Daten matchen. Fuer Morgen: Index 0.
**Warning signs:** Hero-Bereich nach Tab-Wechsel zeigt Platzhalter oder alten Wert.

### Pitfall 5: 4-Tage-Vorlage statt 7-Tage

**What goes wrong:** Daily-Tab zeigt nur 4 Tage weil ocean.main.html nur dfc0-dfc3 hat.
**Why it happens:** Existierendes Template ist aus Phase 3/altem System auf 4 Tage begrenzt; TAGE-01 verlangt 7.
**How to avoid:** Beim Erstellen von ocean-live.html 7 Mock-Zeilen in den Daily-Tab schreiben; nicht 1:1 von ocean.main.html kopieren.
**Warning signs:** Daily-Tab endet bei Tag 4.

## Code Examples

### Tab-Panel CSS (Ocean-Stil mit Fade-Transition)

```css
/* Source: ocean.main.html (adaptiert fuer Fade-Transition) */
.tab-panel {
  display: none;
  opacity: 0;
  transition: opacity 0.3s ease;
}
.tab-panel.active {
  display: block;
}
.tab-panel.fade-in {
  opacity: 1;
}
```

```javascript
// Korrekte Tab-Aktivierung mit Fade
document.querySelectorAll('.tab').forEach(function(btn) {
  btn.addEventListener('click', function() {
    var activePanel = document.querySelector('.tab-panel.active');
    if (activePanel) {
      activePanel.classList.remove('active', 'fade-in');
    }
    document.querySelectorAll('.tab').forEach(function(b) { b.classList.remove('active'); });
    btn.classList.add('active');
    var newPanel = document.getElementById('panel-' + btn.getAttribute('data-tab'));
    newPanel.classList.add('active');
    requestAnimationFrame(function() { newPanel.classList.add('fade-in'); });
    preselectHour(btn.getAttribute('data-tab'));
  });
});
```

### Hero-Update bei Stunden-Auswahl

```javascript
// Source: ocean.main.html lines 591-606 (fuer Mock-Daten adaptiert)
function selectHour(el, dataArray) {
  document.querySelectorAll('.hcard').forEach(function(c) { c.classList.remove('selected'); });
  el.classList.add('selected');
  var idx = parseInt(el.getAttribute('data-idx'));
  var d = dataArray[idx];
  // Hero-Update mit Transition
  var heroTemp = document.getElementById('heroTemp');
  heroTemp.style.transition = 'opacity 0.15s';
  heroTemp.style.opacity = '0';
  setTimeout(function() {
    heroTemp.innerHTML = Math.round(d.temp) + '<sup>°C</sup>';
    heroTemp.style.opacity = '1';
  }, 150);
  document.getElementById('heroDesc').textContent = d.desc;
  document.getElementById('heroWind').textContent = d.wind + ' km/h ' + d.wind_dir;
  document.getElementById('heroHumidity').textContent = d.humidity + '%';
}
```

### Daily-Zeile (7-Tage-Vorlage)

```html
<!-- Source: ocean.main.html lines 487-490 (auf 7 Eintraege erweitert) -->
<div class="drow glass today">
  <div>
    <div class="drow-day">Mo</div>
    <div class="drow-date mono">17.03.</div>
  </div>
  <img class="drow-icon" src="../html/icons/color/partly-cloudy_day.png" alt="">
  <div class="drow-desc">Teilweise bewoelkt</div>
  <div class="drow-pop">10%</div>
  <div class="drow-temps">
    <span class="drow-lo mono">6°</span>
    <div class="drow-bar"><div class="drow-fill" id="bar0"></div></div>
    <span class="drow-hi mono">14°</span>
  </div>
</div>
```

### Stundenleiste (Heute-Tab, Mock-Daten)

```html
<!-- Source: ocean.main.html lines 398-424 (statisch statt SSR-Platzhalter) -->
<div class="hour-strip" id="hourStripHeute">
  <div class="hcard glass selected" data-idx="0" onclick="selectHour(this, MOCK_HOURLY_TODAY)">
    <div class="hcard-time mono">08:00</div>
    <img class="hcard-icon" src="../html/icons/color/partly-cloudy_day.png" alt="">
    <div class="hcard-temp">8°</div>
    <div class="hcard-pop">10%</div>
  </div>
  <!-- ... weitere Stunden ... -->
</div>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SSR-Template mit `<!--$var-->` Platzhaltern | Static mock HTML in Phase 4, Fetch-basiert in Phase 5 | Phase 4 (aktuell) | Theme kann ohne Server entwickelt und getestet werden |
| 4-Tage-Daily-Tab (dfc0-dfc3) | 7-Tage-Daily-Tab | Phase 4 | TAGE-01 Requirement erfuellt |
| Tabs "Aktuell / Stundlich / Tage" (ocean.main.html) | Tabs "Heute / Morgen / Tage" (ocean-live.html) | Phase 4 | Hero+Stundenleiste pro Tag |
| Herunterladen aus templates/themes/ | Ablage in webfrontend/html/ | Phase 4 | Direkter HTTP-Zugriff ohne CGI |

**Deprecated/outdated:**

- `<!--$var-->` SSR-Platzhalter: In ocean-live.html nicht verwenden — alle Werte kommen aus JS (Mock in Ph4, Fetch in Ph5)

## Open Questions

1. **Icon-Pfad-Konvention: Unterverzeichnis oder Suffix?**
   - What we know: color/ Icons haben `_day.png`/`_night.png` Suffix (keine Unterverzeichnisse); ocean.main.html SSR-Template nutzt `/{d|n}/` Unterverzeichnis-Notation
   - What's unclear: Welche Icon-Sets haben `/d/` und `/n/` Unterverzeichnisse? Ist das eine Konvention die nur fuer manche Sets gilt?
   - Recommendation: Fuer Phase 4 statischen Pfad `icons/color/partly-cloudy_day.png` verwenden und visuell pruefen. In Phase 5 (Datenanbindung) icon_mapping.json auswerten.

2. **webpath-Variable in ocean-live.html**
   - What we know: ocean.main.html verwendet `<!--$webpath-->` = `/plugins/{psubfolder}` — wird vom CGI gesetzt
   - What's unclear: Da ocean-live.html eine statische HTML-Datei in `webfrontend/html/` ist (kein CGI), muss der webpath anders gesetzt werden. Relativer Pfad `../..` oder absoluter Pfad `/plugins/{psubfolder}`?
   - Recommendation: In Phase 4 relativen Pfad `./icons/` verwenden (da ocean-live.html in `webfrontend/html/` liegt und die Icons auch dort sind). In Phase 5 wird der webpath aus der CGI-Konfiguration per URL-Parameter oder JS-Variable gesetzt.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Keine automatisierten Tests fuer Frontend-HTML in Phase 4 |
| Config file | none |
| Quick run command | Datei im Browser oeffnen: `file:///path/to/ocean-live.html` |
| Full suite command | Browser-seitige manuelle Pruefung aller Success Criteria |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| THEME-01 | Datei existiert in webfrontend/html/ | smoke | `test -f webfrontend/html/ocean-live.html && echo OK` | Wave 0 |
| THEME-02 | 3 Tab-Buttons vorhanden | manual | Browser-Inspektion | Wave 0 |
| THEME-03 | Tab-Wechsel mit Transition | manual | Klicktest im Browser | Wave 0 |
| THEME-04 | Ocean-Farbschema sichtbar | manual | Visueller Vergleich mit ocean.main.html | Wave 0 |
| HERO-01 | Hero zeigt alle 5 Felder | manual | Browser-Sichtpruefung | Wave 0 |
| HERO-02 | Stundenleiste horizontal scrollbar | manual | Browser + Touch/Mouse | Wave 0 |
| HERO-03 | Stunden-Klick aktualisiert Hero | manual | Klicktest auf 3 verschiedene Stunden | Wave 0 |
| HERO-04 | Heute-Tab: richtige Stunden | manual | Datum-Label in Stundenkarten pruefen | Wave 0 |
| HERO-05 | Morgen-Tab: richtige Stunden | manual | Datum-Label in Stundenkarten pruefen | Wave 0 |
| HERO-06 | Preselection beim Tab-Wechsel | manual | Tab wechseln, Hero-Inhalt pruefen | Wave 0 |
| TAGE-01 | 7-Tage-Tab sichtbar | manual | Tage zaehlen im Daily-Tab | Wave 0 |
| TAGE-02 | Icon/Hoch/Tief/PoP pro Tag | manual | Visueller Scan der Daily-Zeilen | Wave 0 |
| EXTRA-02 | CSS-Transitions | manual | Tab-Wechsel und Hero-Update beobachten | Wave 0 |

### Sampling Rate

- **Per task commit:** `test -f webfrontend/html/ocean-live.html && echo "File exists"` (bash smoke)
- **Per wave merge:** Datei im Browser oeffnen, alle 5 Success Criteria manuell pruefen
- **Phase gate:** Alle 5 Success Criteria gruen vor `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `webfrontend/html/ocean-live.html` — Zieldatei (wird in dieser Phase erstellt, muss nicht vorab existieren)
- [ ] Keine Test-Infrastruktur noetig — alle Tests sind manuelle Browser-Checks

## Sources

### Primary (HIGH confidence)

- `templates/themes/de/ocean.main.html` — vollstaendiges CSS-Design, Tab-Muster, Hero-HTML, Stunden-Strip, JS Tab-Switching, selectHour-Funktion, Drag-Scroll
- `data/json-schema.md` — autoritaeres JSON-Schema; definiert welche Felder fuer Mock-Daten verwendet werden
- `webfrontend/html/icons/` — bestehende Icon-Sets; Datei-Konvention `{name}_day.png`
- `.planning/REQUIREMENTS.md` — definitive Requirement-Beschreibungen fuer alle Phase-4-IDs

### Secondary (MEDIUM confidence)

- `templates/themes/de/fresh.main.html` — alternatives Design-Referenz (Tailwind-basiert, fuer ocean-live NICHT verwenden)
- `.planning/phases/03-cgi-json-endpoint/03-CONTEXT.md` — Show.cgi JSON-Endpoint-Details; bestaetigt Pfadstruktur und Fehlerverhalten

### Tertiary (LOW confidence)

- Icon-Pfad-Konvention fuer Unterverzeichnisse (`/d/` vs `_day`) — muss in Phase 5 verifiziert werden

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — alles ist Vanilla HTML/CSS/JS ohne externe Dependencies (ausser bereits etablierten CDN-Links)
- Architecture: HIGH — ocean.main.html ist vollstaendige Referenz; alle Muster direkt extrahierbar
- Pitfalls: HIGH — display+transition Bug und Icon-Pfad-Diskrepanz sind bekannte, gut dokumentierte HTML/CSS-Probleme

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (stabile Technologien; lang gueltig)
