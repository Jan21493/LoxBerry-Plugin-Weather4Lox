---
phase: 2
slug: delivery-layer-migration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — Perl script, no test harness |
| **Config file** | none |
| **Quick run command** | `perl -c bin/datatoloxone.pl` |
| **Full suite command** | Manual: run script with `--verbose`, inspect log output |
| **Estimated runtime** | ~2 seconds (syntax check) |

---

## Sampling Rate

- **After every task commit:** Run `perl -c bin/datatoloxone.pl`
- **After every plan wave:** Syntax check + manual diff of weatherdata.html output
- **Before `/gsd:verify-work`:** Full manual regression against live data (dual-write comparison)
- **Max feedback latency:** 2 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | JSON-07 | smoke | `perl -c bin/datatoloxone.pl` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | JSON-07 | smoke | Run script without JSON files, check exit code = 1 | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | JSON-08 | manual | Diff old vs new log output for send-names | manual-only | ⬜ pending |
| 02-01-04 | 01 | 1 | JSON-08 | manual | Run old+new scripts against dual-write data, diff logs | manual-only | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/smoke_datatoloxone.sh` — smoke test: syntax check + missing-JSON fail-fast
- [ ] No framework install needed — shell scripts + `perl -c` suffice

*Existing test infrastructure: none — manual testing is the established project approach*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| UDP/MQTT send-names unchanged | JSON-08 | Requires live LoxBerry + Miniserver | Run old script → capture log, run new script → capture log, diff send-names |
| UDP/MQTT values numerically identical | JSON-08 | Requires live grabber data (dual-write) | Compare values from both script versions against same data set |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
