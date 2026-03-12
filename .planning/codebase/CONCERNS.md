# Codebase Concerns

**Analysis Date:** 2026-03-12

---

## Tech Debt

**`strict`/`warnings` disabled in core CGI files:**
- Issue: `use strict` and `use warnings` are commented out in `webfrontend/htmlauth/index.cgi`, `webfrontend/htmlauth/show.cgi`, and `bin/datatoloxone.pl`. This disables Perl's primary safety net against typos in variable names, undeclared variables, and type coercions.
- Files: `webfrontend/htmlauth/index.cgi` (lines 29–30), `webfrontend/htmlauth/show.cgi` (lines 27–28), `bin/datatoloxone.pl` (lines 17–18)
- Impact: Bugs from misspelled variable names or unexpected undef values go undetected at compile time and cause silent data corruption or runtime failures.
- Fix approach: Re-enable both pragmas and resolve the variable declaration issues that prevented them from being enabled (typically `our` vs `my` declarations and CGI symbolic references).

**`show.cgi` is a standalone legacy file with hardcoded version:**
- Issue: `webfrontend/htmlauth/show.cgi` does not use the LoxBerry framework (`lbpbindir`, `LoxBerry::System`, etc.). It has a hardcoded version string `my $version = "4.7.0.2"` at line 35, uses `File::HomeDir` to locate config files, and manually parses `QUERY_STRING` instead of using the CGI module properly.
- Files: `webfrontend/htmlauth/show.cgi`
- Impact: Version number falls out of sync with the plugin version. Config path discovery is fragile. Query string parsing does not handle edge cases (e.g., empty values at end of string).
- Fix approach: Migrate to LoxBerry framework imports like all other CGI files. Use `LoxBerry::System::pluginversion()` for the version.

**`datatoloxone.pl` uses positional array field access throughout:**
- Issue: The entire data pipeline in `bin/datatoloxone.pl` accesses parsed `.dat` file fields by numeric index (e.g., `@fields[11]`, `@fields[28]`). The field meanings are not named constants; the mapping is only documented in format files under `data/`.
- Files: `bin/datatoloxone.pl` (lines 100–1480 and beyond)
- Impact: Adding or reordering a field in any grabber's output silently breaks all downstream consumers. The field-index-to-meaning mapping is tribal knowledge scattered across multiple files.
- Fix approach: Introduce named constants for column indices (or adopt the JSON output path for all consumers), so field additions are caught at the right place.

**Duplicate config key `TOPIC` in `weather4lox.cfg`:**
- Issue: The shipped `config/weather4lox.cfg` contains the `TOPIC` key twice in the `[SERVER]` section (lines 26 and 41). `Config::Simple` silently uses the last occurrence.
- Files: `config/weather4lox.cfg` (lines 26, 41)
- Impact: The quoted form `TOPIC="weather4lox"` and the bare form `TOPIC=weather4lox` coexist. While Config::Simple handles this, it is confusing and fragile if someone manually edits the file.
- Fix approach: Remove the duplicate; keep only one canonical `TOPIC=weather4lox` entry.

**Duplicate `SERVER.WUGRABBER` config write in settings save:**
- Issue: `webfrontend/htmlauth/index.cgi` lines 224–225 call `$cfg->param("SERVER.WUGRABBER", ...)` twice in succession with the same value.
- Files: `webfrontend/htmlauth/index.cgi` (lines 224–225)
- Impact: Cosmetic/harmless today, but confusing during maintenance and indicates copy-paste error that may hide a missing different key.
- Fix approach: Remove the duplicate line.

**`index.cgi.old` committed to repository:**
- Issue: `webfrontend/htmlauth/index.cgi.old` is a full copy of a prior version of the settings CGI checked into the repository. It is not referenced by anything.
- Files: `webfrontend/htmlauth/index.cgi.old`
- Impact: Increases maintenance surface, creates confusion about which file is authoritative, and risks accidental deployment.
- Fix approach: Delete the file and rely on git history.

