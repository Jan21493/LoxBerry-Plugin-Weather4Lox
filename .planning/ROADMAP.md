# Roadmap: Weather4Lox Modernisierung

## Overview

Die Modernisierung erfolgt in funf Phasen: Zuerst wird das JSON-Schema definiert und alle Grabber auf Dual-Write umgestellt. Dann wird der Delivery-Layer (datatoloxone.pl) auf JSON-Lesen migriert. Anschliessend wird show.cgi als JSON-Proxy fur den Browser erweitert. Darauf aufbauend entsteht das ocean-live Theme mit visueller Struktur, Tabs und Hero-Bereich. Zuletzt werden alle Daten live per AJAX eingebunden, Mehrsprachigkeit aktiviert und der Auto-Refresh integriert — das Ergebnis ist ein vollstandig produktionsreifes AJAX-Theme.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: JSON Schema & Grabber Migration** - JSON-Schema definiert, alle Grabber schreiben JSON parallel zu .dat (Dual-Write) (completed 2026-03-12)
- [ ] **Phase 2: Delivery Layer Migration** - datatoloxone.pl liest JSON statt .dat, UDP/MQTT Delivery unverandert
- [ ] **Phase 3: CGI JSON Endpoint** - show.cgi liefert JSON-Wetterdaten mit korrekten HTTP-Headers
- [ ] **Phase 4: ocean-live Theme Grundgerust** - Einzelne HTML-Datei mit Ocean-Design, Tabs, Hero-Bereich und 7-Tage-Ubersicht
- [ ] **Phase 5: Datenanbindung & Vollstandigkeit** - AJAX-Datenladen, Mehrsprachigkeit, Auto-Refresh, Fehlerbehandlung

## Phase Details

### Phase 1: JSON Schema & Grabber Migration
**Goal**: Alle Grabber schreiben strukturierte JSON-Wetterdaten parallel zu den bestehenden .dat-Dateien, sodass das neue System genutzt werden kann ohne das alte zu brechen
**Depends on**: Nothing (first phase)
**Requirements**: JSON-01, JSON-02, JSON-03, JSON-04, JSON-05, JSON-06
**Success Criteria** (what must be TRUE):
  1. Eine JSON-Schema-Dokumentation fur current.json, hourly.json und daily.json existiert mit definierten Feldern und Datentypen
  2. Nach einem Grabber-Lauf existieren current.json, hourly.json und daily.json neben den .dat-Dateien auf der RAM-Disk
  3. Die JSON-Dateien enthalten korrekte UTF-8-Umlaute (a, o, u, ss) und Dezimalpunkte statt Kommas
  4. Alle funf Haupt-Grabber (OpenWeather, VisualCrossing, WeatherFlow, WetterOnline, wttr.in) sowie supplementary Grabber schreiben JSON
  5. Die bestehenden .dat-Dateien existieren unverandert nach dem Grabber-Lauf (kein Regression im alten System)
**Plans:** 3/3 plans complete

Plans:
- [ ] 01-01-PLAN.md — Upgrade write_*_json() in grabber_utils.pl (meta/data envelope, atomic write, AQ fields)
- [ ] 01-02-PLAN.md — Update 5 main grabbers with source/grabber params + create schema documentation
- [ ] 01-03-PLAN.md — Wire 5 supplementary grabbers to write current.json

### Phase 2: Delivery Layer Migration
**Goal**: datatoloxone.pl liest JSON statt .dat und sendet identische UDP/MQTT-Pakete an Loxone wie zuvor
**Depends on**: Phase 1
**Requirements**: JSON-07, JSON-08
**Success Criteria** (what must be TRUE):
  1. datatoloxone.pl liest Wetterdaten aus current.json / daily.json statt aus .dat-Dateien
  2. Loxone Miniserver empfangt identische UDP/MQTT-Werte wie vor der Migration (keine Regression bei Sensorwerten)
  3. datatoloxone.pl schlagt mit einer klaren Fehlermeldung fehl wenn JSON-Dateien nicht vorhanden sind
