# Phase 1: JSON Schema & Grabber Migration - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Alle Grabber schreiben strukturierte JSON-Wetterdaten parallel zu den bestehenden .dat-Dateien (Dual-Write). Eine JSON-Schema-Dokumentation wird erstellt. Das alte .dat-System bleibt unverändert funktionsfähig.

</domain>

<decisions>
## Implementation Decisions

### JSON-Schema-Struktur
- Jede JSON-Datei hat Top-Level-Objekt mit `meta` und `data`
- `meta` enthält: `schema_version` ("1.0"), `source` (Grabber-Name), `generated_at` (ISO 8601), `grabber` (Dateiname)
- `data` bei current.json: einzelnes Objekt mit Wetterdaten
- `data` bei hourly.json und daily.json: Array von Objekten, sortiert nach Zeit
- Feld-Benennung: snake_case (konsistent mit bestehendem grabber_utils.pl)
- Fehlende/leere Werte: JSON `null` (nicht weglassen, nicht Default-Werte)

### Supplementary Grabber Scope
- Alle 5 Supplementary-Grabber (WU, FOSHK, PWS, Loxone, OpenMeteo AQ) schreiben JSON
- Überschreiben current.json wie sie current.dat überschreiben (gleicher Mechanismus)
- Fehlende Felder werden als `null` gesetzt (vollständiges Schema, nicht nur verfügbare Felder)
- OpenMeteo Air Quality: Pollen/AQ-Felder werden ins current-Schema integriert (kein separates File)
- Haupt-Grabber setzen AQ-Felder auf `null`
- Alle Grabber nutzen `write_current_json()` aus grabber_utils.pl

### Fehlerverhalten & Logging
- .dat hat Priorität: JSON-Write-Fehler stoppen nicht den Grabber-Lauf
- Log-Level: LOGOK bei erfolgreichem JSON-Write, LOGWARN bei Fehler
- Keine Re-Validierung nach dem Schreiben (JSON::PP erzeugt gültiges JSON, atomarer Write schützt)
- Bei Encoding-Fehler (ungültiges UTF-8): gesamten JSON-Write überspringen, vorherige Datei bleibt bestehen

### Schema-Dokumentation
- Format: Markdown-Referenz (data/json-schema.md)
- Enthält: Feld-Tabellen (Name, Typ, Einheit, Beschreibung) für current, hourly, daily
- Enthält: Vollständige Beispiel-JSONs mit realistischen Wetterdaten
- Enthält: Mapping-Tabelle .dat-Feldposition → JSON-Feldname (nützlich für Phase 2)
- Ablageort: data/ Verzeichnis (neben den bestehenden .format-Dateien)

### Claude's Discretion
- Exakte Sortierung der Felder innerhalb der JSON-Objekte
- Ob `period` als Feld im Array beibehalten oder durch Array-Index impliziert wird
- Formatierung der Schema-Dokumentation (Tabellen-Layout, Reihenfolge der Abschnitte)
- Handhabung von hourlyhistory.dat (4. Format-Datei, weniger zentral)

</decisions>

<specifics>
## Specific Ideas

- Meta-Header soll Debugging erleichtern: bei Problemen sofort sichtbar welcher Grabber wann geschrieben hat
- AQ-Daten (aqi, pm25, pm10, pollen_*) direkt in current.json — kein zusätzlicher Fetch im Frontend
- Schema-Doku soll das Mapping alt→neu enthalten, damit Phase 2 (datatoloxone.pl Migration) nahtlos anschließen kann

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `grabber_utils.pl`: Enthält bereits `write_current_json()`, `write_daily_json()`, `write_hourly_json()` — Kern-Infrastruktur vorhanden
- `@CURRENT_RAW`, `@DAILY_RAW`, `@HOURLY_RAW`: Positionelle Feld-Listen für .dat→JSON Mapping
- `%WEATHER_CODE_TO_ID`: Weather-Code Normalisierung (Legacy-Codes → semantische IDs)
- `_line_to_hash()`, `_epoch_to_iso()`, `_enrich_weather_id()`: Konvertierungs-Utilities
- `api_call()`: HTTP-Fetch mit JSON-Dekodierung, Error-Handling, Key-Masking

### Established Patterns
- Atomarer Write: .tmp + `File::Copy::move()` (etabliert in allen Grabbern)
- File-Locking: `flock(F,2)` / `flock(F,8)` vor/nach Schreiben
- UTF-8 Handling: `binmode F, ':encoding(UTF-8)'`
- Sanitization: null/--/na/N/A → numerische Defaults in .dat (JSON nutzt stattdessen `null`)
- Größenprüfung: .dat wird nur renamed wenn > 100 Bytes

### Integration Points
- `grabber_openweather.pl` Zeilen 820-822: Ruft bereits `write_*_json()` auf — Referenz-Implementation
- Alle Grabber importieren `grabber_utils.pl` via `require` — JSON-Funktionen sofort verfügbar
- `$lbplogdir`: Ausgabeverzeichnis für .dat und .json (LoxBerry RAM-Disk)
- `fetch.pl`: Orchestriert Grabber-Aufrufe — keine Änderung nötig

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-json-schema-grabber-migration*
*Context gathered: 2026-03-12*
