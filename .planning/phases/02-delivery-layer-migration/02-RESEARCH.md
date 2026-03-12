# Phase 2: Delivery Layer Migration - Research

**Researched:** 2026-03-12
**Domain:** Perl script migration — .dat file reading to JSON reading in datatoloxone.pl
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Fallback-Verhalten**
- Kein Fallback auf .dat — wenn JSON fehlt, Fehlermeldung + Exit
- Alle 3 JSON-Dateien (current.json, dailyforecast.json, hourlyforecast.json) werden beim Start geprüft (fail-fast)
- Alte .dat-Lese-Logik wird komplett entfernt (nicht auskommentiert)

**JSON-Loading**
- Alle 3 JSON-Dateien werden zentral am Anfang des Scripts geladen und in Perl-Hashes/-Arrays geparst
- Saubere Trennung: erst Laden, dann Verarbeiten (UDP/MQTT, HTML-Templates)

**HTML-Template-Sektion**
- HTML-Template-Generierung (alte Themes: dark, light, fresh, ocean) wird ebenfalls auf JSON umgestellt
- Template-Variablennamen bleiben identisch (${dfc.0._tt_h} etc.) — nur die Datenquelle ändert sich
- Alte Themes funktionieren weiter ohne Template-Änderung

**Berechnete Werte (calc+N)**
- calc+4_prec, calc+8_ttmax etc. werden direkt aus JSON-Array-Feldern berechnet (z.B. $hour->{temperature} statt @fields[11])
- period-Feld aus JSON wird für $sendhfc/$senddfc-Filtering genutzt — gleiche Config-Logik wie bisher
- calc+N Werte bleiben nur UDP/MQTT (keine Template-Variablen)
- JSON null-Werte werden bei Aggregation übersprungen (wie bisher -9999 übersprungen wird)

**Sunrise/Sunset Parsing**
- JSON liefert "HH:MM" String — wird per split(':') in Stunde/Minute aufgespalten
- Loxone-Epoch-Berechnung (DateTime->new + epoch - dateref) bleibt identisch
- Bei null im JSON: -9999 senden (keine Regression für Loxone-Logik)
- Gleiche Behandlung für current und daily forecast

### Claude's Discretion
- Log-Level bei fehlenden JSON-Dateien (LOGERR vs LOGCRIT)
- weatherdata.html Debug-Datei: beibehalten oder entfernen
- Exakte Reihenfolge der JSON-Lade-Aufrufe
- Interne Hilfsfunktionen für JSON→Variable-Mapping

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| JSON-07 | datatoloxone.pl liest JSON statt .dat für UDP/MQTT Delivery an Loxone | Full code analysis complete — all .dat read sites identified, JSON field mapping documented |
| JSON-08 | datatoloxone.pl erzeugt identische UDP/MQTT-Werte wie zuvor (keine Regression) | All UDP/MQTT name→value pairs catalogued with exact .dat positions and JSON field equivalents |
</phase_requirements>

---

## Summary

datatoloxone.pl is a monolithic ~1950-line Perl script that currently reads three pipe-delimited .dat files (current.dat, dailyforecast.dat, hourlyforecast.dat) and sends weather values to Loxone Miniserver via UDP/MQTT. It also generates HTML pages for old themes and an index.txt for the Loxone Cloud Weather Emulator. Phase 2 replaces all .dat file reads with JSON reads while keeping every UDP/MQTT value name and value calculation byte-for-byte identical.

The JSON files produced by Phase 1 grabbers use a well-defined envelope (`meta` + `data`). For current.json, `data` is a hash; for daily and hourly forecast JSONs, `data` is an array of hashes indexed by `period`. The .dat-to-JSON field mapping is fully documented in `data/json-schema.md` and is the authoritative reference for this migration. JSON::PP is already available in the Perl environment from grabber_utils.pl usage.

The critical insight is that datatoloxone.pl has **two separate passes** over each data source: one for UDP/MQTT delivery (lines ~118–1224) and a second for HTML template variable population (lines ~1298–1445). Both passes read the same data but set different variable names. The JSON loading must happen once at the top, and both passes must be rewritten to use the same in-memory hash/array data structures.

**Primary recommendation:** Load all three JSON files at script startup with fail-fast validation, parse into `$cur`, `@dfc`, `@hfc` Perl data structures, then replace every `@fields[N]` reference with the named JSON field equivalent per the schema mapping table.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JSON::PP | bundled with Perl 5.14+ | Decode JSON files | Already used in grabber_utils.pl; no new dependency |
| LoxBerry::Log | system | LOGERR/LOGCRIT/LOGINF/LOGOK | Already used throughout datatoloxone.pl |
| DateTime | system | Loxone epoch calculation, sunrise/sunset | Already in use, behaviour unchanged |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Fcntl (LOCK_SH) | bundled | Shared file lock on JSON read | Consistent with flock pattern from grabbers |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON::PP | JSON::XS | JSON::XS is faster but requires XS compilation; JSON::PP is pure-Perl and already present — correct choice for this embedded system |

