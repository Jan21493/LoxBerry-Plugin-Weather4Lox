---
phase: 4
slug: ocean-live-theme-grundgerust
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual browser testing (no automated framework — pure HTML/CSS/JS) |
| **Config file** | none |
| **Quick run command** | `test -f webfrontend/html/ocean-live.html && echo OK` |
| **Full suite command** | Open `webfrontend/html/ocean-live.html` in browser, verify all 5 success criteria |
| **Estimated runtime** | ~2 seconds (smoke) / ~3 minutes (manual full) |

---

## Sampling Rate

- **After every task commit:** Run `test -f webfrontend/html/ocean-live.html && echo OK`
- **After every plan wave:** Open file in browser, verify all success criteria visually
- **Before `/gsd:verify-work`:** Full manual suite must be green
- **Max feedback latency:** 2 seconds (smoke)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | THEME-01 | smoke | `test -f webfrontend/html/ocean-live.html && echo OK` | Wave 0 | ⬜ pending |
| 4-01-02 | 01 | 1 | THEME-04 | manual | Visual comparison with ocean.main.html | Wave 0 | ⬜ pending |
| 4-01-03 | 01 | 1 | THEME-02 | manual | Browser: verify 3 tab buttons visible | Wave 0 | ⬜ pending |
| 4-01-04 | 01 | 1 | THEME-03, EXTRA-02 | manual | Browser: click tabs, verify CSS fade transition | Wave 0 | ⬜ pending |
| 4-01-05 | 01 | 1 | HERO-01 | manual | Browser: verify hero shows temp, icon, desc, wind, humidity | Wave 0 | ⬜ pending |
| 4-01-06 | 01 | 1 | HERO-02 | manual | Browser: verify horizontal hour strip scrolls | Wave 0 | ⬜ pending |
| 4-01-07 | 01 | 1 | HERO-03 | manual | Browser: click 3 hours, verify hero updates | Wave 0 | ⬜ pending |
| 4-01-08 | 01 | 1 | HERO-04 | manual | Browser: Heute tab shows today's hours | Wave 0 | ⬜ pending |
| 4-01-09 | 01 | 1 | HERO-05 | manual | Browser: Morgen tab shows tomorrow's hours | Wave 0 | ⬜ pending |
| 4-01-10 | 01 | 1 | HERO-06 | manual | Browser: tab switch pre-selects correct hour | Wave 0 | ⬜ pending |
| 4-01-11 | 01 | 1 | TAGE-01 | manual | Browser: Tage tab shows 7 days | Wave 0 | ⬜ pending |
| 4-01-12 | 01 | 1 | TAGE-02 | manual | Browser: each day row has icon, high/low, PoP | Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `webfrontend/html/ocean-live.html` — target file (created during phase execution)
- Existing infrastructure covers all phase requirements (no test framework needed — manual browser verification)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 3 Tab-Buttons sichtbar | THEME-02 | Visual UI check | Open file, verify Heute/Morgen/Tage buttons |
| Tab-Wechsel mit CSS-Transition | THEME-03, EXTRA-02 | Animation timing | Click each tab, observe fade transition |
| Ocean-Design Farbschema | THEME-04 | Visual comparison | Compare with ocean.main.html side-by-side |
| Hero zeigt 5 Felder | HERO-01 | Layout verification | Check temp, icon, desc, wind, humidity visible |
| Stundenleiste scrollbar | HERO-02 | Interaction test | Mouse drag / scroll horizontal strip |
| Stunden-Klick aktualisiert Hero | HERO-03 | Interaction + visual | Click 3 different hours, verify hero updates |
| Heute-Tab Stunden korrekt | HERO-04 | Data correctness | Verify hour labels match "today" |
| Morgen-Tab Stunden korrekt | HERO-05 | Data correctness | Verify hour labels match "tomorrow" |
| Preselection bei Tab-Wechsel | HERO-06 | State management | Switch tabs, verify hero shows correct hour |
| 7-Tage-Uebersicht | TAGE-01 | Count verification | Count rows in Tage tab = 7 |
| Pro-Tag Details | TAGE-02 | Layout verification | Each row: icon, high, low, PoP |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 3s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
