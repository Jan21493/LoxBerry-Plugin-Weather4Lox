---
phase: 01-json-schema-grabber-migration
plan: 01
subsystem: api
tags: [perl, json, grabber_utils, atomic-write, json-schema]

# Dependency graph
requires: []
provides:
  - "write_current_json() outputs {meta:{schema_version,source,grabber,generated_at}, data:{...with AQ nulls...}} via atomic .tmp+move"
  - "write_daily_json() outputs {meta:{...}, data:[{period,...},...]} via atomic .tmp+move"
  - "write_hourly_json() outputs {meta:{...}, data:[{period,...},...]} via atomic .tmp+move"
  - "write_current_json_aq() helper for OpenMeteo AQ grabber (merges AQ data into current.json)"
  - "All write functions backward-compatible: existing callers passing only $logdir still work"
affects: [02-grabber-migration, supplementary-grabbers, ocean-live-theme]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "meta/data envelope pattern for all Weather4Lox JSON output files"
    - ".tmp + File::Copy::move() atomic write for JSON (same as existing .dat pattern)"
    - "eval{} + LOGWARN error isolation: JSON write failures never stop grabber execution"
    - "AQ fields default to undef (JSON null) in all current.json writes"
    - "Optional %opts hash for backward-compatible parameter extension"

key-files:
  created: []
  modified:
    - bin/grabber_utils.pl

key-decisions:
  - "write_current_json_aq() added as dedicated helper for OpenMeteo AQ grabber rather than extending write_current_json() signature further"
  - "period field retained explicitly in daily/hourly arrays (self-describing over implicit array index)"
  - "generated_at uses system localtime (when grabber ran), not observation timezone — observation time is data.datetime"

patterns-established:
  - "JSON envelope: always {meta:{schema_version,source,grabber,generated_at}, data:...} — never flat top-level"
  - "Atomic write: always .tmp + File::Copy::move(), never direct open to final path"
  - "Error isolation: eval{} around entire write block, LOGWARN on failure, return without die/exit"
  - "AQ null defaults: always set aqi_eu/aqi_us/pm10/pm25/pollen_* to undef in write_current_json()"

requirements-completed: [JSON-01, JSON-03, JSON-04, JSON-05]

# Metrics
duration: 3min
completed: 2026-03-12
---

# Phase 01 Plan 01: grabber_utils.pl JSON Schema Foundation Summary

**Three write_*_json() functions upgraded to {meta/data} envelope with atomic .tmp+move writes, AQ null fields, and backward-compatible %opts signatures; write_current_json_aq() added for OpenMeteo AQ integration**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-12T20:59:23Z
- **Completed:** 2026-03-12T21:01:51Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- `write_current_json()` upgraded: meta/data envelope, AQ fields (12 fields default to null), atomic write, new backward-compatible `%opts` signature
- `write_current_json_aq()` new helper added: reads current.dat, merges caller-supplied AQ data into current.json
- `write_daily_json()` and `write_hourly_json()` upgraded: meta/data envelope (data is array), atomic write, new `%opts` signature

## Task Commits

Each task was committed atomically:

1. **Task 1: Upgrade write_current_json with meta/data envelope, atomic write, and AQ fields** - `57d8780` (feat)
2. **Task 2: Upgrade write_daily_json and write_hourly_json with meta/data envelope and atomic write** - `a11dfca` (feat)

## Files Created/Modified
- `bin/grabber_utils.pl` - Three write functions upgraded; write_current_json_aq() added

## Decisions Made
- `write_current_json_aq()` added as a dedicated helper rather than extending `write_current_json()` with an `aq_data` flag — cleaner API, explicit intent, OpenMeteo AQ grabber has a distinct calling pattern
- `period` retained as explicit field in daily/hourly JSON arrays — makes data self-describing without relying on array index (aligns with RESEARCH.md recommendation)
- `generated_at` uses `localtime(time)` (system clock when grabber runs) — correct per Pitfall 5 in RESEARCH.md; observation time is `data.datetime` from epoch+tz_long

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

`perl -cw bin/grabber_utils.pl` cannot complete standalone because LOGINF/LOGOK/LOGWARN/LOGCRIT/LOGDEB are LoxBerry macros injected at runtime via `use LoxBerry::Log`. This is a pre-existing condition (line 86 in original file). Validation used `perl -e '...stubs...; do "./bin/grabber_utils.pl"'` pattern instead — all 4 functions defined and loaded cleanly.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Foundation complete: all 3 write functions produce correct JSON schema structure
- Plan 01-02 (main grabber parameter pass-through) can proceed: existing callers need only add `source => "Name", grabber => "filename.pl"` params
- Plan 01-03 (supplementary grabbers + schema docs) can proceed independently
- Backward compatibility confirmed: existing callers passing only `$logdir` continue to work

## Self-Check: PASSED

- FOUND: bin/grabber_utils.pl
- FOUND: .planning/phases/01-json-schema-grabber-migration/01-01-SUMMARY.md
- FOUND commit 57d8780 (Task 1: write_current_json + write_current_json_aq)
- FOUND commit a11dfca (Task 2: write_daily_json + write_hourly_json)

---
*Phase: 01-json-schema-grabber-migration*
*Completed: 2026-03-12*