**Installation:** No new packages needed. JSON::PP ships with Perl core (>= 5.14).

---

## Architecture Patterns

### Recommended Script Structure After Migration

```
datatoloxone.pl (after Phase 2)
│
├── [UNCHANGED] Module imports, config read, log init, MQTT connect
│
├── [NEW] JSON load block (fail-fast, top of main)
│   ├── load_json_file($lbplogdir/current.json)        → $cur  (hashref)
│   ├── load_json_file($lbplogdir/dailyforecast.json)  → @dfc  (array of hashrefs)
│   └── load_json_file($lbplogdir/hourlyforecast.json) → @hfc  (array of hashrefs)
│
├── [REWRITTEN] Current conditions UDP/MQTT send (~lines 118–361)
│   └── $cur->{field_name} instead of @fields[N]
│
├── [REWRITTEN] Daily forecast UDP/MQTT send (~lines 372–597)
│   └── $dfc_entry->{field_name} instead of @fields[N], period from $dfc_entry->{period}
│
├── [REWRITTEN] Hourly forecast UDP/MQTT send (~lines 608–783)
│   └── $hfc_entry->{field_name} instead of @fields[N]
│
├── [REWRITTEN] calc+N aggregation loop (~lines 882–1224)
│   └── Uses @hfc array — same loop logic, field names from JSON
│
├── [UNCHANGED] weatherdata.html close, Create Webpages header
│
├── [REWRITTEN] DFC template variable population (~lines 1298–1359)
│   └── Uses @dfc array — ${dfc.$per._tt_h} etc. from JSON fields
│
├── [REWRITTEN] HFC template variable population (~lines 1388–1445)
│   └── Uses @hfc array — ${hfc.$per._tt} etc. from JSON fields
│
├── [REWRITTEN] Current template variable population (~lines 1477–1553)
│   └── Uses $cur hashref
│
├── [UNCHANGED] Emulator index.txt generation (uses same vars, now from JSON)
│
└── [UNCHANGED] Subroutines: send, sendmqtt, mqttconnect, mean, END
```

### Pattern 1: Central JSON Load with Fail-Fast

Load all JSON at script start before any processing. Exit with clear error if any file is missing or malformed.

```perl
# Source: project pattern established in grabber_utils.pl + CONTEXT.md decision
use JSON::PP ();

sub load_json_file {
    my ($path) = @_;
    unless (-f $path) {
        LOGERR "Required JSON file not found: $path";
        LOGEND;
        exit 1;
    }
    open(my $fh, '<:raw', $path) or do {
        LOGERR "Cannot open JSON file $path: $!";
        LOGEND;
        exit 1;
    };
    my $content = do { local $/; <$fh> };
    close($fh);
    my $decoded = eval { JSON::PP->new->utf8->decode($content) };
    if ($@) {
        LOGERR "JSON parse error in $path: $@";
        LOGEND;
        exit 1;
    }
    return $decoded;
}

# Load all three files at script start
my $cur_json  = load_json_file("$lbplogdir/current.json");
my $dfc_json  = load_json_file("$lbplogdir/dailyforecast.json");
my $hfc_json  = load_json_file("$lbplogdir/hourlyforecast.json");

# Extract data layer
my $cur  = $cur_json->{data};           # hashref
my @dfc  = @{ $dfc_json->{data} };     # array of hashrefs, ordered by period
my @hfc  = @{ $hfc_json->{data} };     # array of hashrefs, ordered by period
```

### Pattern 2: Current Conditions — Field Substitution

The current.dat read was a single-line pipe-split. Replacement uses the `$cur` hashref directly.

```perl
# OLD (lines 118-124):
open(F,"<$lbplogdir/current.dat");
  our $curdata = <F>;
close(F);
chomp $curdata;
my @fields = split(/\|/,$curdata);

# NEW: $cur is already loaded at top. No file open needed.
# Access: $cur->{field_name}
```

Key field substitutions for current (complete mapping):

