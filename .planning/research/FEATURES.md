# Feature Research

**Domain:** Wetter-Dashboard Theme mit Hero-Stundenansicht
**Researched:** 2026-03-12
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Aktuelle Temperatur prominent anzeigen | Grundfunktion jedes Wetter-Widgets | LOW | Hero-Bereich |
| Wetter-Icon passend zum Zustand | Visuelle Soforterfassung | LOW | Icon-Mapping JSON existiert |
| Luftfeuchtigkeit, Wind, Druck | Standard-Wetterdaten die jeder erwartet | LOW | Aus current.json |
| Stündliche Vorhersage scrollbar | Nutzer wollen stundengenau planen | MEDIUM | Horizontale Stundenleiste |
| 7-Tage-Vorhersage | Standard für Wetter-Apps | LOW | Tage-Tab |
| Hoch/Tief-Temperaturen pro Tag | Grundinfo für Tagesplanung | LOW | Aus daily.json |
| Niederschlagswahrscheinlichkeit | Entscheidend für "Brauche ich Regenschirm?" | LOW | PoP-Wert anzeigen |
| Responsive Layout | Funktioniert in verschiedenen iframe-Größen | MEDIUM | LoxBerry Widget-Kontext |
| Mehrsprachigkeit | Plugin unterstützt 5+ Sprachen | MEDIUM | lang-*.json existiert bereits |
| Wetter-Beschreibungstext | "Bedeckt", "Leichter Regen" etc. | LOW | Aus lang-*.json Weather Codes |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Hero-Stundenansicht mit Auswahl | Klick auf Stunde zeigt Details groß | MEDIUM | Kernfeature von ocean-live |
| Smooth Tab-Übergänge | Professionelles Gefühl | LOW | CSS Transitions |
| Dynamisches Nachladen ohne Reload | Daten aktualisieren sich automatisch | MEDIUM | AJAX Fetch mit Interval |
| Sonnenauf-/untergang Anzeige | Nützlich für Tagesplanung | LOW | Daten in current.json verfügbar |
| Mondphase | Interessant für Gartenarbeit/Hobby | LOW | Daten vorhanden |
| UV-Index | Gesundheitsrelevant | LOW | Falls in Wetterdaten vorhanden |
| Windrichtung visuell (Kompass) | Bessere Erfassung als Text | MEDIUM | SVG/CSS Animation |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Echtzeit-Radar-Karte eingebettet | Sieht beeindruckend aus | Hoher Traffic, externe API-Abhängigkeit, iframe-Probleme | Link zu Radar-Seite, separater Map-Tab |
| Animierte Wetter-Hintergründe | Visuell ansprechend | Performance-Problem auf Raspberry Pi, lenkt ab | Subtile CSS-Farbverläufe je nach Wetter |
| Push-Benachrichtigungen | Unwetter-Warnung | Braucht Service Worker, Notification API, Server-Logik | Farbige Warnanzeige im Widget |
| Historische Daten/Graphen | Trends erkennen | Braucht Datenbank, Chart-Library, viel Speicher | Nur aktuelle + Vorhersage |

## Feature Dependencies

```
[JSON-Datenformat]
    └──requires──> [Grabber JSON-Output]
                       └──requires──> [JSON Schema Definition]

[Hero-Stundenansicht] ──requires──> [JSON-Datenformat]
                      ──requires──> [AJAX Fetch]

[Heute/Morgen Tabs] ──requires──> [Stundendaten in JSON]
                    ──requires──> [Tab-Navigation UI]

[Tage-Tab] ──requires──> [Tagesdaten in JSON]

[Mehrsprachigkeit] ──requires──> [lang-*.json Laden per AJAX]
```

### Dependency Notes

- **Hero-Ansicht requires JSON-Format:** Ohne JSON-Daten kann das Theme nichts per AJAX laden
- **Tabs require Stundendaten:** Heute/Morgen-Tabs brauchen stündliche Vorhersagedaten getrennt nach Tag
- **Mehrsprachigkeit requires AJAX:** Sprach-JSON muss vor dem Rendern geladen sein

## MVP Definition

### Launch With (v1)

- [ ] JSON-Output aus Grabbern (current, hourly, daily) — Grundlage für alles
- [ ] ocean-live Theme mit 3 Tabs (Heute/Morgen/Tage) — Kernfunktion
- [ ] Hero-Bereich mit Stundenleiste — Hauptunterscheidungsmerkmal
- [ ] AJAX-basiertes Datenladen — Architektur-Entscheidung
- [ ] Mehrsprachigkeit via lang-*.json — alle bestehenden Sprachen
- [ ] Responsive Layout — verschiedene Widget-Größen
- [ ] datatoloxone.pl JSON-Unterstützung — Delivery-Layer muss JSON lesen

### Add After Validation (v1.x)

- [ ] Auto-Refresh der Daten (z.B. alle 5 Min) — wenn Grundsystem stabil
- [ ] Windrichtungs-Kompass — visuelles Extra
- [ ] Smooth Scroll-Animationen — Polish

### Future Consideration (v2+)

- [ ] Weitere Themes im neuen JSON-basierten System — wenn ocean-live bewährt
- [ ] Entfernung des alten .dat-Systems — nach Testphase
- [ ] Wetter-Warnungen visuell hervorheben — braucht Warndaten

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| JSON-Output Grabber | HIGH | MEDIUM | P1 |
| Hero-Stundenansicht | HIGH | MEDIUM | P1 |
| Tab-Navigation (Heute/Morgen/Tage) | HIGH | LOW | P1 |
| AJAX Datenladen | HIGH | LOW | P1 |
| Mehrsprachigkeit | HIGH | LOW | P1 |
| datatoloxone.pl JSON-Support | HIGH | MEDIUM | P1 |
| Responsive Layout | MEDIUM | MEDIUM | P1 |
| Auto-Refresh | MEDIUM | LOW | P2 |
| Windrichtungs-Kompass | LOW | MEDIUM | P3 |
| Animationen/Transitions | LOW | LOW | P2 |

## Competitor Feature Analysis

| Feature | Fresh Theme | Ocean Theme | ocean-live (Unser Ansatz) |
|---------|-------------|-------------|---------------------------|
| Datenquelle | JS direkt, Perl-Variablen | Server-Side Rendering | AJAX Fetch JSON |
| Navigation | Tab-Buttons | Integrierte Sections | 3 Tabs: Heute/Morgen/Tage |
| Stundenansicht | Liste | Horizontale Karten | Hero + Stundenleiste |
| Visuelles Design | Modern/Clean | Aufwendig/Dunkel | Ocean-Look mit Hero |
| Sprachen | Alle | Nur DE | Alle via JSON |
| Dateiablage | templates/ | templates/ | webfrontend/ |

## Sources

- Analyse bestehender Themes: fresh.main.html, ocean.main.html
- Analyse bestehender Datenformate: data/*.format
- Analyse bestehender Sprach-JSONs: webfrontend/html/lang-*.json

---
*Feature research for: Weather4Lox ocean-live Theme*
*Researched: 2026-03-12*
