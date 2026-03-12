# Pitfalls Research

**Domain:** Perl Weather Plugin — .dat → JSON Migration + AJAX Theme
**Researched:** 2026-03-12
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Bestehende .dat-Konsumenten brechen still

**What goes wrong:**
datatoloxone.pl, show.cgi und andere Skripte lesen .dat-Dateien. Wenn Grabber nur noch JSON schreiben, fallen UDP/MQTT-Delivery und alte Themes still aus — keine Fehlermeldung, einfach keine Daten.

**Why it happens:**
Man vergisst, dass die .dat-Dateien nicht nur vom Frontend gelesen werden, sondern auch vom Delivery-Layer (Loxone Miniserver-Anbindung).

**How to avoid:**
Dual-Write: Grabber schreiben BEIDE Formate parallel. Erst wenn datatoloxone.pl auf JSON umgestellt ist UND getestet, können .dat-Dateien entfallen.

**Warning signs:**
Loxone Miniserver zeigt plötzlich "0" oder alte Werte an. Keine aktuellen Wetterdaten.

**Phase to address:**
Phase 1 (JSON-Format) — Dual-Write von Anfang an implementieren.

---

### Pitfall 2: UTF-8 Encoding-Mismatch zwischen Perl und JavaScript

**What goes wrong:**
Perl-Grabber schreiben JSON mit deutschen Umlauten (ä, ö, ü, ß). Wenn das Encoding nicht konsistent UTF-8 ist, zeigt der Browser "Ã¤" statt "ä" oder JSON.parse() schlägt fehl.

**Why it happens:**
Perl hat komplexes internes Encoding (UTF-8 Flag). `encode_json()` erwartet decoded Perl-Strings, gibt UTF-8 Bytes aus. Wenn der Input bereits UTF-8-Bytes sind, wird doppelt encoded.

**How to avoid:**
- In Grabbern: `use utf8;` und `binmode` korrekt setzen
- JSON-Dateien mit UTF-8 BOM oder explizitem `charset=utf-8` Header ausliefern
- Im CGI: `Content-Type: application/json; charset=utf-8`
- Frühzeitig mit Umlauten testen ("Bewölkt", "Südwest", "Gewitter")

**Warning signs:**
Kaputte Sonderzeichen in der Browser-Konsole, JSON.parse() Fehler.

**Phase to address:**
Phase 1 (JSON-Format) — Encoding-Tests mit Umlaut-Wörtern als Teil der Validierung.

---

### Pitfall 3: CGI Content-Type und Caching-Header fehlen

**What goes wrong:**
show.cgi liefert JSON-Daten, aber mit `text/html` Content-Type oder ohne Cache-Control. Browser cached alte Wetterdaten oder interpretiert JSON als HTML.

**Why it happens:**
Bestehender show.cgi gibt HTML aus. Neuer JSON-Endpunkt muss andere Header setzen.

**How to avoid:**
```perl
print "Content-Type: application/json; charset=utf-8\n";
print "Cache-Control: no-cache, must-revalidate\n";
print "Access-Control-Allow-Origin: *\n\n";
```

**Warning signs:**
Wetterdaten im Browser aktualisieren sich nicht. Browser zeigt gecachte Werte.

**Phase to address:**
Phase 2 (CGI-Anpassung) — Header-Tests als Verifikation.

---

### Pitfall 4: JSON-Schema Inkonsistenz zwischen Grabbern

**What goes wrong:**
Verschiedene Grabber erzeugen leicht unterschiedliche JSON-Strukturen (fehlende Felder, andere Feldnamen, andere Datentypen). Das Theme bricht bei bestimmten Wetterdiensten.

**Why it happens:**
Jeder Grabber wird einzeln angepasst. Ohne Schema-Definition gibt es keinen Vertrag.

**How to avoid:**
- JSON-Schema definieren BEVOR Grabber angepasst werden
- Validierung: Jeder Grabber prüft sein Output gegen das Schema
- Fehlende Felder mit Defaults füllen (null statt fehlen)

**Warning signs:**
Theme funktioniert mit OpenWeather aber nicht mit VisualCrossing. Undefined-Fehler in der Browser-Konsole.

**Phase to address:**
Phase 1 (JSON-Format) — Schema-Definition als erster Schritt.

---

### Pitfall 5: Raspberry Pi Performance bei CGI-Spawning

**What goes wrong:**
Jeder AJAX-Request spawnt einen CGI-Prozess auf dem Raspberry Pi. Bei 3 Datentypen + Sprach-JSON = 4 CGI-Aufrufe pro Seitenladung. Auto-Refresh alle 5 Minuten multipliziert das.

**Why it happens:**
CGI spawnt für jeden Request einen neuen Perl-Prozess. Auf dem Pi dauert das 200-500ms pro Aufruf.

**How to avoid:**
- Alle JSON-Daten in einem einzigen CGI-Aufruf bündeln (`show.cgi?format=json&type=all`)
- Oder: JSON-Dateien direkt über Apache ausliefern (Symlink von $LBPLOGDIR nach webfrontend/html/data/)
- Cache-Headers setzen, damit Browser nicht unnötig nachfragt

**Warning signs:**
Seite lädt langsam, Raspberry Pi CPU-Last steigt.

**Phase to address:**
Phase 2 (CGI-Anpassung) — gebündelten Endpunkt implementieren.