| UDP/MQTT name | Old: @fields[N] | New: $cur->{...} |
|--------------|-----------------|-------------------|
| cur_date | `@fields[0] - $dateref->epoch() + tz_offset` | `$cur->{epoch} - $dateref->epoch()` (tz from `$cur->{timezone}`) |
| cur_loc_n | `@fields[5]` | `$cur->{city}` |
| cur_loc_c | `@fields[6]` | `$cur->{country}` |
| cur_loc_ccode | `@fields[7]` | `$cur->{country_code}` |
| cur_loc_lat | `@fields[8]` | `$cur->{latitude}` |
| cur_loc_long | `@fields[9]` | `$cur->{longitude}` |
| cur_loc_el | `@fields[10]` | `$cur->{elevation}` |
| cur_tt | `@fields[11]` (±C/F conv) | `$cur->{temperature}` |
| cur_tt_fl | `@fields[12]` | `$cur->{feelslike}` |
| cur_hu | `@fields[13]` | `$cur->{humidity}` |
| cur_w_dirdes | `@fields[14]` | `$cur->{wind_direction_desc}` |
| cur_w_dir | `@fields[15]` | `$cur->{wind_direction_deg}` |
| cur_w_sp | `@fields[16]` (±mph conv) | `$cur->{wind_speed}` |
| cur_w_gu | `@fields[17]` | `$cur->{wind_gust}` |
| cur_w_ch | `@fields[18]` | `$cur->{windchill}` |
| cur_pr | `@fields[19]` (±inHg conv) | `$cur->{pressure}` |
| cur_dp | `@fields[20]` | `$cur->{dewpoint}` |
| cur_vis | `@fields[21]` (±mi conv) | `$cur->{visibility}` |
| cur_sr | `@fields[22]` | `$cur->{solar_radiation}` |
| cur_hi | `@fields[23]` | `$cur->{heat_index}` |
| cur_uvi | `@fields[24]` | `$cur->{uv_index}` |
| cur_prec_today | `@fields[25]` (±in conv) | `$cur->{precip_today_mm}` |
| cur_prec_1hr | `@fields[26]` | `$cur->{precip_1hr_mm}` |
| cur_we_icon | `@fields[27]` | `$cur->{weather_icon}` |
| cur_we_code | `@fields[28]` | `$cur->{weather_code}` |
| cur_we_des | `@fields[29]` | `$cur->{weather_description}` |
| cur_moon_p | `@fields[30]` | `$cur->{moon_percent}` |
| cur_moon_a | `@fields[31]` | `$cur->{moon_age}` |
| cur_moon_ph | `@fields[32]` | `$cur->{moon_phase}` |
| cur_moon_h | `@fields[33]` | `$cur->{moon_hemisphere}` |
| cur_sun_r | `@fields[34]` + `@fields[35]` | `split(':', $cur->{sunrise})` → hour/min |
| cur_sun_s | `@fields[36]` + `@fields[37]` | `split(':', $cur->{sunset})` → hour/min |
| cur_ozone | `@fields[38]` | `$cur->{ozone}` |
| cur_sky | `@fields[39]` | `$cur->{cloud_cover}` |
| cur_pop | `@fields[40]` | `$cur->{precip_probability}` |
| cur_snow | `@fields[41]` | `$cur->{snow}` |

**Note on dropped .dat fields:** `@fields[1]` (RFC822 date), `@fields[2]` (tz short), `@fields[3]` (tz long), `@fields[4]` (tz offset) were sent as UDP values in the old code. These were .dat-specific fields not present in JSON. Per schema, they are dropped. The UDP values `cur_date_des`, `cur_date_tz_des_sh`, `cur_date_tz_des`, `cur_date_tz` must either be derived from JSON or dropped. Based on CONTEXT.md (no regression for Loxone), these values must be preserved — derive them:
- `cur_date_tz_des` = `$cur->{timezone}` (IANA name)
- `cur_date_tz_des_sh` = derive short form from IANA name or from `$cur->{datetime}` offset
- `cur_date_des` = ISO datetime string from `$cur->{datetime}`
- `cur_date_tz` = extract numeric offset from `$cur->{datetime}` (e.g., "+01:00" → "0100")

