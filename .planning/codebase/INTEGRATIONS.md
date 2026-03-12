# External Integrations

**Analysis Date:** 2026-03-12

## APIs & External Services

### Primary Weather Services (user selects one as default source)

**OpenWeatherMap:**
- Used for: Current conditions, daily forecast (8 days), hourly forecast (48h OneCall + 3-hourly extension to ~7 days)
- Grabber: `bin/grabber_openweather.pl`
- API endpoints: `https://api.openweathermap.org/data/3.0/onecall` (primary), `https://api.openweathermap.org/data/2.5/forecast` (3-hourly extension)
- Auth: API key stored in `weather4lox.cfg` as `OPENWEATHER.APIKEY`, passed as `?appid=` query param
- Config section: `[OPENWEATHER]`

**Visual Crossing:**
- Used for: Current conditions, daily forecast, hourly forecast
- Grabber: `bin/grabber_visualcrossing.pl`
- API endpoint: `https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline`
- Auth: API key in `VISUALCROSSING.APIKEY`, passed as `?key=` query param
- Config section: `[VISUALCROSSING]`

**WeatherFlow:**
- Used for: Current conditions, daily forecast, hourly forecast from personal weather stations
- Grabber: `bin/grabber_weatherflow.pl`
- API endpoint: `https://swd.weatherflow.com/swd/rest`
- Auth: API key in `WEATHERFLOW.APIKEY`, station ID in `WEATHERFLOW.STATIONID`
- Config section: `[WEATHERFLOW]`

**wttr.in:**
- Used for: Current conditions, daily and hourly forecast (no API key required)
- Grabber: `bin/grabber_wttrin.pl`
- API endpoint: `https://wttr.in`
- Auth: None
- Config section: `[WTTRIN]`

**Wetteronline.de:**
- Used for: Current conditions, daily and hourly forecast (German weather service)
- Grabber: `bin/grabber_wetteronline.pl`
- API endpoints: `https://www.wetteronline.de/wetter/` (current), `https://api-app.wetteronline.de/app/weather/forecast?` (daily), `https://api-app.wetteronline.de/app/weather/hourcast?` (hourly)
- Auth: Hardcoded obfuscated API keys in source (`grabber_wetteronline.pl` line 58–59); uses browser-like User-Agent string
- Config section: `[WETTERONLINE]`

### Supplementary/Override Data Sources (run alongside primary service)

**Weather Underground (Personal Weather Stations):**
- Used for: Overwriting current conditions with local PWS data
- Grabber: `bin/grabber_wu.pl`
- API endpoint: `https://api.weather.com/v2/pws/observations/current`
- Auth: API key in `WUNDERGROUND.APIKEY`, station ID in `WUNDERGROUND.STATIONID`
- Config section: `[WUNDERGROUND]`
- Enabled by: `SERVER.WUGRABBER=1`

**FOSHKplugin (Local Weather Station):**
- Used for: Overwriting current conditions from a locally hosted FOSHKplugin instance
- Grabber: `bin/grabber_foshk.pl`
- API endpoint: Local HTTP server configured in `FOSHK.SERVER` / `FOSHK.PORT`, path `observations/current/json/units=m`
- Auth: None (local network)
- Config section: `[FOSHK]`
- Enabled by: `SERVER.FOSHKGRABBER=1`

**PWSCatchUpload:**
- Used for: Overwriting current conditions from a local PWSCatch instance
- Grabber: `bin/grabber_pwscatchupload.pl`
- Data source: Reads JSON from `/dev/shm/pwscatchupload_w4l.json` (RAM disk, written by external process)
- Auth: None (filesystem read)
- Enabled by: `SERVER.PWSCATCHUPLOADGRABBER=1`

**Open-Meteo Air Quality API:**
- Used for: Air quality and pollen data
- Grabber: `bin/grabber_openmeteo_airquality.pl`
- API endpoint: `https://air-quality-api.open-meteo.com/v1/air-quality`
- Auth: None (free API, no key required)
- Config section: `[OPENMETEOAIRQUALITY]`
- Enabled by: `SERVER.OPENMETEOAIRQUALITYGRABBER=1`

