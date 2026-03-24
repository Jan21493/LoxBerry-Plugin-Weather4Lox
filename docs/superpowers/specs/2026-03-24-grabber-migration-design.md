# Grabber Migration: WetterOnline-Standard fuer alle Grabber

## Ziel

Alle Grabber auf die JSON-Struktur von `grabber_wetteronline.pl` migrieren. camelCase-Feldnamen, verschachtelte Objekte, einheitliche Envelope. .dat-Dateien entfernen. AQ/Pollen-Daten in alle 3 JSON-Dateien integrieren. Refresh-Intervall im JSON fuer Clients.

## Entscheidungen

- **Ansatz:** Grabber-fuer-Grabber (Ansatz A)
- **camelCase:** JSON-Output und Funktionsnamen muessen camelCase sein. Perl-interne Variablen duerfen bleiben, LoxBerry-Framework-Variablen (`$lbplogdir` etc.) unberuehrt.
- **.dat-Dateien:** Werden entfernt (kein Dual-Write, clean break). Aendert die fruehere Dual-Write-Strategie aus DECISIONS.md -- DECISIONS.md muss aktualisiert werden.
- **Patch-Grabber:** Auf JSON-Merge umstellen (readJsonFile -> patchen -> writeJsonFile)
- **AQ/Pollen:** In current.json, hourlyforecast.json und dailyforecast.json integrieren
- **Pollenempfindlichkeit:** In `weather4lox.cfg` Sektion `[POLLEN]`, Skala 0-7
- **Pollenwerte:** Nur umgerechnete Level (0-7), keine Roh-Konzentrationswerte (grains/m3)
- **ocean-live:** `2026_03_24/ocean-live_new.html` als neue Basis
- **Legacy-Grabber:** `grabber_openweather.pl` (v2 API) ist deprecated und wird nicht migriert. Nur `grabber_openweather2.pl` (v3 API) wird migriert.

## Referenz-Schema

Authoritative Referenz: `data/json-schema.md`
Referenz-JSONs: `2026_03_24/current.json`, `2026_03_24/dailyforecast.json`, `2026_03_24/hourlyforecast.json`
Referenz-Grabber: `bin/grabber_wetteronline.pl`

---

## JSON Envelope-Struktur

Jede JSON-Datei:

```json
{
  "refresh": 300,
  "location": {
    "city": "Schwarzenbek",
    "country": "Deutschland",
    "countryCode": "DE",
    "elevation": 50,
    "latitude": 53.509,
    "longitude": 10.487,
    "timezone": "Europe/Berlin",
    "tzOffset": "+0100",
    "tzShort": "CET"
  },
  "<grabberKey>": {
    "filename": "/opt/loxberry/log/plugins/weather4lox/<weatherKey>.json",
    "generatedAt": "2026-03-24T20:40:24",
    "grabberLabel": "Wetter Online",
    "grabberScript": "grabber_wetteronline.pl",
    "schemaVersion": "v1.0"
  },
  "<weatherKey>": { ... }
}
```

- `refresh`: Integer in Sekunden. Jeder Grabber liest seinen Wert aus der Config und fuegt ihn in den Envelope-Hashref ein:
  - Haupt-Grabber: `$pcfg->param("SERVER.CRON") * 60` (CRON ist in Minuten)
  - Patch-Grabber: `$pcfg->param("SERVER.CRON_PATCH") * 60` (neuer Config-Parameter, Default: 1 Min)
- `<grabberKey>`: z.B. `"wetteronline"`, `"openweather"`, `"wunderground"`
- `<weatherKey>`: `"current"` (Objekt), `"dailyforecast"` (Array), `"hourlyforecast"` (Array)

### Neuer Config-Parameter fuer Patch-Grabber

```ini
[SERVER]
CRON_PATCH=1
```

Default: 1 Minute. Steuert das Refresh-Intervall fuer Patch-Grabber (wu, foshk, loxone, pwscatchupload).

---

## AQ & Pollen Integration

### Config: `weather4lox.cfg`

Neuer Abschnitt:

```ini
[POLLEN]
ALDER=0
BIRCH=0
GRASS=0
MUGWORT=0
OLIVE=0
RAGWEED=0
```

Skala 0-7 pro Pollenart. Default 0 (keine Empfindlichkeit). Einstellung ueber `index.cgi` Dropdowns (bestehende UI anpassen, `mapping_custom_mix_pollen.json` entfaellt).

Der `[POLLEN]`-Abschnitt wird in Phase 3 erstellt. `postinstall.sh` fuegt die Default-Werte hinzu falls nicht vorhanden. `index.cgi` schreibt direkt in `weather4lox.cfg` statt in die separate JSON-Datei.

### Pollen-Level-Umrechnung

