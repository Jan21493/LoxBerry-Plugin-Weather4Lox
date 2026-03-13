# Weather4Lox Modernisierung

## What This Is

Modernisierung des LoxBerry Weather4Lox Plugins: Umstellung von pipe-delimierten .dat-Dateien auf JSON als Datenaustauschformat zwischen Grabbern, Delivery-Layer und Web-Frontend. Neues Theme "ocean-live" im Ocean-Design mit Hero-Stundenansicht und AJAX-basiertem Datenladen, abgelegt im webfrontend/ statt in templates/.

## Core Value

Wetterdaten werden als strukturiertes JSON bereitgestellt und das neue ocean-live Theme zeigt sie dynamisch per AJAX mit einer Hero-Ansicht der ausgewählten Stunde an.

## Requirements

### Validated

- ✓ Multi-Source Wetterdaten-Aggregation (OpenWeather, VisualCrossing, WeatherFlow, WetterOnline, wttr.in etc.) — existing
- ✓ Cron-basierte automatische Datenabholung mit konfigurierbaren Intervallen — existing
- ✓ UDP/MQTT Delivery an Loxone Miniserver — existing
- ✓ Admin-UI zur Plugin-Konfiguration (index.cgi) — existing
- ✓ Mehrsprachigkeit (DE, EN, ES, NL, SK, AT) — existing
- ✓ Mehrere Icon-Sets mit JSON-Mapping — existing
- ✓ Cloud-Emulator für Loxone weather.loxone.com — existing
- ✓ Metrisch/Imperial Einheitenkonvertierung — existing

### Active

- [ ] Grabber schreiben JSON statt .dat (current.json, hourly.json, daily.json)
- [ ] Sprach-Daten ausschließlich über bestehende lang-*.json Dateien
- [ ] Neues Theme "ocean-live" im webfrontend/ (nicht templates/)
- [ ] Ocean-Design mit Hero-Bereich für ausgewählte Stunde
- [ ] Stundenleiste zur Auswahl der angezeigten Stunde
- [ ] 3 Tabs: Heute | Morgen | Tage
- [ ] Heute-Tab: Stundenwerte des heutigen Tages mit Hero + Stundenleiste
- [ ] Morgen-Tab: Stundenwerte des morgigen Tages mit Hero + Stundenleiste
- [ ] Tage-Tab: 7-Tage-Vorhersage Übersicht
- [ ] AJAX/Fetch zum Laden der JSON-Wetterdaten im Browser
- [ ] Alle Sprachen unterstützt via lang-*.json
- [ ] Einzelne HTML-Datei pro Theme (wie bisheriges Ocean/Fresh-Pattern)
- [ ] datatoloxone.pl liest JSON statt .dat

### Out of Scope

- Entfernung des alten .dat-Systems — erst nach erfolgreicher Testphase des neuen JSON-Systems
- Entfernung der alten Themes (dark, light, fresh, ocean) — parallel betreiben, später entfernen
- Neue Wetterdienst-Integrationen — bestehende Grabber werden nur auf JSON-Output umgestellt
- Mobile App — Web-Frontend only

## Context

- LoxBerry Plugin-Architektur: Perl-basiert, nutzt LoxBerry::System, LoxBerry::Log, LoxBerry::JSON, LoxBerry::IO
- Bestehende Grabber schreiben pipe-delimited .dat-Dateien (42 Felder current, 40 daily, 36 hourly)
- Datenformat dokumentiert in data/*.format Dateien
- Aktuelle Themes: dark, light, fresh (alle Sprachen), ocean (nur DE), arctic (nur DE)
- Fresh-Theme bindet Daten per JavaScript direkt ein — das Muster für ocean-live
- Ocean-Theme hat aufwendiges visuelles Design — der Look für ocean-live
- Sprach-JSON-Dateien existieren bereits: webfrontend/html/lang-{de,en,es,nl,sk}.json
- show.cgi rendert aktuell serverseitig mit <!--$varname--> Platzhaltern — ocean-live nutzt stattdessen AJAX
- RAM-Disk basiertes Datensystem: $LBPLOGDIR für aktive Daten, $LBPDATA für Persistenz

## Constraints

- **Tech Stack**: Perl für Backend/Grabber (LoxBerry-Ökosystem), HTML/CSS/JS für Frontend — keine externen Build-Tools
- **Kompatibilität**: Altes .dat-System muss parallel lauffähig bleiben bis Testphase abgeschlossen
- **LoxBerry Framework**: Alle Pfade über LoxBerry-Variablen ($lbpbindir, $lbplogdir, etc.)
- **Delivery-Layer**: datatoloxone.pl muss weiterhin UDP/MQTT an Loxone senden können
- **Einzeldatei-Theme**: ocean-live als eine HTML-Datei (mit eingebettetem CSS/JS)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| JSON statt .dat | Strukturiertes Format, direkt im Browser nutzbar, keine Position-Indizes nötig | — Pending |
| AJAX statt Server-Side Rendering | Dynamisches Laden ohne Page-Reload, entkoppelt Theme von CGI | — Pending |
| Theme im webfrontend/ statt templates/ | Direkter Zugriff auf JSON-Daten ohne CGI-Umweg | — Pending |
| Ocean-Design als Basis | Visuell ansprechendes Design des bestehenden Ocean-Themes | — Pending |
| Hero + Stundenleiste Pattern | Ausgewählte Stunde groß anzeigen, Stunden-Strip zur Navigation | — Pending |
| Parallelbetrieb alt/neu | Risikominimierung, altes System als Fallback | — Pending |

---
*Last updated: 2026-03-12 after initialization*
