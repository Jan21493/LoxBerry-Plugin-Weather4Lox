---
phase: 01-json-schema-grabber-migration
plan: 03
subsystem: api
tags: [perl, json, grabber, weather4lox, loxberry]

# Dependency graph
requires:
  - phase: 01-json-schema-grabber-migration
    plan: 01
    provides: write_current_json and write_current_json_aq functions in grabber_utils.pl
provides:
  - WU grabber writes current.json after current.dat via write_current_json
  - FOSHK grabber writes current.json after current.dat via write_current_json
  - PWSCatchUpload grabber requires grabber_utils.pl and writes current.json
  - Loxone grabber requires grabber_utils.pl and writes current.json
  - OpenMeteo AQ grabber merges AQ fields into current.json via write_current_json_aq
affects: [02-main-grabbers, 03-datatoloxone, 04-ocean-theme]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "eval-wrapped JSON write with LOGWARN on failure (dat-priority maintained)"
    - "dual-write: JSON alongside .dat, .dat write is authoritative"
    - "require grabber_utils.pl added to grabbers lacking it (PWS, Loxone)"

key-files:
  created: []
  modified:
    - bin/grabber_wu.pl
    - bin/grabber_foshk.pl
    - bin/grabber_pwscatchupload.pl
    - bin/grabber_loxone.pl
    - bin/grabber_openmeteo_airquality.pl

key-decisions:
  - "pollen_*: use today_max values from %pollen_result hash as current pollen level fields in %aq_values"
  - "Legacy airquality_pollen.json write preserved — write_current_json_aq added AFTER it (dual-write philosophy)"

patterns-established:
  - "write_current_json call pattern: eval { write_current_json($lbplogdir, source => '...', grabber => '...') }; LOGWARN ... if $@"
  - "require placement: after use statements block, before Read Settings section"

requirements-completed: [JSON-06]

# Metrics
duration: 2min
completed: 2026-03-12
---

# Phase 1 Plan 03: Supplementary Grabbers JSON Integration Summary

**5 supplementary grabbers wired to produce current.json via write_current_json/write_current_json_aq — all eval-wrapped, dat-priority maintained, legacy AQ file preserved**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-12T21:05:01Z
- **Completed:** 2026-03-12T21:06:36Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- WU and FOSHK grabbers (already had require) now call write_current_json after move() with correct source names
- PWSCatchUpload and Loxone grabbers gained require grabber_utils.pl and write_current_json calls
- OpenMeteo AQ grabber builds %aq_values from existing pollen/AQI variables and calls write_current_json_aq after the legacy file write

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire WU, FOSHK, PWSCatchUpload, and Loxone grabbers** - `69d2994` (feat)
2. **Task 2: Convert OpenMeteo AQ grabber to current.json merge** - `50dea37` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `bin/grabber_wu.pl` - Added write_current_json call after move() with source "WeatherUnderground"
- `bin/grabber_foshk.pl` - Added write_current_json call after move() with source "FOSHK"
- `bin/grabber_pwscatchupload.pl` - Added require grabber_utils.pl; added write_current_json with source "PWSCatchUpload"
- `bin/grabber_loxone.pl` - Added require grabber_utils.pl; added write_current_json with source "Loxone"
- `bin/grabber_openmeteo_airquality.pl` - Added %aq_values hash and write_current_json_aq call after legacy airquality_pollen.json write

## Decisions Made

- Used `today_max` from `%pollen_result` as the pollen level fields in `%aq_values` — represents the highest severity level for the current day, which is the most actionable value for the JSON consumers
- Legacy `airquality_pollen.json` write preserved intact with comment; `write_current_json_aq` added after it, not replacing it

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. The `BEGIN failed--compilation aborted at line 27` from `perl -cw` is a pre-existing environment limitation (LoxBerry::System not installed on this dev machine). All 5 grabbers have the correct structure confirmed by line-number inspection.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 5 supplementary grabbers now produce current.json — JSON-06 requirement complete
- Phase 1 full: grabber_utils.pl foundation (01-01) + main grabbers (01-02) + supplementary grabbers (01-03) all wired
- Ready for Phase 2: datatoloxone.pl migration or Phase 3: ocean-live theme

---
*Phase: 01-json-schema-grabber-migration*
*Completed: 2026-03-12*
