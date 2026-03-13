# Coding Conventions

**Analysis Date:** 2026-03-12

## Language and Strictness

**Primary language:** Perl 5 (scripts and CGI)

**Strictness pragmas:**
- All grabber scripts (`bin/grabber_*.pl`) and utilities (`bin/grabber_utils.pl`) use `use strict; use warnings;` at the top.
- `bin/datatoloxone.pl` and several CGI files (`webfrontend/htmlauth/index.cgi`, `webfrontend/htmlauth/show.cgi`) have `strict`/`warnings` commented out (`#use strict; #use warnings;`). This is intentional legacy behavior, not an oversight — these files use package-global `our` variables as a substitute.
- New code added to the project (e.g. `grabber_utils.pl`) consistently uses `use strict; use warnings;`.

**Rule:** Always use `use strict; use warnings;` in any new grabber or utility script. CGI files in `webfrontend/htmlauth/` may omit them for legacy compatibility.

---

## Naming Patterns

**Files:**
- Grabber scripts: `grabber_<servicename>.pl` — all lowercase, underscore-separated (e.g. `grabber_openweather.pl`, `grabber_visualcrossing.pl`)
- Utility shared code: `grabber_utils.pl`
- Orchestration scripts: lowercase verbs (`fetch.pl`, `cronjob.pl`, `datatoloxone.pl`)
- Web CGI files: lowercase nouns/verbs (`index.cgi`, `show.cgi`, `ajax-handler.cgi`)
- Shell scripts: lowercase with underscores (`weather4lox_cronjob.sh`)

**Functions (subroutines):**
- Public utility functions: lowercase with underscores (`api_call`, `sanitize_url`, `sanitize_dump`, `write_current_json`)
- Private helper functions in `grabber_utils.pl`: prefixed with underscore (`_read_dat_lines`, `_val`, `_line_to_hash`, `_epoch_to_iso`, `_hhmm`, `_enrich_weather_id`)
- Per-service mapping functions: `<service>_to_lox` pattern (e.g. `owm_to_lox`, `vc_to_lox`, `weatherflow_to_lox`, `wttr_to_lox`)

**Variables:**
- Scalar variables: lowercase with underscores (`$api_key`, `$decoded_json`, `$urlmasked`)
- Config values read from .cfg: ALL_CAPS with dot notation as section reference (`$pcfg->param("OPENWEATHER.APIKEY")`)
- Loop variables: short names (`$i`, `$n`, `$t`, `$results`)
- Filename variables: descriptive suffixed with `name`/`nametmp` (e.g. `$currentname`, `$currentnametmp`)

**Constants / lookup tables:**
- Module-level hash constants: SCREAMING_SNAKE_CASE (`%WEATHER_CODE_TO_ID`, `%owm_to_lox`, `@CURRENT_RAW`, `@DAILY_RAW`, `@HOURLY_RAW`)

**Scope keywords:**
- `my` for all local variables
- `our` for package-global variables in files without strict (legacy `datatoloxone.pl`, some CGI files)
- Both appear freely in `datatoloxone.pl` due to disabled strict

---

## Module Imports

**Standard ordering pattern in grabbers:**
1. LoxBerry platform modules (`LoxBerry::System`, `LoxBerry::Log`)
2. HTTP/network modules (`LWP::UserAgent`)
3. Data format modules (`JSON qw(decode_json)`, `JSON::PP`)
4. File system modules (`File::Copy`)
5. CLI option parsing (`Getopt::Long`)
6. Time/date modules (`Time::Piece`, `DateTime`, `POSIX`)
7. Domain-specific modules (`Astro::MoonPhase`, `Math::Function::Interpolator`)
8. Shared internal utility: `require "$lbpbindir/grabber_utils.pl";`

**Platform path variables** (injected by LoxBerry::System at runtime):
- `$lbpbindir` — plugin bin directory
- `$lbplogdir` — plugin log/data directory (runtime `.dat` files live here)
- `$lbpconfigdir` — plugin config directory
- `$lbptemplatedir` — plugin template directory

**Pattern for optional module loading** (used in `grabber_wetteronline.pl`):
```perl
sub require_or_logdie {
    my ($module) = @_;
    eval "require $module; 1;" or do {
        LOGCRIT "Missing Perl module $module - cannot continue.";
        exit 2;
    };
    return 1;
}
require_or_logdie('DateTime::Format::ISO8601');
```
Use this pattern when a module is conditionally needed (e.g. only for `--hourly` mode).

---

## Configuration Reading

