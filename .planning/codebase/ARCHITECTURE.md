# Architecture

**Analysis Date:** 2026-03-12

## Pattern Overview

**Overall:** Pipeline / Scheduled ETL Plugin for LoxBerry

**Key Characteristics:**
- Scheduled cron-triggered pipeline: fetch → parse → normalize → deliver
- No persistent database — all state lives in pipe-delimited flat `.dat` files in the RAM-disk log directory (`$LBPLOGDIR`)
- Dual-transport output: UDP packets to Loxone Miniserver AND/OR MQTT broker
- Multi-source weather aggregation: a primary service for current conditions, optional alternate services for daily and hourly forecasts, plus optional local station grabbers
- LoxBerry plugin framework integration throughout (`LoxBerry::System`, `LoxBerry::Log`, `LoxBerry::Web`, `LoxBerry::IO`, `LoxBerry::JSON`)

---

## Layers

**Scheduling Layer:**
- Purpose: Decide when to trigger fetches based on configured intervals
- Location: `bin/cronjob.pl`, `bin/weather4lox_cronjob.sh`
- Contains: Interval arithmetic against `SERVER.CRON` and `SERVER.CRON_ALTERNATE` settings; calls `fetch.pl` with `--default` and/or `--alternate` flags
- Depends on: `config/weather4lox.cfg`
- Used by: LoxBerry hourly cron hook (`system/cron/cron.hourly/99-weather4lox_cronjob`)

**Orchestration Layer:**
- Purpose: Dispatch to the correct grabber script(s) based on configuration
- Location: `bin/fetch.pl`
- Contains: Reads `SERVER.WEATHERSERVICE`, `SERVER.WEATHERSERVICEDFC`, `SERVER.WEATHERSERVICEHFC` from config; dynamically resolves and invokes `grabber_<service>.pl` with `--current`, `--daily`, `--hourly` flags; optionally invokes supplementary grabbers (WU, FOSHK, PWSCatchUpload, Loxone, OpenMeteo AQ); always invokes `datatoloxone.pl` at the end
- Depends on: All grabbers in `bin/`, `config/weather4lox.cfg`
- Used by: `cronjob.pl`, `webfrontend/htmlauth/ajax-handler.cgi` (manual trigger)

**Grabber Layer (Data Acquisition):**
- Purpose: Call external weather APIs, normalize raw JSON/HTML into the internal pipe-delimited flat-file format, write `.dat` files
- Location: `bin/grabber_*.pl`
- Contains:
  - `grabber_openweather.pl` — OpenWeatherMap OneCall API v3.0; handles current, daily, hourly; includes OWM→Loxone weather-code mapping table
  - `grabber_visualcrossing.pl` — Visual Crossing Timeline API
  - `grabber_weatherflow.pl` — WeatherFlow/Tempest REST API
  - `grabber_wetteronline.pl` — Web-scraped WetterOnline (current via HTML scrape, daily/hourly via private app API)
  - `grabber_wttrin.pl` — wttr.in JSON API
  - `grabber_openmeteo_airquality.pl` — Open-Meteo Air Quality API
  - `grabber_wu.pl` — Weather Underground PWS current observation
  - `grabber_foshk.pl` — Local FOSHKplugin station
  - `grabber_pwscatchupload.pl` — Local PWSCatchUpload station
  - `grabber_loxone.pl` — Loxone Miniserver local sensor read-back
- Depends on: `grabber_utils.pl` (shared HTTP helper), `config/weather4lox.cfg`, `LWP::UserAgent`, `JSON`, service-specific Perl modules
- Produces: `$LBPLOGDIR/current.dat`, `$LBPLOGDIR/dailyforecast.dat`, `$LBPLOGDIR/hourlyforecast.dat`, `$LBPLOGDIR/hourlyhistory.dat` (pipe-delimited, one record per line)

