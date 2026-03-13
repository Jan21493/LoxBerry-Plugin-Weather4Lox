# Project Research Summary

**Project:** Weather4Lox Modernisierung
**Domain:** Perl-basiertes Wetter-Plugin — JSON Migration + AJAX Theme
**Researched:** 2026-03-12
**Confidence:** HIGH

## Executive Summary

Weather4Lox ist ein ausgereiftes LoxBerry-Plugin mit 11 Wetter-Grabbern, das aktuell pipe-delimited .dat-Dateien als Datenaustauschformat nutzt und Themes serverseitig per Perl-Variablensubstitution rendert. Die Modernisierung umfasst zwei Hauptachsen: (1) Umstellung des Datenformats auf JSON für strukturierten Zugriff und (2) ein neues AJAX-basiertes Theme "ocean-live" im Ocean-Design mit Hero-Stundenansicht.

Der empfohlene Ansatz nutzt ausschließlich bestehende Technologien — Perl mit LoxBerry::JSON für die Backend-Seite, Vanilla JavaScript mit Fetch API für das Frontend. Keine zusätzlichen Dependencies oder Build-Tools nötig. Die Migration erfolgt über Dual-Write (JSON + .dat parallel), um das bestehende System nicht zu brechen.

Hauptrisiken sind UTF-8 Encoding-Probleme bei deutschen Umlauten, JSON-Schema-Inkonsistenzen zwischen verschiedenen Grabbern, und CGI-Performance auf dem Raspberry Pi. Alle drei sind mit klaren Strategien vermeidbar.

## Key Findings

### Recommended Stack

Keine neuen Dependencies nötig. Das bestehende LoxBerry-Ökosystem (Perl 5.20+, LoxBerry::JSON, Apache CGI) reicht aus. Frontend nutzt Vanilla JavaScript (Fetch API, DOM API, CSS Custom Properties) — keine Build-Tools, kein jQuery, kein Framework.

**Core technologies:**
- LoxBerry::JSON: Atomares JSON File-I/O mit Locking — bereits verfügbar
- Vanilla JS Fetch API: Browser-natives JSON-Laden — kein Overhead
- CSS Custom Properties: Theme-Styling ohne Preprocessor — dynamisch anpassbar

### Expected Features

**Must have (table stakes):**
- Aktuelle Wetterdaten prominent (Temperatur, Icon, Beschreibung)
- Stündliche Vorhersage mit Auswahl (Hero + Stundenleiste)
- 7-Tage-Vorhersage
- Mehrsprachigkeit (5+ Sprachen)
- Responsive Layout

**Should have (competitive):**
- Smooth Tab-Übergänge
- Auto-Refresh ohne Reload
- Sonnenauf-/untergang, Mondphase, UV-Index

**Defer (v2+):**
- Radar-Karte eingebettet
- Historische Daten/Graphen
- Weitere Themes im neuen System

### Architecture Approach

Grabber schreiben JSON-Dateien parallel zu .dat auf die RAM-Disk. Ein CGI-Endpunkt (show.cgi) dient als JSON-Proxy für den Browser. Das ocean-live Theme (einzelne HTML-Datei in webfrontend/html/) lädt per Fetch die JSON-Daten und rendert client-seitig.

**Major components:**
1. JSON Writer in Grabbern — normalisiertes Schema, atomares Schreiben
2. CGI JSON Proxy — show.cgi erweitert für JSON-Auslieferung mit korrekten Headers
3. ocean-live.html — AJAX-basiertes Theme mit Hero-Stundenansicht und 3 Tabs
4. datatoloxone.pl — liest JSON statt .dat für UDP/MQTT Delivery

### Critical Pitfalls

1. **Dual-Write vergessen** — datatoloxone.pl und alte Themes brauchen weiterhin .dat bis zur vollständigen Migration
2. **UTF-8 Encoding** — Perl-JSON-Encoding mit deutschen Umlauten ist fehleranfällig, `use utf8;` und `LC_NUMERIC` setzen
3. **JSON-Schema Inkonsistenz** — Schema ZUERST definieren, dann alle Grabber anpassen
4. **CGI Performance** — Gebündelter Endpunkt statt 4 separate CGI-Aufrufe pro Seitenladung
5. **Dezimaltrennzeichen** — Deutsches Locale erzeugt Komma statt Punkt in JSON-Zahlen

