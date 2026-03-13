---
phase: 05-datenanbindung-vollstaendigkeit
plan: 01
subsystem: ui
tags: [i18n, html, json, ocean-live, lang-files, data-binding]

# Dependency graph
requires:
  - phase: 04-ocean-live-theme-grundgerust
    provides: ocean-live.html with Ocean theme, tab panels, hero section, mock data
provides:
  - All 5 lang files (de/en/es/nl/sk) extended with 11 new theme keys for ocean-live
  - ocean-live.html DOM IDs for live data binding (heroSunrise, heroSunset, heroFeelslike, statHumidity/Wind/Pressure/Visibility/Dewpoint/Precip/UVI/Clouds/Gusts/Feelslike, statWindDir)
  - ocean-live.html loading overlay and error banner HTML+CSS infrastructure
  - 21 data-i18n attributes on all hardcoded German labels in ocean-live.html
affects:
  - 05-02 (AJAX data loading, i18n application)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "data-i18n='theme.*' attribute pattern for i18n binding to lang JSON keys"
    - "German text as fallback content in data-i18n elements (text stays until lang JSON loads)"
    - "id=stat* naming convention for stat-val elements bound to live data"
    - "Loading overlay hidden by default (style=display:none), shown during AJAX fetch"

key-files:
  created: []
  modified:
    - webfrontend/html/lang-de.json
    - webfrontend/html/lang-en.json
    - webfrontend/html/lang-es.json
    - webfrontend/html/lang-nl.json
    - webfrontend/html/lang-sk.json
    - webfrontend/html/ocean-live.html

key-decisions:
  - "New lang keys inserted after dew_point key, before weekdays array to maintain logical grouping"
  - "data-i18n attributes added to stat-label elements (not stat-val) so JS can replace label text via lang key lookup"
  - "Loading overlay and error banner inserted before first <script> tag in body so DOM is ready when scripts run"
  - "heroFeelslike ID added to 4th astro item simultaneously with data-i18n for feels_like label"

patterns-established:
  - "Lang key convention: theme.{key_name} for all ocean-live theme UI strings"
  - "Stat value ID convention: id=stat{PropertyName} (camelCase, e.g. statDewpoint, statFeelslike)"
  - "Hero-level ID convention: id=hero{PropertyName} for hero section values"

requirements-completed: [LANG-01, LANG-02, DATA-05, DATA-06, EXTRA-01]

# Metrics
duration: 3min
completed: 2026-03-13
---

# Phase 05 Plan 01: Datenanbindung Vorbereitung Summary

**5 lang files extended with 11 i18n keys each, ocean-live.html equipped with 21 data-i18n attributes, DOM IDs for 12 stat values, loading overlay, and error banner -- complete Wave 0 prep for Plan 02 AJAX binding**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-13T19:57:30Z
- **Completed:** 2026-03-13T20:00:04Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Extended all 5 lang files (de/en/es/nl/sk) with 11 new theme keys: tab_today, tab_tomorrow, tab_days, hours_today, hours_tomorrow, forecast_7day, click_hour_detail, loading, error_loading, gusts, live_dashboard
- Added 21 data-i18n attributes to all hardcoded German labels in ocean-live.html covering tabs, header, astro row, stat labels, strip titles, and forecast heading
- Added DOM IDs to 12 stat value elements (statHumidity, statWind, statWindDir, statPressure, statVisibility, statDewpoint, statPrecip, statUVI, statClouds, statGusts, statFeelslike, heroFeelslike) plus heroSunrise and heroSunset
- Added loading overlay and error banner HTML/CSS infrastructure (hidden by default)
- All JSON files validated as structurally sound; no visual regression in ocean-live.html (German text as fallback)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend all 5 lang-*.json with new theme keys** - `f500503` (feat)
2. **Task 2: Add DOM infrastructure to ocean-live.html** - `7c5dbc6` (feat)

## Files Created/Modified
- `webfrontend/html/lang-de.json` - Added 11 theme keys after dew_point (German)
- `webfrontend/html/lang-en.json` - Added 11 theme keys after dew_point (English)
- `webfrontend/html/lang-es.json` - Added 11 theme keys after dew_point (Spanish)
- `webfrontend/html/lang-nl.json` - Added 11 theme keys after dew_point (Dutch)
- `webfrontend/html/lang-sk.json` - Added 11 theme keys after dew_point (Slovak)
- `webfrontend/html/ocean-live.html` - Loading overlay, error banner, 21 data-i18n attrs, 14 new DOM IDs

## Decisions Made
- New lang keys inserted after `dew_point`, before `weekdays` array -- maintains logical grouping of scalar theme keys before array keys
- `data-i18n` applied to label elements, not value elements -- label text gets i18n-replaced, value elements keep stat IDs for AJAX binding
- `heroFeelslike` ID added to 4th astro item simultaneously with its `data-i18n` attribute, completing both i18n and live-binding prep in one pass
- Loading overlay/error banner placed before the inline scripts so DOM elements are available when any script references them

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 02 can immediately begin AJAX data loading -- all DOM IDs and data-i18n hooks are in place
- i18n system (Plan 02) can traverse `[data-i18n]` elements and replace textContent with lang JSON values
- Loading overlay can be shown/hidden via `document.getElementById('loadingOverlay').style.display`
- Error banner can display messages via `document.getElementById('errorMsg').textContent`
- No blockers

---
*Phase: 05-datenanbindung-vollstaendigkeit*
*Completed: 2026-03-13*