grains/m3 -> Level 0-7. Die bestehende `pollenLevel()` Funktion (aktuell 0-4) wird auf 0-7 erweitert.

Schwellwert-Tabelle (grains/m3 -> Level):

| Level | Alder/Birch/Olive | Grass/Mugwort/Ragweed |
|-------|-------------------|----------------------|
| 0     | 0                 | 0                    |
| 1     | 1-5               | 1-2                  |
| 2     | 6-15              | 3-5                  |
| 3     | 16-30             | 6-10                 |
| 4     | 31-60             | 11-20                |
| 5     | 61-100            | 21-35                |
| 6     | 101-200           | 36-50                |
| 7     | >200              | >50                  |

Alle Werte im JSON sind Integer 0-7.

### personalMix-Berechnung

Formel (gewichteter Durchschnitt):

```
personalMix = round( sum(level_i * weight_i) / sum(weight_i) )
```

- `level_i`: Pollen-Level (0-7) fuer Pollenart i
- `weight_i`: Sensitivity-Wert (0-7) aus `[POLLEN]`-Config fuer Pollenart i
- Nur Arten mit `weight_i > 0` fliessen ein
- Wenn alle Weights 0: `personalMix = 0`
- Ergebnis: Integer 0-7

Fuer dailyforecast: `personalMix.avg` und `personalMix.max` werden separat berechnet -- avg aus den avg-Werten, max aus den max-Werten der einzelnen Pollenarten (jeweils gewichtet).

### current.json -- `current` Objekt

```json
"airQuality": { "aqiEu": 61, "aqiUs": 80, "pm10": 24.1, "pm25": 21.8 },
"pollen": {
  "alder": 1, "birch": 1, "grass": 0,
  "mugwort": 0, "olive": 0, "ragweed": 0,
  "personalMix": 1
}
```

- `airQuality` und `pollen` auf gleicher Ebene wie `temperature`, `wind`, etc.

### hourlyforecast[n]

```json
"airQuality": null,
"pollen": {
  "alder": 2, "birch": 1, "grass": 0,
  "mugwort": 0, "olive": 0, "ragweed": 0,
  "personalMix": 2
}
```

- `airQuality`: `null` (API liefert keine hourly AQ-Werte)
- Pollen: Level 0-7, Matching via Timestamp (API `time` <-> `hourlyforecast[n].time.datetime`)
- Abdeckung: 5 Tage (API `forecast_days=5`), restliche Stunden in hourlyforecast ohne Pollen-Match bekommen `pollen: null`

### dailyforecast[n]

```json
"airQuality": null,
"pollen": {
  "alder": { "avg": 1, "max": 3 },
  "birch": { "avg": 1, "max": 2 },
  "grass": { "avg": 0, "max": 0 },
  "mugwort": { "avg": 0, "max": 0 },
  "olive": { "avg": 0, "max": 0 },
  "ragweed": { "avg": 0, "max": 0 },
  "personalMix": { "avg": 1, "max": 3 }
}
```

- Tageswerte berechnet aus 24 Stundenwerten (avg + max der Level)
- Abdeckung: 5 Tage (API-Limit). Tage ohne Pollen-Daten bekommen `pollen: null`

### AQ-Grabber Rewrite-Scope

Der `grabber_openmeteo_airquality.pl` wird grundlegend umgebaut:
- Liest alle 3 JSON-Dateien via `readJsonFile()`
- Matched hourly Pollen-Daten per Timestamp zu bestehenden Stunden-Eintraegen
- Aggregiert daily Pollen-Daten (avg + max) aus den Stundenwerten pro Tag
- Berechnet `personalMix` aus `[POLLEN]`-Config
- Schreibt alle 3 JSON-Dateien zurueck via `writeJsonFile()`
- `airquality_pollen.json` (Legacy) entfaellt

---

## Bekannte Bugs (fixen waehrend Migration)

- `grabber_wu.pl`: `rain1Hr` -> `rain1hr` (Feldname-Inkonsistenz)
- `datatoloxone.pl`: `$cur->{precipitation}{snow1hr}` -> `snow1h` (Feldname stimmt nicht mit Schema ueberein)
- `show.cgi`: `rain_today_mm` -> `rainToday`, `rain_1hr_mm` -> `rain1hr` (alte snake_case Feldnamen)

---

## Migrations-Reihenfolge

### Phase 1 -- Haupt-Grabber (current + daily + hourly JSON)

Jeder bekommt: `$grabberKey`, `$location`-Hash, 3x `writeJsonFile()`, `refresh` aus `SERVER.CRON * 60`, kein .dat-Code.

