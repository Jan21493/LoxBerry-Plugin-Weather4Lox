# Codebase Structure

**Analysis Date:** 2026-03-12

## Directory Layout

```
weather4lox/                    # Plugin root (LoxBerry plugin package)
├── plugin.cfg                  # Plugin metadata (name, version, autoupdate URLs)
├── release.cfg                 # Release channel descriptor
├── prerelease.cfg              # Pre-release channel descriptor
├── postinstall.sh              # Post-install hook: Apache config, cron, dummy data, symlinks
├── postupgrade.sh              # Post-upgrade hook
├── preupgrade.sh               # Pre-upgrade hook
├── postroot.sh                 # Post-install root hook (privileged operations)
├── LICENSE                     # Apache 2.0
├── README.md                   # Brief project description
├── bin/                        # All backend Perl/Bash scripts
│   ├── cronjob.pl              # Interval gate: decides when to call fetch.pl
│   ├── fetch.pl                # Orchestrator: dispatches to grabbers, then datatoloxone.pl
│   ├── datatoloxone.pl         # Delivery: reads .dat files, sends UDP/MQTT, renders HTML
│   ├── grabber_utils.pl        # Shared: api_call(), sanitize_url(), sanitize_dump()
│   ├── grabber_openweather.pl  # Grabber: OpenWeatherMap OneCall API
│   ├── grabber_visualcrossing.pl # Grabber: Visual Crossing Timeline API
│   ├── grabber_weatherflow.pl  # Grabber: WeatherFlow/Tempest REST API
│   ├── grabber_wetteronline.pl # Grabber: WetterOnline (scrape + private app API)
│   ├── grabber_wttrin.pl       # Grabber: wttr.in JSON API
│   ├── grabber_openmeteo_airquality.pl # Grabber: Open-Meteo Air Quality API
│   ├── grabber_wu.pl           # Supplementary: Weather Underground PWS
│   ├── grabber_foshk.pl        # Supplementary: local FOSHKplugin station
│   ├── grabber_pwscatchupload.pl # Supplementary: local PWSCatchUpload station
│   ├── grabber_loxone.pl       # Supplementary: Loxone Miniserver sensor read-back
│   ├── cloudemu                # Bash: manage DNSMasq + Apache for cloud emulation
│   ├── ownip.pl                # Helper: resolve LoxBerry's own IP address
│   └── weather4lox_cronjob.sh  # Hourly: persist RAM-disk .dat files to $LBPDATA
├── config/
│   ├── weather4lox.cfg         # Runtime plugin config (INI format, Config::Simple)
│   └── apache2.conf            # Apache2 vhost config for cloud emulator
├── daemon/
│   └── daemon                  # Bash: boot hook to restore RAM-disk state
├── data/
│   ├── current.format          # Field index documentation for current.dat (42 fields)
│   ├── dailyforecast.format    # Field index documentation for dailyforecast.dat (40 fields)
│   ├── hourlyforecast.format   # Field index documentation for hourlyforecast.dat (36 fields)
│   ├── hourlyhistory.format    # Field index documentation for hourlyhistory.dat (38 fields)
│   └── dummies/                # Bootstrap .dat files (empty/placeholder weather data)
│       ├── current.dat
│       ├── dailyforecast.dat
│       ├── hourlyforecast.dat
│       ├── index.txt
│       └── weatherdata.html
├── templates/
│   ├── settings.html           # HTML::Template for admin settings page
│   ├── help.html               # Help page template
│   ├── addresslist.html        # Geolocation address list template
│   ├── Wettercodes.md          # Weather code reference (German)
│   ├── lang/                   # Language files for admin UI and grabbers
│   │   ├── language_de.ini
│   │   ├── language_en.ini
│   │   ├── language_es.ini
│   │   ├── language_nl.ini
│   │   └── language_sk.ini
│   └── themes/                 # Weather display HTML templates, per language
│       ├── de/                 # German locale theme variants
│       ├── en/                 # English locale theme variants
│       ├── es/                 # Spanish locale theme variants
│       ├── nl/                 # Dutch locale theme variants
│       └── at/                 # Austrian (de dialect) locale theme variants
│           Each locale dir contains:
│           ├── dark.main.html      # New-style: single template, all views
│           ├── dark.dfc.html       # Old-style: daily forecast partial
│           ├── dark.hfc.html       # Old-style: hourly forecast partial
│           ├── dark.map.html       # Map view partial
│           ├── light.main.html / light.dfc.html / light.hfc.html / light.map.html
│           ├── arctic.main.html    # New-style only themes (no separate partials)
│           ├── fresh.main.html
│           └── ocean.main.html
├── webfrontend/
│   ├── htmlauth/               # Authenticated CGI scripts (LoxBerry auth required)
│   │   ├── index.cgi           # Admin settings UI
│   │   ├── show.cgi            # Weather display widget
│   │   ├── ajax-handler.cgi    # JSON AJAX handler (manual fetch trigger)
│   │   ├── geolocation.cgi     # Nominatim geocoding helper
│   │   └── index.cgi.old       # Legacy settings CGI (kept as reference)
│   └── html/                   # Public static assets (no auth)
│       ├── weathercodes.html   # Weather codes reference page
│       ├── weathercodes1.html  # Alternative weather codes page
│       ├── WeatherCodes.md     # Weather code reference (English)
│       ├── lang-de.json / lang-en.json / lang-es.json / lang-nl.json / lang-sk.json
│       ├── icons/              # Weather icon sets
│       │   ├── color/          # Color icon set
│       │   ├── dark/           # Dark icon set
│       │   ├── flat/           # Flat icon set
│       │   ├── green/          # Green icon set
│       │   ├── light/          # Light icon set
│       │   ├── naturalistic/   # Naturalistic icon set
│       │   ├── realistic/      # Realistic icon set
│       │   ├── silver/         # Silver icon set (default)
│       │   ├── svg/            # SVG icon set
│       │   ├── custom/         # User-provided custom icons
│       │   └── emu/forecast/   # Cloud emulator forecast icons
│       ├── images/             # UI images
│       └── jquery/             # jQuery UI assets (css, js, themes)
├── icons/                      # Plugin icon files (LoxBerry plugin manager)
│   ├── icon_64.png
│   ├── icon_128.png
│   ├── icon_256.png
│   └── icon_512.png
├── sudoers/
│   └── sudoers                 # sudoers rules for plugin privileged operations
├── uninstall/
│   └── uninstall               # Uninstall hook script
└── dpkg/
    └── apt                     # Debian package dependencies list
```

