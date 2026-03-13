# Phase 1: JSON Schema & Grabber Migration - Research

**Researched:** 2026-03-12
**Domain:** Perl grabber architecture, JSON::PP, .dat-to-JSON conversion, LoxBerry plugin system
**Confidence:** HIGH — primary source is the actual codebase

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**JSON-Schema-Struktur:**
- Jede JSON-Datei hat Top-Level-Objekt mit `meta` und `data`
- `meta` enthalt: `schema_version` ("1.0"), `source` (Grabber-Name), `generated_at` (ISO 8601), `grabber` (Dateiname)
- `data` bei current.json: einzelnes Objekt mit Wetterdaten
- `data` bei hourly.json und daily.json: Array von Objekten, sortiert nach Zeit
- Feld-Benennung: snake_case (konsistent mit bestehendem grabber_utils.pl)
- Fehlende/leere Werte: JSON `null` (nicht weglassen, nicht Default-Werte)

**Supplementary Grabber Scope:**
- Alle 5 Supplementary-Grabber (WU, FOSHK, PWS, Loxone, OpenMeteo AQ) schreiben JSON
- Uberschreiben current.json wie sie current.dat uberschreiben (gleicher Mechanismus)
- Fehlende Felder werden als `null` gesetzt (vollstandiges Schema, nicht nur verfugbare Felder)
- OpenMeteo Air Quality: Pollen/AQ-Felder werden ins current-Schema integriert (kein separates File)
- Haupt-Grabber setzen AQ-Felder auf `null`
- Alle Grabber nutzen `write_current_json()` aus grabber_utils.pl

**Fehlerverhalten & Logging:**
- .dat hat Prioritat: JSON-Write-Fehler stoppen nicht den Grabber-Lauf
- Log-Level: LOGOK bei erfolgreichem JSON-Write, LOGWARN bei Fehler
- Keine Re-Validierung nach dem Schreiben (JSON::PP erzeugt gultiges JSON, atomarer Write schutzt)
- Bei Encoding-Fehler (ungultiges UTF-8): gesamten JSON-Write uberspringen, vorherige Datei bleibt bestehen

**Schema-Dokumentation:**
- Format: Markdown-Referenz (data/json-schema.md)
- Enthalt: Feld-Tabellen (Name, Typ, Einheit, Beschreibung) fur current, hourly, daily
- Enthalt: Vollstandige Beispiel-JSONs mit realistischen Wetterdaten
- Enthalt: Mapping-Tabelle .dat-Feldposition -> JSON-Feldname (nutzlich fur Phase 2)
- Ablageort: data/ Verzeichnis (neben den bestehenden .format-Dateien)

### Claude's Discretion
- Exakte Sortierung der Felder innerhalb der JSON-Objekte
- Ob `period` als Feld im Array beibehalten oder durch Array-Index impliziert wird
- Formatierung der Schema-Dokumentation (Tabellen-Layout, Reihenfolge der Abschnitte)
- Handhabung von hourlyhistory.dat (4. Format-Datei, weniger zentral)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| JSON-01 | JSON-Schema fur current, hourly und daily Wetterdaten definiert und dokumentiert | Field lists in @CURRENT_RAW/@DAILY_RAW/@HOURLY_RAW in grabber_utils.pl map directly to schema fields; .format files document all 42/40/36 positions |
| JSON-02 | Alle Grabber (OpenWeather, VisualCrossing, WeatherFlow, WetterOnline, wttr.in) schreiben JSON-Dateien parallel zu .dat (Dual-Write) | All 5 main grabbers already call write_current/daily/hourly_json() — calls exist but output format needs meta/data wrapper upgrade |
| JSON-03 | JSON-Dateien werden atomar geschrieben (.tmp + rename) mit File-Locking | Current write_*_json() functions write DIRECTLY without .tmp — must add atomic write pattern matching the .dat approach |
| JSON-04 | JSON-Encoding ist konsistent UTF-8 mit korrektem Umlaut-Handling | JSON::PP->utf8 flag is set; current open uses '>:raw' which is correct for utf8-encoded output from JSON::PP |
| JSON-05 | Dezimalzahlen nutzen Punkt als Trennzeichen unabhangig vom System-Locale | JSON::PP produces locale-independent output; _val() coerces numeric strings via Perl arithmetic — no locale issue |
| JSON-06 | Supplementary Grabber (WU, FOSHK, PWSCatchUpload, Loxone, OpenMeteo AQ) schreiben ebenfalls JSON | None of the 5 supplementary grabbers currently call write_current_json(); WU/FOSHK already require grabber_utils.pl; PWS and Loxone do NOT — need require + call added |
</phase_requirements>

