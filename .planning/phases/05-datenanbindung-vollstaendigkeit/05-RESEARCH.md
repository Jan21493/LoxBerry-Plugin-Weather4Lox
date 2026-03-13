# Phase 5: Datenanbindung & Vollstandigkeit - Research

**Researched:** 2026-03-13
**Domain:** Vanilla JS Fetch API, i18n mit JSON-Sprachdateien, AJAX Auto-Refresh, Error Handling
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DATA-01 | Theme ladt Wetterdaten per Fetch API von show.cgi JSON-Endpoint | show.cgi bestatigt: `?format=json&type=current|hourly|daily` liefert JSON mit Content-Type application/json |
| DATA-02 | Theme ladt Sprachdaten per Fetch aus lang-*.json | lang-de.json etc. existieren in webfrontend/html/ — `theme.*` Schlussel enthalten alle UI-Labels |
| DATA-03 | Theme ladt Icon-Mapping per Fetch aus icons/{iconset}/icon_mapping.json | icon_mapping.json bestatigt: `icons.{weather_id}.icon_day` / `.icon_night` Schema |
| DATA-04 | Auto-Refresh ladt Daten periodisch nach (Intervall >= 5 Minuten) | `setInterval` / `setTimeout` Pattern — kein Framework benotigt |
| DATA-05 | Ladeanzeige wahrend AJAX-Requests | CSS Overlay + JS show/hide Pattern; kein externes Library benotigt |
| DATA-06 | Fehlermeldung wenn Daten nicht geladen werden konnen | show.cgi liefert 404/500 mit JSON-Fehlerobjekt; `response.ok` Check in Fetch |
| LANG-01 | Alle UI-Texte kommen aus lang-*.json | `theme.*` Schlussel in lang-*.json bestatigt vollstandige Abdeckung |
| LANG-02 | Unterstutzte Sprachen: DE, EN, ES, NL, SK | lang-de.json, lang-en.json, lang-es.json, lang-nl.json, lang-sk.json existieren alle |
| LANG-03 | Sprache wird per URL-Parameter oder Konfiguration gesetzt | Pattern bereits in ocean-live.html: `getUrlParam('lang')` — gleiches Muster wie `mode` Parameter |
| EXTRA-01 | Sonnenauf- und Sonnenuntergang im Hero-Bereich angezeigt | astro-row HTML-Struktur existiert bereits in ocean-live.html (Phase 4) mit hartcodierten Werten; Phase 5 bindet `data.sunrise` / `data.sunset` aus current.json an |
</phase_requirements>

## Summary

Phase 5 ist eine reine JavaScript-Erweiterung des in Phase 4 fertigen `ocean-live.html`. Das Theme hat bereits alle DOM-Strukturen, CSS-Klassen und Interaktionslogik. Die einzige Aufgabe: die statischen `MOCK_*` Arrays durch drei parallele Fetch-Calls ersetzen (`current`, `hourly`, `daily`), eine vierte Anfrage fur die Sprachdatei hinzufugen, Icon-Mapping per Fetch laden statt hardcodiert, und einen periodischen 5-Minuten-Refresh implementieren. Fehlerbehandlung und Ladeanzeige sind HTML/CSS-Erganzungen ohne externe Abhangigkeiten.

Die existierende `preselectHour()`-Funktion und alle `render*`-Funktionen (Phase 4) bleiben unverandert. Der Planner muss nur verstehen, welche globalen Variablen (`MOCK_CURRENT`, `MOCK_HOURLY_TODAY`, `MOCK_HOURLY_TOMORROW`, `MOCK_DAILY`) durch Fetch-Ergebnisse ersetzt werden, und welche DOM-IDs noch nicht an Live-Daten gebunden sind. Sunrise/Sunset (`EXTRA-01`) stehen bereits im astro-row HTML — nur die Textwerte sind noch hartcodiert.

Der kritische technische Punkt: `hourlyforecast.json` liefert alle Stunden ab jetzt in einem einzigen Array (geordnet nach `epoch`). Das Theme braucht eine Filterfunktion die "heute" (gleicher Kalendertag) von "morgen" trennt — basierend auf dem `datetime` Feld (ISO 8601 String). Das `weather_icon` Feld im JSON ist ein raw Iconname (z.B. `"partly-cloudy"`) — das muss gegen `icon_mapping.json` aufgelost werden um den richtigen Dateinamen zu erhalten. Tag/Nacht-Unterscheidung fur Icons muss aus dem Vergleich der Stunden-`datetime` mit Sunrise/Sunset aus `current.json` berechnet werden.

