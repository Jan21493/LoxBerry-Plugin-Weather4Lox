# Phase 3: CGI JSON Endpoint - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

show.cgi liefert Wetterdaten als JSON uber HTTP mit korrekten Headers (Content-Type, Cache-Control). Browser-Clients konnen current, hourly und daily Daten per Fetch laden. Die bestehende HTML-Template-Funktionalitat von show.cgi bleibt unverandert erhalten.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

Alle Entscheidungen dieser Phase wurden dem Ermessen von Claude uberlassen. Die folgenden Entscheidungen basieren auf der Codebase-Analyse und den Entscheidungen vorheriger Phasen.

### Zugriffspfad

- JSON-Endpoint bleibt in show.cgi (webfrontend/htmlauth/show.cgi) — kein neuer Endpoint
- Bestehende Query-Parameter-Infrastruktur wird wiederverwendet (Zeilen 59-76)
- Neuer Parameter `format=json` wird hinzugefugt, kombiniert mit `type=current|hourly|daily`
- ocean-live Theme in webfrontend/html/ ruft show.cgi per relativem Pfad auf (LoxBerry erlaubt same-origin Requests zu htmlauth/)
- Falls Auth-Probleme auftreten: kann in spaterer Phase ein unauthentifizierter Proxy ergänzt werden

### Einheiten-Handling

- JSON-Endpoint liefert die JSON-Dateien 1:1 von Disk — immer metrische Rohwerte
- Keine serverseitige metric/imperial Konvertierung fur JSON-Responses (im Gegensatz zur HTML-Template-Logik)
- Frontend ist fur Einheiten-Konvertierung zustandig (Phase 5: Datenanbindung)
- Begrundung: JSON-Dateien enthalten bereits die kanonischen metrischen Werte aus Phase 1; Konvertierung im Frontend ist flexibler und vermeidet Doppellogik

### Fehler-Responses

- Fehlender `type` Parameter oder ungueltiger Wert: HTTP 400 mit JSON `{"error": "Invalid or missing type parameter. Use type=current|hourly|daily", "code": 400}`
- JSON-Datei nicht gefunden auf Disk: HTTP 404 mit JSON `{"error": "Weather data not available", "code": 404}`
- JSON-Datei nicht lesbar/korrupt: HTTP 500 mit JSON `{"error": "Internal server error", "code": 500}`
- Alle Error-Responses haben ebenfalls Content-Type: application/json; charset=utf-8

### Response-Struktur

- JSON-Dateien werden 1:1 von Disk durchgereicht (File-Slurp + print)
- Kein Parsen, kein Transformieren, kein Umhullen — maximale Performance
- Die meta/data-Struktur aus Phase 1 ist bereits die endgultige API-Struktur
- Datei-Mapping: type=current → current.json, type=hourly → hourlyforecast.json, type=daily → dailyforecast.json

### Implementation-Ansatz

- Neuer Code-Block am Anfang von show.cgi, VOR der bestehenden .dat-Lese-Logik
- Wenn `format=json` erkannt: JSON-Response senden und `exit` (kein Durchfall in HTML-Logik)
- Bestehende HTML-Template-Funktionalitat bleibt zu 100% unverandert
- Kein Refactoring des bestehenden Codes — nur Erweiterung

</decisions>

<specifics>
## Specific Ideas

- Die Requirements sind klar definiert (CGI-01, CGI-02, CGI-03) — wenig Interpretationsspielraum
- show.cgi hat bereits Query-Parameter-Parsing — `format` und `type` werden einfach hinzugefugt
- File-Slurp Ansatz (JSON von Disk lesen + direkt ausgeben) ist der einfachste und performanteste Weg
- Keine Abhaengigkeit von Phase 2 noetig — Phase 3 haengt nur von Phase 1 ab (JSON-Dateien muessen existieren)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `show.cgi` Zeilen 59-76: Query-Parameter-Parsing — wird um `format` und `type` erweitert
- `show.cgi` Zeile 47: `$pcfg` Config-Objekt — Zugriff auf Plugin-Konfiguration
- LoxBerry-Variablen: `$home/log/plugins/$psubfolder/` als Pfad zu JSON-Dateien auf RAM-Disk

### Established Patterns
- CGI-Output: `print "Content-type: text/html\n\n"` (Zeile 396) — Muster fur HTTP-Header-Ausgabe
- Early-Exit: `exit;` nach vollstandiger Response (Zeile 139, 217, 306) — gleiche Struktur fur JSON-Response
- Datei-Lesen: `open(F,"<$path") || die "..."` (Zeile 149, 227, 314) — Basis fur JSON File-Read

### Integration Points
- Query-Parameter `format` und `type`: Neue Parameter im bestehenden Parsing-Block (Zeile 72)
- JSON-Dateipfade: `$home/log/plugins/$psubfolder/current.json` (analog zu current.dat Zeile 314)
- Response-Punkt: Neuer Block nach Parameter-Parsing (ca. Zeile 77), vor der MAP VIEW Sektion (Zeile 117)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-cgi-json-endpoint*
*Context gathered: 2026-03-13*
