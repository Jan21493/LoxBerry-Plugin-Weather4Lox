---
phase: 05-datenanbindung-vollstaendigkeit
plan: 02
subsystem: ui
tags: [ajax, fetch, i18n, json, ocean-live, live-data, auto-refresh, icon-mapping]

# Dependency graph
requires:
  - phase: 05-01
    provides: DOM IDs, data-i18n attributes, loading overlay, error banner in ocean-live.html
  - phase: 04-01
    provides: renderHourStrip, renderDaily, selectHour, preselectHour render functions
provides:
  - ocean-live.html fully connected to show.cgi JSON endpoints (current/hourly/daily)
  - Live i18n binding via lang-*.json fetch and applyLang()
  - Icon resolution via icon_mapping.json fetch (no hardcoded ICON_MAP)
  - Auto-refresh every 5 minutes via scheduleRefresh()
  - All 12 stat DOM IDs + hero bound to real API fields
  - Sunrise/sunset from current.json displayed in heroSunrise/heroSunset
affects:
  - Production deployment (theme is now production-ready)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Promise.all for parallel fetch of 5 endpoints (current, hourly, daily, lang, icon_mapping)"
    - "Hyphen-to-underscore conversion for icon_mapping.json key lookup: code.replace(/-/g, '_')"
    - "Hourly split by datetime.slice(0,10) comparison with today/tomorrowStr from current.json"
    - "scheduleRefresh() recursive setTimeout pattern -- retries even on error"
    - "hourlyTodayRendered/hourlyTomorrowRendered globals for preselectHour reference"
    - "isDaytime() using sunrise/sunset HH parse for day/night icon selection"
    - "applyLang() traverses data-i18n attributes, resolves dotted key paths in lang JSON"

key-files:
  created: []
  modified:
    - webfrontend/html/ocean-live.html

key-decisions:
  - "getUrlParam defined in first script block (before configuration) to avoid ordering dependency on second script block"
  - "hourlyTodayRendered/hourlyTomorrowRendered globals set in renderAll() for preselectHour access"
  - "Empty tomorrow strip handled gracefully: shows loading text instead of empty container"
  - "statPressure/statVisibility use innerHTML only for static unit suffix <small> tag; server data via separate concatenation"
  - "Boot sequence: fade-in and lucide.createIcons() called synchronously before async loadAllData()"
  - "scheduleRefresh() retries on error to maintain auto-refresh even after transient failures"

# Metrics
duration: 3min
completed: 2026-03-13
---

# Phase 05 Plan 02: Datenanbindung AJAX Summary

**ocean-live.html fully migrated from mock data to live AJAX loading: loadAllData() fetches current/hourly/daily/lang/icon_mapping in parallel, binds all DOM IDs, applies i18n, resolves icons via icon_mapping.json, and auto-refreshes every 5 minutes**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-13T20:02:17Z
- **Completed:** 2026-03-13T20:04:50Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Removed all MOCK_* variables (MOCK_CURRENT, MOCK_HOURLY_TODAY, MOCK_HOURLY_TOMORROW, MOCK_DAILY) -- zero MOCK_ references remain
- Removed hardcoded ICON_MAP object and ICON_BASE variable entirely
- Implemented loadAllData() using Promise.all to fetch 5 endpoints in parallel: show.cgi current, show.cgi hourly, show.cgi daily, lang-{lang}.json, icons/{iconset}/icon_mapping.json
- Implemented resolveIcon() using fetched icon_mapping.json with hyphen-to-underscore key conversion
- Implemented transformHourly() converting API hourly objects to renderHourStrip-compatible format
- Implemented isDaytime() using sunrise/sunset hour parse for day/night determination
- Implemented applyLang() traversing [data-i18n] elements and populating from lang JSON key paths
- Implemented renderAll() binding all 12 stat DOM IDs + hero fields + heroSunrise/heroSunset to current.json
- Implemented scheduleRefresh() for auto-refresh every 5 minutes (retries on error)
- Updated preselectHour() to use hourlyTodayRendered/hourlyTomorrowRendered instead of removed MOCK arrays
- Empty tomorrow strip handled gracefully with informational message
- Boot sequence: synchronous fade-in + lucide.createIcons(), then async loadAllData() + scheduleRefresh()
- Language selectable via ?lang=XX URL param (de/en/es/nl/sk), fallback to de
- Iconset selectable via ?iconset=XX URL param, fallback to color

## Task Commits

1. **Task 1: Implement loadAllData, data transformation, i18n, and auto-refresh** - `3073d7c` (feat)

## Files Created/Modified

- `webfrontend/html/ocean-live.html` - Complete replacement of first script block (mock data + ICON_MAP) with AJAX system; preselectHour updated; initialization replaced with boot sequence

## Decisions Made

- `getUrlParam` defined in first script block to resolve forward-reference issue -- it is also still defined in second script block (no harm in non-strict JS)
- Global `hourlyTodayRendered` and `hourlyTomorrowRendered` arrays set inside `renderAll()` so `preselectHour()` can reference them on tab switch
- `statPressure` and `statVisibility` use `innerHTML` only for the static unit `<small>` tag suffix; the numeric server value is concatenated as a string before assignment to prevent XSS
- Boot sequence calls `lucide.createIcons()` synchronously (before AJAX) because icons are static SVG, not data-dependent
- `scheduleRefresh()` catches errors and schedules again -- ensures the 5-minute cycle continues even after transient network failures

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - theme will show error banner until deployed to a LoxBerry with a configured show.cgi endpoint (expected behavior).

## Next Phase Readiness

- ocean-live.html is now production-ready for deployment
- All requirements DATA-01 through DATA-04 and LANG-03 satisfied
- No further development planned for this phase

---
*Phase: 05-datenanbindung-vollstaendigkeit*
*Completed: 2026-03-13*
