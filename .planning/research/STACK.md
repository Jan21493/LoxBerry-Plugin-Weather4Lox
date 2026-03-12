# Stack Research

**Domain:** Perl-basiertes Wetter-Plugin — Migration .dat → JSON + AJAX Theme
**Researched:** 2026-03-12
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Perl JSON module | 4.x (CPAN) | JSON encode/decode in Grabbern | Bereits auf LoxBerry verfügbar via `LoxBerry::JSON`, nutzt `JSON` unter der Haube |
| LoxBerry::JSON | (LoxBerry built-in) | JSON Lesen/Schreiben mit Locking | Framework-konform, atomares Schreiben, File-Locking für Concurrent Access |
| Vanilla JavaScript (ES6+) | n/a | AJAX Fetch, DOM-Manipulation im Theme | Keine Build-Tools nötig, funktioniert direkt im Browser, kein Framework-Overhead |
| Fetch API | Browser-native | JSON-Wetterdaten laden | Modern, Promise-basiert, in allen aktuellen Browsern verfügbar |
| CSS Custom Properties | Browser-native | Theme-Styling, Farbvariablen | Erlaubt Ocean-Design ohne Preprocessor, dynamisch anpassbar |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| LoxBerry::IO | (built-in) | UDP/MQTT Delivery an Loxone | Unverändert — datatoloxone.pl nutzt dies weiterhin |
| LoxBerry::Log | (built-in) | Strukturiertes Logging | In allen Perl-Skripten für konsistentes Logging |
| LoxBerry::System | (built-in) | Pfadvariablen, Sprachsystem | Zugriff auf $lbplogdir, $lbpdatadir etc. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Browser DevTools | AJAX-Debugging, JSON-Inspektion | Network-Tab zum Prüfen der JSON-Responses |
| perl -MJSON -e | JSON-Validierung auf Kommandozeile | Schnelltest ob generiertes JSON valide ist |

## Installation

```bash
# Keine zusätzlichen Installationen nötig!
# LoxBerry bringt alle benötigten Perl-Module mit:
# - JSON (via LoxBerry::JSON)
# - LWP::UserAgent (bereits für Grabber)
# - File::Copy (für atomares Schreiben)

# Frontend: Vanilla JS/CSS — kein npm, kein Build-Tool
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Vanilla JS Fetch | jQuery AJAX | Nur wenn jQuery bereits geladen — aber für ocean-live nicht nötig |
| CSS Custom Properties | SASS/LESS | Nur wenn Build-Pipeline existiert — hier nicht der Fall |
| LoxBerry::JSON | JSON::XS | JSON::XS ist schneller, aber LoxBerry::JSON bietet File-Locking |
| Einzelne HTML-Datei | Web Components | Nur bei komplexen wiederverwendbaren Komponenten — hier Overkill |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| jQuery | Unnötiger Overhead für ein einzelnes Theme, 90KB+ | Vanilla JS Fetch + DOM API |
| React/Vue/Angular | Braucht Build-Pipeline, Overkill für Wetter-Widget | Vanilla JS mit Template Literals |
| SASS/LESS | Braucht Compiler, LoxBerry hat keinen Build-Step | CSS Custom Properties |
| WebSockets | Overkill — Wetterdaten ändern sich nur alle 5-15 Minuten | Fetch mit optionalem Auto-Refresh |
| IndexedDB/localStorage | Wetterdaten sind kurzlebig, kein Offline-Support nötig | Direkt aus JSON-Dateien laden |

## Stack Patterns by Variant

**Für JSON-Generierung in Grabbern:**
- Nutze `LoxBerry::JSON` für File-I/O mit Locking
- Schreibe erst in .tmp, dann rename (atomares Schreiben wie bei .dat)
- UTF-8 encoding explizit setzen (`encode_json` erzeugt UTF-8)

**Für AJAX im Theme:**
- Nutze native `fetch()` mit `Response.json()`
- Kein Polyfill nötig — LoxBerry-Nutzer haben aktuelle Browser
- Error-Handling mit `.catch()` für Netzwerkfehler

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| LoxBerry::JSON | Perl 5.20+ | Standard auf LoxBerry 3.x |
| Fetch API | Chrome 42+, Firefox 39+, Safari 10.1+ | Alle relevanten Browser |
| CSS Custom Properties | Chrome 49+, Firefox 31+, Safari 9.1+ | Kein IE-Support nötig |

## Sources

- LoxBerry Plugin-Entwicklungsdokumentation — Framework-Module und Conventions
- Bestehender Codebase-Code — grabber_*.pl Pattern, datatoloxone.pl Delivery
- MDN Web Docs — Fetch API, CSS Custom Properties Kompatibilität

---
*Stack research for: Weather4Lox JSON Modernisierung*
*Researched: 2026-03-12*