**Primary recommendation:** Ersetze die MOCK-Variablen durch ein zentrales `loadAllData()` Promise.all pattern, nutze `?lang=de` URL-Parameter fur Sprachauswahl, implementiere Loading-Overlay und Error-Banner als CSS-Klassen auf `<body>`, und plane den 5-Minuten-Refresh als `setTimeout`-Rekursion statt `setInterval`.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Fetch API (native) | Browser-built-in | HTTP-Requests zu show.cgi und JSON-Dateien | Kein jQuery/axios benotigt; alle modernen Browser; kein Build-Tooling |
| Promise.all (native) | Browser-built-in | Paralleles Laden von current + hourly + daily + lang + icon_mapping | 5 Requests parallel statt sequentiell = 5x schneller |
| setTimeout (native) | Browser-built-in | Periodischer Auto-Refresh | Rekursiver setTimeout statt setInterval — verhindert Stapeln von Requests bei langsamer Verbindung |
| Vanilla JS | — | Gesamte Implementierung | Projekt-Constraint: keine Build-Tools, keine Frameworks |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Keine zusatzlichen Libraries | — | — | Alle benotigten APIs sind browser-native |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Fetch API | XMLHttpRequest | Fetch ist moderner, Promise-basiert; XHR nur fur IE11 notig (nicht relevant) |
| Fetch API | jQuery.ajax | jQuery bereits im Projekt vorhanden (webfrontend/html/jquery/), aber ocean-live.html braucht es nicht |
| setTimeout Rekursion | setInterval | setInterval stapelt Aufrufe wenn vorheriger Request noch lauft; setTimeout-Rekursion wartet auf Abschluss |

**Installation:** Keine npm-Packages. Alles browser-nativ.

## Architecture Patterns

### Recommended Project Structure

```
webfrontend/html/
├── ocean-live.html          # Wird erweitert (einzige Zieldatei)
├── icons/
│   └── color/
│       └── icon_mapping.json   # Wird per Fetch geladen (DATA-03)
├── lang-de.json                # Wird per Fetch geladen (DATA-02)
├── lang-en.json
├── lang-es.json
├── lang-nl.json
└── lang-sk.json
```

### Pattern 1: Paralleles Laden aller Daten beim Start

**What:** `Promise.all` ladt current, hourly, daily, lang und icon_mapping gleichzeitig. Erst wenn alle geladen sind, wird gerendert.
**When to use:** Beim Seitenload und bei jedem Auto-Refresh.

```javascript
// Alle URLs relativ zu webfrontend/html/ (ocean-live.html liegt dort)
var BASE_CGI = '../../htmlauth/show.cgi';  // Pfad von webfrontend/html/ zu htmlauth/
var ICONSET  = 'color';  // Fallback; kann spater aus Config kommen

function loadAllData(lang) {
  return Promise.all([
    fetch(BASE_CGI + '?format=json&type=current').then(checkOk).then(function(r){ return r.json(); }),
    fetch(BASE_CGI + '?format=json&type=hourly').then(checkOk).then(function(r){ return r.json(); }),
    fetch(BASE_CGI + '?format=json&type=daily').then(checkOk).then(function(r){ return r.json(); }),
    fetch('lang-' + lang + '.json').then(checkOk).then(function(r){ return r.json(); }),
    fetch('icons/' + ICONSET + '/icon_mapping.json').then(checkOk).then(function(r){ return r.json(); })
  ]);
}

function checkOk(response) {
  if (!response.ok) throw new Error('HTTP ' + response.status + ' bei ' + response.url);
  return response;
}

// Verwendung beim Start:
loadAllData(currentLang).then(function(results) {
  var currentData  = results[0].data;  // Envelope: { meta, data }
  var hourlyData   = results[1].data;  // Array
  var dailyData    = results[2].data;  // Array
  var langStrings  = results[3];       // Direkt als Objekt
  var iconMapping  = results[4].icons; // icon_mapping.json .icons Objekt
  renderAll(currentData, hourlyData, dailyData, langStrings, iconMapping);
}).catch(showError);
```

### Pattern 2: Stunden-Filterung nach Datum

**What:** `hourlyforecast.json` liefert einen kontinuierlichen Array ab der aktuellen Stunde. "Heute" = gleicher Kalendertag wie `new Date()`, "Morgen" = Folgetag.
**When to use:** Beim Aufbau von `hourStripHeute` und `hourStripMorgen`.

```javascript
function filterHoursByDate(hourlyArray, targetDate) {
  // targetDate: Date-Objekt (z.B. new Date() fur heute)
  var targetDay = targetDate.toISOString().slice(0, 10); // "YYYY-MM-DD"
  return hourlyArray.filter(function(h) {
    return h.datetime.slice(0, 10) === targetDay;
  });
}

var today    = new Date();
var tomorrow = new Date(today); tomorrow.setDate(today.getDate() + 1);

var todayHours    = filterHoursByDate(hourlyData, today);
var tomorrowHours = filterHoursByDate(hourlyData, tomorrow);
```

**Wichtig:** `datetime` im JSON ist ISO 8601 mit Timezone-Offset (z.B. `"2026-03-12T22:00:00+01:00"`). `.slice(0, 10)` gibt "YYYY-MM-DD" in Ortszeit — NICHT in UTC. Da der Server lokal laeuft und die Timestamps in lokaler Zeit sind, ist dieser Vergleich korrekt.