**Wind direction mapping duplicated across every grabber:**
- Issue: Every grabber (`grabber_openweather.pl`, `grabber_visualcrossing.pl`, `grabber_wetteronline.pl`, `grabber_wttrin.pl`, `grabber_weatherflow.pl`) contains an identical 9-branch `if/elsif` ladder to convert wind degrees to compass direction strings. The code is copy-pasted, not shared.
- Files: `bin/grabber_openweather.pl` (lines 227–235, 377–385, 486–494), `bin/grabber_visualcrossing.pl` (same pattern), and all other grabbers.
- Impact: A fix to the boundary conditions (e.g., exactly 360°) or a new direction abbreviation must be applied in 5+ places.
- Fix approach: Extract `wind_deg_to_dir()` as a shared sub in `bin/grabber_utils.pl`.

**Cleanup/null-substitution pattern duplicated 3× per grabber:**
- Issue: Each grabber repeats the same block of `s/\|null\|/...` regex substitutions three times (for current, daily, hourly `.dat.tmp` files). The pattern is identical across all grabbers.
- Files: `bin/grabber_openweather.pl` (lines 719–816), `bin/grabber_visualcrossing.pl` (lines 496–591), and similarly in all other main grabbers.
- Impact: Any new null-value pattern to sanitize must be added in 15+ locations.
- Fix approach: Move the cleanup block into a `clean_datfile($path)` utility function in `grabber_utils.pl`.

---

## Security Considerations