---

## Summary

Phase 1 is a Perl-only backend phase. The infrastructure in `grabber_utils.pl` is substantially built — `write_current_json()`, `write_daily_json()`, and `write_hourly_json()` exist and are already called by all 5 main grabbers. However, three gaps remain that prevent the phase from being complete.

**Gap 1 — Schema structure mismatch:** The current JSON functions output a flat object/array at the top level. The locked decision requires a `{meta: {...}, data: ...}` wrapper. This means upgrading the three write functions in `grabber_utils.pl` — the only file that needs changing for the main grabbers.

**Gap 2 — No atomic write in JSON functions:** The existing `write_*_json()` functions write directly to the final file path (no `.tmp` + rename). This violates JSON-03. The `.dat` write pattern (`.tmp` + `File::Copy::move()` + size check) must be adopted for JSON writes.

**Gap 3 — Supplementary grabbers not wired:** None of the 5 supplementary grabbers (WU, FOSHK, PWSCatchUpload, Loxone, OpenMeteo AQ) call `write_current_json()`. Two of them (PWSCatchUpload, Loxone) don't even `require grabber_utils.pl`. Additionally, OpenMeteo AQ currently writes its own separate `airquality_pollen.json` file — this must be integrated into `current.json` via `write_current_json()` instead.

**Primary recommendation:** Fix `grabber_utils.pl` first (meta/data wrapper + AQ fields + atomic write), then add the three-line call block to each supplementary grabber. Write schema documentation last from the verified field lists.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JSON::PP | Core (5.010+) | JSON encoding for output | Pure-Perl, always available on LoxBerry Raspberry Pi; no XS dep issues; already used in grabber_utils.pl |
| File::Copy | Core | `move()` for atomic rename | Already used in all grabbers for .dat atomic write |
| POSIX | Core | `strftime()` for ISO 8601 timestamps | Already used in grabber_utils.pl |
| Encode | Core | UTF-8 encode/decode | Already imported in several grabbers |

### Already Available (no new installs)
| Library | Already Used By |
|---------|----------------|
| LoxBerry::System | All grabbers |
| LoxBerry::Log | All grabbers (LOGOK, LOGWARN macros) |
| JSON (XS variant) | Main grabbers for API response decoding |

**Installation:** None required. All dependencies are Perl core modules or already present in the LoxBerry ecosystem.

---

## Architecture Patterns

### Current State — What Exists

`grabber_utils.pl` already provides:
- `@CURRENT_RAW` (42 fields), `@DAILY_RAW` (40 fields), `@HOURLY_RAW` (36 fields) — positional field lists
- `%WEATHER_CODE_TO_ID` — legacy numeric code to semantic string mapping
- `_read_dat_lines()`, `_line_to_hash()`, `_val()`, `_epoch_to_iso()`, `_hhmm()`, `_enrich_weather_id()` — conversion helpers
- `write_current_json($lbplogdir)`, `write_daily_json($lbplogdir)`, `write_hourly_json($lbplogdir)` — functional but incomplete

All 5 main grabbers already have at end-of-file:
```perl
write_current_json($lbplogdir) if $current;
write_daily_json($lbplogdir) if $daily;
write_hourly_json($lbplogdir) if $hourly;
```

### What Must Change

**Pattern 1: meta/data JSON wrapper structure (JSON-01)**

The output JSON structure must change from:
```json
{ "field": "value", ... }
```
To:
```json
{
  "meta": {
    "schema_version": "1.0",
    "source": "OpenWeatherMap",
    "grabber": "grabber_openweather.pl",
    "generated_at": "2026-03-12T14:30:00+01:00"
  },
  "data": { "field": "value", ... }
}
```

