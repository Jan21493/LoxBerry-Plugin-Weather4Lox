# Testing Patterns

**Analysis Date:** 2026-03-12

## Test Framework

**Runner:** None — no automated test framework is present in this codebase.

**No test files found.** A search for `*.t`, `*.test`, and all test-related config files returned zero results. There is no `t/` directory, no `Test::More`, no `Test::Simple`, no `prove` configuration, and no CI pipeline configuration.

**Run Commands:**
```bash
# No automated test runner available.
# Manual invocation examples for development testing:

# Run a grabber in verbose mode (shows all log output to STDOUT):
perl bin/grabber_openweather.pl --current --daily --hourly --verbose

# Run the full fetch chain in verbose mode:
perl bin/fetch.pl --verbose

# Run datatoloxone in verbose mode:
perl bin/datatoloxone.pl --verbose
```

---

## Manual Testing Approach

The project uses a manual, integration-style approach to validation:

**1. Verbose mode logging:** Every script accepts `--verbose` which sets `$log->stdout(1)` and `$log->loglevel(7)`, printing all LOG levels to STDOUT. This is the primary development feedback mechanism.

**2. Dummy data files:** `data/dummies/` contains pre-populated `.dat` files for all three data types (`current.dat`, `dailyforecast.dat`, `hourlyforecast.dat`) that are copied on install. These allow `datatoloxone.pl` to run without live API calls after a fresh install.

**3. Temp-file validation:** Each grabber validates output before committing it — the `.dat.tmp` file must exceed 100 bytes before being renamed to the live `.dat` file:
```perl
my $size = -s "$lbplogdir/current.dat.tmp";
if ($size > 100) {
    move("$lbplogdir/current.dat.tmp", "$lbplogdir/current.dat");
}
```

**4. LOGDEB dumps:** After writing `.dat` files, grabbers log the entire file content at debug level for visual inspection:
```perl
open(F, "<$lbplogdir/current.dat.tmp");
    @filecontent = <F>;
    foreach (@filecontent) {
        chomp ($_);
        LOGDEB "$_";
    }
close (F);
```

**5. `api_call()` response dump:** `grabber_utils.pl` logs the full JSON response body at debug level when `--verbose` is active, allowing inspection of raw API payloads.

---

## Test File Organization

**No test files exist.** There is no testing directory structure to document.

---

## How to Validate Changes Manually

### Testing a grabber change

```bash
# 1. Run the specific grabber in verbose mode
perl bin/grabber_openweather.pl --current --verbose

# 2. Inspect the output dat file (pipe-delimited)
cat $LBPLOGDIR/weather4lox/current.dat

# 3. Run the JSON export chain
perl bin/grabber_openweather.pl --current --daily --hourly --verbose

# 4. Inspect JSON output
cat $LBPLOGDIR/weather4lox/current.json
```

### Testing grabber_utils.pl changes

Because `grabber_utils.pl` is `require`d by all grabbers, any grabber invocation exercises the utility functions. Focus testing on:
- `api_call()` — call any grabber with `--verbose` to see URL masking and JSON dump
- `write_*_json()` — run a grabber with `--current --daily --hourly` then inspect the `.json` files
- `sanitize_url()` / `sanitize_dump()` — run with `--verbose --maskkeys` to confirm API keys are masked in logs

### Testing datatoloxone.pl changes

```bash
# Run after grabbers have populated .dat files:
perl bin/datatoloxone.pl --verbose
# Inspect weatherdata.html to confirm HTML output
# Inspect UDP/MQTT output if those channels are configured
```

### Testing the full pipeline

```bash
perl bin/fetch.pl --verbose
# This runs fetch -> grabbers -> datatoloxone in sequence
```

---

## Mocking

**No mocking framework is used.** There is no mechanism to stub HTTP calls, filesystem access, or LoxBerry platform functions.

**Practical workaround for API isolation:** The `data/dummies/` pre-populated `.dat` files allow `datatoloxone.pl` to be tested without live API access. However, the grabbers themselves always make live HTTP requests.

**API key masking is not mocking:** The `--maskkeys` / `$maskkeys` flag controls whether API keys are redacted in log output. It does not affect actual API calls.

---

## Coverage

**Requirements:** None enforced. No coverage tooling (`Devel::Cover` or similar) is configured.

**Known untested paths (by inspection):**
- Weather code mapping fallbacks — the `// [1, "clear"]` default in `owm_to_lox()` and equivalent functions in other grabbers is never exercised in a controlled way
- The data interpolation logic in `grabber_openweather.pl` (lines 576-699) that backfills hourly data from 3-hourly forecast
- The `sanitize_dump()` masking when `$apikey` appears in URL path segments (not query params)
- `write_*_json()` functions with empty or malformed `.dat` files
- `_epoch_to_iso()` UTC fallback path when no timezone is available
- Error paths: file open failures, API 4xx/5xx responses (only exercised in production)

---

## Test Types

**Unit Tests:** Not present.

**Integration Tests:** Not present in code; performed manually by running scripts against live APIs.

**End-to-End Tests:** Not present; manual testing involves running the full fetch pipeline and checking output files and LoxBerry UI.

**Regression Tests:** Not present. Changes are validated by comparing `.dat`/`.json` output files before and after modification during development.

---

## Adding Tests (Recommended Approach)

If a test harness were to be introduced, the recommended approach for this codebase is:

**Framework:** `Test::More` (standard Perl, no additional install required) with `prove` runner.

**Recommended test structure:**
```
t/
├── sanitize_url.t       # Unit test grabber_utils::sanitize_url
├── sanitize_dump.t      # Unit test grabber_utils::sanitize_dump
├── val.t                # Unit test grabber_utils::_val type coercion
├── epoch_to_iso.t       # Unit test grabber_utils::_epoch_to_iso
├── owm_to_lox.t         # Unit test all OWM code mappings
├── vc_to_lox.t          # Unit test Visual Crossing code mappings
└── write_json.t         # Integration: write_current_json from fixture .dat
```

**Example test skeleton for `sanitize_url()`:**
```perl
use Test::More tests => 4;
require 'bin/grabber_utils.pl';

is(sanitize_url('https://api.example.com?key=secret123', 'key'),
   'https://api.example.com?key=***MASKED***',
   'masks key param');

is(sanitize_url('https://api.example.com?appid=abc&units=metric', 'appid'),
   'https://api.example.com?appid=***MASKED***&units=metric',
   'masks appid only, preserves other params');

is(sanitize_url(undef, 'key'), undef, 'handles undef input');

is(sanitize_url('https://no-key.example.com', 'key'),
   'https://no-key.example.com',
   'passthrough when param not present');
```

**Key challenge for testability:** The grabber scripts use LoxBerry platform globals (`$lbpbindir`, `$lbplogdir`, etc.) injected by `LoxBerry::System` at import time. Unit testing utility functions in isolation requires either mocking these globals or extracting utility code into a standalone module that does not depend on LoxBerry at load time. `grabber_utils.pl` is already a step in that direction.

---

*Testing analysis: 2026-03-12*