### Pattern 3: Icon-Auflosung per icon_mapping.json

**What:** `weather_icon` im JSON ist ein normalisierter Code (z.B. `"partly-cloudy"`). Das Theme braucht den tatsachlichen Dateinamen aus `icon_mapping.json`.
**When to use:** Uberall wo Icons angezeigt werden.

```javascript
// icon_mapping.json Struktur (bestatigt durch Dateiinspektion):
// { "icons": { "partly_cloudy": { "icon_day": "cloudy_day.png", "icon_night": "cloudy_night.png" } } }
// ACHTUNG: weather_icon nutzt Bindestriche ("partly-cloudy"), icon_mapping nutzt Unterstriche ("partly_cloudy")

function normalizeIconKey(weatherIcon) {
  return weatherIcon.replace(/-/g, '_');  // "partly-cloudy" -> "partly_cloudy"
}

function isDaytime(datetimeStr, sunriseStr, sunsetStr) {
  var h = parseInt(datetimeStr.slice(11, 13));  // Stunden aus "2026-03-12T14:00:00+01:00"
  var sr = parseInt(sunriseStr.slice(0, 2));   // Stunden aus "06:23"
  var ss = parseInt(sunsetStr.slice(0, 2));    // Stunden aus "18:05"
  return h >= sr && h < ss;
}

function resolveIconPath(weatherIcon, datetimeStr, sunrise, sunset, iconMapping, iconset) {
  var key = normalizeIconKey(weatherIcon);
  var entry = iconMapping[key];
  if (!entry) return 'icons/' + iconset + '/' + weatherIcon + '_day.png'; // Fallback
  var dn = isDaytime(datetimeStr, sunrise, sunset) ? 'icon_day' : 'icon_night';
  return 'icons/' + iconset + '/' + entry[dn];
}
```

**Wichtig:** Das Bindestriche-vs-Unterstriche-Problem: `weather_icon` im JSON verwendet Bindestriche (`partly-cloudy`), `icon_mapping.json` Keys verwenden Unterstriche (`partly_cloudy`). Dies wurde durch direkte Dateiinspektion verifiziert — beide Quellen live gecheckt.

### Pattern 4: Tag/Nacht-Bestimmung fur Hourly Icons

**What:** Hourly-Daten haben kein `dn` Feld. Tag/Nacht muss aus Sunrise/Sunset des Tages berechnet werden.
**When to use:** Bei `renderHourStrip()` — jede Stundenkarte braucht das richtige Icon.

```javascript
// Sunrise/Sunset kommt aus current.json (fur heute) oder dailyforecast period=1/2
// Fur "morgen" sunrise/sunset: aus dailyforecast data[1].sunrise, data[1].sunset
function getHourDayNight(hourEpoch, sunriseStr, sunsetStr) {
  var d = new Date(hourEpoch * 1000);
  var h = d.getHours();
  var sr = parseInt(sunriseStr.split(':')[0]);
  var ss = parseInt(sunsetStr.split(':')[0]);
  return (h >= sr && h < ss) ? 'day' : 'night';
}
```

### Pattern 5: i18n UI-Text-Bindung

**What:** Alle statisch eingebetteten deutschen Texte (Tab-Labels, Stat-Labels, Ueberschriften) werden durch Schlussel aus `lang-*.json theme.*` ersetzt.
**When to use:** Nach Fetch von lang-*.json, alle DOM-Elemente mit `data-i18n` Attribut aktualisieren.

```javascript
// Empfohlener Ansatz: data-i18n Attribute statt inline-Text
// <span data-i18n="theme.humidity">Luftfeuchte</span>
// Beim Laden: alle [data-i18n] Elemente aktualisieren
function applyLang(strings) {
  document.querySelectorAll('[data-i18n]').forEach(function(el) {
    var key = el.getAttribute('data-i18n');
    var parts = key.split('.');  // "theme.humidity" -> ["theme", "humidity"]
    var val = strings;
    for (var i = 0; i < parts.length; i++) {
      val = val && val[parts[i]];
    }
    if (val) el.textContent = val;
  });
}
```

**Alternativ (einfacher, kein HTML-Umbau):** Direkte DOM-ID-Bindung fur wenige Labels — aber `data-i18n` ist wartbarer.

**Verfugbare Schlussel in lang-*.json `theme.*` (verifiziert):**
- `theme.humidity`, `theme.wind`, `theme.pressure`, `theme.visibility`, `theme.dew_point`
- `theme.uv_index`, `theme.precipitation`, `theme.cloud_cover`, `theme.feels_like`
- `theme.sunrise`, `theme.sunset`, `theme.temperature`
- `theme.current_weather`, `theme.forecast`, `theme.daily_forecast`, `theme.hourly_forecast`
- `theme.weekdays` (Array), `theme.weekdays_short` (Array), `theme.months` (Array)