---

## Directory Purposes

**`bin/`:**
- Purpose: All executable backend logic — scheduled scripts, grabbers, delivery, utilities
- Contains: Perl `.pl` scripts and Bash `.sh`/no-extension scripts
- Key files: `fetch.pl` (orchestrator), `datatoloxone.pl` (delivery), `grabber_utils.pl` (shared HTTP utility), all `grabber_*.pl` files

**`config/`:**
- Purpose: Runtime configuration persisted between updates
- Contains: `weather4lox.cfg` (INI, read by all scripts via `Config::Simple`), `apache2.conf` (cloud emulator vhost)
- Key files: `config/weather4lox.cfg` — single source of truth for all service keys, coordinates, intervals, and feature flags

**`daemon/`:**
- Purpose: LoxBerry boot-time hook
- Contains: Single `daemon` bash script that restores RAM-disk state on reboot
- Generated: No. Committed: Yes.

**`data/`:**
- Purpose: Static reference files and bootstrap dummy data
- Contains: `.format` files (field index docs), `dummies/` directory with placeholder `.dat` files for fresh installs
- Key files: `data/current.format`, `data/dailyforecast.format`, `data/hourlyforecast.format`, `data/hourlyhistory.format` — authoritative field definitions for all `.dat` interchange files

**`templates/`:**
- Purpose: HTML templates for admin UI and weather display
- Contains: `settings.html` (HTML::Template syntax with `<TMPL_VAR>` tags), theme HTML files (custom `<!--$varname-->` substitution), INI language files
- Key files: `templates/settings.html` (admin UI), `templates/themes/<lang>/<theme>.main.html` (weather display)

