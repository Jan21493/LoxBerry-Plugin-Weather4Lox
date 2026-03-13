# Requirements: Weather4Lox Modernisierung

**Defined:** 2026-03-12
**Core Value:** Wetterdaten als strukturiertes JSON bereitgestellt, ocean-live Theme zeigt sie dynamisch per AJAX mit Hero-Stundenansicht an

## v1 Requirements

### JSON Datenformat

- [x] **JSON-01**: JSON-Schema für current, hourly und daily Wetterdaten definiert und dokumentiert
- [x] **JSON-02**: Alle Grabber (OpenWeather, VisualCrossing, WeatherFlow, WetterOnline, wttr.in) schreiben JSON-Dateien parallel zu .dat (Dual-Write)
- [x] **JSON-03**: JSON-Dateien werden atomar geschrieben (.tmp + rename) mit File-Locking
- [x] **JSON-04**: JSON-Encoding ist konsistent UTF-8 mit korrektem Umlaut-Handling (ä, ö, ü, ß)
- [x] **JSON-05**: Dezimalzahlen nutzen Punkt als Trennzeichen unabhängig vom System-Locale
- [x] **JSON-06**: Supplementary Grabber (WU, FOSHK, PWSCatchUpload, Loxone, OpenMeteo AQ) schreiben ebenfalls JSON
- [x] **JSON-07**: datatoloxone.pl liest JSON statt .dat für UDP/MQTT Delivery an Loxone
- [x] **JSON-08**: datatoloxone.pl erzeugt identische UDP/MQTT-Werte wie zuvor (keine Regression)

### CGI Endpoint

- [x] **CGI-01**: show.cgi liefert JSON-Wetterdaten mit Content-Type: application/json; charset=utf-8
- [x] **CGI-02**: show.cgi setzt Cache-Control: no-cache Headers für JSON-Responses
- [x] **CGI-03**: show.cgi unterstützt Parameter format=json mit type=current|hourly|daily

### Theme Struktur

- [ ] **THEME-01**: ocean-live.html als einzelne Datei in webfrontend/html/ abgelegt
- [ ] **THEME-02**: Theme hat 3 Tab-Buttons: Heute | Morgen | Tage
- [ ] **THEME-03**: Tab-Wechsel zeigt/versteckt zugehörige Inhalte mit CSS-Transitions
- [ ] **THEME-04**: Visuelles Design orientiert sich am bestehenden Ocean-Theme (Farbschema, Typografie, Layout)

### Hero & Stundenansicht

- [ ] **HERO-01**: Hero-Bereich zeigt ausgewählte Stunde groß an (Temperatur, Icon, Beschreibung, Wind, Feuchtigkeit)
- [ ] **HERO-02**: Horizontale Stundenleiste unter dem Hero zeigt alle Stunden des Tages
- [ ] **HERO-03**: Klick auf Stunde in der Leiste aktualisiert den Hero-Bereich
- [ ] **HERO-04**: Heute-Tab zeigt Stunden des heutigen Tages
- [ ] **HERO-05**: Morgen-Tab zeigt Stunden des morgigen Tages
- [ ] **HERO-06**: Aktuelle Stunde (Heute) bzw. erste Stunde (Morgen) ist bei Tab-Wechsel vorausgewählt

### Tage-Tab

- [ ] **TAGE-01**: Tage-Tab zeigt 7-Tage-Vorhersage als Übersicht
- [ ] **TAGE-02**: Pro Tag: Wetter-Icon, Hoch/Tief-Temperatur, Niederschlagswahrscheinlichkeit

### Datenanbindung

- [ ] **DATA-01**: Theme lädt Wetterdaten per Fetch API von show.cgi JSON-Endpoint
- [ ] **DATA-02**: Theme lädt Sprachdaten per Fetch aus lang-*.json
- [ ] **DATA-03**: Theme lädt Icon-Mapping per Fetch aus icons/{iconset}/icon_mapping.json
- [ ] **DATA-04**: Auto-Refresh lädt Daten periodisch nach (Intervall ≥ 5 Minuten)
- [ ] **DATA-05**: Ladeanzeige während AJAX-Requests
- [ ] **DATA-06**: Fehlermeldung wenn Daten nicht geladen werden können

