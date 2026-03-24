# Weather4Lox Modernisierung -- Architektur-Entscheidungen

Konsolidiert aus `.planning/` (49 Dateien, geloescht nach Erstellung dieses Dokuments).
Vollstaendige JSON-Schema-Referenz inkl. Field-Mapping: `data/json-schema.md`

---

## Projekt-Status (Stand 2026-03-13)

| Phase | Beschreibung | Status | Datum |
|-------|-------------|--------|-------|
| 1 | JSON Schema & Grabber Migration | **Fertig** (3/3 Plans) | 2026-03-12 |
| 2 | Delivery Layer Migration (datatoloxone.pl) | **Fertig** (1/1 Plans) | 2026-03-12 |
| 3 | CGI JSON Endpoint (show.cgi) | **Fertig** (1/1 Plans) | 2026-03-13 |
| 4 | ocean-live Theme Grundgeruest | **Fertig** (1/1 Plans) | 2026-03-13 |
| 5 | Datenanbindung & Vollstaendigkeit | **Fertig** (3/3 Plans) | 2026-03-13 |

**v1 Requirements:** 34/34 erfuellt. Alle Requirements (JSON-01..08, CGI-01..03, THEME-01..04, HERO-01..06, TAGE-01..02, DATA-01..06, LANG-01..03, EXTRA-01..02) abgedeckt.

### Relevante Commits

| Commit | Beschreibung |
|--------|-------------|
| `57d8780` | write_current_json + write_current_json_aq Upgrade |
| `a11dfca` | write_daily_json + write_hourly_json Upgrade |
| `c5bd681` | 5 Haupt-Grabber: source/grabber Params + eval-Safety |
| `aed5250` | data/json-schema.md Schema-Dokumentation |
| `69d2994` | 4 Supplementary Grabber (WU, FOSHK, PWS, Loxone) |
| `50dea37` | OpenMeteo AQ Grabber -> current.json Merge |
| `fa17836` | datatoloxone.pl komplett auf JSON umgestellt |
| `10d6a58` | show.cgi JSON API Endpoint |
| `85f3178` | ocean-live.html Grundgeruest (Mock-Daten) |
| `123e530` | Icon-Pfad-Fix (suffix statt subdirectory) |
| `f500503` | 5 Lang-Dateien: 11 neue Theme-Keys |
| `7c5dbc6` | DOM-Infrastruktur (IDs, data-i18n, Loading/Error UI) |
| `3073d7c` | AJAX Live-Daten, i18n, Auto-Refresh |
| `e887888` | 4 Fixes aus Checkpoint (Icons, Font, SVG-Chart, leere Stats) |

---

## Migrations-Strategie

### Dual-Write Prinzip
- Grabber schreiben **JSON parallel zu .dat** -- .dat bleibt fuer Rollback
- **.dat hat Prioritaet:** JSON-Write-Fehler stoppen NICHT den Grabber-Lauf
- JSON-Write in `eval{}` gekapselt, bei Fehler: `LOGWARN` + return (nie `die`/`exit`)
- Bei Encoding-Fehler (ungueltiges UTF-8): gesamten JSON-Write ueberspringen, vorherige Datei bleibt

### Atomarer Write
- Immer `.tmp` + `File::Copy::move()` -- nie direkt in Zieldatei schreiben
- Gleich fuer .dat und .json (bewaehrtes Pattern)
- Leser sieht nie eine unvollstaendige Datei

### Fehler-Verhalten
- `LOGOK` bei erfolgreichem JSON-Write
- `LOGWARN` bei Fehler
- Keine Re-Validierung nach Schreiben (JSON::PP erzeugt gueltiges JSON)
- datatoloxone.pl: `LOGCRIT` + exit bei fehlendem JSON (fail-fast, kein .dat-Fallback)

---

## JSON Schema-Entscheidungen

### Envelope-Struktur
Jede JSON-Datei hat `{location, <grabberKey>, <weatherKey>}` als Top-Level-Struktur.

