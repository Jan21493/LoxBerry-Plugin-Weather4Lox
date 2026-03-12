---
phase: 1
slug: json-schema-grabber-migration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual shell testing + perl -cw syntax checks (no automated test framework in project) |
| **Config file** | none |
| **Quick run command** | `perl -cw bin/grabber_utils.pl` |
| **Full suite command** | `for f in bin/grabber_*.pl; do perl -cw "$f"; done` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `perl -cw bin/grabber_utils.pl`
- **After every plan wave:** Run `for f in bin/grabber_*.pl; do perl -cw "$f"; done`
- **Before `/gsd:verify-work`:** Full syntax check must pass + manual grabber run on device
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | JSON-01 | manual | `test -f data/json-schema.md` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | JSON-02, JSON-03 | syntax | `perl -cw bin/grabber_utils.pl` | ✅ | ⬜ pending |
| 01-02-02 | 02 | 1 | JSON-04 | code review | `grep 'utf8' bin/grabber_utils.pl` | ✅ | ⬜ pending |
| 01-03-01 | 03 | 2 | JSON-02 | syntax | `perl -cw bin/grabber_openweather.pl` | ✅ | ⬜ pending |
| 01-03-02 | 03 | 2 | JSON-02 | syntax | `perl -cw bin/grabber_visualcrossing.pl` | ✅ | ⬜ pending |
| 01-03-03 | 03 | 2 | JSON-02 | syntax | `perl -cw bin/grabber_weatherflow.pl` | ✅ | ⬜ pending |
| 01-03-04 | 03 | 2 | JSON-02 | syntax | `perl -cw bin/grabber_wetteronline.pl` | ✅ | ⬜ pending |
| 01-03-05 | 03 | 2 | JSON-02 | syntax | `perl -cw bin/grabber_wttrin.pl` | ✅ | ⬜ pending |
| 01-04-01 | 04 | 2 | JSON-06 | syntax | `perl -cw bin/grabber_wu.pl` | ✅ | ⬜ pending |
| 01-04-02 | 04 | 2 | JSON-06 | syntax | `perl -cw bin/grabber_foshk.pl` | ✅ | ⬜ pending |
| 01-04-03 | 04 | 2 | JSON-06 | syntax | `perl -cw bin/grabber_pwscatchupload.pl` | ✅ | ⬜ pending |
| 01-04-04 | 04 | 2 | JSON-06 | syntax | `perl -cw bin/grabber_loxone.pl` | ✅ | ⬜ pending |
| 01-04-05 | 04 | 2 | JSON-06 | syntax | `perl -cw bin/grabber_openmeteo_airquality.pl` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `data/json-schema.md` — schema documentation (JSON-01)

*No test framework to install — Perl syntax checks are the only automatable gate. LoxBerry is an embedded Raspberry Pi system; full integration tests require device access.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| JSON files created on RAM-disk after grabber run | JSON-02 | Requires LoxBerry device with configured API keys | Run grabber, check `$lbplogdir/current.json` exists |
| UTF-8 umlauts correct (ä, ö, ü, ß) | JSON-04 | Requires live weather data with German city names | `python3 -c "import json,sys; d=json.load(open('current.json')); print(d)"` |
| Decimal points not commas | JSON-05 | Requires live numeric weather data | Inspect JSON output for numeric fields |
| .dat files unchanged after dual-write | JSON-02 | Requires before/after diff on device | `md5sum current.dat` before and after grabber run |
| AQ fields populated by OpenMeteo AQ | JSON-06 | Requires OpenMeteo API access | Run AQ grabber, inspect `current.json` for aqi/pollen fields |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