**Pattern (used in every grabber):**
```perl
my $pcfg   = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $apikey = $pcfg->param("SERVICENAME.APIKEY");
my $url    = $pcfg->param("SERVICENAME.URL");
```

**Config file structure:** INI sections named after service in ALL_CAPS (e.g. `[OPENWEATHER]`, `[VISUALCROSSING]`, `[SERVER]`, `[WEB]`). See `config/weather4lox.cfg` for all sections and keys.

---

## Logging

**Framework:** `LoxBerry::Log` (platform-provided module)

**Logger initialization pattern (standard in every script):**
```perl
my $log = LoxBerry::Log->new(
    package => 'weather4lox',
    name    => 'grabber_<service>',
    logdir  => "$lbplogdir",
);
```

**Log level macros** (used directly as bare words, injected by LoxBerry::Log):
- `LOGSTART "message"` — begin of script execution
- `LOGEND` — end of script (called in `END {}` block)
- `LOGDEB "message"` — debug-level detail (only shown at loglevel 7)
- `LOGINF "message"` — informational progress
- `LOGOK "message"` — successful operation confirmation
- `LOGWARN "message"` — non-fatal warning
- `LOGCRIT "message"` — critical error (usually before `exit 2`)

**Verbose mode pattern (consistent across all scripts):**
```perl
my $verbose = '';
GetOptions('verbose' => \$verbose, 'quiet' => sub { $verbose = 0 });
if ($verbose) {
    $log->stdout(1);
    $log->loglevel(7);
}
```

**END block pattern (required in all scripts):**
```perl
END {
    LOGEND;
}
```

---

## Command-line Option Parsing

**Framework:** `Getopt::Long`

**Standard options for main grabbers:**
```perl
my $verbose  = '';
my $current  = '';
my $daily    = '';
my $hourly   = '';
my $maskkeys = 1;   # default: mask API keys in log output
GetOptions(
    'verbose'  => \$verbose,
    'quiet'    => sub { $verbose = 0 },
    'current'  => \$current,
    'daily'    => \$daily,
    'hourly'   => \$hourly,
    'maskkeys' => \$maskkeys,
);
```

Supplemental grabbers that only augment current data (foshk, wu, loxone, pwscatchupload) only have `--verbose`/`--quiet`.

---

## API Calls

**All HTTP fetches go through the shared `api_call()` function in `grabber_utils.pl`:**
```perl
my $decoded_json = api_call(
    url      => "$url/...",
    maskkeys => $maskkeys,
    keyparam => 'appid',   # name of query param to mask in logs
    info     => "for Location $stationid (Current Weather Data)",
);
```
`api_call` returns an already-decoded JSON hashref. It exits with code 2 on HTTP failure.

**Non-JSON responses** (e.g. HTML scraping for wttr.in/wetteronline) use `api_call` with the `match` parameter:
```perl
my $content = api_call(
    url   => $myUrl,
    match => qr/pattern/,
    info  => "...",
);
```

**Direct LWP usage** is only used inside `grabber_wetteronline.pl`'s `getUrl()` helper for HTML scraping.

---

## File I/O and Data Files

**Output data format:** Pipe-delimited flat files (`.dat`) written to `$lbplogdir/`. Field order is defined by the positional arrays in `grabber_utils.pl` (`@CURRENT_RAW`, `@DAILY_RAW`, `@HOURLY_RAW`).

**Safe write pattern (write-to-tmp, validate, rename):**
```perl
open(F, ">$lbplogdir/current.dat.tmp") or $error = 1;
  flock(F, 2);       # exclusive lock
  if ($error) { LOGCRIT "..."; exit 2; }
  binmode F, ':encoding(UTF-8)';
  # ... print F fields separated by "|" ...
  flock(F, 8);       # unlock
close(F);

# Validate file size before promoting
my $size = -s "$lbplogdir/current.dat.tmp";
if ($size > 100) {
    move("$lbplogdir/current.dat.tmp", "$lbplogdir/current.dat");
}
```

**File handle convention:** Single-letter `F` is used throughout for file handles (not lexical `my $fh`) in older code. New code in `grabber_utils.pl` uses lexical `my $fh`.

**Data cleaning pattern (null/missing value normalization):**
```perl
s/\|null\|/"|0|"/eg;
s/\|--\|/"|0|"/eg;
s/\|na\|/"|-9999.00|"/eg;
s/\|NA\|/"|-9999.00|"/eg;
s/\|n\/a\|/"|-9999.00|"/eg;
s/\|N\/A\|/"|-9999.00|"/eg;
```
Sentinel value `-9999` (or `-9999.00`) means "no data available" throughout the codebase.

