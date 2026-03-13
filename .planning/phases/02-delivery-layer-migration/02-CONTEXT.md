# Phase 2: Delivery Layer Migration - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

datatoloxone.pl wird komplett von .dat auf JSON umgestellt: sowohl der UDP/MQTT-Versand an Loxone als auch die HTML-Template-Generierung für alte Themes. Die .dat-Lese-Logik wird entfernt. Alle gesendeten Werte (Namen, Einheiten, Berechnungen) bleiben identisch — keine Regression für Loxone-Nutzer.

</domain>

<decisions>
## Implementation Decisions

### Fallback-Verhalten
- Kein Fallback auf .dat — wenn JSON fehlt, Fehlermeldung + Exit
- Alle 3 JSON-Dateien (current.json, dailyforecast.json, hourlyforecast.json) werden beim Start geprüft (fail-fast)
- Alte .dat-Lese-Logik wird komplett entfernt (nicht auskommentiert)

### JSON-Loading
- Alle 3 JSON-Dateien werden zentral am Anfang des Scripts geladen und in Perl-Hashes/-Arrays geparst
- Saubere Trennung: erst Laden, dann Verarbeiten (UDP/MQTT, HTML-Templates)

### HTML-Template-Sektion
- HTML-Template-Generierung (alte Themes: dark, light, fresh, ocean) wird ebenfalls auf JSON umgestellt
- Template-Variablennamen bleiben identisch (${dfc.0._tt_h} etc.) — nur die Datenquelle ändert sich
- Alte Themes funktionieren weiter ohne Template-Änderung

### Berechnete Werte (calc+N)
- calc+4_prec, calc+8_ttmax etc. werden direkt aus JSON-Array-Feldern berechnet (z.B. $hour->{temperature} statt @fields[11])
- period-Feld aus JSON wird für $sendhfc/$senddfc-Filtering genutzt — gleiche Config-Logik wie bisher
- calc+N Werte bleiben nur UDP/MQTT (keine Template-Variablen)
- JSON null-Werte werden bei Aggregation übersprungen (wie bisher -9999 übersprungen wird)

### Sunrise/Sunset Parsing
- JSON liefert "HH:MM" String — wird per split(':') in Stunde/Minute aufgespalten
- Loxone-Epoch-Berechnung (DateTime->new + epoch - dateref) bleibt identisch
- Bei null im JSON: -9999 senden (keine Regression für Loxone-Logik)
- Gleiche Behandlung für current und daily forecast

### Claude's Discretion
- Log-Level bei fehlenden JSON-Dateien (LOGERR vs LOGCRIT)
- weatherdata.html Debug-Datei: beibehalten oder entfernen
- Exakte Reihenfolge der JSON-Lade-Aufrufe
- Interne Hilfsfunktionen für JSON→Variable-Mapping

</decisions>

<specifics>
## Specific Ideas

- json-schema.md enthält .dat-Position → JSON-Feldname Mapping — direkt als Referenz für die Migration nutzbar
- Dual-Write in den Grabbern bleibt aktiv — .dat-Dateien existieren weiterhin für Rollback-Sicherheit
- Phase 1 Entscheidung: period-Feld wird explizit in JSON-Arrays beibehalten — direkt für $sendhfc/$senddfc Filter nutzbar

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `data/json-schema.md`: Vollständiges Feld-Mapping .dat-Position → JSON-Feldname (erstellt in Phase 1)
- `JSON::PP`: Bereits im Perl-Ökosystem verfügbar, wird von grabber_utils.pl genutzt
- `grabber_utils.pl` JSON-Write-Funktionen: Zeigen das exakte JSON-Format das gelesen werden muss

### Established Patterns
- Atomarer Write (.tmp + rename) in den Grabbern — JSON-Dateien sind immer konsistent
- File-Locking (flock) — wird auch beim Lesen benötigt
- Unit-Conversion ($metric): Celsius↔Fahrenheit, km/h↔mph etc. — bleibt identisch
- Loxone-Epoch: DateTime-basierte Berechnung (epoch - 1.1.2009 reference)

### Integration Points
- `$lbplogdir`: Verzeichnis für current.json, dailyforecast.json, hourlyforecast.json (gleich wie .dat)
- `$pcfg->param("SERVER.SENDDFC")` / `$pcfg->param("SERVER.SENDHFC")`: Steuern welche Perioden gesendet werden
- `&send` / `&mqttconnect`: UDP/MQTT-Funktionen bleiben unverändert
- Theme-Templates in `$lbptemplatedir/themes/`: Nutzen `<!--$variablename-->` Syntax — Variablennamen bleiben stabil

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-delivery-layer-migration*
*Context gathered: 2026-03-12*