**Recommendation (Claude's discretion):** Send `$cur->{datetime}` for `cur_date_des`, `$cur->{timezone}` for `cur_date_tz_des`, and derive short tz and numeric offset from the `$cur->{datetime}` ISO string. This preserves all UDP names while removing the .dat dependency.

### Pattern 3: Sunrise/Sunset Parsing from JSON "HH:MM" String

```perl
# JSON delivers "HH:MM" string; old .dat delivered separate hour/minute integers
# CONTEXT.md decision: split(':') to get hour and minute

my ($sunr_h, $sunr_m) = defined($cur->{sunrise})
    ? split(/:/, $cur->{sunrise})
    : (undef, undef);

# Then apply same Loxone epoch calculation:
if (defined $sunr_h && $sunr_h < 24 && $sunr_h >= 0
    && defined $sunr_m && $sunr_m < 60 && $sunr_m >= 0) {
    my $sunrdate = DateTime->new(
        year   => $epochdate->year(),
        month  => $epochdate->month(),
        day    => $epochdate->day(),
        hour   => $sunr_h,
        minute => $sunr_m,
    );
    $name = "cur_sun_r";
    $value = $sunrdate->epoch() - $dateref->epoch();
} else {
    $name = "cur_sun_r";
    $value = -9999;  # null in JSON → -9999
}
&send;
```

### Pattern 4: Daily Forecast Loop — Period-Based Filtering

```perl
# OLD: foreach (@dfcdata) — reads from @dfcdata array of pipe-delimited lines
# NEW: foreach my $dfc_entry (@dfc) — iterates JSON objects

foreach my $dfc_entry (@dfc) {
    my $per = $dfc_entry->{period};  # replaces @fields[0]

    # Same senddfc filter logic:
    my $send_this = 0;
    foreach (split(/;/, $senddfc)) {
        if ($_ eq $per) { $send_this = 1; }
    }
    next unless $send_this;

    # DFC: Today is dfc0
    $per = $per - 1;

    # Field access: $dfc_entry->{high_temp} instead of @fields[11]
    # All other logic identical
}
```

Key DFC field substitutions:

| UDP/MQTT name | Old: @fields[N] | New: $dfc_entry->{...} |
|--------------|-----------------|------------------------|
| dfc$per\_date | `@fields[1] - $dateref->epoch()` | `$dfc_entry->{epoch} - $dateref->epoch()` |
| dfc$per\_day | `@fields[2]` | derive from `$dfc_entry->{datetime}` via DateTime |
| dfc$per\_month | `@fields[3]` | derive from `$dfc_entry->{datetime}` |
| dfc$per\_monthn | `@fields[4]` | derive from `$dfc_entry->{datetime}` |
| dfc$per\_monthn_sh | `@fields[5]` | derive from `$dfc_entry->{datetime}` |
| dfc$per\_year | `@fields[6]` | derive from `$dfc_entry->{datetime}` |
| dfc$per\_hour | `@fields[7]` | derive from `$dfc_entry->{datetime}` |
| dfc$per\_min | `@fields[8]` | derive from `$dfc_entry->{datetime}` |
| dfc$per\_wday | `@fields[9]` | derive from `$dfc_entry->{datetime}` (DateTime->day_name) |
| dfc$per\_wday_sh | `@fields[10]` | derive from `$dfc_entry->{datetime}` (DateTime->day_abbr) |
| dfc$per\_tt_h | `@fields[11]` | `$dfc_entry->{high_temp}` |
| dfc$per\_tt_l | `@fields[12]` | `$dfc_entry->{low_temp}` |
| dfc$per\_pop | `@fields[13]` | `$dfc_entry->{precip_probability}` |
| dfc$per\_prec | `@fields[14]` | `$dfc_entry->{precip_mm}` |
| dfc$per\_snow | `@fields[15]` | `$dfc_entry->{snow_cm}` |
| dfc$per\_w_sp_h | `@fields[16]` | `$dfc_entry->{wind_speed_max}` |
| dfc$per\_w_dirdes_h | `@fields[17]` | `$dfc_entry->{wind_dir_max_desc}` |
| dfc$per\_w_dir_h | `@fields[18]` | `$dfc_entry->{wind_dir_max_deg}` |
| dfc$per\_w_sp_a | `@fields[19]` | `$dfc_entry->{wind_speed_avg}` |
| dfc$per\_w_dirdes_a | `@fields[20]` | `$dfc_entry->{wind_dir_avg_desc}` |
| dfc$per\_w_dir_a | `@fields[21]` | `$dfc_entry->{wind_dir_avg_deg}` |
| dfc$per\_hu_a | `@fields[22]` | `$dfc_entry->{humidity_avg}` |
| dfc$per\_hu_h | `@fields[23]` | `$dfc_entry->{humidity_max}` |
| dfc$per\_hu_l | `@fields[24]` | `$dfc_entry->{humidity_min}` |
| dfc$per\_we_icon | `@fields[25]` | `$dfc_entry->{weather_icon}` |
| dfc$per\_we_code | `@fields[26]` | `$dfc_entry->{weather_code}` |
| dfc$per\_we_des | `@fields[27]` | `$dfc_entry->{weather_description}` |
| dfc$per\_ozone | `@fields[28]` | `$dfc_entry->{ozone}` |
| dfc$per\_moon_p | `@fields[29]` | `$dfc_entry->{moon_percent}` |
| dfc$per\_dp | `@fields[30]` | `$dfc_entry->{dewpoint}` |
| dfc$per\_pr | `@fields[31]` | `$dfc_entry->{pressure}` |
| dfc$per\_uvi | `@fields[32]` | `$dfc_entry->{uv_index}` |
| dfc$per\_sun_r | `@fields[33]`+`@fields[34]` | `split(':', $dfc_entry->{sunrise})` |
| dfc$per\_sun_s | `@fields[35]`+`@fields[36]` | `split(':', $dfc_entry->{sunset})` |
| dfc$per\_vis | `@fields[37]` | `$dfc_entry->{visibility}` |
| dfc$per\_moon_a | `@fields[38]` | `$dfc_entry->{moon_age}` |
| dfc$per\_moon_ph | `@fields[39]` | `$dfc_entry->{moon_phase}` |

**Note on derived date fields (dfc$per\_day, \_month, etc.):** The .dat file stored pre-computed day/month/weekday integers and strings. JSON only has `epoch` and `datetime`. Derive from the epoch via DateTime:

```perl
my $epochdatedfc = DateTime->from_epoch(epoch => $dfc_entry->{epoch});
# Then: $epochdatedfc->day, ->month, ->month_name, ->day_name, etc.
```

This is already done for `$epochdatedfc` in the old code (line 406) using `@fields[1]` — pattern is identical, just swap the source.

### Pattern 5: Hourly Forecast Loop

Key HFC field substitutions (hourlyforecast.dat positions → JSON fields):

| UDP/MQTT name | Old: @fields[N] | New: $hfc_entry->{...} |
|--------------|-----------------|------------------------|
| hfc$per\_per | `@fields[0]` | `$hfc_entry->{period}` |
| hfc$per\_date | `@fields[1] - $dateref->epoch()` | `$hfc_entry->{epoch} - $dateref->epoch()` |
| hfc$per\_tt | `@fields[11]` | `$hfc_entry->{temperature}` |
| hfc$per\_tt_fl | `@fields[12]` | `$hfc_entry->{feelslike}` |
| hfc$per\_hi | `@fields[13]` | `$hfc_entry->{heat_index}` |
| hfc$per\_hu | `@fields[14]` | `$hfc_entry->{humidity}` |
| hfc$per\_w_dirdes | `@fields[15]` | `$hfc_entry->{wind_direction_desc}` |
| hfc$per\_w_dir | `@fields[16]` | `$hfc_entry->{wind_direction_deg}` |
| hfc$per\_w_sp | `@fields[17]` | `$hfc_entry->{wind_speed}` |
| hfc$per\_w_ch | `@fields[18]` | `$hfc_entry->{windchill}` |
| hfc$per\_pr | `@fields[19]` | `$hfc_entry->{pressure}` |
| hfc$per\_dp | `@fields[20]` | `$hfc_entry->{dewpoint}` |
| hfc$per\_sky | `@fields[21]` | `$hfc_entry->{sky_percent}` |
| hfc$per\_sky\_des | `@fields[22]` | `$hfc_entry->{sky_description}` |
| hfc$per\_uvi | `@fields[23]` | `$hfc_entry->{uv_index}` |
| hfc$per\_prec | `@fields[24]` | `$hfc_entry->{precip_mm}` |
| hfc$per\_snow | `@fields[25]` | `$hfc_entry->{snow_cm}` |
| hfc$per\_pop | `@fields[26]` | `$hfc_entry->{precip_probability}` |
| hfc$per\_we_code | `@fields[28]` | `$hfc_entry->{weather_code}` |
| hfc$per\_we_icon | `@fields[27]` | `$hfc_entry->{weather_icon}` |
| hfc$per\_we_des | `@fields[29]` | `$hfc_entry->{weather_description}` |
| hfc$per\_ozone | `@fields[30]` | `$hfc_entry->{ozone}` |
| hfc$per\_sr | `@fields[31]` | `$hfc_entry->{solar_radiation}` |
| hfc$per\_vis | `@fields[32]` | `$hfc_entry->{visibility}` |
| hfc$per\_moon_p | `@fields[33]` | `$hfc_entry->{moon_percent}` |
| hfc$per\_moon_a | `@fields[34]` | `$hfc_entry->{moon_age}` |
| hfc$per\_moon_ph | `@fields[35]` | `$hfc_entry->{moon_phase}` |

### Pattern 6: calc+N Aggregation — JSON null Handling

Old code skipped values with `if @fields[N] > 0` (effectively treating -9999 as skip). JSON uses `null`. Replace:

```perl
# OLD: skip -9999
$tmpprec4 = $tmpprec4 + @fields[24] if @fields[24] > 0;

# NEW: skip null
$tmpprec4 = $tmpprec4 + $hfc_entry->{precip_mm}
    if defined($hfc_entry->{precip_mm}) && $hfc_entry->{precip_mm} > 0;

# OLD: skip -9999 string comparison
push(@tmpttmean4, @fields[11]) if @fields[11] ne "-9999";

# NEW: skip null
push(@tmpttmean4, $hfc_entry->{temperature})
    if defined($hfc_entry->{temperature});
```

### Pattern 7: Emulator (index.txt) Date Fields from JSON

The emulator section (lines 1693–1822) uses `@fields[N]` extensively after re-splitting `$curdata`. After migration, it reads from `$cur` hashref and `@hfc` array. The emulator's hfcdate DateTime construction currently uses:

```perl
# OLD: @fields[6]=year, @fields[3]=month, @fields[2]=day, @fields[7]=hour, @fields[8]=min
$hfcdate = DateTime->new(year=>@fields[6], month=>@fields[3], day=>@fields[2], ...);

# NEW: parse from $hfc_entry->{epoch}
$hfcdate = DateTime->from_epoch(epoch => $hfc_entry->{epoch});
```

The past-forecast filter `DateTime->compare($epochdate, $hfcdate)` remains identical — only the construction of `$hfcdate` changes.

### Pattern 8: Template Variable Population (HTML Old Themes)

The template section uses Perl symbolic references (`${dfc.$per._tt_h}`) to populate variables that the template substitution regex `$_ =~ s/<!--\$(.*?)-->/${$1}/g` then expands. These variable names must remain identical. Only the data source changes:

```perl
# OLD (line 1336):
${dfc.$per._tt_h} = @fields[11];

# NEW:
${dfc.$per._tt_h} = $dfc_entry->{high_temp};
# (with same metric conversion logic applied)
```

**The template variable names do not change.** This is purely a data source swap.

### Anti-Patterns to Avoid

- **Partial migration:** Do not leave any `open(F,"<$lbplogdir/current.dat")` or `split(/\|/)` calls in the file — all .dat reads must be removed as per CONTEXT.md decisions.
- **Re-reading files:** Do not open the JSON files more than once. Load at top, reuse the same in-memory structures in all sections (UDP loop, template loop, emulator loop).
- **Silently swallowing parse errors:** If JSON is malformed, the script must exit with a clear error, not produce zeroed-out data.
- **Using die without logging:** Always log with LOGERR before exit so the LoxBerry log captures the failure reason.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON decoding | Custom string parser | JSON::PP->decode() | Handles Unicode, nesting, null, edge cases correctly |
| DateTime from ISO string | Manual string parsing | DateTime->from_epoch($entry->{epoch}) | Epoch is already in JSON; avoids ISO parsing complexity |
| Timezone offset arithmetic | Manual UTC+N calculation | Use epoch directly (no tz offset needed for Loxone date calc) | Loxone epoch = epoch - dateref->epoch(), timezone already embedded |

---

## Common Pitfalls

### Pitfall 1: The "double pass" over data
**What goes wrong:** The script processes each .dat file twice — once for UDP/MQTT (foreach loop with @fields), once for template variables (second foreach loop). Developers migrating one loop forget the second, leaving orphaned @fields references that silently produce empty values when the .dat file is removed.
**Why it happens:** The two passes are visually separated by ~800 lines of code. There is no single "read" call to update — the data was implicitly shared through the @dfcdata/@hfcdata global arrays being re-iterated.
**How to avoid:** Search the entire file for `@fields[` and `split(/\|/)` after the migration and ensure zero occurrences remain.
**Warning signs:** Any remaining `@fields[N]` references after migration.

### Pitfall 2: Dropped .dat fields sent as UDP values
**What goes wrong:** The old code sends `cur_date_des` (RFC822 date), `cur_date_tz_des_sh`, `cur_date_tz_des`, `cur_date_tz` — these come from .dat positions 1–4 which are dropped from JSON. If they are simply deleted from UDP output, any Loxone user relying on those virtual inputs will lose data silently.
**Why it happens:** The field drop decision was made at the JSON schema level (Phase 1) without considering all consumers.
**How to avoid:** Derive these values from JSON fields that ARE present (`$cur->{datetime}`, `$cur->{timezone}`). `cur_date_des` = `$cur->{datetime}`, `cur_date_tz_des` = `$cur->{timezone}`, numeric tz offset from ISO string.
**Warning signs:** Fewer UDP packets being sent after migration than before.

### Pitfall 3: null vs -9999 in aggregation logic
**What goes wrong:** The calc+N aggregation (precipitation, temperature min/max, mean) used `-9999` sentinel values in .dat. The code checked `if @fields[N] ne "-9999"` or `if @fields[N] > 0`. JSON uses `null` (Perl `undef`). Math on `undef` produces warnings and incorrect results (undef treated as 0 in numeric context).
**Why it happens:** The sentinel value changed from string "-9999" to Perl undef.
**How to avoid:** Every aggregation conditional must check `defined($hfc_entry->{field})` before arithmetic or array push.
**Warning signs:** Perl "Use of uninitialized value" warnings in log.

### Pitfall 4: DFC sunrise/sunset uses wrong date context
**What goes wrong:** The dfc sunrise/sunset calculation uses `$epochdate` (current conditions date) as the year/month/day base. This is correct when daily forecast dates are close to today, but must remain identical to the old behavior. With JSON, the `$dfc_entry->{epoch}` provides the correct per-forecast-day epoch — use `$epochdatedfc` not `$epochdate` for the base date.
**Why it happens:** The old code (line 547) already uses `$epochdate` (current conditions date, NOT dfc date) for the sunrise calculation — this is the existing behavior and must be preserved even though it's arguable.
**How to avoid:** Keep the exact same DateTime construction pattern — use `$epochdate->year()`, `$epochdate->month()`, `$epochdate->day()` as the base (matching existing line 549), just swap `@fields[33]/@fields[34]` to `split(':', $dfc_entry->{sunrise})`.

### Pitfall 5: Emulator hourly forecast date construction
**What goes wrong:** The emulator's past-forecast filter uses `DateTime->compare($epochdate, $hfcdate)`. The old `$hfcdate` was constructed from individual year/month/day/hour/minute fields (@fields[6,3,2,7,8]). With JSON, use `DateTime->from_epoch(epoch => $hfc_entry->{epoch})` directly — this is simpler AND timezone-correct.
**Why it happens:** The old approach split out date components from .dat; JSON epoch is already a Unix timestamp.
**How to avoid:** Use `DateTime->from_epoch` for `$hfcdate` in the emulator section.

---

## Code Examples

### JSON Load Helper (recommended implementation)

```perl
# Source: project convention from grabber_utils.pl JSON::PP usage
sub load_json_file {
    my ($path) = @_;
    unless (-f $path) {
        LOGCRIT "Required JSON file not found: $path";
        LOGEND;
        exit 1;
    }
    local $/;
    open(my $fh, '<:raw', $path) or do {
        LOGCRIT "Cannot open $path: $!";
        LOGEND;
        exit 1;
    };
    flock($fh, 1);  # LOCK_SH — shared read lock
    my $raw = <$fh>;
    flock($fh, 8);  # LOCK_UN
    close($fh);
    my $decoded = eval { JSON::PP->new->utf8->decode($raw) };
    if ($@ || !$decoded) {
        LOGCRIT "JSON parse error in $path: $@";
        LOGEND;
        exit 1;
    }
    return $decoded;
}
```

**Log level recommendation (Claude's discretion):** Use LOGCRIT for missing/unreadable JSON files (the grabber didn't run — a critical operational failure). Use LOGERR for JSON parse errors (file exists but is corrupt — less likely, still serious).

### Null-Safe Value Helper

```perl
# For numeric values: return undef as -9999 where Loxone expects it
# (only needed for values that were -9999 in .dat)
sub _jval {
    my ($v) = @_;
    return defined($v) ? $v : -9999;
}

# Usage:
$value = _jval($cur->{snow});  # null → -9999 for Loxone
```

### Derived Date Fields from epoch

```perl
# For DFC template variables needing day/month/weekday strings:
my $dt = DateTime->from_epoch(epoch => $dfc_entry->{epoch});
${dfc.$per._day}      = $dt->day;
${dfc.$per._month}    = $dt->month;
${dfc.$per._monthn}   = $dt->month_name;
${dfc.$per._monthn_sh}= substr($dt->month_abbr, 0, 3);
${dfc.$per._year}     = $dt->year;
${dfc.$per._hour}     = $dt->hour;
${dfc.$per._min}      = $dt->minute;
${dfc.$per._wday}     = $dt->day_name;
${dfc.$per._wday_sh}  = $dt->day_abbr;
```

### Deriving Legacy Timezone Fields from JSON

```perl
# cur_date_tz_des (IANA name, e.g. "Europe/Berlin") — available directly
$cur_date_tz_des = $cur->{timezone};

# cur_date_des (was RFC822, now ISO 8601 is best available)
$cur_date_des = $cur->{datetime};

# cur_date_tz_des_sh (short tz, e.g. "CET") — not directly in JSON
# Option: derive from DateTime using $cur->{timezone}
my $dt_cur = DateTime->from_epoch(
    epoch     => $cur->{epoch},
    time_zone => $cur->{timezone},
);
$cur_date_tz_des_sh = $dt_cur->time_zone_short_name();

# cur_date_tz (numeric offset, e.g. "0100") — extract from datetime ISO string
# $cur->{datetime} = "2026-03-12T20:45:00+01:00"
if ($cur->{datetime} =~ /([+-]\d{2}):(\d{2})$/) {
    $cur_date_tz = sprintf("%s%02d%02d", ($1 >= 0 ? '+' : ''), abs($1), $2);
    # Result: "+0100"
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Read pipe-delimited .dat, split by `\|`, access by position | Read JSON, decode to Perl hash/array, access by name | Phase 2 | Eliminates positional coupling — field names are self-documenting |
| -9999 sentinel for missing values | JSON null (Perl undef) | Phase 1 JSON schema | Must add defined() checks in aggregation |
| Sunrise/sunset as two integers (hour, minute) in .dat | Single "HH:MM" string in JSON | Phase 1 JSON schema | Requires split(':') before DateTime construction |

---

## Open Questions

1. **Dropped .dat date fields (cur_date_des, cur_date_tz_des_sh, cur_date_tz, dfc date components)**
   - What we know: These were sent as UDP/MQTT values. Some Loxone users may use them in their automation.
   - What's unclear: Whether any real users rely on `cur_date_des` (RFC822 format) specifically, versus just the epoch-based `cur_date`.
   - Recommendation: Derive and send all of them from JSON (see Code Examples section). Cost is trivial; regression risk avoided.

2. **weatherdata.html debug file**
   - What we know: Currently populated with every value sent, used for debugging. Claude's discretion per CONTEXT.md.
   - What's unclear: Whether to keep it as-is (simple to maintain — just changes source of $value) or remove it.
   - Recommendation: Keep it — zero additional complexity since the `send` subroutine already writes it, and it aids debugging without performance impact.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None detected — Perl script, no test harness |
| Config file | none |
| Quick run command | `perl -c bin/datatoloxone.pl` (syntax check only) |
| Full suite command | Manual: run script with `--verbose`, inspect log output |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| JSON-07 | datatoloxone.pl reads JSON files (not .dat) | smoke | `perl -c bin/datatoloxone.pl` + grep for no `\.dat` opens | ❌ Wave 0 |
| JSON-07 | Fail-fast when JSON file missing | smoke | Run script without JSON files, check exit code = 1 | ❌ Wave 0 |
| JSON-08 | UDP/MQTT names unchanged | manual | Diff old vs new log output for `cur_` / `dfc` / `hfc` names | manual-only |
| JSON-08 | UDP/MQTT values numerically identical | manual | Run both old+new scripts against same .dat/.json dual-write data, diff logs | manual-only |

**JSON-08 regression testing is manual-only** because it requires a live LoxBerry environment with actual grabber data. The dual-write setup from Phase 1 (both .dat and .json exist) enables this: run old script → capture log, run new script → capture log, compare.

### Sampling Rate
- **Per task commit:** `perl -c bin/datatoloxone.pl`
- **Per wave merge:** Syntax check + manual diff of weatherdata.html output
- **Phase gate:** Full manual regression against live data before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] No automated test infrastructure exists for this Perl script
- [ ] A shell smoke test script (e.g., `tests/smoke_datatoloxone.sh`) would be useful but is not strictly required given manual testing capability via dual-write

*(Existing test infrastructure: none — manual testing is the established project approach)*

---

## Sources

### Primary (HIGH confidence)
- `bin/datatoloxone.pl` — complete source read (lines 1–1950), all .dat read sites catalogued
- `data/json-schema.md` — authoritative field mapping document produced in Phase 1
- `bin/grabber_utils.pl` — JSON::PP usage pattern (lines 145, 377, 441, 504, 565)
- `.planning/phases/02-delivery-layer-migration/02-CONTEXT.md` — all implementation decisions

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` — JSON-07, JSON-08 requirement definitions
- `.planning/STATE.md` — Phase 1 decisions affecting data format

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — JSON::PP confirmed in grabber_utils.pl; DateTime already in datatoloxone.pl
- Architecture: HIGH — complete source code read; all .dat access sites identified; JSON schema fully documented
- Pitfalls: HIGH — identified from direct source inspection, not guesswork
- Field mapping: HIGH — cross-referenced datatoloxone.pl @fields[N] usage against data/json-schema.md mapping table

**Research date:** 2026-03-12
**Valid until:** 2026-06-12 (stable domain — Perl + LoxBerry environment changes slowly)