For hourly/daily, `data` is an array:
```json
{
  "meta": { ... },
  "data": [ { "period": 1, ... }, { "period": 2, ... } ]
}
```

The `source` and `grabber` fields must be passed as parameters to the write functions. Signature change:
```perl
# Current (grabber_utils.pl):
sub write_current_json { my ($logdir) = @_; ... }

# Required:
sub write_current_json { my ($logdir, %opts) = @_;
    # $opts{source}  — human name, e.g. "OpenWeatherMap"
    # $opts{grabber} — filename, e.g. "grabber_openweather.pl"
    ...
}
```

Caller side stays simple (backward compatible if opts are optional):
```perl
write_current_json($lbplogdir,
    source  => "OpenWeatherMap",
    grabber => "grabber_openweather.pl",
) if $current;
```

**Pattern 2: Atomic write for JSON (JSON-03)**

Replace direct open in write_*_json() with .tmp + move pattern:
```perl
# WRONG (current):
my $out = "$logdir/current.json";
open my $fh, '>:raw', $out or do { LOGWARN "..."; return; };
print $fh $json_obj->encode(\%rec);
close $fh;
LOGOK "...";

# CORRECT (must implement):
my $out = "$logdir/current.json";
my $tmp = "$out.tmp";
open my $fh, '>:raw', $tmp or do { LOGWARN "Cannot write $tmp: $!"; return; };
print $fh $json_obj->encode(\%rec);
close $fh;
File::Copy::move($tmp, $out) or do { LOGWARN "Cannot rename $tmp to $out: $!"; return; };
LOGOK "Saved current weather data as JSON to $out";
```

Note: No size check needed for JSON (unlike .dat 100-byte guard) since JSON::PP->encode will produce valid output or die — if it dies, it's caught by eval.

**Pattern 3: Error isolation (JSON-03 + error behavior decision)**

JSON-Write errors must not stop the grabber. Wrap all three write calls in eval:
```perl
eval { write_current_json($lbplogdir, source => "OpenWeatherMap", grabber => "grabber_openweather.pl") }
    if $current;
LOGWARN "JSON write failed: $@" if $@;
```

Alternatively (simpler): handle inside the functions and always return instead of die. The locked decision ("JSON-Write-Fehler stoppen nicht den Grabber-Lauf") is best satisfied by catching errors inside `write_*_json()` with `eval` and converting to LOGWARN + return.

**Pattern 4: AQ field integration in current.json (JSON-06)**

The locked decision says AQ fields go into `current.json`. All grabbers must output the full current schema including AQ fields, set to `null` when not available. OpenMeteo AQ grabber sets them from its API response.

New AQ fields to add to `@CURRENT_RAW` schema (not the .dat — the JSON schema only):
```
aqi_eu, aqi_us, pm10, pm25, pollen_alder, pollen_birch, pollen_grass,
pollen_mugwort, pollen_olive, pollen_ragweed, pollen_overall_today,
pollen_overall_tomorrow
```

These fields are NOT in the .dat (they have no .dat column positions). The `write_current_json()` function reads from current.dat and will naturally set these to `null` when not present. The OpenMeteo AQ grabber needs a dedicated write path: after writing its current.dat overlay, it reads the resulting current.dat, applies the AQ values on top of the parsed record, and calls a modified write function.

**Pattern 5: Supplementary grabber wiring (JSON-06)**

For WU, FOSHK (already require grabber_utils.pl), after the `move()` call:
```perl
# After: move($currentnametmp, $currentname);
# Add:
eval { write_current_json($lbplogdir, source => "WeatherUnderground", grabber => "grabber_wu.pl") };
LOGWARN "JSON write failed: $@" if $@;
```

For PWSCatchUpload and Loxone (do NOT currently require grabber_utils.pl), add at top:
```perl
require "$lbpbindir/grabber_utils.pl";
```
Then same call pattern after the move().

