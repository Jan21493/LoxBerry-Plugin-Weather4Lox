---
phase: 02-delivery-layer-migration
plan: "01"
subsystem: delivery-layer
tags: [perl, json, migration, udp, mqtt, loxone]
requirements_satisfied: [JSON-07, JSON-08]

dependency_graph:
  requires:
    - Phase 01 JSON files: current.json, dailyforecast.json, hourlyforecast.json
  provides:
    - bin/datatoloxone.pl: Complete JSON-based delivery layer
  affects:
    - All UDP/MQTT virtual inputs in Loxone Miniserver
    - HTML theme pages (dark, light, fresh, ocean)
    - Cloud Weather Emulator (index.txt)

tech_stack:
  added:
    - JSON::PP (pure-Perl JSON decoder, Perl core >= 5.14)
  patterns:
    - load_json_file() with fail-fast LOGCRIT + exit for missing/malformed JSON
    - _jval() null-safe helper: JSON null -> -9999 for Loxone compatibility
    - flock(LOCK_SH) shared read lock on JSON files
    - DateTime->from_epoch(epoch => $entry->{epoch}) for date derivation
    - split(/:/, $entry->{sunrise}) for HH:MM sunrise/sunset parsing

key_files:
  modified:
    - bin/datatoloxone.pl: Complete JSON migration — 616 insertions, 519 deletions

decisions:
  - Used LOGCRIT (not LOGERR) for all JSON load failures — operational failure requiring attention
  - Kept weatherdata.html debug output — zero extra complexity, aids debugging
  - Derived cur_date_tz_des_sh via DateTime->time_zone_short_name() from IANA timezone
  - Derived cur_date_tz (numeric offset like "+0100") from ISO 8601 datetime string regex
  - Preserved Pitfall 4 behavior: DFC sunrise/sunset uses $epochdate (current date) as base, not dfc date
  - Used DateTime->from_epoch() for emulator hfcdate construction (cleaner than field-by-field)
  - Emulator station header derives UTC offset string from datetime ISO regex

metrics:
  duration: 7 min
  completed: 2026-03-12
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
---

# Phase 02 Plan 01: Delivery Layer Migration Summary

**One-liner:** Complete migration of datatoloxone.pl from pipe-delimited .dat file reading to JSON hash/array access, preserving all UDP/MQTT value names and calculation logic with zero .dat remnants.

## What Was Built

datatoloxone.pl has been fully migrated from reading three pipe-delimited .dat files (current.dat, dailyforecast.dat, hourlyforecast.dat) to reading three structured JSON files (current.json, dailyforecast.json, hourlyforecast.json). The migration covers:

1. **JSON infrastructure**: `use JSON::PP`, `load_json_file()` sub with fail-fast validation (LOGCRIT + exit), `_jval()` null-safe helper, flock(LOCK_SH) shared read locking
2. **Central JSON loading at startup**: All three files loaded once into `$cur` (hashref), `@dfc` (array of hashrefs), `@hfc` (array of hashrefs)
3. **Current conditions UDP/MQTT section**: All 42 .dat positions replaced with named hash fields; legacy tz fields derived from JSON
4. **Daily forecast UDP/MQTT section**: Loop converted from `foreach (@dfcdata)` to `foreach my $dfc_entry (@dfc)`; date components derived via `DateTime->from_epoch`
5. **Hourly forecast UDP/MQTT section**: Same pattern as DFC; all field access uses `$hfc_entry->{field_name}`
6. **calc+N aggregation**: All `-9999` sentinel comparisons replaced with `defined()` checks; `@fields[N]` replaced with `$hfc_entry->{field}`
7. **HTML template sections** (DFC, HFC, current): Variable names unchanged; data source swapped to JSON hash/array
8. **Emulator index.txt**: Current conditions from `$cur` hashref; hourly forecast loop uses `DateTime->from_epoch` for past-forecast filtering

## Verification Results

| Check | Result |
|-------|--------|
| `perl -c` syntax check | PASS |
| `@fields[` references | 0 |
| `split(/\|/)` references | 0 |
| `.dat` open() calls | 0 |
| `$curdata/@dfcdata/@hfcdata` refs | 0 |
| `load_json_file` occurrences | 4 (1 def + 3 calls) |
| `JSON::PP` occurrences | 2 |
| LOGCRIT in load_json_file | 3 (file not found, can't open, parse error) |
| flock(LOCK_SH) | yes |
| Key UDP names present | all present |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as specified.

### Notes

- Task 2 (validation pass) required no fixes — migration in Task 1 was complete on the first pass
- The `split./\|/.` grep in the plan verification hits false positives on this dev machine (matches `\|` within regex character classes like `[+-]`); verified with exact Perl match: 0 real occurrences

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: JSON migration | fa17836 | feat(02-01): migrate datatoloxone.pl from .dat to JSON reading |
| Task 2: Validation pass | — | No changes needed — validated against Task 1 commit |

## Self-Check: PASSED