**Plans:** 1 plan

Plans:
- [ ] 02-01-PLAN.md — Migrate datatoloxone.pl from .dat to JSON (load infrastructure + all sections + cleanup)

### Phase 3: CGI JSON Endpoint
**Goal**: show.cgi stellt Wetterdaten als JSON uber HTTP bereit, sodass Browser-Clients die Daten per Fetch laden konnen
**Depends on**: Phase 1
**Requirements**: CGI-01, CGI-02, CGI-03
**Success Criteria** (what must be TRUE):
  1. Ein Browser-Aufruf von show.cgi?format=json&type=current gibt Content-Type: application/json; charset=utf-8 zuruck
  2. Ein Browser-Aufruf mit type=hourly bzw. type=daily gibt die jeweiligen JSON-Daten zuruck
  3. Die HTTP-Response enthalt Cache-Control: no-cache Header
  4. Der Endpoint gibt die JSON-Daten aus den auf der RAM-Disk liegenden JSON-Dateien zuruck
**Plans**: TBD

### Phase 4: ocean-live Theme Grundgerust
**Goal**: Eine einzelne HTML-Datei in webfrontend/html/ mit dem vollstandigen Ocean-Design, 3 Tabs, Hero-Bereich und 7-Tage-Ubersicht — visuell vollstandig, noch ohne Live-Daten
**Depends on**: Phase 3
**Requirements**: THEME-01, THEME-02, THEME-03, THEME-04, HERO-01, HERO-02, HERO-03, HERO-04, HERO-05, HERO-06, TAGE-01, TAGE-02, EXTRA-02
**Success Criteria** (what must be TRUE):
  1. Die Datei webfrontend/html/ocean-live.html existiert und lasst sich im Browser offnen
  2. Drei Tab-Buttons (Heute / Morgen / Tage) sind sichtbar und Tab-Wechsel zeigt/versteckt Inhalte mit CSS-Transition
  3. Der Hero-Bereich zeigt Temperatur, Wetter-Icon, Beschreibung, Wind und Feuchtigkeit gross an
  4. Eine horizontale Stundenleiste ist sichtbar; Klick auf eine Stunde aktualisiert den Hero-Bereich mit den Werten dieser Stunde
  5. Der Tage-Tab zeigt eine 7-Tage-Ubersicht mit Icon, Hoch/Tief-Temperatur und Niederschlagswahrscheinlichkeit pro Tag
**Plans**: TBD

### Phase 5: Datenanbindung & Vollstandigkeit
**Goal**: Das ocean-live Theme ladt Wetterdaten und Sprachstrings live per AJAX, aktualisiert sich automatisch und behandelt Fehler sauber — vollstandig produktionsreif
**Depends on**: Phase 4
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, LANG-01, LANG-02, LANG-03, EXTRA-01
**Success Criteria** (what must be TRUE):
  1. Das Theme ladt beim Offnen automatisch aktuelle Wetterdaten von show.cgi und zeigt sie an — ohne manuelles Nachladen
  2. Alle UI-Texte (Tab-Labels, Einheiten, Beschreibungen) erscheinen in der konfigurierten Sprache (DE, EN, ES, NL, SK)
  3. Wahrenddessen eine Ladeanzeige zu sehen ist; bei Fehler erscheint eine verstandliche Fehlermeldung
  4. Das Theme aktualisiert die Daten automatisch alle 5+ Minuten ohne Seiten-Reload
  5. Sonnenaufgang und Sonnenuntergang sind im Hero-Bereich sichtbar

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. JSON Schema & Grabber Migration | 3/3 | Complete   | 2026-03-12 |
| 2. Delivery Layer Migration | 0/1 | Planning complete | - |
| 3. CGI JSON Endpoint | 0/TBD | Not started | - |
| 4. ocean-live Theme Grundgerust | 0/TBD | Not started | - |
| 5. Datenanbindung & Vollstandigkeit | 0/TBD | Not started | - |