**`qx()` shell execution with API-supplied values (injection risk):**
- Issue: Several grabbers pass API response values directly into `qx()` (backtick) shell calls without sanitization. For example, `grabber_openweather.pl` passes `$decoded_json->{timezone}` directly into shell: `qx(TZ='$decoded_json->{timezone}' date +%Z)`. A malicious or malformed API response containing shell metacharacters in the timezone field could achieve command injection.
- Files: `bin/grabber_openweather.pl` (lines 208, 212), `bin/grabber_visualcrossing.pl` (lines 172, 176), `bin/grabber_weatherflow.pl` (line 192), `bin/grabber_wetteronline.pl` (lines 582, 587, 595)
- Impact: Unexpected shell execution if a weather API returns a crafted timezone string.
- Current mitigation: The values originate from trusted API providers. The `TZ='...'` quoting uses single quotes which prevents variable expansion but not all injection.
- Recommendations: Validate the timezone string against a whitelist pattern (`/^[A-Za-z_\/+-]+$/`) before interpolating into `qx()`. Alternatively, use `POSIX::strftime` with `$ENV{TZ}` set programmatically (as already done in `grabber_utils.pl`'s `_epoch_to_iso()`).

**`MQTT_SIMPLE_ALLOW_INSECURE_LOGIN` set globally in environment:**
- Issue: `bin/datatoloxone.pl` line 1895 sets `$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1`, which permits unencrypted MQTT credentials to be transmitted. This is set unconditionally, regardless of broker TLS configuration.
- Files: `bin/datatoloxone.pl` (line 1895)
- Impact: Credentials could be exposed in plaintext on the network if the broker does not enforce TLS.
- Current mitigation: MQTT is local-network only in typical LoxBerry deployments.
- Recommendations: Only set the flag when the broker is detected as non-TLS, or document the known limitation prominently.

**Wetteronline API key hardcoded in source and config:**
- Issue: The Wetteronline grabber embeds two private API keys in plain text (`$apikey = "av=2&mv=13&c=d2ViOmFxcnhwWDR3ZWJDSlRuWeb="` and `$apikey_current = "c=d293ZWI6QzhMNFRINmVUbkRoVWFqYg=="`). These appear verbatim in `bin/grabber_wetteronline.pl` and are also written to `config/weather4lox.cfg` via `index.cgi`.
- Files: `bin/grabber_wetteronline.pl` (lines 58–59), `webfrontend/htmlauth/index.cgi` (line 217), `config/weather4lox.cfg` (line 82)
- Impact: Anyone who can read the plugin files or config has these credentials. If the Wetteronline service revokes or rotates these keys, the grabber silently breaks for all users.
- Current mitigation: Keys appear obfuscated as base64 but are not actually encrypted.
- Recommendations: Document the keys as community-shared/reverse-engineered credentials; monitor for revocation.

**`show.cgi` parses `QUERY_STRING` manually, no input sanitization:**
- Issue: `webfrontend/htmlauth/show.cgi` (lines 59–76) manually splits `QUERY_STRING` and applies URL-decoding via a regex (`s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg`). The decoded values are then used via symbolic references (`${$var} = $query{$var}`), which allows any query parameter name that matches a global variable to be overwritten.
- Files: `webfrontend/htmlauth/show.cgi` (lines 59–76)
- Impact: An attacker who can craft a URL with a matching variable name (e.g., `?home=/tmp`) could redirect file reads. The risk is mitigated because `htmlauth/` is behind LoxBerry authentication.
- Recommendations: Replace manual parsing with `CGI->new->Vars` and eliminate symbolic reference variable assignment.

---

## Known Bugs

**Error check after file open runs after flock, not before:**
- Symptoms: In grabbers, the file is opened and `flock(F,2)` is called, and only then the `$error` flag is checked. If the open fails, the flock succeeds on an undefined filehandle or is a no-op, but the subsequent `if ($error) { exit 2 }` check still exits correctly. However, the log message says the wrong path (references `$lbpconfigdir` instead of `$lbplogdir`).
- Files: `bin/grabber_openweather.pl` (line 200: `LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp"`), same pattern in all grabbers' current section.
- Impact: Log messages for file-open failures point to the wrong directory, causing confusion during debugging.
- Fix approach: Change `$lbpconfigdir` to `$lbplogdir` in the LOGCRIT message.

**`datatoloxone.pl` reads `current.dat` without error handling:**
- Symptoms: `bin/datatoloxone.pl` line 118 opens `$lbplogdir/current.dat` with no `or die` and no error check. If the file is missing or empty (e.g., on a fresh install before any fetch runs), `$curdata` is undef, and subsequent `split` and field accesses silently produce empty values.
- Files: `bin/datatoloxone.pl` (lines 118–133)
- Impact: Silent data corruption sent to Loxone Miniserver or MQTT on fresh install or after a failed fetch.
- Fix approach: Add `or LOGCRIT "..."; exit 1` to the `open()` call, or ensure dummy files are always present (postinstall.sh already copies dummy files but only if absent).

**Minimal file size check of 100 bytes is fragile:**
- Symptoms: All grabbers check `if ($currentsize > 100) { move(...) }` before promoting the `.dat.tmp` file to `.dat`. A valid file with many `-9999` sentinel values could legitimately be under 100 bytes, or a truncated file larger than 100 bytes would be promoted.
- Files: `bin/grabber_openweather.pl` (lines 744–746), and identically in every other grabber.
- Impact: Corrupt or empty `.dat` files could be promoted if the fetch partially succeeds.
- Fix approach: Validate that the file contains at least one non-comment, non-empty line with the correct number of `|`-delimited fields rather than relying on file size.

---

## Performance Bottlenecks

**Synchronous sequential grabber execution via `system()`:**
- Problem: `bin/fetch.pl` calls each grabber and optional supplementary grabbers sequentially using `system()`. Each API call blocks until the previous one completes.
- Files: `bin/fetch.pl` (lines 109, 125, 134, 146, 159, 167, 175, 183, 191, 198)
- Cause: Simple `system()` calls with no parallelism.
- Improvement path: For grabbers that are independent (e.g., the WU grabber, FOSHK grabber, and the main grabber), parallel execution with `fork()` or `Parallel::ForkManager` could reduce wall-clock time significantly.

**`Astro::MoonPhase::phase()` called once per forecast period:**
- Problem: In the hourly grabbers, `phase($epoch)` from `Astro::MoonPhase` is called inside the per-record loop (up to 168 iterations). This is a pure computation but still accumulates.
- Files: `bin/grabber_openweather.pl` (lines 528–534), `bin/grabber_visualcrossing.pl` (lines 464–470), `bin/grabber_wetteronline.pl` (line 1420)
- Cause: No memoization or batch computation.
- Improvement path: Cache `phase()` results keyed to the hour or day bucket, since moon phase changes slowly.

**`datatoloxone.pl` reads entire `.dat` files into memory for template substitution:**
- Problem: `bin/datatoloxone.pl` reads all three `.dat` files into memory and then generates HTML pages via line-by-line template substitution using `$_ =~ s/<!--\$(.*?)-->/${$1}/g` (eval-like symbolic glob substitution).
- Files: `bin/datatoloxone.pl` (lines 1277, 1367, 1454, 1560)
- Cause: Legacy template engine uses Perl glob variable interpolation in template strings.
- Improvement path: Migrate to `HTML::Template` (already used in `index.cgi`) which is safer and caches compiled templates.

---

## Fragile Areas

**`grabber_wetteronline.pl` is a web scraper, not an API client:**
- Files: `bin/grabber_wetteronline.pl`
- Why fragile: The wetteronline grabber scrapes the wetteronline.de HTML page to extract a JSON blob embedded in a `<script>` tag using a recursive regex (`qr/WO\.geo = (\{...\})/s`). It then hits undocumented internal API endpoints (`api-web.wo-cloud.com`, `api-app.wetteronline.de`) with hardcoded private API keys. Any front-end change to wetteronline.de or rotation of their internal API keys breaks this grabber entirely and silently.
- Safe modification: Any change to URL patterns, JSON key names, or the regex must be tested against a live response. The `api_call()` abstraction in `grabber_utils.pl` helps but does not protect against schema changes.
- Test coverage: None.

**Hourly data interpolation in `grabber_openweather.pl` accesses `.dat.tmp` file while still open for writing:**
- Files: `bin/grabber_openweather.pl` (lines 544–700)
- Why fragile: After writing the first 48 hours of hourly data, the script re-opens the same `hourlyforecast.dat.tmp` file in `+<` (read-write) mode without closing the previous write handle, and appends interpolated data. The interpolation reads `$oldfields[1]` from the last line parsed and uses `$i` from the outer scope. If the initial write has fewer records than expected, `$lastline` may be wrong, causing index-shifted output.
- Safe modification: Always close the write handle before re-opening for read-write. Add a guard that verifies `$lastline` is non-empty before interpolating.

**Template substitution via Perl symbolic references is an implicit eval:**
- Files: `bin/datatoloxone.pl` (line 1277: `$_ =~ s/<!--\$(.*?)-->/${$1}/g`)
- Why fragile: The substitution dereferences `${$1}` where `$1` is taken directly from the template HTML file. If a template file ever contains `<!--$ENV{HOME}-->` or similar, it would expose the value of arbitrary Perl global or environment variables. Template files are developer-controlled, so risk is low, but the pattern is inherently unsafe.
- Safe modification: Validate that template variable names match a strict pattern (`/^[a-z_][a-z0-9_.]*$/i`) before dereferencing.

**`show.cgi` hardcodes its own version number:**
- Files: `webfrontend/htmlauth/show.cgi` (line 35)
- Why fragile: The string `"4.7.0.2"` is hardcoded and must be manually updated on each release. It is already out of sync with `release.cfg` or `prerelease.cfg`.
- Safe modification: Replace with `LoxBerry::System::pluginversion()`.

---

## Dependencies at Risk

**Wetteronline integration depends on private/undocumented APIs:**
- Risk: The grabber uses two base64-encoded API keys for `api-web.wo-cloud.com` and `api-app.wetteronline.de`. These are not public APIs; they appear to be the mobile app backend. Wetteronline can rotate keys or change their API at any time without notice.
- Impact: `grabber_wetteronline.pl` stops working completely with no actionable error.
- Migration plan: Monitor the wetteronline.de website for structural changes; maintain fallback to another service in user configuration.

**wttr.in dependency is an unofficial, best-effort service:**
- Risk: `grabber_wttrin.pl` depends on the public `wttr.in` service which has no SLA or official API contract.
- Impact: Service outages or changes to the JSON response schema break the grabber.
- Migration plan: Users should configure a paid API (OpenWeatherMap, Visual Crossing) as fallback.

**`Math::Function::Interpolator` is a non-standard Perl module:**
- Risk: `grabber_wetteronline.pl` requires `Math::Function::Interpolator` and `Math::Function::Interpolator::Linear` for hourly forecast generation. These modules are not part of the Perl core or common LoxBerry base image.
- Impact: If the module is missing, the wetteronline hourly grabber exits with a LOGCRIT (handled gracefully via `require_or_logdie`), but silently delivers no hourly data.
- Migration plan: Ensure the modules are listed in `dpkg/apt` package manifest; add to postinstall verification.

---

## Test Coverage Gaps

**No automated tests exist:**
- What's not tested: Every grabber, the data pipeline, the CGI settings handler, the emulator output generator, and MQTT publishing.
- Files: All files in `bin/` and `webfrontend/htmlauth/`
- Risk: Regressions in field mapping, unit conversion, or API response parsing go undetected until a user reports them in production.
- Priority: High — the plugin runs on a live smart home system where stale or wrong weather data affects automation rules.

**No validation of `.dat` file field counts:**
- What's not tested: Whether the number of pipe-delimited fields written by a grabber matches what `datatoloxone.pl` and `grabber_utils.pl` expect.
- Files: All grabbers write to `.dat` files; `grabber_utils.pl` (lines 182–218 define field lists); `bin/datatoloxone.pl` accesses by index.
- Risk: A silent column-count mismatch (adding a field in one grabber without updating the consumer) causes all downstream field reads to be off by one. Loxone receives wrong sensor values with no error.
- Priority: High — any new grabber feature that adds a column must be validated end-to-end.

**No tests for weather code mapping tables:**
- What's not tested: The `owm_to_lox`, `vc_to_lox`, and `wetteronline_to_lox` hash lookups and their fallback behavior.
- Files: `bin/grabber_openweather.pl` (lines 88–164), `bin/grabber_visualcrossing.pl` (lines 113–145), `bin/grabber_wetteronline.pl` (lines 246–550)
- Risk: Unmapped weather codes silently fall back to `"clear"` (code 1), making stormy conditions appear as sunny in the Loxone UI.
- Priority: Medium.

---

## Missing Critical Features

**No retry logic on API call failure:**
- Problem: `grabber_utils.pl`'s `api_call()` exits immediately with code 2 on any non-200 HTTP status. Transient network errors (e.g., a 503 during a service restart) cause the entire fetch to fail and leave stale data.
- Blocks: Reliable data delivery during network instability.
- Suggested fix: Add configurable retry with backoff (e.g., 3 retries with 10-second delay) before propagating a fatal error.

**No stale-data detection or alerting:**
- Problem: If a grabber fails silently (e.g., the `.dat.tmp` file is too small and is not promoted), `datatoloxone.pl` continues to use the old `.dat` file indefinitely. The Miniserver receives no indication that data is stale.
- Blocks: Users cannot distinguish "no update yet" from "update is broken".
- Suggested fix: Include a `last_successful_fetch` timestamp in the MQTT/UDP output and in the emulator metadata.

**JSON output not generated by all grabbers:**
- Problem: `grabber_utils.pl` provides `write_current_json()`, `write_daily_json()`, `write_hourly_json()`. These are called by the main API grabbers (OpenWeather, VisualCrossing, etc.), but `grabber_wu.pl`, `grabber_foshk.pl`, `grabber_loxone.pl`, and `grabber_pwscatchupload.pl` only patch `current.dat` in place and do not regenerate the JSON files. The JSON outputs become stale relative to the `.dat` files after a patch-only update.
- Files: `bin/grabber_wu.pl`, `bin/grabber_foshk.pl`, `bin/grabber_loxone.pl`, `bin/grabber_pwscatchupload.pl`
- Priority: Medium — only affects consumers using the newer JSON API.

---

*Concerns audit: 2026-03-12*