**Fehlende Schlussel** (mussen in allen 5 lang-Dateien erganzt werden):
- Tab-Labels: "Heute", "Morgen", "Tage" — noch nicht in lang-*.json vorhanden
- "Heutige Stunden", "Morgige Stunden" Ueberschriften
- Fehler- und Lademeldungen

### Pattern 6: Loading-Overlay und Error-Banner

**What:** Einfaches CSS-Klassen-Toggle auf `<body>` oder dediziertem Overlay-Element.
**When to use:** DATA-05 (Loading) und DATA-06 (Error).

```html
<!-- In ocean-live.html hinzufugen, vor </body> -->
<div id="loadingOverlay" class="loading-overlay" style="display:none">
  <div class="loading-spinner"></div>
</div>
<div id="errorBanner" class="error-banner" style="display:none">
  <span id="errorMsg">Wetterdaten konnten nicht geladen werden.</span>
</div>
```

```css
.loading-overlay {
  position: fixed; inset: 0; background: rgba(15,23,42,0.6);
  display: flex; align-items: center; justify-content: center;
  z-index: 100; backdrop-filter: blur(4px);
}
.loading-spinner {
  width: 48px; height: 48px; border-radius: 50%;
  border: 3px solid rgba(56,189,248,0.3);
  border-top-color: var(--sky);
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
.error-banner {
  position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
  background: rgba(244,63,94,0.15); border: 1px solid var(--rose);
  color: var(--text-primary); padding: 12px 24px; border-radius: 12px;
  z-index: 101; backdrop-filter: blur(12px);
}
```

```javascript
function showLoading() { document.getElementById('loadingOverlay').style.display = 'flex'; }
function hideLoading() { document.getElementById('loadingOverlay').style.display = 'none'; }
function showError(msg) {
  var b = document.getElementById('errorBanner');
  document.getElementById('errorMsg').textContent = msg || 'Daten konnten nicht geladen werden.';
  b.style.display = 'block';
  setTimeout(function() { b.style.display = 'none'; }, 8000);
}
```

### Pattern 7: Auto-Refresh mit setTimeout-Rekursion

**What:** Periodisch neu laden ohne `setInterval`-Stapel-Problem.
**When to use:** DATA-04 — alle 5+ Minuten.

```javascript
var REFRESH_INTERVAL_MS = 5 * 60 * 1000; // 5 Minuten

function scheduleRefresh() {
  setTimeout(function() {
    loadAllData(currentLang)
      .then(function(results) {
        // Daten aktualisieren, UI neu rendern
        renderAll(results[0].data, results[1].data, results[2].data, results[3], results[4].icons);
        scheduleRefresh(); // naechsten Refresh planen
      })
      .catch(function(err) {
        showError('Auto-Refresh fehlgeschlagen.');
        scheduleRefresh(); // trotz Fehler weiter versuchen
      });
  }, REFRESH_INTERVAL_MS);
}
```

### Pattern 8: Sprach-Erkennung per URL-Parameter

**What:** `?lang=de` URL-Parameter bestimmt die geladene Sprachdatei. Fallback: `de`.
**When to use:** LANG-03.

```javascript
var currentLang = getUrlParam('lang') || 'de';
var SUPPORTED_LANGS = ['de', 'en', 'es', 'nl', 'sk'];
if (SUPPORTED_LANGS.indexOf(currentLang) === -1) currentLang = 'de';
```

### Anti-Patterns to Avoid

- **`setInterval` fur Auto-Refresh:** Wenn ein Request langer als das Intervall dauert, stapeln sich Aufrufe. Immer `setTimeout`-Rekursion nach Abschluss verwenden.
- **UTC vs. Ortszeit bei Datum-Vergleichen:** `new Date().toISOString()` gibt UTC. ISO-8601-Strings aus dem JSON haben Timezone-Offset. Immer `.slice(0, 10)` auf dem JSON-String verwenden, nicht auf `toISOString()`.
- **`weather_icon` direkt als Dateiname:** `weather_icon` im JSON ist ein normalisierter Code ohne Extension und mit Bindestrichen. Immer gegen `icon_mapping.json` aufzulosen. Niemals `weatherIcon + '.png'` direkt.
- **Alle 5 Fetches sequentiell:** `fetch(current).then(() => fetch(hourly)).then(...)` — jeder Request wartet auf den vorigen. `Promise.all` fur parallele Ausfuhrung verwenden.
- **`innerHTML` fur Fehlermeldungen mit Server-Daten:** Fehlermeldungen die Daten vom Server enthalten konnen XSS-Angriffsvektoren sein. Immer `textContent` fur dynamische Strings.
- **Harte Sprachstrings im HTML belassen:** Wenn Phase 5 `data-i18n` einfuhrt, mussen ALLE hardcodierten deutschen Strings aus dem HTML entfernt werden — sonst erscheinen sie als Fallback bei fehlendem lang-Fetch, was inkonsistent ist.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP-Requests | XMLHttpRequest Wrapper | Native `fetch()` | Browser-native, Promise-basiert, kein Boilerplate |
| Parallele Requests | Manuelle Promise-Verkettung | `Promise.all()` | Eine Zeile statt komplexer Sequenzlogik |
| Icon-Aufloesung | Eigene Icon-Mapping-Logik | `icon_mapping.json` per Fetch | Bereits fur alle 11 Icon-Sets vorhanden und gepflegt |
| CSS Loading-Spinner | Canvas/SVG Animation | CSS `border + animation: spin` | 5 Zeilen CSS, keine externe Library |
| i18n | Eigenes Template-System | `data-i18n` Attribute + `applyLang()` | < 10 Zeilen JS, keine Library benotigt |
| Auto-Refresh | Komplexes Scheduling | `setTimeout`-Rekursion | 5 Zeilen, kein Library |