**`webfrontend/htmlauth/`:**
- Purpose: CGI scripts served under LoxBerry authenticated area
- Contains: Perl CGI scripts for plugin admin and weather display
- Key files: `index.cgi` (admin settings), `show.cgi` (weather widget), `ajax-handler.cgi` (AJAX endpoint)

**`webfrontend/html/`:**
- Purpose: Public static web assets (no authentication required)
- Contains: Icon sets, jQuery assets, language JSON files, weather code reference HTML pages
- Generated: No (icons and jQuery are vendored). Committed: Yes.

---

## Key File Locations

**Entry Points:**
- `bin/cronjob.pl`: Minutely cron entry — interval gate
- `bin/fetch.pl`: Fetch pipeline orchestrator
- `bin/datatoloxone.pl`: Data delivery to Loxone (UDP/MQTT) and HTML rendering
- `webfrontend/htmlauth/index.cgi`: Admin web UI
- `webfrontend/htmlauth/show.cgi`: Weather display widget
- `daemon/daemon`: Boot hook

**Configuration:**
- `config/weather4lox.cfg`: All runtime settings (service selection, API keys, coordinates, intervals, output settings)
- `plugin.cfg`: Plugin identity and LoxBerry framework metadata
- `config/apache2.conf`: Cloud emulator Apache vhost

**Core Logic:**
- `bin/grabber_utils.pl`: Shared HTTP client and key-masking utility — included by all grabbers
- `bin/grabber_openweather.pl`: Reference grabber implementation (most complete)
- `bin/datatoloxone.pl`: ~1400-line central delivery script; contains all UDP/MQTT send logic and HTML rendering

**Data Format Documentation:**
- `data/current.format`: Field index for `current.dat` (position 0–41)
- `data/dailyforecast.format`: Field index for `dailyforecast.dat` (position 0–39)
- `data/hourlyforecast.format`: Field index for `hourlyforecast.dat` (position 0–35)
- `data/hourlyhistory.format`: Field index for `hourlyhistory.dat` (position 0–37)

**Templates:**
- `templates/settings.html`: Admin UI (HTML::Template, `<TMPL_VAR>` / `<TMPL_IF>` / `<TMPL_LOOP>`)
- `templates/themes/<lang>/<theme>.main.html`: Weather display — new-style, uses `<!--$varname-->` placeholders
- `templates/lang/language_<lang>.ini`: Grabber and UI string translations

---

## Naming Conventions

**Files:**
- Grabber scripts: `grabber_<servicename>.pl` (lowercase, underscores) — e.g. `grabber_openweather.pl`, `grabber_wetteronline.pl`
- Theme HTML: `<themename>.<view>.html` where `<view>` is `main`, `dfc`, `hfc`, or `map` — e.g. `dark.main.html`, `light.dfc.html`
- Language files (templates): `language_<langcode>.ini` — e.g. `language_de.ini`
- Language files (web static): `lang-<langcode>.json` — e.g. `lang-en.json`
- Data files: `<type>.dat` and `<type>.dat.tmp` (temp written then renamed atomically)
- Config: `weather4lox.cfg` (single file, INI sections per service)

**Config INI Sections:**
- `[SERVER]` — global plugin settings (cron intervals, output targets, feature flags)
- `[WEB]` — display preferences (theme, iconset, language)
- `[OPENWEATHER]`, `[VISUALCROSSING]`, `[WEATHERFLOW]`, etc. — per-service API credentials and coordinates