```json
{
  "location": { "city": "...", "country": "...", "latitude": 53.509, ... },
  "wetteronline": {
    "filename": "/opt/loxberry/log/plugins/weather4lox/current.json",
    "generatedAt": "2026-03-24T20:40:24",
    "grabberLabel": "Wetter Online",
    "grabberScript": "grabber_wetteronline.pl",
    "schemaVersion": "v1.0"
  },
  "current": { ... }
}
```

- `location`: Standort-Daten (city, country, countryCode, elevation, latitude, longitude, timezone, tzOffset, tzShort)
- `<grabberKey>`: Source-spezifische Metadaten (z.B. `wetteronline`, `wunderground`) mit filename, generatedAt, grabberLabel, grabberScript, schemaVersion
- `<weatherKey>`: `current` (Objekt), `dailyforecast` (Array), `hourlyforecast` (Array)
- Mehrere grabberKeys moeglich (z.B. current.json hat `wetteronline` + `wunderground`)

### Feld-Konventionen
- **camelCase** fuer alle Feldnamen (z.B. `cloudCover`, `feelsLike`, `dirLabel`, `rainToday`)
- Fehlende Werte: JSON `null` (nicht weglassen, nicht ""/0/-9999)
- `day` als 0-basierter Index in dailyforecast (0 = heute, 1 = morgen, ...)
- `hour` als 0-basierter Index in hourlyforecast (0 = erste Stunde, 1 = +1h, ...)
- `generatedAt`: System-Lokalzeit (wann Grabber lief), NICHT Beobachtungszeit (ISO 8601 ohne Offset)
- Beobachtungszeit ist `current.time.datetime` (ISO 8601 mit Offset)
- Verwandte Felder in Unterobjekten gruppiert: `temperature`, `wind`, `precipitation`, `moon`, `time`, `weatherCode`
- `weatherCode.weather4lox`: normalisierter Identifier fuer Icon-Mapping
- `weatherCode.loxone`: String (nicht Integer) -- Loxone Wetter-Code

### Encoding
- UTF-8 via `JSON::PP->new->pretty->canonical->utf8` mit `open '>:raw'`
- Dezimalzahlen: Punkt (Locale-unabhaengig durch JSON::PP + `$v + 0` Coercion)
- **Nie** `JSON::PP->utf8` mit `'>:encoding(UTF-8)'` kombinieren (Doppel-Encoding)

---

## JSON Schema-Referenz

Die vollstaendige Referenz mit allen Feldtabellen befindet sich in:

**`data/json-schema.md`** (authoritative Referenz)

### Kurzuebersicht der Struktur

| Datei | weatherKey | Datenstruktur | Index-Feld |
|-------|-----------|---------------|------------|
| current.json | `current` | Einzelnes Objekt mit `temperature`, `wind`, `precipitation`, `moon`, `time`, `weatherCode` | -- |
| dailyforecast.json | `dailyforecast` | Array von Objekten mit `temperature.max/min`, `wind.avg/max`, `humidity`, `precipitation`, `moon` | `day` (0-basiert) |
| hourlyforecast.json | `hourlyforecast` | Array von Objekten mit `temperature`, `wind`, `precipitation`, `moon` | `hour` (0-basiert) |

### Referenz-Dateien
Echte JSON-Ausgaben als Referenz: `2026_03_24/current.json`, `2026_03_24/dailyforecast.json`, `2026_03_24/hourlyforecast.json`

---

## Grabber-Scope

### 5 Haupt-Grabber (schreiben current + daily + hourly JSON)
| Grabber | source-Wert |
|---------|-------------|
| grabber_openweather.pl | "OpenWeatherMap" |
| grabber_visualcrossing.pl | "VisualCrossing" |
| grabber_weatherflow.pl | "WeatherFlow" |
| grabber_wetteronline.pl | "WetterOnline" |
| grabber_wttrin.pl | "wttr.in" |