**Shared Utility Layer:**
- Purpose: Common API call wrapper with key-masking for secure log output
- Location: `bin/grabber_utils.pl`
- Contains: `api_call()` (HTTP GET via LWP, structured logging, masked URL/response dumping), `sanitize_url()`, `sanitize_dump()`
- Depends on: `LWP::UserAgent`, `LoxBerry::Log` macros (must be loaded into caller namespace)
- Used by: All `grabber_*.pl` via `require "$lbpbindir/grabber_utils.pl"`

**Delivery Layer:**
- Purpose: Read flat `.dat` files, convert units, calculate derived aggregates, push named values to Loxone via UDP and/or MQTT; render cached HTML weather display pages
- Location: `bin/datatoloxone.pl`
- Contains:
  - Reads `current.dat`, `dailyforecast.dat`, `hourlyforecast.dat`, `hourlyhistory.dat`
  - Emits named UDP packets (`cur_*`, `dfc<N>_*`, `hfc<N>_*`, `calc+<H>_*`) to Loxone Miniserver on configured port
  - Publishes MQTT messages under configured topic
  - Renders `webpage.html`, `webpage.dfc.html`, `webpage.hfc.html`, `webpage.map.html` by substituting Perl variables into HTML theme templates
  - Calculates derived rolling aggregates: precipitation, snow, solar radiation, temperature min/max/mean, PoP min/max over +4h, +8h, +12h, +16h, +24h, +32h, +40h, +48h windows
- Depends on: `$LBPLOGDIR/*.dat`, `templates/themes/<lang>/<theme>.*html`, `config/weather4lox.cfg`, `LoxBerry::IO`, `Net::MQTT::Simple`, `IO::Socket`, `DateTime`

**Web Frontend Layer:**
- Purpose: Authenticated admin UI for plugin configuration, manual data fetch, weather display
- Location: `webfrontend/htmlauth/`
- Contains:
  - `index.cgi` — Main settings page; reads/writes `weather4lox.cfg`; uses `HTML::Template` with `templates/settings.html`; enforces default API URLs on each load
  - `show.cgi` — Weather display widget; reads `.dat` files directly; serves parameterized HTML views (theme, lang, map, iconset, dfc, hfc)
  - `ajax-handler.cgi` — JSON AJAX endpoint; currently handles `fetch` action by invoking `fetch.pl`
  - `geolocation.cgi` — Nominatim-based geocoding helper for coordinate lookup in settings
- Depends on: `LoxBerry::System`, `LoxBerry::Web`, `CGI`, `Config::Simple`, `HTML::Template`

**Cloud Emulator Layer:**
- Purpose: DNS redirect of `weather.loxone.com` to the LoxBerry host so Loxone Miniservers receive Weather4Lox data via the standard Loxone cloud weather protocol
- Location: `bin/cloudemu`
- Contains: Bash script; manages DNSMasq config and Apache2 virtual host `001-<plugin>.conf`; started/stopped by `daemon/daemon` and `bin/fetch.pl` flow

**Daemon / Startup Layer:**
- Purpose: Restore RAM-disk `.dat` files from persistent storage on boot; optionally re-enable cloud emulator
- Location: `daemon/daemon`
- Contains: Copies `$LBPDATA/<plugin>/*.dat` → `$LBPLOGDIR/<plugin>/*.dat` if not already present; reads `SERVER.EMU` to decide whether to reinvoke `cloudemu enable`

---

## Data Flow

**Scheduled Weather Fetch:**

1. LoxBerry cron fires `bin/weather4lox_cronjob.sh` every hour
2. `weather4lox_cronjob.sh` copies current RAM-disk `.dat` files back to persistent `$LBPDATA` storage, then exits (persistence backup)
3. LoxBerry cron independently fires `bin/cronjob.pl` every minute
4. `cronjob.pl` checks interval: if `timestamp_minutes % CRON == 0`, invokes `bin/fetch.pl --cronjob --default`; if alternate services configured and `% CRON_ALTERNATE == 0`, also adds `--alternate`
5. `fetch.pl` resolves which grabber script(s) to run from config; invokes `grabber_<service>.pl --current [--daily] [--hourly]` via `system()`
6. Selected grabber(s) call the external weather API via `api_call()`, parse JSON/HTML response, write normalized pipe-delimited rows to `$LBPLOGDIR/current.dat`, `dailyforecast.dat`, `hourlyforecast.dat`
7. Optional supplementary grabbers (WU, FOSHK, PWSCatchUpload, Loxone, OpenMeteo AQ) are invoked in sequence to merge/overwrite specific fields
8. `fetch.pl` invokes `bin/datatoloxone.pl`
9. `datatoloxone.pl` reads all `.dat` files, converts units (metric/imperial), calculates rolling aggregates, emits named UDP packets to Loxone Miniserver and/or MQTT messages, renders cached HTML pages from theme templates