**Key insight:** Alle benotigten Funktionalitaten sind entweder browser-nativ (Fetch, Promise, setTimeout) oder bereits als Datei im Projekt vorhanden (lang-*.json, icon_mapping.json). Phase 5 ist ausschliesslich Integrationsarbeit — kein neuer technischer Stack.

## Common Pitfalls

### Pitfall 1: UTC/Ortszeit-Verwechslung bei Datumsfilterung

**What goes wrong:** `hourlyforecast.json` hat ISO-8601-Timestamps mit `+01:00` Offset. Wenn `new Date().toISOString().slice(0,10)` fur "heute" verwendet wird, ergibt das UTC-Datum — das kann um Mitternacht um 1 Stunde abweichen und dazu fuhren, dass Stunden dem falschen Tag zugeordnet werden.
**Why it happens:** JavaScript `toISOString()` gibt immer UTC. Die JSON-Timestamps haben lokalen Offset.
**How to avoid:** Immer das `datetime` Feld aus dem JSON-String direkt per `.slice(0, 10)` auslesen (das ist bereits in Ortszeit). Fur "heute" ein Referenzdatum aus `current.json.data.datetime.slice(0, 10)` ableiten, nicht aus `new Date().toISOString()`.
**Warning signs:** Nachts fehlen Stunden im Heute-Strip oder Morgen-Strip hat zu viele/wenige Eintrege.

### Pitfall 2: icon_mapping.json Schlussel-Format Mismatch

**What goes wrong:** `weather_icon` im JSON lautet `"partly-cloudy"` (Bindestriche). `icon_mapping.json` Keys lauten `"partly_cloudy"` (Unterstriche). Direkter Lookup schlagt fehl.
**Why it happens:** Das JSON-Schema nutzt Bindestriche fur lesbare Identifier, die icon_mapping.json nutzt Unterstriche als JavaScript-freundliche Keys.
**How to avoid:** Immer `weatherIcon.replace(/-/g, '_')` vor dem Lookup in `iconMapping`.
**Warning signs:** Icons zeigen den CSS-Fallback oder broken image — kein JS-Fehler, nur falsche Pfade.

### Pitfall 3: Fehlende Tab-Label Keys in lang-*.json

**What goes wrong:** Tab-Labels "Heute", "Morgen", "Tage" sind nicht in den bestehenden lang-*.json Dateien vorhanden. Wenn Phase 5 diese per `data-i18n` setzen will, fehlen die Schlussel.
**Why it happens:** Die bestehenden lang-Dateien wurden fur das alte weathercodes.html erstellt — nicht fur das neue ocean-live Theme. Nur der `theme.*` Namespace ist relevant; Tab-spezifische Labels fehlen.
**How to avoid:** In Wave 0 / Task 1: alle 5 lang-*.json Dateien um fehlende Theme-Schlussel erganzen (tab_today, tab_tomorrow, tab_days, error_loading, loading usw.).
**Warning signs:** Tab-Labels zeigen leere Strings oder den `data-i18n` Attributwert statt Text.

### Pitfall 4: show.cgi URL-Pfad von ocean-live.html aus

**What goes wrong:** `ocean-live.html` liegt in `webfrontend/html/`. Das CGI liegt in `webfrontend/htmlauth/`. Relativer Pfad ist `../../htmlauth/show.cgi` oder absolut `/plugins/{psubfolder}/htmlauth/show.cgi`. Wenn der falsche Pfad verwendet wird, schlagen alle Fetch-Calls fehl.
**Why it happens:** `htmlauth/` und `html/` sind zwei verschiedene Verzeichnisse im LoxBerry-Webserver.
**How to avoid:** show.cgi URL als konfigurierbaren Parameter oder URL-Parameter ubergeben. Alternativ: Fetch-URL direkt testen. Einfachste Losung: `?cgi=../../htmlauth/show.cgi` URL-Parameter oder Hardcoding mit Kommentar.
**Warning signs:** 404 auf alle show.cgi Requests im Browser-Netzwerk-Tab.