---

### Pitfall 6: Dezimaltrennzeichen in JSON

**What goes wrong:**
Perl mit deutschem Locale erzeugt "3,7" statt "3.7" für Dezimalzahlen. JSON erfordert Punkt als Dezimaltrennzeichen. JSON.parse() schlägt fehl.

**Why it happens:**
LoxBerry läuft oft mit `LANG=de_DE.UTF-8`. Perl's String-Interpolation nutzt dann Komma.

**How to avoid:**
- `use POSIX qw(setlocale LC_NUMERIC); setlocale(LC_NUMERIC, "C");` am Anfang jedes Grabbers
- Oder: Zahlen explizit als Perl-Nummern (nicht Strings) an encode_json übergeben
- Testen mit `LANG=de_DE.UTF-8`

**Warning signs:**
JSON.parse() Fehler, NaN-Werte im Theme.

**Phase to address:**
Phase 1 (JSON-Format) — Locale-Handling als Teil des JSON Writers.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Dual-Write .dat + JSON | Risikofreie Migration | Doppelter I/O, zwei Code-Pfade | Während Migration — muss entfernt werden |
| Inline CSS/JS in HTML | Eine Datei, einfach zu verteilen | Schwer zu cachen, große Datei | Akzeptabel für Einzeldatei-Theme |
| Hardcoded JSON-Pfade im Theme | Schnell implementiert | Bricht bei anderem LoxBerry-Setup | Nie — LoxBerry-Pfade dynamisch ermitteln |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| LoxBerry Apache | JSON-Dateien nicht über Apache erreichbar | show.cgi als Proxy oder Apache Alias konfigurieren |
| Icon-Mapping | Hardcoded Icon-Pfade statt icon_mapping.json | Icon-Mapping JSON laden, dynamisch auflösen |
| Sprach-JSONs | Nur DE testen | Von Anfang an mit EN und DE testen |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Zu häufiger Auto-Refresh | Pi CPU 100%, Seite laggt | Refresh-Interval ≥ Cron-Interval (5+ Min) | Bei < 1 Min Refresh |
| Ungecachte Sprach-JSONs | 50KB pro Seitenladung | Cache-Control Header, localStorage | Bei jedem Seitenaufruf |
| Große JSON-Dateien | Langsames Parsing | Nur benötigte Daten laden | Bei > 500KB JSON |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Keine Ladeanzeige bei AJAX | Nutzer sieht leere Seite | Loading-Spinner bis Daten da |
| Fehler bei Datenladen unsichtbar | Nutzer denkt Plugin ist kaputt | Fehlermeldung anzeigen "Daten konnten nicht geladen werden" |
| Zu viele Daten in der Stundenleiste | Unübersichtlich, kein Platz | Max 24h pro Tab, horizontal scrollbar |
| Kein visueller Unterschied Heute/Morgen | Nutzer verwechselt Tabs | Datum prominent im Hero anzeigen |

## "Looks Done But Isn't" Checklist

- [ ] **JSON-Output:** Alle Grabber getestet — nicht nur OpenWeather, auch VisualCrossing, wttr.in etc.
- [ ] **Encoding:** Test mit Umlauten ("Südwestwind", "Bewölkt", "Gewitter")
- [ ] **Leere Daten:** Was passiert wenn hourly.json noch nicht existiert? (Erster Start)
- [ ] **Icon-Mapping:** Alle Wetter-Codes haben ein Icon — nicht nur Sonne und Regen
- [ ] **Tage-Tab:** 7 Tage angezeigt — nicht nur 5 (manche APIs liefern weniger)
- [ ] **Sprachen:** EN und DE getestet — Texte nicht abgeschnitten
- [ ] **datatoloxone.pl:** UDP/MQTT Werte identisch zu vorher — Loxone-Konfiguration darf nicht brechen

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| .dat-Konsumenten brechen | LOW | Dual-Write aktivieren, .dat weiter schreiben |
| UTF-8 Encoding kaputt | LOW | `use utf8;` hinzufügen, binmode setzen |
| JSON-Schema inkonsistent | MEDIUM | Schema definieren, alle Grabber anpassen |
| CGI Performance | MEDIUM | Gebündelten Endpunkt implementieren |
| Locale Dezimaltrennzeichen | LOW | LC_NUMERIC auf "C" setzen |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| .dat-Konsumenten brechen | Phase 1 (JSON Format) | datatoloxone.pl liest JSON, Loxone erhält Werte |
| UTF-8 Encoding | Phase 1 (JSON Format) | Umlaut-Test in JSON-Dateien |
| CGI Headers | Phase 2 (CGI Endpoint) | Browser DevTools: Content-Type prüfen |
| Schema Inkonsistenz | Phase 1 (JSON Format) | Alle Grabber gegen Schema validieren |
| Pi Performance | Phase 2 (CGI Endpoint) | Response-Zeit messen |
| Dezimaltrennzeichen | Phase 1 (JSON Format) | JSON.parse() Test mit deutschen Locale |

## Sources

- Bestehender Codebase-Code: grabber_*.pl, datatoloxone.pl, show.cgi
- LoxBerry Plugin-Entwicklungsdokumentation
- Perl JSON Encoding Best Practices (perldoc JSON, perldoc Encode)

---
*Pitfalls research for: Weather4Lox JSON Modernisierung*
*Researched: 2026-03-12*