**Manual Fetch (from Admin UI):**

1. User clicks "Fetch Now" button in `webfrontend/htmlauth/index.cgi`
2. JavaScript calls `webfrontend/htmlauth/ajax-handler.cgi?ajax=fetch`
3. `ajax-handler.cgi` invokes `bin/fetch.pl -v` directly
4. Same pipeline as scheduled fetch from step 5 onward

**Weather Display (Web Widget):**

1. Browser requests `webfrontend/htmlauth/show.cgi?theme=<T>&lang=<L>&iconset=<I>&dfc=<D>&hfc=<H>`
2. `show.cgi` reads `.dat` files, applies unit conversion, populates Perl variable namespace
3. Substitutes `<!--$varname-->` placeholders in `templates/themes/<lang>/<theme>.main.html` (new-style) or separate `.dfc.html`/`.hfc.html` (old-style)
4. Serves rendered HTML directly

**State Management:**
- No database. Active state lives in pipe-delimited flat files in the RAM-disk log directory (`$LBPLOGDIR/weather4lox/`)
- Persisted via hourly `weather4lox_cronjob.sh` copying RAM-disk files to `$LBPDATA/weather4lox/`
- On boot, `daemon/daemon` restores RAM-disk files from persistent copies

---

## Key Abstractions

**Pipe-Delimited Flat File Database:**
- Purpose: Normalized, position-indexed weather data interchange format shared between grabbers and delivery layer
- Format: One record per weather period, fields separated by `|`, positions documented in `data/*.format` files
- Files: `$LBPLOGDIR/current.dat` (42 fields), `$LBPLOGDIR/dailyforecast.dat` (40 fields/period), `$LBPLOGDIR/hourlyforecast.dat` (36 fields/period), `$LBPLOGDIR/hourlyhistory.dat` (38 fields/period)
- Schema docs: `data/current.format`, `data/dailyforecast.format`, `data/hourlyforecast.format`, `data/hourlyhistory.format`

**Grabber Contract:**
- Purpose: Each grabber is a self-contained Perl script that accepts `--current`, `--daily`, `--hourly`, `--verbose`, `--maskkeys` command-line flags and writes to the standard `.dat` files
- New grabbers follow the pattern: read config → `api_call()` → parse JSON → write pipe-delimited rows to `.dat.tmp` → rename to `.dat`
- Example implementations: `bin/grabber_openweather.pl`, `bin/grabber_visualcrossing.pl`

**Weather Code Mapping:**
- Purpose: Translate service-specific weather condition codes to the Loxone internal picto-code (integer 1–30) and normalized icon slug (e.g. `rain`, `snow`, `tstorms`)
- Pattern: Hash lookup table `%<service>_to_lox` defined at top of each grabber, accessed via a local `<service>_to_lox()` subroutine
- Examples: `%owm_to_lox` in `bin/grabber_openweather.pl`, similar tables in all other grabbers

**Named Value Delivery:**
- Purpose: Loxone Miniserver reads weather data as named virtual inputs; each `cur_*`, `dfc<N>_*`, `hfc<N>_*`, `calc+<H>_*` name maps to a Loxone virtual input
- Implementation: `&send` subroutine in `bin/datatoloxone.pl` sends UDP datagram `<name>: <value>` and/or publishes MQTT message `<topic>/<name>`

