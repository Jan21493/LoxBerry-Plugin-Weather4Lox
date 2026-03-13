---
phase: 5
slug: datenanbindung-vollstaendigkeit
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Keine automatisierten Tests (Frontend-HTML, konsistent mit Phase 4) |
| **Config file** | none |
| **Quick run command** | `test -f webfrontend/html/ocean-live.html && echo "File exists"` |
| **Full suite command** | Browser-seitige manuelle Prufung aller 5 Success Criteria |
| **Estimated runtime** | ~2 seconds (file check) / ~5 minutes (manual browser) |

---

## Sampling Rate

- **After every task commit:** Run `test -f webfrontend/html/ocean-live.html && echo OK`
- **After every plan wave:** Browser-Prufung: Fetch-Calls im Netzwerk-Tab sichtbar, Icons korrekt, Sprache umschaltbar
- **Before `/gsd:verify-work`:** Full suite must be green — alle 5 Success Criteria manuell bestatigt
- **Max feedback latency:** 2 seconds (file check)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | DATA-01 | manual | Browser Netzwerk-Tab: GET show.cgi?format=json&type=current | ✅ | ⬜ pending |
| 05-01-02 | 01 | 1 | DATA-02 | manual | `?lang=en` — "Today"/"Tomorrow"/"Days" sichtbar | ✅ | ⬜ pending |
| 05-01-03 | 01 | 1 | DATA-03 | manual | Netzwerk-Tab: GET icon_mapping.json; Icons sichtbar | ✅ | ⬜ pending |
| 05-01-04 | 01 | 1 | DATA-04 | manual | console.log Timestamps uber 10+ min beobachten | ✅ | ⬜ pending |
| 05-01-05 | 01 | 1 | DATA-05 | manual | DevTools Throttling: Spinner sichtbar | ✅ | ⬜ pending |
| 05-01-06 | 01 | 1 | DATA-06 | manual | show.cgi URL ungultig setzen; Error-Banner erscheint | ✅ | ⬜ pending |
| 05-01-07 | 01 | 1 | LANG-01 | manual | `?lang=en`: alle Labels in Englisch | ✅ | ⬜ pending |
| 05-01-08 | 01 | 1 | LANG-02 | manual | Alle 5 `?lang=XX` URLs testen | ✅ | ⬜ pending |
| 05-01-09 | 01 | 1 | LANG-03 | manual | `?lang=en`, `?lang=de` URL-Parameter | ✅ | ⬜ pending |
| 05-01-10 | 01 | 1 | EXTRA-01 | manual | Hero: Sunrise/Sunset Zeiten aus echten Daten | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Neue lang-Keys (`theme.tab_today`, `theme.tab_tomorrow` etc.) in allen 5 lang-*.json erganzen
- [ ] DOM-IDs fur sunrise/sunset in ocean-live.html (`heroSunrise`, `heroSunset`)
- [ ] DOM-IDs fur loading-overlay und error-banner HTML in ocean-live.html
- [ ] show.cgi CGI-Pfad in Entwicklungsumgebung verifizieren und dokumentieren

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Fetch-Call beim Offnen | DATA-01 | Browser-native Fetch; kein Node.js-Testrunner | Netzwerk-Tab prufen |
| Sprachstrings geladen | DATA-02, LANG-01 | DOM-Text Vergleich | `?lang=en` offnen, Labels prüfen |
| Icon-Auflosung | DATA-03 | Visuelle Prufung | Icons im Theme sichtbar |
| Auto-Refresh 5 min | DATA-04 | Timing-Verhalten | Console-Logs uber 10+ min |
| Loading-Spinner | DATA-05 | Visuelle Prufung | DevTools Throttling |
| Fehlermeldung | DATA-06 | Fehler-Szenario | URL auf ungultig setzen |
| 5 Sprachen | LANG-02 | Multi-Language | Alle 5 `?lang=XX` testen |
| URL-Parameter Sprache | LANG-03 | URL-Handling | `?lang=de` vs `?lang=en` |
| Sunrise/Sunset | EXTRA-01 | Visuelle Prufung | Hero-Bereich inspizieren |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