1. `grabber_openweather2.pl` (grabberKey: `"openweather"`)
2. `grabber_visualcrossing.pl` (grabberKey: `"visualcrossing"`)
3. `grabber_weatherflow.pl` (grabberKey: `"weatherflow"`)
4. `grabber_wttrin.pl` (grabberKey: `"wttrin"`)

### Phase 2 -- Patch-Grabber (JSON-Merge auf current.json)

`readJsonFile()` -> Felder patchen -> eigenen `$grabberKey` hinzufuegen -> `writeJsonFile()`. `refresh` aus `SERVER.CRON_PATCH * 60`.

5. `grabber_wu.pl` -- Inkonsistenzen fixen, Merge-Pattern beibehalten
6. `grabber_foshk.pl` -- von .dat-Patch auf JSON-Merge
7. `grabber_loxone.pl` -- von .dat-Patch auf JSON-Merge
8. `grabber_pwscatchupload.pl` -- snake_case -> camelCase + Standard-Envelope

### Phase 3 -- AQ + Pollen Integration

Abhaengigkeit: Phase 1 muss abgeschlossen sein (AQ merged in bestehende JSONs).

9. `[POLLEN]`-Abschnitt in `weather4lox.cfg` + `postinstall.sh` Default-Seeding
10. `grabber_openmeteo_airquality.pl` -- kompletter Rewrite der Output-Logik:
    - Merged in alle 3 JSON-Dateien
    - `pollenLevel()` auf 0-7 erweitern
    - `personalMix` berechnen
    - `mapping_custom_mix_pollen.json` entfaellt

### Phase 4 -- Consumer-Anpassung

Abhaengigkeit: Phase 1-3 muessen abgeschlossen sein.

11. `ocean-live_new.html` -> `ocean-live.html` (Rename zu Beginn von Phase 4):
    - Envelope: `results[0].current` statt `results[0].data`
    - Location: `results[0].location.city` statt `c.city`
    - Felder: `c.temperature.air`, `c.wind.speed`, `c.weatherCode.weather4lox`, etc.
    - Refresh: dynamisch aus `results[0].refresh * 1000`
    - AQ/Pollen-Anzeige: derzeit kein UI geplant, Daten stehen im JSON bereit
12. `datatoloxone.pl` -- Feld-Zugriffe pruefen/anpassen, `snow1hr` -> `snow1h` fixen
13. `show.cgi` -- falsche Feldnamen fixen
14. `index.cgi` -- Pollen-Settings von `mapping_custom_mix_pollen.json` auf `weather4lox.cfg [POLLEN]` umstellen

### Phase 5 -- Cleanup

15. .dat-Code aus allen Grabbern + Consumern entfernen
16. `data/*.format` Dateien loeschen
17. `mapping_custom_mix_pollen.json` entfernen
18. `airquality_pollen.json` (Legacy-Datei) entfernen
19. `grabber_openweather.pl` (Legacy v2 API) entfernen
20. DECISIONS.md aktualisieren (Dual-Write -> clean break)

---

## Grabber-Key Mapping

| Grabber | grabberKey | Typ | Schreibt |
|---------|-----------|-----|----------|
| grabber_wetteronline.pl | `wetteronline` | Haupt | current + daily + hourly |
| grabber_openweather2.pl | `openweather` | Haupt | current + daily + hourly |
| grabber_visualcrossing.pl | `visualcrossing` | Haupt | current + daily + hourly |
| grabber_weatherflow.pl | `weatherflow` | Haupt | current + daily + hourly |
| grabber_wttrin.pl | `wttrin` | Haupt | current + daily + hourly |
| grabber_wu.pl | `wunderground` | Patch | current (merge) |
| grabber_foshk.pl | `foshk` | Patch | current (merge) |
| grabber_loxone.pl | `loxone` | Patch | current (merge) |
| grabber_pwscatchupload.pl | `pwscatchupload` | Patch | current (merge) |
| grabber_openmeteo_airquality.pl | `openmeteoAq` | AQ | current + daily + hourly (merge) |

---

## Erfolgskriterien

1. Alle 10 Grabber produzieren JSON im wetteronline-Format (camelCase, Envelope)
2. Kein .dat-Code mehr in Grabbern oder Consumern
3. `ocean-live.html` nutzt dynamisches Refresh-Intervall aus JSON
4. AQ + Pollen in allen 3 JSON-Dateien, Werte als Level 0-7
5. `personalMix` berechnet aus `[POLLEN]`-Config in `weather4lox.cfg`
6. `data/json-schema.md` dokumentiert das finale Schema inkl. AQ/Pollen
7. Bekannte Bugs (snow1hr, rain1Hr, show.cgi Feldnamen) behoben
8. Legacy-Dateien entfernt (*.dat, *.format, mapping_custom_mix_pollen.json, airquality_pollen.json)