For OpenMeteo AQ, the situation is different — it writes to `airquality_pollen.json` (its own format) and does NOT write current.dat at all. It needs a new `write_current_json_aq()` helper (or the existing write function extended) that: reads current.dat, merges in AQ values, writes current.json. This is the most complex supplementary case.

### Recommended File-by-File Change Plan

| File | Change Type | Scope |
|------|-------------|-------|
| `bin/grabber_utils.pl` | Modify | Add meta/data wrapper, atomic write, AQ fields in schema, signature update |
| `bin/grabber_openweather.pl` | Modify | Pass source+grabber params to write_*_json calls |
| `bin/grabber_visualcrossing.pl` | Modify | Pass source+grabber params |
| `bin/grabber_weatherflow.pl` | Modify | Pass source+grabber params |
| `bin/grabber_wetteronline.pl` | Modify | Pass source+grabber params |
| `bin/grabber_wttrin.pl` | Modify | Pass source+grabber params |
| `bin/grabber_wu.pl` | Modify | Add write_current_json call after move() |
| `bin/grabber_foshk.pl` | Modify | Add write_current_json call after move() |
| `bin/grabber_pwscatchupload.pl` | Modify | Add require grabber_utils.pl + write_current_json call |
| `bin/grabber_loxone.pl` | Modify | Add require grabber_utils.pl + write_current_json call |
| `bin/grabber_openmeteo_airquality.pl` | Modify | Replace custom airquality_pollen.json write with write_current_json_aq() call |
| `data/json-schema.md` | Create | Full schema documentation |

### Recommended Project Structure (no new directories needed)

```
bin/
  grabber_utils.pl        # Central change: meta/data, atomic, AQ fields
  grabber_openweather.pl  # Add source/grabber params
  grabber_*.pl            # Same pattern
data/
  current.format          # Unchanged reference
  dailyforecast.format    # Unchanged reference
  hourlyforecast.format   # Unchanged reference
  hourlyhistory.format    # Unchanged reference (out of scope per discretion)
  json-schema.md          # New: schema documentation
```

### Anti-Patterns to Avoid

- **Non-atomic JSON writes:** Never `open > current.json` directly. Always `.tmp` + `move()`.
- **Die on JSON error:** JSON write failures must use `LOGWARN + return`, never `exit` or `die` — .dat system must survive.
- **Flat top-level structure:** Never output `{"temperature": 20}` — always wrap in `{meta:{...}, data:{...}}`.
- **Comma decimals:** Never interpolate Perl locale-formatted floats into JSON manually — always use `JSON::PP->encode()` which handles numeric coercion internally.
- **Separate AQ file:** OpenMeteo AQ must NOT keep writing to `airquality_pollen.json` as the primary output — AQ fields go into current.json.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON encoding with UTF-8 | Custom string serialization | `JSON::PP->new->pretty->canonical->utf8` | Handles escape sequences, Unicode, number formatting correctly |
| Atomic file write | Own locking scheme | `.tmp` + `File::Copy::move()` | Already proven pattern in all grabbers; OS-level rename is atomic on Linux |
| Epoch to ISO 8601 | Custom date formatting | `_epoch_to_iso()` already in grabber_utils.pl | Handles TZ correctly via `$ENV{TZ}` + POSIX::tzset() |
| Decimal point normalization | `s/,/./g` substitution | JSON::PP numeric coercion via `$v + 0` in `_val()` | Already implemented; locale-independent |

---

## Common Pitfalls

### Pitfall 1: JSON::PP `->utf8` vs `'>:encoding(UTF-8)'` open
**What goes wrong:** Combining `JSON::PP->utf8` (which outputs raw UTF-8 bytes) with `open '>:encoding(UTF-8)'` double-encodes, producing mojibake.
**Why it happens:** `->utf8` already converts the internal Perl string to UTF-8 bytes. Adding `:encoding(UTF-8)` on the filehandle encodes those bytes again.
**How to avoid:** When using `JSON::PP->utf8`, always open with `'>:raw'` — exactly what the current `write_current_json()` does. Keep this pattern unchanged.
**Warning signs:** `\xC3\xA4` appearing literally in output instead of `a with umlaut`.