**Named Value Prefixes (UDP/MQTT):**
- `cur_*` — current conditions (e.g. `cur_tt`, `cur_hu`, `cur_w_sp`)
- `dfc<N>_*` — daily forecast period N (e.g. `dfc1_tt_h`, `dfc3_we_icon`)
- `hfc<N>_*` — hourly forecast period N (e.g. `hfc1_tt`, `hfc12_pop`)
- `calc+<H>_*` — derived rolling aggregates over next H hours (e.g. `calc+24_prec`, `calc+48_ttmax`)

**Weather Icon Slugs:**
- Normalized icon names: `clear`, `partlycloudy`, `mostlycloudy`, `cloudy`, `rain`, `chancerain`, `snow`, `sleet`, `tstorms`, `fog`, `wind`, etc.
- Used in both `<icon_slug>` field in `.dat` files and as icon file basenames in `webfrontend/html/icons/<set>/`

---

## Where to Add New Code

**New Weather Service Grabber:**
- Create: `bin/grabber_<newservice>.pl` following the existing grabber contract
- Must: accept `--current`, `--daily`, `--hourly`, `--verbose`, `--maskkeys` flags; use `require "$lbpbindir/grabber_utils.pl"` for HTTP calls; write to `$lbplogdir/current.dat.tmp` → rename to `current.dat`; translate service-specific codes to Loxone picto-codes and icon slugs using a `%<service>_to_lox` hash
- Reference implementation: `bin/grabber_openweather.pl`
- Register: Add service option to `templates/settings.html` dropdown; add config section to `config/weather4lox.cfg`; `fetch.pl` discovers grabbers dynamically by filename pattern

**New Weather Display Theme:**
- Create: `templates/themes/<lang>/<themename>.main.html` (new-style: all views in one file using JavaScript tab switching)
- Or: `templates/themes/<lang>/<themename>.main.html` + `<themename>.dfc.html` + `<themename>.hfc.html` + `<themename>.map.html` (old-style: separate files)
- Use `<!--$varname-->` placeholders matching Perl variable names set in `datatoloxone.pl` and `show.cgi`
- Register: Add theme option to `templates/settings.html` select element

**New Delivered Data Variable:**
- Add field to the appropriate `.dat` file format (document in `data/*.format`)
- Populate the field in the relevant `grabber_*.pl` at the correct pipe-delimited position
- Read and emit in `bin/datatoloxone.pl` using `$name = "..."; $value = @fields[N]; &send;`
- Expose in `bin/datatoloxone.pl` / `webfrontend/htmlauth/show.cgi` for template use

**New Admin Settings Section:**
- Add fields to `config/weather4lox.cfg` under appropriate INI section
- Add form fields to `templates/settings.html` using `<TMPL_VAR>` for values and `<TMPL_IF>` for conditionals
- Read new params in `webfrontend/htmlauth/index.cgi` and relevant grabber/script

**New Language Translation:**
- Add: `templates/lang/language_<langcode>.ini` (for grabber strings — wind directions, month names)
- Add: `webfrontend/html/lang-<langcode>.json` (for weathercodes.html page)
- Add: Theme HTML files in `templates/themes/<langcode>/` for display templates

---

## Special Directories

**`.planning/`:**
- Purpose: Claude GSD planning documents
- Generated: No (manually curated)
- Committed: Yes

**`data/dummies/`:**
- Purpose: Bootstrap placeholder `.dat` files copied on fresh install by `postinstall.sh`
- Generated: No
- Committed: Yes

**`webfrontend/html/icons/emu/forecast/`:**
- Purpose: Icon symlink target for cloud emulator mode (Loxone cloud weather icon protocol)
- Generated: Partially (symlinks created by `postinstall.sh`)
- Committed: Directory structure yes, symlinks no

**`webfrontend/html/jquery/`:**
- Purpose: Vendored jQuery UI library assets
- Generated: No (vendored)
- Committed: Yes

---

*Structure analysis: 2026-03-12*
