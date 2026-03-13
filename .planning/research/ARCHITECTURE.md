# Architecture Research

**Domain:** JSON-basiertes Wetter-Plugin mit AJAX Theme
**Researched:** 2026-03-12
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     External Weather APIs                     │
│  (OpenWeather, VisualCrossing, WeatherFlow, WetterOnline...) │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTP/JSON
┌──────────────────────────▼──────────────────────────────────┐
│                    Grabber Layer (Perl)                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │ OWM      │  │ VisCross │  │ WttrIn   │  │ ...      │     │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘     │
│       └──────────────┴──────────────┴──────────────┘          │
│                           │                                   │
│                    ┌──────▼──────┐                             │
│                    │ JSON Writer │  (NEU: statt .dat)          │
│                    └──────┬──────┘                             │
└───────────────────────────┼──────────────────────────────────┘
                            │ current.json / hourly.json / daily.json
┌───────────────────────────▼──────────────────────────────────┐
│                     $LBPLOGDIR (RAM-Disk)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ current.json │  │ hourly.json  │  │ daily.json   │        │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │
│         │                 │                  │                │
│    ┌────┴─────────────────┴──────────────────┘                │
│    │                                                          │
│    ▼                                    ▼                     │
│  ┌─────────────────┐         ┌──────────────────────┐        │
│  │ datatoloxone.pl │         │ CGI JSON Endpoint    │        │
│  │ (Delivery)      │         │ (show.cgi / ajax)    │        │
│  └────────┬────────┘         └──────────┬───────────┘        │
│           │                             │                    │
└───────────┼─────────────────────────────┼────────────────────┘
            │                             │
     ┌──────▼──────┐              ┌───────▼────────┐
     │ UDP / MQTT  │              │ Browser (AJAX) │
     │ → Loxone    │              │ ocean-live.html│
     └─────────────┘              └────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Grabber Scripts | API-Aufruf, JSON-Parsing, normalisiertes JSON schreiben | grabber_*.pl — schreiben jetzt JSON statt .dat |
| JSON Writer | Atomares Schreiben der JSON-Dateien auf RAM-Disk | LoxBerry::JSON mit .tmp + rename Pattern |
| datatoloxone.pl | JSON lesen, Einheiten konvertieren, UDP/MQTT senden | Perl — liest JSON statt .dat, sonst gleiche Logik |
| CGI JSON Endpoint | JSON-Dateien via HTTP bereitstellen | show.cgi oder neuer Endpunkt — Content-Type: application/json |
| ocean-live.html | Wetterdaten per Fetch laden, Hero-UI rendern | Einzelne HTML-Datei mit eingebettetem CSS/JS |
| lang-*.json | Übersetzungen für alle UI-Texte | Bestehendes Format, per Fetch geladen |

## Recommended Project Structure

```
webfrontend/
├── html/
│   ├── ocean-live.html       # Neues Theme (einzelne Datei)
│   ├── lang-de.json          # Sprachdateien (bestehend)
│   ├── lang-en.json
│   ├── lang-es.json
│   ├── lang-nl.json
│   ├── lang-sk.json
│   └── icons/                # Icon-Sets (bestehend)
│       └── {iconset}/
│           └── icon_mapping.json
├── htmlauth/
│   ├── index.cgi             # Admin UI (bestehend)
│   ├── show.cgi              # Display CGI (erweitert für JSON)
│   └── ajax-handler.cgi      # AJAX Handler (bestehend)

data/
├── current.json.schema       # JSON Schema Dokumentation
├── hourly.json.schema
├── daily.json.schema
├── current.format            # Alt — bleibt für Kompatibilität
├── hourlyforecast.format
└── dailyforecast.format

bin/
├── grabber_*.pl              # Modifiziert: schreiben JSON + .dat
├── datatoloxone.pl           # Modifiziert: liest JSON
└── fetch.pl                  # Unverändert
```

### Structure Rationale

- **ocean-live.html in webfrontend/html/:** Direkter Zugriff ohne CGI-Rendering, neben den Sprach-JSONs
- **JSON-Schemas in data/:** Neben den bestehenden .format-Dateien, dokumentiert das neue Format
- **Grabber bleiben in bin/:** Gleiche Ablage, nur Output-Format ändert sich

## Architectural Patterns

### Pattern 1: Dual-Output Grabber

**What:** Grabber schreiben sowohl JSON als auch .dat (Parallelphase)
**When to use:** Während der Migration, bis altes System entfernt wird
**Trade-offs:** Doppelter I/O, aber risikofreie Migration

**Example:**
```perl
# Am Ende jedes Grabbers:
# 1. Altes Format (bleibt)
write_dat_file("$lbplogdir/current.dat", @fields);

# 2. Neues Format (zusätzlich)
my $json = encode_json(\%weather_data);
write_json_file("$lbplogdir/current.json", $json);
```

