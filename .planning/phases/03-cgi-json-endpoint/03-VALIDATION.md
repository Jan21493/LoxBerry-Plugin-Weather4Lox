---
phase: 3
slug: cgi-json-endpoint
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None installed — manual curl + Perl syntax check |
| **Config file** | none |
| **Quick run command** | `perl -c webfrontend/htmlauth/show.cgi` |
| **Full suite command** | `curl -v "http://loxberry/plugins/weather4lox/show.cgi?format=json&type=current"` |
| **Estimated runtime** | ~2 seconds (syntax check); manual curl requires live system |

---

## Sampling Rate

- **After every task commit:** Run `perl -c webfrontend/htmlauth/show.cgi`
- **After every plan wave:** Manual curl test on dev LoxBerry for all three types
- **Before `/gsd:verify-work`:** Full curl test for all three types + error cases must pass
- **Max feedback latency:** 2 seconds (syntax check)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | CGI-01 | smoke | `perl -c webfrontend/htmlauth/show.cgi` | ✅ | ⬜ pending |
| 03-01-02 | 01 | 1 | CGI-02 | smoke | `perl -c webfrontend/htmlauth/show.cgi` | ✅ | ⬜ pending |
| 03-01-03 | 01 | 1 | CGI-03 | smoke | `perl -c webfrontend/htmlauth/show.cgi` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `perl -c` syntax check is the only automated validation available in this environment

*Existing infrastructure covers automated syntax validation. Functional testing requires live LoxBerry system.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Content-Type: application/json; charset=utf-8 returned | CGI-01 | Requires live CGI execution with LoxBerry modules | `curl -v "http://loxberry/plugins/weather4lox/show.cgi?format=json&type=current"` — check Content-Type header |
| Cache-Control: no-cache header present | CGI-02 | Requires live CGI execution | `curl -v "http://loxberry/plugins/weather4lox/show.cgi?format=json&type=current"` — check Cache-Control header |
| type=current/hourly/daily return respective JSON files | CGI-03 | Requires JSON files on RAM disk | Test each: `curl "...?format=json&type=current"`, `...&type=hourly"`, `...&type=daily"` — verify JSON output |
| Invalid type returns 400 error | CGI-03 | Requires live CGI execution | `curl -v "...?format=json&type=invalid"` — check Status: 400 |
| Missing JSON file returns 404 | CGI-03 | Requires RAM disk state | Remove a JSON file, request it — check Status: 404 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
