---
phase: 04-ocean-live-theme-grundgerust
plan: 01
subsystem: ui

tags: [html, css, javascript, ocean-theme, glassmorphism, tabs, hero, mock-data]

# Dependency graph
requires:
  - phase: 03-cgi-json-endpoint
    provides: show.cgi JSON endpoint that Phase 5 will use for live data
provides:
  - "webfrontend/html/ocean-live.html — complete Ocean dark theme scaffold with 3 tabs, hero area, hourly strip, 7-day overview, using static mock data"
affects:
  - phase-05-datenanbindung

# Tech tracking
tech-stack:
  added: [lucide-icons-cdn, google-fonts-outfit-jetbrains-mono]
  patterns:
    - "Single-file self-contained HTML theme (CSS + HTML + JS inline)"
    - "Tab panel fade transition using display+opacity+requestAnimationFrame (not display:none+transition)"
    - "Hero above tab panels shared between Heute/Morgen; hidden for Tage"
    - "Icon path convention: icons/color/{name}_{day|night}.png (suffix, not subdirectory)"
    - "renderHourStrip() + renderDaily() dynamic DOM generation from JS data arrays"
    - "Drag-scroll on hour strips via pointer events"
    - "preselectHour() auto-selects current hour on Heute, first hour on Morgen"

key-files:
  created:
    - webfrontend/html/ocean-live.html
  modified: []

key-decisions:
  - "Hero section placed above tab panels (not inside them) so Heute and Morgen share one hero DOM without duplicate IDs"
  - "Icon paths use suffix convention (icons/color/clear_day.png) not subdirectory convention from ocean.main.html SSR template"
  - "Tab fade uses display:block + requestAnimationFrame + opacity transition — display:none with opacity transition does not work"
  - "selectHour() receives dataArray as parameter so same function works for both Heute and Morgen strips"

patterns-established:
  - "Pattern 1: preselectHour(tabName) called on tab switch and on page load — provides initial hero state"
  - "Pattern 2: icon_mapping object maps weather codes to icon filenames — allows live data to use same icon convention"
  - "Pattern 3: renderHourStrip/renderDaily receive containerId + dataArray — decoupled from data source, ready for Phase 5 AJAX swap"

requirements-completed: [THEME-01, THEME-02, THEME-03, THEME-04, HERO-01, HERO-02, HERO-03, HERO-04, HERO-05, HERO-06, TAGE-01, TAGE-02, EXTRA-02]

# Metrics
duration: ~90min
completed: 2026-03-13
---

# Phase 4 Plan 01: ocean-live Theme Grundgerust Summary

**Self-contained ocean-live.html with Ocean dark glassmorphism theme, 3-tab UI (Heute/Morgen/Tage), shared hero area, scrollable hourly strips with click-to-update hero, 7-day daily overview — all fully interactive using inline mock data**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-03-13 (session start)
- **Completed:** 2026-03-13
- **Tasks:** 3 (2 auto + 1 human-verify checkpoint, approved)
- **Files modified:** 1

## Accomplishments

- Created `webfrontend/html/ocean-live.html` as a single self-contained file (~750+ lines) with full Ocean dark theme CSS, HTML structure, and all interactive JavaScript
- Implemented 3-tab layout (Heute/Morgen/Tage) with CSS fade transitions using `display + requestAnimationFrame + opacity` pattern
- Hero area (temperature, icon, description, wind, humidity) shared above tabs — updates smoothly via `selectHour()` with opacity fade; `preselectHour()` auto-selects current hour (Heute) or first hour (Morgen)
- 7-day daily overview rendered dynamically with temperature bars showing relative high/low range across 7 days
- Added icon path fix (deviation) to map weather codes correctly using `icon_mapping` object for `icons/color/{name}_{dn}.png` convention

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ocean-live.html with CSS, HTML structure, and mock data** - `85f3178` (feat)
2. **Task 2: Add all interactive JavaScript behavior** - `85f3178` (feat, same commit — JS part of same file)
3. **Task 3: Visual verification** - checkpoint approved by user
4. **Deviation fix: icon paths** - `123e530` (fix)

**Plan metadata:** (this commit — docs: complete plan)

## Files Created/Modified

- `webfrontend/html/ocean-live.html` — Complete self-contained Ocean theme with mock data, 3 tabs, hero, hour strips, 7-day overview

## Decisions Made

- Hero section placed ABOVE tab panels so Heute and Morgen share a single `#heroSection` DOM node without duplicate IDs — plan specified this architectural decision
- Icon paths use flat suffix convention (`icons/color/clear_day.png`) because `webfrontend/html/icons/color/` stores files without day/night subdirectories — unlike ocean.main.html SSR template which uses `/{d|n}/` subdirectory paths
- `selectHour(el, dataArray)` receives the data array as a parameter rather than relying on global state — this makes the function work for both Heute and Morgen strips without modification
- `renderHourStrip()` and `renderDaily()` are decoupled from data source — Phase 5 can call same functions with live AJAX data

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed weather icon paths using icon_mapping**
- **Found during:** Visual verification (Task 3 / post-checkpoint)
- **Issue:** Icon `<img>` src paths were rendering as broken images because weather_icon values from mock data did not match the actual filename pattern in `icons/color/`
- **Fix:** Added `icon_mapping` object mapping common weather description codes (e.g. `"partly-cloudy"`, `"clear"`, `"rain"`) to actual icon filenames; `selectHour()` and `renderHourStrip()` now use mapped names
- **Files modified:** `webfrontend/html/ocean-live.html`
- **Verification:** Icons displayed correctly after fix; user approved visual check
- **Committed in:** `123e530`

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Fix necessary for correct visual output. No scope creep.

## Issues Encountered

- Icon path convention difference between SSR template (`ocean.main.html` uses `/{d|n}/` subdirectories) and live theme (`icons/color/` flat files with `_day`/`_night` suffix) required a mapping fix post-build

## User Setup Required

None - no external service configuration required. File opens standalone in any browser.

## Next Phase Readiness

- `ocean-live.html` is fully functional with mock data — ready for Phase 5 AJAX data wiring
- `renderHourStrip(containerId, dataArray)` and `renderDaily(containerId, dataArray)` are data-source agnostic — Phase 5 replaces mock arrays with live API responses
- `selectHour()` and `preselectHour()` need no changes for live data
- Icon mapping (`icon_mapping` object in ocean-live.html) must be kept in sync with actual icon filenames when Phase 5 maps real API weather codes

---
*Phase: 04-ocean-live-theme-grundgerust*
*Completed: 2026-03-13*