### Pitfall 5: Fehlende Stunden fur "morgen" wenn hourlyforecast weniger als 48h hat

**What goes wrong:** Nicht jeder Grabber liefert 48+ Stunden. Wenn hourlyforecast nur 24h ab jetzt enthalt, gibt es keine Stunden fur "morgen" nach 24 Uhr heute.
**Why it happens:** Grabber-Konfiguration bestimmt Vorhersagehorizont; nicht standardisiert uber alle Grabber.
**How to avoid:** `filterHoursByDate(hourlyData, tomorrow).length === 0` prufen und Morgen-Tab ausblenden oder Hinweistext zeigen wenn leer.
**Warning signs:** Morgen-Tab zeigt leeren hour-strip.

### Pitfall 6: Race Condition bei schnellem Tab-Wechsel wahrend Loading

**What goes wrong:** Benutzer wechselt Tab wahrend Fetch noch lauft. `renderHourStrip` schreibt in den falschen Container.
**Why it happens:** Fetch ist asynchron; aktiver Tab kann sich andern bevor Callback ausgefuhrt wird.
**How to avoid:** Loading-Overlay deaktiviert Tab-Buttons wahrend des initialen Loads. Bei Refresh (im Hintergrund) kein Overlay — aber `renderAll` rendert immer alle drei Tabs komplett, unabhangig vom aktiven Tab.
**Warning signs:** Falsche Daten in falschen Tabs nach schnellem Wechsel.

## Code Examples

Verifizierte Muster basierend auf tatsachlichem JSON-Schema und existierendem Code:

### Vollstandiger loadAllData Aufruf

```javascript
// Source: Abgeleitet aus show.cgi Quellcode (Zeilen 82-130) und json-schema.md
var ICONSET = 'color';  // Standardwert; spater aus Config
var CGI_BASE = '../../htmlauth/show.cgi';

function loadAllData(lang) {
  showLoading();
  return Promise.all([
    fetch(CGI_BASE + '?format=json&type=current').then(r){ if(!r.ok) throw new Error('current: '+r.status); return r.json(); }),
    fetch(CGI_BASE + '?format=json&type=hourly').then(function(r) { if(!r.ok) throw new Error('hourly: '+r.status); return r.json(); }),
    fetch(CGI_BASE + '?format=json&type=daily').then(function(r) { if(!r.ok) throw new Error('daily: '+r.status); return r.json(); }),
    fetch('lang-' + lang + '.json').then(function(r) { if(!r.ok) throw new Error('lang: '+r.status); return r.json(); }),
    fetch('icons/' + ICONSET + '/icon_mapping.json').then(function(r) { if(!r.ok) throw new Error('icons: '+r.status); return r.json(); })
  ]).then(function(results) {
    hideLoading();
    return {
      current:     results[0].data,
      hourly:      results[1].data,
      daily:       results[2].data,
      lang:        results[3],
      iconMapping: results[4].icons
    };
  }).catch(function(err) {
    hideLoading();
    showError('Wetterdaten konnten nicht geladen werden: ' + err.message);
    throw err;
  });
}
```

### Sunrise/Sunset im Hero anzeigen (EXTRA-01)

```javascript
// DOM-IDs bereits in ocean-live.html (Phase 4) vorhanden:
// <div class="astro-val mono">06:23</div> (hartcodiert)
// Phase 5: DOM-IDs hinzufugen und an currentData binden
function renderSunriseSunset(currentData) {
  // source: current.json data.sunrise = "06:23", data.sunset = "18:05"
  var srEl = document.getElementById('heroSunrise');
  var ssEl = document.getElementById('heroSunset');
  if (srEl) srEl.textContent = currentData.sunrise || '--:--';
  if (ssEl) ssEl.textContent = currentData.sunset  || '--:--';
}
```

### Stunden-Filter mit Referenzdatum aus JSON

```javascript
// Source: Abgeleitet aus json-schema.md (datetime Format ISO 8601)
function splitHoursByDay(hourlyArray, currentDatetime) {
  // currentDatetime z.B. "2026-03-12T20:45:00+01:00"
  var todayStr    = currentDatetime.slice(0, 10); // "2026-03-12"
  var todayDate   = new Date(todayStr + 'T00:00:00');
  var tomorrowDate = new Date(todayDate); tomorrowDate.setDate(todayDate.getDate() + 1);
  var tomorrowStr = tomorrowDate.toISOString().slice(0, 10);

  return {
    today:    hourlyArray.filter(function(h) { return h.datetime.slice(0, 10) === todayStr; }),
    tomorrow: hourlyArray.filter(function(h) { return h.datetime.slice(0, 10) === tomorrowStr; })
  };
}
```

### Rendering-Update: renderHourStrip mit echten Daten