### Pitfall 2: Backward compatibility of write_*_json() signature
**What goes wrong:** If source/grabber params are added as required positional args, existing callers break.
**Why it happens:** 5 main grabbers already call these functions without extra params.
**How to avoid:** Use `my ($logdir, %opts) = @_` — extra hash params are optional, default to empty string/undef when not passed. Existing callers continue to work during incremental updates.

### Pitfall 3: OpenMeteo AQ reads current.dat that may not exist yet
**What goes wrong:** OpenMeteo AQ runs as a supplementary grabber — it assumes a main grabber has already written current.dat. If run standalone or before main grabber, `write_current_json()` will find no current.dat and silently return.
**Why it happens:** `write_current_json()` has an early `return unless -f $dat` guard.
**How to avoid:** This is acceptable behavior (matches .dat behavior — AQ grabber also fails silently if current.dat doesn't exist). Document this dependency in schema docs.

### Pitfall 4: PWSCatchUpload and Loxone grabbers have no grabber_utils.pl require
**What goes wrong:** Calling `write_current_json()` without `require "$lbpbindir/grabber_utils.pl"` causes "Undefined subroutine" error, stopping the grabber.
**Why it happens:** These two grabbers were written before grabber_utils.pl existed.
**How to avoid:** Add `require "$lbpbindir/grabber_utils.pl";` near top of each file, after the other `use` statements.
**Warning signs:** Fatal `Undefined subroutine &main::write_current_json` at runtime.

### Pitfall 5: `meta.generated_at` timezone
**What goes wrong:** Using `localtime()` without TZ context gives system timezone, which may differ from the weather location's timezone stored in current.dat.
**Why it happens:** `generated_at` reflects when the grabber ran, not the weather observation time. System TZ is correct here.
**How to avoid:** `generated_at` should use system localtime (when the grabber generated the file). The observation time is `data.datetime` derived from `epoch` + `tz_long`. Keep them separate and document the distinction.

### Pitfall 6: Supplementary grabbers write current.dat.tmp then rename — JSON must read AFTER rename
**What goes wrong:** Calling `write_current_json()` before `move($currentnametmp, $currentname)` reads stale data.
**Why it happens:** All supplementary grabbers work by patching `.tmp`, then renaming. The final current.dat only exists after rename.
**How to avoid:** Always place `write_current_json()` call AFTER the `move()` call and after the size check. The reference pattern from grabber_openweather.pl (lines 820-822) shows this correctly.

---

## Code Examples

### Upgraded write_current_json signature (grabber_utils.pl)

```perl
sub write_current_json {
    my ($logdir, %opts) = @_;
    my $source  = $opts{source}  // '';
    my $grabber = $opts{grabber} // '';

    my $dat = "$logdir/current.dat";
    return unless -f $dat;
    my @lines = _read_dat_lines($dat);
    return unless @lines;

    my %raw = _line_to_hash($lines[0], \@CURRENT_RAW);
    my $tz  = $raw{tz_long} || _system_timezone();

    # Build clean data record
    my %rec;
    $rec{datetime} = _epoch_to_iso($raw{epoch}, $tz);
    $rec{epoch}    = _val($raw{epoch});
    $rec{timezone} = $tz;
    $rec{sunrise}  = _hhmm($raw{sunrise_hour}, $raw{sunrise_min});
    $rec{sunset}   = _hhmm($raw{sunset_hour},  $raw{sunset_min});

    for my $f (@CURRENT_RAW) {
        next if $DROP_CURRENT{$f};
        next if $f eq 'epoch';
        $rec{$f} = _val($raw{$f});
    }

    # AQ fields default to null (set by OpenMeteo AQ grabber only)
    for my $aqf (qw(aqi_eu aqi_us pm10 pm25
                    pollen_alder pollen_birch pollen_grass pollen_mugwort
                    pollen_olive pollen_ragweed
                    pollen_overall_today pollen_overall_tomorrow)) {
        $rec{$aqf} //= undef;
    }

    _enrich_weather_id(\%rec);

    # Build meta
    my $generated_at = strftime("%Y-%m-%dT%H:%M:%S%z", localtime(time));
    $generated_at =~ s/(\d{2})(\d{2})$/$1:$2/;  # insert colon in tz offset

    my %envelope = (
        meta => {
            schema_version => "1.0",
            source         => $source,
            grabber        => $grabber,
            generated_at   => $generated_at,
        },
        data => \%rec,
    );

    my $json_obj = JSON::PP->new->pretty->canonical->utf8;
    my $out = "$logdir/current.json";
    my $tmp = "$out.tmp";

    eval {
        open my $fh, '>:raw', $tmp or die "Cannot open $tmp: $!";
        print $fh $json_obj->encode(\%envelope);
        close $fh;
        File::Copy::move($tmp, $out) or die "Cannot rename $tmp to $out: $!";
    };
    if ($@) {
        LOGWARN "JSON write failed for $out: $@";
        return;
    }
    LOGOK "Saved current weather data as JSON to $out";
}
```

### Caller pattern in main grabbers (after existing .dat write block)

```perl
# After the existing .dat write:
# write_current_json($lbplogdir) if $current;  <-- OLD
# Replace with:
if ($current) {
    eval { write_current_json($lbplogdir,
        source  => "OpenWeatherMap",
        grabber => "grabber_openweather.pl") };
    LOGWARN "JSON write failed: $@" if $@;
}
```

### Supplementary grabber wiring (WU, FOSHK, PWS, Loxone)

```perl
# After: move($currentnametmp, $currentname);
# After: LOGOK "Current Data saved successfully.";
# Before: exit;

eval { write_current_json($lbplogdir,
    source  => "WeatherUnderground",
    grabber => "grabber_wu.pl") };
LOGWARN "JSON write failed: $@" if $@;
```

### Schema documentation structure (data/json-schema.md)

```markdown
# Weather4Lox JSON Schema v1.0

## current.json

### Structure
{ "meta": {...}, "data": {...} }

### meta fields
| Field | Type | Description |
| schema_version | string | Always "1.0" |
| source | string | Human-readable grabber name |
| grabber | string | Perl script filename |
| generated_at | string | ISO 8601 datetime (system TZ) |

### data fields
| Field | Type | Unit | .dat position | Description |
| epoch | number | s | 0 | Unix timestamp |
| datetime | string | ISO 8601 | derived | Local datetime from epoch+tz |
| timezone | string | Olson | 3 | e.g. "Europe/Berlin" |
...

## .dat -> JSON field mapping

| .dat position | .dat description | JSON field | Notes |
| 0 | Epoch | epoch | numeric |
| 1 | Date RFC822 | (dropped) | replaced by datetime |
...
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| write directly to final file | .tmp + move() for .dat | Must extend same pattern to JSON writes |
| No JSON output | write_*_json() functions exist | Infrastructure in place, needs structural update |
| -9999 sentinel values | `null` in JSON | Already handled by `_val()` |
| Localized month/weekday names in .dat | ISO 8601 datetime in JSON | Already implemented in _epoch_to_iso() |
| Separate airquality_pollen.json | AQ fields in current.json | Requires OpenMeteo AQ grabber redesign |

**Current state of main grabbers (VERIFIED by code inspection):**
- OpenWeather: calls write_*_json — EXISTS, needs param update
- VisualCrossing: calls write_*_json — EXISTS, needs param update
- WeatherFlow: calls write_*_json — EXISTS, needs param update
- WetterOnline: calls write_*_json — EXISTS, needs param update
- wttr.in: calls write_*_json — EXISTS, needs param update

**Current state of supplementary grabbers (VERIFIED by code inspection):**
- grabber_wu.pl: requires grabber_utils.pl — NO write_current_json call
- grabber_foshk.pl: requires grabber_utils.pl — NO write_current_json call
- grabber_pwscatchupload.pl: does NOT require grabber_utils.pl, NO json call
- grabber_loxone.pl: does NOT require grabber_utils.pl, NO json call
- grabber_openmeteo_airquality.pl: requires grabber_utils.pl, writes own separate airquality_pollen.json

---

## Open Questions

1. **OpenMeteo AQ merge strategy**
   - What we know: AQ grabber reads its own API, does not write current.dat — it has no overlap with the current.dat patch mechanism used by WU/FOSHK/PWS/Loxone
   - What's unclear: Should it call a new `write_current_json_aq(%aq_data)` helper that reads current.dat, injects AQ fields, and writes current.json? Or should OpenMeteo AQ be refactored to write an intermediate current.dat overlay first?
   - Recommendation: Add `write_current_json_aq(%aq_data)` to grabber_utils.pl — cleaner than touching the .dat flow. This function reads current.dat, applies AQ overrides to the %rec hash, wraps in meta/data, writes atomically. The OpenMeteo AQ grabber passes its collected values as named parameters.

2. **`period` field retention in hourly/daily arrays**
   - What we know: `period` (1-based index) exists in .dat; `_val()` already extracts it; Claude's discretion applies
   - What's unclear: Whether downstream consumers (Phase 2, Phase 5) need period as explicit field or can rely on array index
   - Recommendation: Keep `period` as explicit field in JSON — it costs nothing and makes the data self-describing, consistent with defensive schema design.

3. **hourlyhistory.json**
   - What we know: hourlyhistory.dat format exists (same 42 fields as current.format minus a few). Claude has discretion on this.
   - Recommendation: Out of scope for Phase 1. The 4th format file is not referenced in any requirement or success criterion. Document the gap in json-schema.md as "not yet defined."

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual shell testing (no automated test framework detected in project) |
| Config file | none |
| Quick run command | `perl -cw bin/grabber_utils.pl` (syntax check) |
| Full suite command | Manual grabber run + file inspection |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| JSON-01 | json-schema.md exists with field tables | manual | `test -f data/json-schema.md` | No — Wave 0 |
| JSON-02 | Main grabbers produce current.json | smoke | `perl -cw bin/grabber_openweather.pl` etc. | No live .dat in dev |
| JSON-03 | JSON written atomically (.tmp + rename) | code review | `grep -n '\.tmp' bin/grabber_utils.pl` | Partial |
| JSON-04 | UTF-8 umlauts correct in JSON | smoke | inspect output file with `file` + `python3 -c "import json,sys; json.load(sys.stdin)"` | No |
| JSON-05 | Decimal points in JSON numbers | smoke | inspect JSON output for comma decimals | No |
| JSON-06 | Supplementary grabbers produce current.json | smoke | `perl -cw bin/grabber_wu.pl` etc. | No |

### Sampling Rate
- **Per task commit:** `perl -cw bin/grabber_utils.pl && perl -cw bin/grabber_openweather.pl`
- **Per wave merge:** Syntax check all modified .pl files
- **Phase gate:** Manual grabber run on LoxBerry device, verify current.json matches schema before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] No automated test runner — all validation is manual or syntax-check-only
- [ ] `data/json-schema.md` — must be created (JSON-01)
- [ ] No example .dat files in repo for offline testing

*(Note: LoxBerry is an embedded Raspberry Pi system; full integration tests require device access. Syntax checks are the only automatable pre-commit gate.)*

---

## Sources

### Primary (HIGH confidence)
- Direct code inspection: `bin/grabber_utils.pl` — full source read, all functions verified
- Direct code inspection: all 10 grabbers — grep for json calls, require statements, file structure
- Direct inspection: `data/*.format` files — all 4 format files read, field counts verified

### Secondary (MEDIUM confidence)
- CONTEXT.md decisions — locked by user in prior discussion session
- REQUIREMENTS.md — all 6 phase requirements traced

### Tertiary (LOW confidence)
- None — all claims verified directly from codebase

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified from existing imports in all grabbers
- Current grabber state: HIGH — verified by direct grep across all .pl files
- Architecture gaps: HIGH — verified by reading actual function implementations
- AQ integration approach: MEDIUM — write_current_json_aq() is a design recommendation, not yet confirmed by user

**Research date:** 2026-03-12
**Valid until:** Stable — pure Perl codebase, no external API changes affect this analysis