### 5 Supplementary Grabber (schreiben nur current JSON)
| Grabber | source-Wert | Besonderheit |
|---------|-------------|-------------|
| grabber_wu.pl | "WeatherUnderground" | hatte bereits require grabber_utils |
| grabber_foshk.pl | "FOSHK" | hatte bereits require grabber_utils |
| grabber_pwscatchupload.pl | "PWSCatchUpload" | require grabber_utils **hinzugefuegt** |
| grabber_loxone.pl | "Loxone" | require grabber_utils **hinzugefuegt** |
| grabber_openmeteo_airquality.pl | "OpenMeteoAQ" | nutzt `write_current_json_aq()` statt `write_current_json()` |

### Grabber-Aufruf-Pattern
```perl
# Envelope aufbauen und JSON schreiben:
my $weatherKey = "current";
my $envelope = {
    location    => $location,
    $grabberKey => {
        filename      => "$lbplogdir/$weatherKey.json",
        generatedAt   => $dtCurrent->iso8601(),
        grabberLabel  => $grabberLabel,
        grabberScript => $grabberFile,
        schemaVersion => "v1.0",
    },
    $weatherKey => \%currentData,
};
writeJsonFile($lbplogdir, $weatherKey, $envelope);
# analog fuer dailyforecast und hourlyforecast
```

### Wichtige Reihenfolge-Regel
`writeJsonFile()` fuer Supplementary Grabber (z.B. WU) muss NACH dem Haupt-Grabber aufgerufen werden, da das bestehende Envelope per `readJsonFile()` gelesen und um den eigenen `$grabberKey` erweitert wird.

---

## CGI JSON Endpoint (show.cgi)

### API-Design
- URL: `show.cgi?format=json&type=current|hourly|daily`
- JSON wird 1:1 von Disk durchgereicht (File-Slurp, kein Parsen/Transformieren)
- Immer metrische Rohwerte -- Frontend macht Einheiten-Konvertierung
- Type-Mapping: current -> current.json, hourly -> hourlyforecast.json, daily -> dailyforecast.json

### HTTP-Responses
| Situation | Status | Body |
|-----------|--------|------|
| Erfolg | 200 | JSON-Datei von Disk |
| Fehlender/ungueltiger type | 400 | `{"error": "...", "code": 400}` |
| JSON-Datei nicht vorhanden | 404 | `{"error": "Weather data not available", "code": 404}` |
| Datei nicht lesbar | 500 | `{"error": "Internal server error", "code": 500}` |

- Alle Responses: `Content-Type: application/json; charset=utf-8` + `Cache-Control: no-cache`
- Eingefuegt VOR der HTML-Logik, exit nach Response (kein Durchfall)

---

## Delivery Layer (datatoloxone.pl)

### Migration .dat -> JSON
- Komplett umgestellt: 0 `@fields[]`-Referenzen, 0 `split(/\|/)`, 0 `.dat` open()-Aufrufe
- `load_json_file()` mit fail-fast (LOGCRIT + exit)
- `_jval()` Null-Safe Helper: JSON null -> -9999 fuer Loxone-Kompatibilitaet
- `flock(LOCK_SH)` Shared Read Lock auf JSON-Dateien
- HTML-Template-Variablennamen unveraendert -- nur Datenquelle gewechselt
- `weatherdata.html` Debug-Output beibehalten
- calc+N Aggregation: `defined()` statt `-9999`-Vergleiche

### Sunrise/Sunset
- JSON liefert "HH:MM" String -> `split(':')`
- Loxone-Epoch-Berechnung (DateTime->new + epoch - 1.1.2009 Ref) bleibt identisch
- Bei null: -9999 senden (keine Regression)

---

## ocean-live Theme

### Architektur
- Einzelne HTML-Datei: `webfrontend/html/ocean-live.html` (inline CSS + JS)
- 3 Tabs: Heute | Morgen | Tage
- Hero-Bereich UEBER den Tab-Panels (geteilt zwischen Heute/Morgen, hidden bei Tage)
- Tab-Fade: `display:block` + `requestAnimationFrame` + `opacity transition`