## Implications for Roadmap

### Phase 1: JSON Datenformat
**Rationale:** Grundlage für alles — ohne JSON-Daten kann das Theme nichts laden
**Delivers:** JSON-Schema Definition, Grabber schreiben JSON (Dual-Write), datatoloxone.pl liest JSON
**Addresses:** Datenformat-Migration, Schema-Konsistenz
**Avoids:** .dat-Konsumenten-Bruch durch Dual-Write

### Phase 2: CGI JSON Endpoint
**Rationale:** Browser braucht einen Weg, JSON-Daten zu laden
**Delivers:** show.cgi JSON-Proxy mit korrekten Headers, gebündelter Endpunkt
**Addresses:** HTTP-Zugriff auf Wetterdaten
**Avoids:** Performance-Probleme durch CGI-Spawning

### Phase 3: ocean-live Theme Grundgerüst
**Rationale:** HTML/CSS Struktur muss stehen bevor Daten eingebunden werden
**Delivers:** HTML-Datei mit Ocean-Design, Tab-Navigation, Hero-Bereich Layouts
**Addresses:** Visuelles Design, Tab-Struktur

### Phase 4: Datenanbindung & Interaktion
**Rationale:** Theme mit echten Daten verbinden, Stundenleiste interaktiv machen
**Delivers:** AJAX Fetch, Stundenauswahl, Hero-Aktualisierung, Mehrsprachigkeit
**Addresses:** Dynamisches Datenladen, UX-Interaktion

### Phase 5: Integration & Polish
**Rationale:** Alles zusammenführen, testen, konfigurierbar machen
**Delivers:** show.cgi Integration, Icon-Mapping, Auto-Refresh, Fehlerbehandlung
**Addresses:** Produktionsreife, Edge Cases

### Phase Ordering Rationale

- JSON-Format zuerst weil es die Datengrundlage für alles ist
- CGI-Endpoint vor Theme weil das Theme Daten laden muss
- Theme-Gerüst vor Datenanbindung weil HTML-Struktur stehen muss
- Integration zuletzt weil alles zusammenspielen muss

### Research Flags

Phasen die tiefere Recherche bei der Planung brauchen:
- **Phase 1:** JSON-Schema Design — welche Felder, Datentypen, Defaults
- **Phase 3:** Ocean-Design Analyse — bestehende ocean.main.html im Detail studieren

Phasen mit Standard-Patterns (Recherche optional):
- **Phase 2:** CGI-Erweiterung — etabliertes Perl-CGI-Pattern
- **Phase 4:** Fetch API + DOM — Standard Web-Entwicklung

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Keine neuen Dependencies, alles existiert bereits |
| Features | HIGH | Klare User-Anforderungen, Ocean-Theme als Referenz |
| Architecture | HIGH | Bestehende Architektur gut verstanden, klarer Migrationspfad |
| Pitfalls | HIGH | Domain-spezifisch, aus Codebase-Analyse abgeleitet |

**Overall confidence:** HIGH

### Gaps to Address

- Exaktes JSON-Schema muss definiert werden — welche Felder aus den 42/40/36 .dat-Feldern übernommen werden
- Ocean-Theme CSS muss im Detail analysiert werden für ocean-live Design-Übernahme
- Performance-Test auf Raspberry Pi mit CGI JSON-Proxy nötig

## Sources

### Primary (HIGH confidence)
- Bestehender Codebase: grabber_*.pl, datatoloxone.pl, show.cgi, ocean.main.html, fresh.main.html
- Bestehende Datenformat-Dokumentation: data/*.format
- LoxBerry Framework Module: LoxBerry::JSON, LoxBerry::IO, LoxBerry::System

### Secondary (MEDIUM confidence)
- Perl JSON Encoding Best Practices
- MDN Web Docs: Fetch API, CSS Custom Properties

---
*Research completed: 2026-03-12*
*Ready for roadmap: yes*