### Pattern 2: CGI JSON Proxy

**What:** show.cgi liest JSON-Datei und liefert sie mit korrektem Content-Type aus
**When to use:** Wenn der Browser nicht direkt auf $LBPLOGDIR zugreifen kann
**Trade-offs:** Ein CGI-Aufruf pro Datenabfrage, aber sicher und kontrolliert

**Example:**
```perl
# show.cgi?format=json&type=current
print "Content-Type: application/json; charset=utf-8\n\n";
open(my $fh, '<', "$lbplogdir/current.json");
print <$fh>;
```

### Pattern 3: Client-Side Rendering mit Fetch

**What:** Browser lädt JSON per Fetch, rendert DOM mit JavaScript
**When to use:** Im ocean-live Theme für alle Wetterdaten
**Trade-offs:** Braucht JS im Browser, aber dynamisch und kein Server-Rendering nötig

## Data Flow

### Neuer JSON Data Flow

```
[Cron] → [fetch.pl] → [grabber_*.pl]
                           │
                     ┌─────▼─────┐
                     │ API Call   │
                     └─────┬─────┘
                           │
                    ┌──────▼──────┐
                    │ Parse JSON  │
                    │ Response    │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        current.json  hourly.json  daily.json
        current.dat   hourly.dat   daily.dat  (parallel)
              │            │            │
              └────────────┼────────────┘
                           │
                    ┌──────▼──────┐
                    │datatoloxone │──→ UDP/MQTT → Loxone
                    └─────────────┘
```

### AJAX Theme Data Flow

```
[Browser]
    │
    ├── fetch("show.cgi?format=json&type=current")
    │       → current.json → Hero-Bereich aktualisieren
    │
    ├── fetch("show.cgi?format=json&type=hourly")
    │       → hourly.json → Stundenleiste + Hero (Heute/Morgen)
    │
    ├── fetch("show.cgi?format=json&type=daily")
    │       → daily.json → Tage-Tab aktualisieren
    │
    └── fetch("lang-de.json")
            → Übersetzungen → UI-Texte setzen
```

### Key Data Flows

1. **Grabber → JSON:** Jeder Grabber normalisiert API-Daten in ein einheitliches JSON-Schema und schreibt atomar auf RAM-Disk
2. **JSON → Browser:** show.cgi dient als Proxy, setzt korrekte Headers (Content-Type, Cache-Control, CORS)
3. **JSON → Loxone:** datatoloxone.pl liest JSON, extrahiert Werte, sendet via UDP/MQTT

## Anti-Patterns

### Anti-Pattern 1: Direkter Dateizugriff vom Browser

**What people do:** Browser greift direkt auf /tmp/lbplog/weather4lox/current.json zu
**Why it's wrong:** RAM-Disk ist nicht über Apache erreichbar, Sicherheitsrisiko
**Do this instead:** CGI-Endpunkt als Proxy nutzen (show.cgi)

### Anti-Pattern 2: Unterschiedliche JSON-Schemas pro Grabber

**What people do:** Jeder Grabber hat sein eigenes JSON-Format
**Why it's wrong:** Theme muss pro Grabber unterschiedlichen Code haben
**Do this instead:** Einheitliches JSON-Schema, alle Grabber normalisieren darauf

### Anti-Pattern 3: Sprach-Strings im JavaScript hardcoden

**What people do:** Deutsche Texte direkt im JS Code
**Why it's wrong:** Bricht Mehrsprachigkeit
**Do this instead:** Alle UI-Texte aus lang-*.json laden

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Weather APIs | HTTP GET → JSON Parse → Normalize → Write JSON | Bestehend, Output-Format ändert sich |
| Loxone Miniserver | datatoloxone.pl → UDP/MQTT | Unverändert, liest nur JSON statt .dat |
| LoxBerry Apache | CGI-Proxy für JSON-Dateien | Neuer Endpunkt in show.cgi |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Grabber ↔ JSON-Dateien | File I/O (atomar) | JSON statt pipe-delimited |
| JSON-Dateien ↔ datatoloxone | File I/O (lesen) | Neues Parse-Format |
| show.cgi ↔ Browser | HTTP/JSON | Neuer JSON-Endpunkt |
| ocean-live ↔ lang-*.json | HTTP Fetch | Bestehende Dateien, neuer Zugriffspfad |

## Sources

- Bestehende Codebase-Architektur (.planning/codebase/ARCHITECTURE.md)
- LoxBerry Plugin-Dokumentation — CGI, Pfadvariablen, Apache-Konfiguration
- Bestehende Grabber-Implementierungen — Pattern für atomares Schreiben

---
*Architecture research for: Weather4Lox JSON Modernisierung*
*Researched: 2026-03-12*
