# Technology Stack

**Analysis Date:** 2026-03-12

## Languages

**Primary:**
- Perl 5 - All backend data-fetching, processing, and web CGI scripts (`bin/*.pl`, `webfrontend/htmlauth/*.cgi`)

**Secondary:**
- Bash/Shell - Installation, daemon startup, cronjob orchestration, and Cloud Emulator control (`postinstall.sh`, `postroot.sh`, `postupgrade.sh`, `preupgrade.sh`, `daemon/daemon`, `bin/cloudemu`, `bin/weather4lox_cronjob.sh`)
- HTML/CSS/JS - Web frontend templates and jQuery-based UI (`templates/*.html`, `templates/themes/**/*.html`, `webfrontend/html/`)
- JSON - Language files and structured weather output (`webfrontend/html/lang-*.json`)
- INI - Plugin configuration and translations (`config/weather4lox.cfg`, `templates/lang/language_*.ini`)

## Runtime

**Environment:**
- LoxBerry OS (Debian/Raspberry Pi Linux) — the plugin is exclusively designed for the LoxBerry smart home gateway platform
- Minimum LoxBerry version: 1.2.5 (declared in `plugin.cfg`)
- Plugin Interface: 2.0

**Web Server:**
- Apache2 — serves both the standard LoxBerry web frontend and the optional Cloud Emulator on port 6066 (`config/apache2.conf`)
- CGI execution via Apache2 mod_cgi for `*.cgi` scripts

**Package Manager:**
- Debian APT — system-level Perl module installation declared in `dpkg/apt`

## Frameworks

**Core:**
- LoxBerry::System — LoxBerry platform integration (plugin versioning, path vars, language loading). Provided by LoxBerry OS.
- LoxBerry::Log — Structured logging to plugin log directory. Provided by LoxBerry OS.
- LoxBerry::Web — CGI web response helpers and template rendering. Provided by LoxBerry OS.
- LoxBerry::IO — LoxBerry I/O utilities (used in `datatoloxone.pl`, `grabber_loxone.pl`). Provided by LoxBerry OS.
- LoxBerry::JSON — LoxBerry JSON helpers (used in `ajax-handler.cgi`). Provided by LoxBerry OS, requires LoxBerry 2.0+.
- HTML::Template — Perl template engine for rendering settings and address list pages (`webfrontend/htmlauth/index.cgi`, `geolocation.cgi`)

**Testing:**
- No test framework detected

**Build/Dev:**
- No build system; plugin is distributed as a ZIP archive for LoxBerry's plugin installer

## Key Dependencies

**Critical (declared in `dpkg/apt`):**
- `libjson-perl` — JSON encode/decode for all weather API responses
- `libdatetime-format-iso8601-perl` — ISO 8601 date parsing (used in `grabber_wetteronline.pl`)
- `dnsmasq` — DNS redirection for the Cloud Emulator feature (redirects `weather.loxone.com`)

**Used in Perl scripts (CPAN/system packages):**
- `LWP::UserAgent` — HTTP client for all weather API calls (`bin/grabber_*.pl`, `webfrontend/htmlauth/geolocation.cgi`)
- `JSON` / `JSON::PP` — JSON decoding (all grabbers); `JSON::PP` used in `grabber_utils.pl` for output
- `Config::Simple` — INI-style config file read/write (`weather4lox.cfg`)
- `Getopt::Long` — Command-line argument parsing for all `bin/*.pl` scripts
- `Time::Piece` — Time formatting and manipulation in most grabbers
- `Time::Seconds` — Time arithmetic (`grabber_visualcrossing.pl`)
- `DateTime` — Date calculations with Loxone epoch conversion (`datatoloxone.pl`, `grabber_wetteronline.pl`, `grabber_openmeteo_airquality.pl`)
- `Astro::MoonPhase` — Moon phase calculations injected into weather data (`grabber_openweather.pl`, `grabber_visualcrossing.pl`, `grabber_weatherflow.pl`, `grabber_wttrin.pl`, `grabber_wetteronline.pl`)
- `Net::MQTT::Simple` — MQTT publishing of weather data to Loxone Miniserver (`datatoloxone.pl`)
- `IO::Socket` — UDP packet sending to Loxone Miniserver (`datatoloxone.pl`)
- `Math::Function::Interpolator` — Hourly data interpolation (`grabber_wttrin.pl`)
- `File::Copy` — Atomic `.tmp` → `.dat` file promotion in all grabbers
- `File::HomeDir` — Home directory resolution (`show.cgi`, `datatoloxone.pl`)
- `CGI` — CGI parameter handling for web interface scripts
- `CGI::Carp` — CGI error output to browser
- `HTML::Entities` — HTML entity encoding (`grabber_wetteronline.pl`)
- `URI::Escape` — URL encoding for geolocation search (`geolocation.cgi`)
- `HTTP::Request` — Low-level HTTP request construction (`grabber_wetteronline.pl`)
- `Encode` — UTF-8 encoding/decoding throughout all grabbers
- `POSIX` — `strftime`, `floor`, and timezone operations (`grabber_utils.pl`, `grabber_openmeteo_airquality.pl`)

## Configuration

**Environment:**
- All runtime paths are injected by LoxBerry OS as Perl variables: `$lbpconfigdir`, `$lbpbindir`, `$lbplogdir`, `$lbptemplatedir`, `$lbhomedir`, `$lbpdata`
- Plugin config file: `config/weather4lox.cfg` (INI format, read/written via `Config::Simple`)
- No `.env` files; no secrets in source — API keys stored exclusively in `weather4lox.cfg` at runtime

**Build:**
- `plugin.cfg` — Plugin metadata for LoxBerry installer (name, version, autoupdate URLs)
- `release.cfg` — Current release version and download URL for autoupdate
- `prerelease.cfg` — Prerelease version for beta autoupdate channel
- `postinstall.sh` / `postupgrade.sh` — Post-install hooks run by LoxBerry installer

## Platform Requirements

**Development:**
- Perl 5 with CPAN modules listed above
- LoxBerry OS environment variables (or manual substitution for `REPLACELBP*` tokens)

**Production:**
- LoxBerry OS 1.2.5+ on Raspberry Pi (any architecture — `ARCHITECTURE=""` in `plugin.cfg`)
- Apache2 with mod_cgi
- dnsmasq (for Cloud Emulator feature)
- All Perl modules from `dpkg/apt` auto-installed by LoxBerry plugin installer

---

*Stack analysis: 2026-03-12*