**JSON output:** After writing `.dat` files, grabbers call the three export helpers from `grabber_utils.pl`:
```perl
write_current_json($lbplogdir)  if $current;
write_daily_json($lbplogdir)    if $daily;
write_hourly_json($lbplogdir)   if $hourly;
```

---

## Number Formatting

**sprintf patterns used consistently:**
- Temperature: `sprintf("%.1f", $value)` — one decimal place
- Percentage (humidity, clouds, pop): `sprintf("%.0f", $value)` — no decimals
- Precipitation (mm): `sprintf("%.2f", $value)` — two decimal places
- UV index: `sprintf("%.2f", $value)` — two decimal places
- Pressure: `sprintf("%.0f", $value)` — no decimals
- Hours/minutes: `sprintf("%02d", $value)` — zero-padded two digits

**Wind speed conversion:** API values in m/s are multiplied by 3.6 to produce km/h for output.

---

## Wind Direction Pattern

Wind degree-to-string conversion appears identically in every grabber (repeated code pattern):
```perl
if ( $wdir >= 0   && $wdir <= 22  ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'})  }
if ( $wdir > 22   && $wdir <= 68  ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }
# ... etc for all 8 directions ...
```
Language strings are loaded from `language.ini` via `%L`. The 8-direction table covers 0-360 degrees.

---

## Unicode / Encoding

**All file writes use UTF-8:**
```perl
binmode F, ':encoding(UTF-8)';
```

**String decoding from language hash:**
```perl
Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'})
```

**`grabber_wetteronline.pl` and `grabber_wttrin.pl` additionally declare:**
```perl
use utf8;
use Encode qw(encode_utf8);
```

---

## Error Handling

**Fatal errors** exit with code 2 immediately after a `LOGCRIT` call:
```perl
LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
exit 2;
```

**`api_call()` centralizes HTTP failure handling** — callers do not need to check the response.

**Conditional field access for optional JSON fields** (prevents undef warnings):
```perl
if ($decoded_json->{current}->{rain}->{'1h'}) {
    print F sprintf("%.2f", $decoded_json->{current}->{rain}->{'1h'}), "|";
} else {
    print F "0|";
}
```

**Defined-or default** used in `grabber_utils.pl` helper functions:
```perl
my $url      = $p{url}      // '';
my $maskkeys = $p{maskkeys} // 1;
my $keyparam = $p{keyparam} // 'key';
```

**`eval` for dynamic module loading** in `require_or_logdie()` (see `grabber_wetteronline.pl`).

---

## Comments

**File-level header comment** (required): brief description of script purpose, then Apache 2.0 license block. Every script has this.

**Section separators:** `##########################################################################` delimiter lines divide scripts into sections (Modules, Read Settings, Main program).

**Inline comments:** Used sparingly on complex logic, primarily for weather code mappings. German-language explanatory comments appear in newer grabbers (e.g. the OWM weather code comments in `grabber_openweather.pl`).

**Commented-out code:** Present throughout (especially `datatoloxone.pl` and various CGI files). Legacy code is commented rather than deleted.

---

## Service-Specific Code-to-Icon Mapping

Each grabber that fetches from a weather API implements a `<service>_to_lox()` function that maps vendor-specific weather codes to Loxone Picto-Codes (integer 1-29) and normalized icon names (e.g. `"clear"`, `"rain"`, `"snow"`):

```perl
# Example from grabber_openweather.pl
sub owm_to_lox {
    my ($owm_id) = @_;
    my $data = $owm_to_lox{$owm_id} // [1, "clear"];   # fallback to clear
    if (!exists $owm_to_lox{$owm_id}) {
        LOGWARN "Unknown ID from OpenWeatherMap: $owm_id.";
    }
    return @$data;   # returns (picto_code, icon_name)
}
```

The normalized icon names map to `webfrontend/html/icons/` filenames.

---

## Template Engine (Web Frontend)

CGI files use `HTML::Template` from LoxBerry:
```perl
my $template = HTML::Template->new(
    filename          => "$lbptemplatedir/settings.html",
    global_vars       => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
    associate         => $cfg,
);
my %L = LoxBerry::Web::readlanguage($template, "language.ini");
```

Form parameters are accessed via CGI import names (`$R::fieldname` pattern after `$cgi->import_names('R')`).

---

*Convention analysis: 2026-03-12*