**Theme Template System:**
- Purpose: Cacheable HTML weather display pages, rendered server-side by substituting Perl variable values
- Placeholder syntax: `<!--$varname-->` in HTML files
- Templates: `templates/themes/<lang>/<theme>.main.html`, `.dfc.html`, `.hfc.html`, `.map.html`
- Languages: `de`, `en`, `es`, `nl`, `at` (dialect variant of `de`)

---

## Entry Points

**Scheduled Cron (every minute):**
- Location: `bin/cronjob.pl`
- Triggers: LoxBerry cron system (`system/cron/cron.01min/` or minutely hook)
- Responsibilities: Interval gating; delegates to `fetch.pl`

**Scheduled Cron (every hour):**
- Location: `bin/weather4lox_cronjob.sh`
- Triggers: LoxBerry cron hook `system/cron/cron.hourly/99-weather4lox_cronjob`
- Responsibilities: Persistence backup of RAM-disk `.dat` files to `$LBPDATA`

**Admin UI:**
- Location: `webfrontend/htmlauth/index.cgi`
- Triggers: HTTP GET/POST via Apache CGI (LoxBerry authenticated web area)
- Responsibilities: Plugin configuration; triggers manual fetch via `ajax-handler.cgi`

**Weather Display Widget:**
- Location: `webfrontend/htmlauth/show.cgi`
- Triggers: HTTP GET with query parameters (theme, lang, iconset, dfc, hfc)
- Responsibilities: Read `.dat` files, render and serve themed HTML weather display

**System Boot:**
- Location: `daemon/daemon`
- Triggers: LoxBerry daemon system on boot
- Responsibilities: Restore RAM-disk `.dat` state; re-enable cloud emulator if configured

---

## Error Handling

**Strategy:** Log and exit. Grabbers write to `$LBPLOGDIR` log files via LoxBerry::Log macros. Fatal errors call `LOGCRIT` then `exit(1)` or `exit(2)`. The pipeline is not retried automatically on failure — the next cron interval is the recovery mechanism.

**Patterns:**
- HTTP failures: `api_call()` in `grabber_utils.pl` logs `LOGCRIT` on non-200 status and returns undef; callers must check return value
- Missing grabber script: `fetch.pl` calls `LOGCRIT` and `exit(1)` if `grabber_<service>.pl` not found
- Empty data files: `datatoloxone.pl` substitutes sentinel value `1230764400` (Loxone epoch base) and zeros for missing/corrupt `.dat` data
- CGI fatal errors: `CGI::Carp qw(fatalsToBrowser)` surfaces Perl die() output to the browser in web scripts

---

## Cross-Cutting Concerns

**Logging:** `LoxBerry::Log` macros throughout all Perl scripts (`LOGSTART`, `LOGINF`, `LOGDEB`, `LOGWARN`, `LOGCRIT`, `LOGOK`, `LOGEND`). Log name per script (e.g. `fetch`, `datatoloxone`, `grabber_openweather`). Log directory: `$LBPLOGDIR`. Loglevel controllable via `--verbose` flag or LoxBerry plugin management UI.

**API Key Security:** `grabber_utils.pl` `api_call()` masks the API key query parameter in all log output by default (`maskkeys=1`). Configurable via `SERVER.MASKKEYS` in `weather4lox.cfg` and `--maskkeys` CLI flag.

**Unit Conversion:** All internal storage is metric (°C, km/h, mm, km). Unit conversion to imperial happens at read time in `datatoloxone.pl` and `show.cgi`, gated on `SERVER.METRIC=0`.

**Internationalization:** Language strings loaded from `templates/lang/language_<lang>.ini` via `LoxBerry::System::readlanguage()`. Wind direction descriptions and month/day names are localized inside each grabber using the `%L` hash.

**LoxBerry Path Variables:** All scripts rely on LoxBerry framework environment variables: `$lbpbindir`, `$lbpconfigdir`, `$lbplogdir`, `$lbptemplatedir`, `$lbpdatadir`, `$LBPDATA`, `$LBPLOG` — provided by `use LoxBerry::System`.

---

*Architecture analysis: 2026-03-12*