### Mehrsprachigkeit

- [ ] **LANG-01**: Alle UI-Texte (Tab-Labels, Einheiten, Beschreibungen) kommen aus lang-*.json
- [ ] **LANG-02**: Unterstützte Sprachen: DE, EN, ES, NL, SK
- [ ] **LANG-03**: Sprache wird per URL-Parameter oder Konfiguration gesetzt

### Zusatz-Features

- [ ] **EXTRA-01**: Sonnenauf- und Sonnenuntergang im Hero-Bereich angezeigt
- [ ] **EXTRA-02**: Smooth CSS-Transitions bei Tab-Wechsel und Hero-Aktualisierung

## v2 Requirements

### Erweiterte Visualisierung

- **VIS-01**: Windrichtungs-Kompass (visuell statt Text)
- **VIS-02**: UV-Index Anzeige
- **VIS-03**: Mondphase Anzeige

### System-Migration

- **MIG-01**: Gebündelter CGI-Endpunkt (alle Daten in einem Request)
- **MIG-02**: Entfernung des alten .dat-Systems nach Testphase
- **MIG-03**: Entfernung der alten Themes (dark, light, fresh, ocean)
- **MIG-04**: Weitere Themes im neuen JSON-basierten System

## Out of Scope

| Feature | Reason |
|---------|--------|
| Radar-Karte eingebettet | Hoher Traffic, externe API-Abhängigkeit, iframe-Probleme |
| Animierte Wetter-Hintergründe | Performance-Problem auf Raspberry Pi |
| Push-Benachrichtigungen | Braucht Service Worker, Server-Logik — Overkill |
| Historische Daten/Graphen | Braucht Datenbank, Chart-Library, viel Speicher |
| Mobile App | Web-Frontend only |
| Neue Wetterdienst-Integrationen | Bestehende Grabber werden nur auf JSON umgestellt |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| JSON-01 | Phase 1 | Complete |
| JSON-02 | Phase 1 | Complete |
| JSON-03 | Phase 1 | Complete |
| JSON-04 | Phase 1 | Complete |
| JSON-05 | Phase 1 | Complete |
| JSON-06 | Phase 1 | Complete |
| JSON-07 | Phase 2 | Complete |
| JSON-08 | Phase 2 | Complete |
| CGI-01 | Phase 3 | Complete |
| CGI-02 | Phase 3 | Complete |
| CGI-03 | Phase 3 | Complete |
| THEME-01 | Phase 4 | Pending |
| THEME-02 | Phase 4 | Pending |
| THEME-03 | Phase 4 | Pending |
| THEME-04 | Phase 4 | Pending |
| HERO-01 | Phase 4 | Pending |
| HERO-02 | Phase 4 | Pending |
| HERO-03 | Phase 4 | Pending |
| HERO-04 | Phase 4 | Pending |
| HERO-05 | Phase 4 | Pending |
| HERO-06 | Phase 4 | Pending |
| TAGE-01 | Phase 4 | Pending |
| TAGE-02 | Phase 4 | Pending |
| EXTRA-02 | Phase 4 | Pending |
| DATA-01 | Phase 5 | Pending |
| DATA-02 | Phase 5 | Pending |
| DATA-03 | Phase 5 | Pending |
| DATA-04 | Phase 5 | Pending |
| DATA-05 | Phase 5 | Pending |
| DATA-06 | Phase 5 | Pending |
| LANG-01 | Phase 5 | Pending |
| LANG-02 | Phase 5 | Pending |
| LANG-03 | Phase 5 | Pending |
| EXTRA-01 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0

---
*Requirements defined: 2026-03-12*
*Last updated: 2026-03-12 after roadmap creation — all requirements mapped*