### Datenanbindung
- `loadAllData()`: Promise.all fuer 5 parallele Fetches (current, hourly, daily, lang, icon_mapping)
- Auto-Refresh alle 5 Min via `scheduleRefresh()` (retry bei Fehler)
- Sprache per `?lang=XX` URL-Param (de/en/es/nl/sk), Fallback: de
- Iconset per `?iconset=XX`, Fallback: color
- Icon-Aufloesung: `weather_code` -> `WEATHER_CODE_MAP` -> `icon_mapping.json` (mit `_day`/`_night` Suffix)

### DOM-Konventionen
- `id=stat{PropertyName}` (camelCase) fuer Stat-Werte: statHumidity, statWind, statWindDir, statPressure, statVisibility, statDewpoint, statPrecip, statUVI, statClouds, statGusts, statFeelslike
- `id=hero{PropertyName}` fuer Hero-Werte: heroSunrise, heroSunset, heroFeelslike
- `data-i18n="theme.{key}"` fuer i18n-Labels (21 Attribute)
- Lang-Key-Konvention: `theme.tab_today`, `theme.loading`, `theme.gusts` etc.

### i18n Keys (11 neue in jeder lang-*.json)
`tab_today`, `tab_tomorrow`, `tab_days`, `hours_today`, `hours_tomorrow`, `forecast_7day`, `click_hour_detail`, `loading`, `error_loading`, `gusts`, `live_dashboard`

---

## Offene Punkte (v2)

| Feature | Status |
|---------|--------|
| VIS-01: Windrichtungs-Kompass (visuell) | Geplant |
| VIS-02: UV-Index Anzeige | Geplant |
| VIS-03: Mondphase Anzeige | Geplant |
| MIG-01: Gebuendelter CGI-Endpunkt | Geplant |
| MIG-02: Entfernung .dat-System nach Testphase | Geplant |
| MIG-03: Entfernung alte Themes (dark, light, fresh, ocean) | Geplant |
| MIG-04: Weitere Themes im JSON-System | Geplant |
| hourlyhistory.json Schema | Nicht definiert in v1.0 |
| CGI-Auth html/ vs htmlauth/ | Funktioniert aktuell; Proxy-Fallback geplant falls noetig |

### Out of Scope (permanent)
- Radar-Karte (Traffic, externe API, iframe-Probleme)
- Animierte Wetter-Hintergruende (Performance auf Raspberry Pi)
- Push-Benachrichtigungen (braucht Service Worker)
- Historische Daten/Graphen (braucht DB, Chart-Library)
- Mobile App (Web-Frontend only)
- Neue Wetterdienst-Integrationen

---

## Bekannte Pitfalls

1. **UTF-8 Doppel-Encoding:** `JSON::PP->utf8` mit `open '>:encoding(UTF-8)'` = Mojibake. Immer `'>:raw'` verwenden.
2. **Supplementary Grabber Reihenfolge:** `write_current_json()` NACH `move()` auf .dat aufrufen (liest current.dat).
3. **OpenMeteo AQ ohne current.dat:** Wenn kein Haupt-Grabber gelaufen ist, gibt write_current_json_aq() nichts aus (silent return).
4. **PWSCatchUpload/Loxone:** Hatten kein `require grabber_utils.pl` -- wurde in Phase 1 hinzugefuegt.
5. **`local $/` Scoping:** In show.cgi JSON-Block muss `local $/` im Block bleiben, sonst bricht .dat-Parsing.
6. **Tab-Transition:** `display:none` + `opacity transition` funktioniert nicht -- `display:block` + `requestAnimationFrame` + opacity.

---

*Erstellt: 2026-03-21 aus .planning/ Konsolidierung*
*Referenz-Schema: data/json-schema.md*