**Loxone Miniserver:**
- Used for: Pulling sensor data directly from the Loxone Miniserver to augment current conditions
- Grabber: `bin/grabber_loxone.pl`
- Protocol: LoxBerry::IO (LoxBerry's built-in Miniserver communication layer)
- Auth: Managed by LoxBerry OS
- Enabled by: `SERVER.LOXGRABBER=1`

### Geolocation

**Nominatim (OpenStreetMap):**
- Used for: Location search / coordinate lookup in the settings UI
- Endpoint: `https://nominatim.openstreetmap.org/search?q=...&format=json&addressdetails=1`
- Auth: None (open API; custom User-Agent `Weather4Lox-LoxBerry/4.15` sent as per OSM policy)
- Used in: `webfrontend/htmlauth/geolocation.cgi`

## Data Storage

**Databases:**
- No external database. All persistent data stored as pipe-delimited flat files (`.dat`) and JSON files on disk.
- Live working files in `$LBPLOGDIR` (RAM disk when available): `current.dat`, `dailyforecast.dat`, `hourlyforecast.dat`, `hourlyhistory.dat`
- Corresponding JSON exports: `current.json`, `dailyforecast.json`, `hourlyforecast.json` (written by `grabber_utils.pl` helpers `write_current_json`, `write_daily_json`, `write_hourly_json`)
- Persisted backup copy in `$LBPDATADIR` (written by `bin/weather4lox_cronjob.sh`, restored on boot by `daemon/daemon`)
- Plugin config: `config/weather4lox.cfg` (INI format, read/written by `Config::Simple`)

**File Storage:**
- Local filesystem only. No cloud storage.

**Caching:**
- No explicit cache layer. Data files on RAM disk act as a working cache; `.tmp` files promote to `.dat` atomically via `File::Copy::move` after validation (size > 100 bytes).

## Authentication & Identity

**Auth Provider:**
- LoxBerry OS handles all user authentication for the plugin's web admin pages (`webfrontend/htmlauth/` — requires login via LoxBerry)
- API keys for external weather services are stored by the user in `config/weather4lox.cfg` and never committed to the repository

## Monitoring & Observability

**Error Tracking:**
- None (no external service)

**Logs:**
- LoxBerry::Log framework writes structured log files to `$LBPLOGDIR/` (e.g., `fetch.log`, `datatoloxone.log`, `grabber_openweather.log`)
- Log level controlled per-plugin via LoxBerry's admin UI (`CUSTOM_LOGLEVELS=True` in `plugin.cfg`)
- API keys masked in log output by `grabber_utils.pl::sanitize_url` and `sanitize_dump` when `maskkeys` flag is set (default: enabled)

## CI/CD & Deployment

**Hosting:**
- Runs on user's own LoxBerry hardware (Raspberry Pi)
- Plugin distributed as a ZIP archive downloaded by LoxBerry's plugin installer

**Autoupdate:**
- Release channel: polling `https://raw.githubusercontent.com/jan21493/LoxBerry-Plugin-Weather4Lox/v4-prod/release.cfg`
- Prerelease channel: polling `https://raw.githubusercontent.com/jan21493/LoxBerry-Plugin-Weather4Lox/v4-prod/prerelease.cfg`
- Archive download: GitHub releases ZIP (URL in `release.cfg`)

**CI Pipeline:**
- None detected

## Environment Configuration

**Required config keys (in `config/weather4lox.cfg`):**
- `SERVER.WEATHERSERVICE` — name of primary grabber (e.g., `openweather`, `visualcrossing`, `weatherflow`, `wttrin`, `wetteronline`)
- `SERVER.WEATHERSERVICEDFC` / `SERVER.WEATHERSERVICEHFC` — optional alternate grabbers for daily/hourly forecasts
- `SERVER.CRON` / `SERVER.CRON_ALTERNATE` — fetch interval in minutes (default: 15)
- `SERVER.SENDUDP` / `SERVER.UDPPORT` — UDP output to Loxone Miniserver
- `SERVER.TOPIC` — MQTT topic prefix (default: `weather4lox`)
- `SERVER.EMU` — enable Cloud Emulator (0/1)
- `SERVER.METRIC` — metric (1) or imperial (0) units
- Per-service sections: `[OPENWEATHER]`, `[VISUALCROSSING]`, `[WEATHERFLOW]`, `[WUNDERGROUND]`, `[FOSHK]`, `[WTTRIN]`, `[WETTERONLINE]`, `[OPENMETEOAIRQUALITY]`
- Each service section contains: `APIKEY`, `COORDLAT`, `COORDLONG`, `LANG`, `URL` (URL values reset to defaults on each settings save via `webfrontend/htmlauth/index.cgi`)

**Secrets location:**
- `config/weather4lox.cfg` at runtime on the LoxBerry device. Not stored in the repository (file in repo is a template with empty API key values).

## Webhooks & Callbacks

**Incoming:**
- Cloud Emulator: Apache2 virtual host on port 6066 intercepts requests to `weather.loxone.com` / `weather-beta.loxone.com` (DNS redirected via dnsmasq) and serves weather data in the format expected by the Loxone Miniserver (`config/apache2.conf`, `bin/cloudemu`)
- AJAX handler: `webfrontend/htmlauth/ajax-handler.cgi` handles JSON-based AJAX calls from the settings UI (e.g., trigger fetch, save MQTT settings)

**Outgoing:**
- UDP packets to Loxone Miniserver (`datatoloxone.pl`, via `IO::Socket`, port configured in `SERVER.UDPPORT`, default 7000)
- MQTT publish to Loxone Miniserver (`datatoloxone.pl`, via `Net::MQTT::Simple`, topic prefix from `SERVER.TOPIC`)

---

*Integration audit: 2026-03-12*