```javascript
// Anpassung von Phase 4's renderHourStrip — identisches Interface, neue Daten
function buildHourCardData(hourEntry, sunriseStr, sunsetStr, iconMapping) {
  var hour = hourEntry.datetime.slice(11, 13); // "14" aus "...T14:00..."
  var dn   = isDaytime(hourEntry.datetime, sunriseStr, sunsetStr) ? 'day' : 'night';
  var iconKey  = (hourEntry.weather_icon || 'clear').replace(/-/g, '_');
  var iconFile = (iconMapping[iconKey] || {})[dn === 'day' ? 'icon_day' : 'icon_night']
                 || hourEntry.weather_icon + '_' + dn + '.png';
  return {
    hour:     hour,
    temp:     hourEntry.temperature,
    pop:      hourEntry.precip_probability,
    wind:     hourEntry.wind_speed,
    wind_dir: hourEntry.wind_direction_desc,
    humidity: hourEntry.humidity,
    icon:     iconFile,  // bereits aufgeloester Dateiname
    desc:     hourEntry.weather_description,
    dn:       dn
  };
}
```

### Neue lang-*.json Schlussel (mussen erganzt werden)

```json
{
  "theme": {
    "tab_today": "Heute",
    "tab_tomorrow": "Morgen",
    "tab_days": "Tage",
    "hours_today": "Heutige Stunden",
    "hours_tomorrow": "Morgige Stunden",
    "forecast_7day": "7-Tage Vorhersage",
    "click_hour_detail": "Stunde anklicken fur Details",
    "loading": "Wetterdaten werden geladen...",
    "error_loading": "Daten konnten nicht geladen werden.",
    "gusts": "Boen",
    "live_dashboard": "Live Dashboard"
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MOCK_* Variablen als Datenquelle | Fetch API mit Promise.all | Phase 5 | Echte Wetterdaten statt Testdaten |
| Hardcodierte DE-Strings im HTML | data-i18n Attribute + lang-*.json Fetch | Phase 5 | Vollstandige Mehrsprachigkeit |
| Einmaliger Render beim Laden | Periodischer Auto-Refresh alle 5min | Phase 5 | Dashboard bleibt aktuell |
| Kein Fehler-Feedback | Error-Banner + Loading-Overlay | Phase 5 | Produktionsreife UX |
| Hardcodierte sunrise/sunset Werte | Werte aus current.json | Phase 5 | EXTRA-01 mit echten Daten |

**Deprecated/outdated:**
- `MOCK_CURRENT`, `MOCK_HOURLY_TODAY`, `MOCK_HOURLY_TOMORROW`, `MOCK_DAILY`: Werden in Phase 5 vollstandig entfernt
- `ICON_MAP` Hardcoding in ocean-live.html: Wird durch `icon_mapping.json` Fetch ersetzt

## Open Questions

1. **Absoluter vs. relativer CGI-Pfad**
   - What we know: `ocean-live.html` liegt in `webfrontend/html/`; show.cgi in `webfrontend/htmlauth/`
   - What's unclear: Ob LoxBerry den Webserver so konfiguriert hat, dass relativer Pfad `../../htmlauth/show.cgi` funktioniert, oder ob der absolute Plugin-Pfad (`/plugins/{psubfolder}/htmlauth/show.cgi`) benotigt wird
   - Recommendation: URL-Parameter `?cgi=...` anbieten als Override; Default auf relativen Pfad; im ersten Task testen und dokumentieren

2. **lang-*.json fehlende Schlussel fur neue Theme-Labels**
   - What we know: Bestehende lang-Dateien haben nur `weathercodes.html`-relevante Keys und `theme.*` Grundmenge
   - What's unclear: Ob die Erweiterung der lang-Dateien zu Merge-Konflikten im Haupt-Branch fuhrt
   - Recommendation: Alle neuen Schlussel unter `theme.*` Namespace hinzufugen — das ist der existierende Namespace fur Theme-Strings

3. **Iconset-Konfiguration**
   - What we know: `stdiconset` wird aus `weather4lox.cfg` gelesen von show.cgi; ocean-live.html hat keinen CGI-Kontext
   - What's unclear: Wie ocean-live.html den konfigurierten Iconset-Namen erhalt (zeige.cgi konnte ihn als Query-Parameter zuruckliefern)
   - Recommendation: Fur Phase 5 Fallback auf `'color'` hardcoden mit `?iconset=color` als ueberschreibbaren URL-Parameter

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Keine automatisierten Tests fur Frontend-HTML (konsistent mit Phase 4) |
| Config file | none |
| Quick run command | `test -f webfrontend/html/ocean-live.html && echo "File exists"` |
| Full suite command | Browser-seitige manuelle Prufung aller 5 Success Criteria |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DATA-01 | Fetch-Call an show.cgi beim Offnen | manual | Browser Netzwerk-Tab: GET .../show.cgi?format=json&type=current sichtbar | Wave 0 |
| DATA-02 | Sprachstrings geladen; Tab-Labels in konfig. Sprache | manual | `?lang=en` oeffnen, "Today"/"Tomorrow"/"Days" sichtbar | Wave 0 |
| DATA-03 | Icons korrekt aufgelost aus icon_mapping.json | manual | Netzwerk-Tab: GET .../icon_mapping.json sichtbar; Icons sichtbar | Wave 0 |
| DATA-04 | Auto-Refresh nach 5 min ohne Seiten-Reload | manual | `console.log` Timestamps uber 10+ Minuten beobachten | Wave 0 |
| DATA-05 | Loading-Spinner wahrend Fetch | manual | Langsames Netzwerk simulieren (DevTools Throttling), Spinner sichtbar | Wave 0 |
| DATA-06 | Fehlermeldung bei Netzwerkfehler | manual | show.cgi URL auf ungultigen Pfad setzen; Error-Banner erscheint | Wave 0 |
| LANG-01 | Alle UI-Texte aus lang-*.json | manual | `?lang=en` testen: alle Labels in Englisch | Wave 0 |
| LANG-02 | DE/EN/ES/NL/SK funktionieren | manual | Alle 5 `?lang=XX` URLs testen | Wave 0 |
| LANG-03 | Sprache per URL-Parameter | manual | `?lang=en`, `?lang=de` etc. testen | Wave 0 |
| EXTRA-01 | Sunrise/Sunset im Hero sichtbar | manual | Hero-Bereich: Sonnenaufgang und Sonnenuntergang Zeiten aus echten Daten | Wave 0 |

### Sampling Rate

- **Per task commit:** `test -f webfrontend/html/ocean-live.html && echo OK` (Datei existiert)
- **Per wave merge:** Browser-Prufung: Fetch-Calls im Netzwerk-Tab sichtbar, Icons korrekt, Sprache umschaltbar
- **Phase gate:** Alle 5 Success Criteria manuell bestatigt vor `/gsd:verify-work`

### Wave 0 Gaps

- [ ] Neue lang-Keys (`theme.tab_today`, `theme.tab_tomorrow` etc.) in allen 5 lang-*.json Dateien erganzen
- [ ] DOM-IDs fur sunrise/sunset in ocean-live.html hinzufugen (`heroSunrise`, `heroSunset`)
- [ ] DOM-IDs fur loading-overlay und error-banner HTML in ocean-live.html hinzufugen
- [ ] show.cgi CGI-Pfad in Entwicklungsumgebung verifizieren und dokumentieren

*(Keine neue Test-Infrastruktur benotigt — alle Tests sind manuelle Browser-Checks, konsistent mit Phase 4)*

## Sources

### Primary (HIGH confidence)

- `webfrontend/html/ocean-live.html` (Phase 4 Output) — vollstandige DOM-Struktur, bestehende JS-Funktionen, MOCK-Variablen die ersetzt werden
- `data/json-schema.md` — autoritative Felddefinitionen fur current.json, hourlyforecast.json, dailyforecast.json inkl. Envelope-Struktur
- `webfrontend/htmlauth/show.cgi` (Zeilen 82-130) — bestatigt `?format=json&type=current|hourly|daily` Endpoint, Content-Type, Cache-Control, Fehlercodes 400/404/500
- `webfrontend/html/icons/color/icon_mapping.json` — bestatigt Schema: `{ "icons": { "partly_cloudy": { "icon_day": "...", "icon_night": "..." } } }` mit Unterstrich-Keys
- `webfrontend/html/lang-de.json` und `lang-en.json` — bestatigt `theme.*` Namespace mit vollstandiger Schlusseliste; fehlende Tab-Labels dokumentiert
- `.planning/REQUIREMENTS.md` — definitive Requirement-Beschreibungen fur alle Phase-5-IDs

### Secondary (MEDIUM confidence)

- `.planning/phases/04-ocean-live-theme-grundgerust/04-RESEARCH.md` — Phase-4-Architektur-Entscheidungen; bestatigt Trennung Mock-Daten / AJAX
- `.planning/STATE.md` — Designentscheidung: `renderHourStrip()` und `renderDaily()` sind von Datenquelle entkoppelt

### Tertiary (LOW confidence)

- CGI-Pfad-Auflosung von `webfrontend/html/` aus — muss zur Laufzeit verifiziert werden; konnte je nach LoxBerry-Konfiguration variieren

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — ausschliesslich browser-native APIs; keine externen Abhangigkeiten
- Architecture: HIGH — JSON-Schema vollstandig dokumentiert; show.cgi Endpoint verifiziert; lang-Dateien und icon_mapping.json direkt inspiziert
- Pitfalls: HIGH — UTC/Ortszeit Bug und icon-Mismatch durch direkte Quellcode-Inspektion aufgedeckt; nicht aus Erfahrungswerten

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (stabile Technologien; lang.json Keys konnen sich andern wenn neue Grabber hinzukommen)
