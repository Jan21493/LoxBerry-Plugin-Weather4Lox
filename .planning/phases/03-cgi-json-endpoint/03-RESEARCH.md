# Phase 3: CGI JSON Endpoint - Research

**Researched:** 2026-03-13
**Domain:** Perl CGI, show.cgi HTTP response handling, LoxBerry plugin file system conventions
**Confidence:** HIGH — primary source is the actual codebase; all architectural decisions were pre-locked in CONTEXT.md

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Zugriffspfad:**
- JSON-Endpoint bleibt in show.cgi (webfrontend/htmlauth/show.cgi) — kein neuer Endpoint
- Bestehende Query-Parameter-Infrastruktur wird wiederverwendet (Zeilen 59-76)
- Neuer Parameter `format=json` wird hinzugefugt, kombiniert mit `type=current|hourly|daily`
- ocean-live Theme in webfrontend/html/ ruft show.cgi per relativem Pfad auf (LoxBerry erlaubt same-origin Requests zu htmlauth/)
- Falls Auth-Probleme auftreten: kann in spaterer Phase ein unauthentifizierter Proxy ergänzt werden

**Einheiten-Handling:**
- JSON-Endpoint liefert die JSON-Dateien 1:1 von Disk — immer metrische Rohwerte
- Keine serverseitige metric/imperial Konvertierung fur JSON-Responses
- Frontend ist fur Einheiten-Konvertierung zustandig (Phase 5)
- Begrundung: JSON-Dateien enthalten bereits die kanonischen metrischen Werte aus Phase 1

**Fehler-Responses:**
- Fehlender `type` Parameter oder ungueltiger Wert: HTTP 400 mit JSON `{"error": "Invalid or missing type parameter. Use type=current|hourly|daily", "code": 400}`
- JSON-Datei nicht gefunden auf Disk: HTTP 404 mit JSON `{"error": "Weather data not available", "code": 404}`
- JSON-Datei nicht lesbar/korrupt: HTTP 500 mit JSON `{"error": "Internal server error", "code": 500}`
- Alle Error-Responses haben ebenfalls Content-Type: application/json; charset=utf-8

**Response-Struktur:**
- JSON-Dateien werden 1:1 von Disk durchgereicht (File-Slurp + print)
- Kein Parsen, kein Transformieren, kein Umhullen — maximale Performance
- Die meta/data-Struktur aus Phase 1 ist bereits die endgultige API-Struktur
- Datei-Mapping: type=current → current.json, type=hourly → hourlyforecast.json, type=daily → dailyforecast.json

**Implementation-Ansatz:**
- Neuer Code-Block am Anfang von show.cgi, VOR der bestehenden .dat-Lese-Logik
- Wenn `format=json` erkannt: JSON-Response senden und `exit` (kein Durchfall in HTML-Logik)
- Bestehende HTML-Template-Funktionalitat bleibt zu 100% unverandert
- Kein Refactoring des bestehenden Codes — nur Erweiterung

### Claude's Discretion

Alle Entscheidungen dieser Phase wurden dem Ermessen von Claude uberlassen. Die Entscheidungen oben wurden basierend auf Codebase-Analyse gemacht.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CGI-01 | show.cgi liefert JSON-Wetterdaten mit Content-Type: application/json; charset=utf-8 | Established CGI header pattern: `print "Content-type: text/html\n\n"` (line 396) — same pattern, different Content-Type value |
| CGI-02 | show.cgi setzt Cache-Control: no-cache Headers fur JSON-Responses | CGI allows multiple headers before blank line separator; `print "Cache-Control: no-cache\n"` added before `\n\n` |
| CGI-03 | show.cgi unterstutzt Parameter format=json mit type=current\|hourly\|daily | Query parameter parsing loop (lines 59-76) already handles arbitrary params; add `format` and `type` to the `foreach $var` list (line 72) or read directly from `%query` |
</phase_requirements>

---

## Summary

Phase 3 is a minimal, surgical Perl CGI extension. The entire implementation is a single new code block inserted into `webfrontend/htmlauth/show.cgi` at approximately line 77 — after query parameter parsing (line 76) and before the MAP VIEW section (line 117). The block detects `format=json`, resolves the JSON file path based on the `type` parameter, reads and prints the file, and exits. The existing HTML rendering path is completely untouched.

The design is already fully specified in CONTEXT.md. Research confirms that the existing CGI patterns in show.cgi are the canonical LoxBerry approach: raw HTTP header strings printed to STDOUT, early-exit after each response branch. No new Perl modules are needed — file reading uses the same `open(F, "<", $path) || ...` idiom already present three times in the file.

The only genuine complexity is error handling: three distinct HTTP status codes (400, 404, 500) must be returned as JSON with correct Content-Type. Perl CGI raw-header mode requires printing the `Status:` header directly when a non-200 status code is needed.

**Primary recommendation:** Insert the JSON block at line 77, using `$query{format}` and `$query{type}` directly from the existing `%query` hash. Handle Status codes via `print "Status: 400 Bad Request\n"` before Content-Type.

---

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Perl | system (5.x) | CGI script runtime | Already in use — show.cgi is Perl |
| CGI module | system | Query string parsing already done | Already loaded via `use CGI qw/:standard/` |
| File open/read | builtin | Read JSON from disk | Already used at lines 149, 227, 314 |

### No New Dependencies

This phase requires zero new Perl modules. Everything needed is already present in show.cgi:
- Query parameter parsing: `%query` hash already populated
- File reading: `open(F, "<", $path) || die "..."` pattern
- Response output: `print "Header: value\n"` to STDOUT
- Early exit: `exit;` pattern

---

## Architecture Patterns

### Recommended Insertion Point

```
show.cgi structure (with new block position):

  Lines 1-76:   Module loading, config, query parameter parsing
>>> INSERT HERE: JSON endpoint block (new, ~30 lines)
  Lines 117-139: MAP VIEW section
  Lines 142-218: Daily Forecast section
  Lines 224-307: Hourly Forecast section
  Lines 309-404: Current Conditions section + HTML output
```

### Pattern 1: CGI HTTP Response (established in show.cgi)

**What:** Print HTTP headers to STDOUT, blank line, then body. CGI protocol.
**When to use:** Every response branch in show.cgi uses this.
**Example:**
```perl
# Source: show.cgi line 396 (existing HTML pattern)
print "Content-type: text/html\n\n";

# JSON equivalent (new pattern):
print "Content-type: application/json; charset=utf-8\n";
print "Cache-Control: no-cache\n";
print "\n";
```

### Pattern 2: Non-200 HTTP Status in Perl CGI

**What:** Perl CGI in raw-header mode requires a `Status:` pseudo-header to send non-200 responses.
**When to use:** 400, 404, 500 error responses.
**Example:**
```perl
# CGI raw header mode — Status line before Content-Type
print "Status: 404 Not Found\n";
print "Content-type: application/json; charset=utf-8\n";
print "Cache-Control: no-cache\n";
print "\n";
print '{"error": "Weather data not available", "code": 404}', "\n";
exit;
```

### Pattern 3: Early-Exit Response Branch (established in show.cgi)

**What:** Each view (map, dfc, hfc) checks its condition, handles the full response, then `exit`s.
**When to use:** JSON block follows the same pattern — detect condition, respond, exit.
**Example:**
```perl
# Source: show.cgi lines 122-140 (existing map view pattern)
if ($map) {
  print "Content-type: text/html\n\n";
  # ... output ...
  exit;
}

# JSON equivalent structure:
if ($query{format} && $query{format} eq 'json') {
  # ... validate type, read file, output, exit ...
}
```

### Pattern 4: File Read to STDOUT (adapted from show.cgi)

**What:** Open file, slurp content, print, close. For JSON pass-through, print raw file content.
**When to use:** type=current|hourly|daily responses.
**Example:**
```perl
# Adapted from show.cgi line 149 pattern — but slurp entire file, not line-by-line
my $json_path = "$home/log/plugins/$psubfolder/current.json";
if (!open(my $fh, "<:raw", $json_path)) {
    # → 404 or 500 error response
}
local $/;  # enable slurp mode
my $json_content = <$fh>;
close($fh);
print $json_content;
exit;
```

Note: `<:raw` layer prevents any Perl encoding layer from mangling the UTF-8 content. The JSON files are written as UTF-8 by grabber_utils.pl — reading raw and printing raw is correct.

### Anti-Patterns to Avoid

- **Parsing the JSON before re-emitting it:** No `use JSON::PP` needed. File-slurp + raw print is the correct approach. Parsing would add latency and risk mangling the already-valid JSON.
- **Using CGI.pm's `header()` function:** show.cgi does NOT use `CGI->header()` — it prints raw headers. Mixing styles risks double headers. Stay consistent with the existing file.
- **Falling through to HTML logic:** The `exit;` after the JSON response MUST be present. Without it, the HTML template logic would run and `die` trying to parse JSON files as .dat format.
- **Reading `format` and `type` from the `foreach $var` loop (line 72):** That loop only reads known vars into named scalars. For the JSON block, reading directly from `%query` is simpler and avoids touching existing code: `$query{format}` and `$query{type}`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP status codes | Custom status string logic | `print "Status: NNN Reason\n"` per CGI spec | Standard CGI protocol; webserver interprets Status header |
| UTF-8 JSON output | Encoding layer conversion | `open(..., "<:raw", ...)` + raw print | JSON files already UTF-8; raw pass-through avoids double-encoding |
| File existence check | Separate `stat()` call | `open()` return value + `-e` check | open() failure already distinguishes "not found" from "not readable" |

---

## Common Pitfalls

### Pitfall 1: Missing Status Header for Non-200 Responses

**What goes wrong:** CGI scripts that omit the `Status:` header always return HTTP 200, even when printing an error JSON body. The browser/client receives `200 OK` with `{"error": "..."}` — Fetch API sees success, not failure.
**Why it happens:** Perl's `print` goes directly to STDOUT. CGI protocol requires the webserver to handle HTTP status via the `Status:` pseudo-header in the CGI response.
**How to avoid:** Always print `Status: NNN Reason\n` as the FIRST header line for any non-200 response.
**Warning signs:** Browser DevTools showing 200 status on requests that should be 400/404/500.

### Pitfall 2: Double Newline Position

**What goes wrong:** CGI requires exactly one blank line (empty line) between headers and body. Printing headers without the trailing `\n\n` (or printing the body before the blank line) causes the webserver to treat body content as headers.
**Why it happens:** Existing show.cgi uses `print "Content-type: text/html\n\n"` — the `\n\n` is the header-block terminator built into one print. When adding multiple headers, the pattern changes.
**How to avoid:** Print each header with `\n`, then print an explicit `\n` as the separator before any body content.
**Warning signs:** Blank page or raw header text appearing in browser response body.

### Pitfall 3: File Path Derivation

**What goes wrong:** Using a hardcoded path instead of the LoxBerry variable pattern. If the plugin is installed under a different subfolder name, the hardcoded path breaks.
**Why it happens:** The `$psubfolder` variable (line 38-39) is derived at runtime from the script's own path. It must be used for all file path construction.
**How to avoid:** Use `"$home/log/plugins/$psubfolder/current.json"` — identical to how the .dat files are referenced (e.g., line 149: `"$home/log/plugins/$psubfolder/dailyforecast.dat"`).
**Warning signs:** 404 responses on a correctly installed system.

### Pitfall 4: Encoding Layer on File Open

**What goes wrong:** Opening the JSON file with a UTF-8 encoding layer (`:encoding(UTF-8)` or `:utf8`) and printing to STDOUT without a matching layer causes "Wide character in print" warnings or double-encoded output.
**Why it happens:** JSON::PP writes UTF-8 bytes to the file. If Perl then decodes those bytes into a character string and re-encodes them, the result is wrong.
**How to avoid:** Open with `<:raw` (or no layer, which is also binary on most systems). Print the raw bytes. STDOUT in CGI context is unbuffered and binary.
**Warning signs:** Umlauts (ä, ö, ü) appearing as multi-byte garbage in browser; Perl "Wide character in print" warnings in error log.

### Pitfall 5: `$/` Scoping in Slurp Mode

**What goes wrong:** Setting `local $/` to `undef` to enable slurp mode affects all subsequent file reads in the same scope if not properly localized.
**Why it happens:** `$/` is a global. Without `local`, unsetting it in the JSON block would cause the .dat reads lower in show.cgi to also slurp entire files in one read, breaking the line-by-line parsing.
**How to avoid:** Always use `local $/` (not `$/ = undef`). The `local` keyword scopes the change to the enclosing block.
**Warning signs:** HTML templates rendering incorrectly for non-JSON requests after adding the JSON block.

---

## Code Examples

Verified patterns from the existing codebase:

### Complete JSON Block Structure

```perl
# Source: derived from show.cgi patterns at lines 59-76, 122-140, 149, 314, 396

#############################################
# JSON API ENDPOINT
#############################################

if ($query{format} && $query{format} eq 'json') {

    # Validate type parameter
    my $type = $query{type} // '';
    my %type_map = (
        'current' => 'current.json',
        'hourly'  => 'hourlyforecast.json',
        'daily'   => 'dailyforecast.json',
    );

    unless ($type_map{$type}) {
        print "Status: 400 Bad Request\n";
        print "Content-type: application/json; charset=utf-8\n";
        print "Cache-Control: no-cache\n";
        print "\n";
        print '{"error": "Invalid or missing type parameter. Use type=current|hourly|daily", "code": 400}', "\n";
        exit;
    }

    my $json_path = "$home/log/plugins/$psubfolder/$type_map{$type}";

    if (!-e $json_path) {
        print "Status: 404 Not Found\n";
        print "Content-type: application/json; charset=utf-8\n";
        print "Cache-Control: no-cache\n";
        print "\n";
        print '{"error": "Weather data not available", "code": 404}', "\n";
        exit;
    }

    if (!open(my $fh, "<:raw", $json_path)) {
        print "Status: 500 Internal Server Error\n";
        print "Content-type: application/json; charset=utf-8\n";
        print "Cache-Control: no-cache\n";
        print "\n";
        print '{"error": "Internal server error", "code": 500}', "\n";
        exit;
    }

    local $/;
    my $json_content = <$fh>;
    close($fh);

    print "Content-type: application/json; charset=utf-8\n";
    print "Cache-Control: no-cache\n";
    print "\n";
    print $json_content;
    exit;
}
```

### Existing File Open Pattern (reference)

```perl
# Source: show.cgi line 149 (existing dailyforecast.dat read)
open(F,"<$home/log/plugins/$psubfolder/dailyforecast.dat") || die "Cannot open ...";
  our @dfcdata = <F>;
close(F);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| show.cgi only serves HTML templates | show.cgi extended with JSON API branch | Phase 3 (this phase) | Browser clients can fetch weather data without HTML parsing |
| Weather data in pipe-delimited .dat files | Weather data in JSON files (Phase 1 output) | Phase 1 complete | JSON files are the canonical source; .dat remains for legacy |

---

## Open Questions

1. **CGI authentication in LoxBerry htmlauth/ vs. html/**
   - What we know: show.cgi lives in `htmlauth/` which requires LoxBerry authentication
   - What's unclear: Whether ocean-live theme (in `html/`) can fetch from `htmlauth/` without auth prompts in same-origin browser context. CONTEXT.md notes "LoxBerry erlaubt same-origin Requests zu htmlauth/" as the working assumption.
   - Recommendation: Proceed with implementation. Auth behavior is a Phase 5 concern and a proxy fallback is already planned if needed. This phase only needs to prove the JSON endpoint works — auth testing happens when Phase 5 integrates the theme.

2. **`-e` check vs. `open()` failure for 404 vs. 500 distinction**
   - What we know: `open()` failure can mean file not found OR permissions error. The CONTEXT.md specifies separate 404 (not found) and 500 (not readable) codes.
   - Recommendation: Use `-e $json_path` as a pre-check for file existence → 404 if missing; then `open()` failure → 500 for permission/corruption errors. This is the cleanest distinction without relying on `$!` errno parsing.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None installed — manual curl + Perl syntax check |
| Config file | none |
| Quick run command | `perl -c webfrontend/htmlauth/show.cgi` |
| Full suite command | `curl` against live LoxBerry instance |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CGI-01 | show.cgi returns Content-Type: application/json; charset=utf-8 for format=json requests | smoke | `perl -c webfrontend/htmlauth/show.cgi` (syntax only) | ✅ show.cgi exists |
| CGI-02 | Response includes Cache-Control: no-cache header | smoke | Manual curl on live system | ❌ requires live LoxBerry |
| CGI-03 | format=json&type=current returns current.json data; type=hourly and type=daily return respective files | smoke | Manual curl on live system | ❌ requires live LoxBerry |

### Sampling Rate

- **Per task commit:** `perl -c webfrontend/htmlauth/show.cgi`
- **Per wave merge:** Manual curl test on dev LoxBerry: `curl -v "http://loxberry/plugins/weather4lox/show.cgi?format=json&type=current"`
- **Phase gate:** Full curl test for all three types + error cases before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] No automated test harness for CGI output — requires live LoxBerry system with JSON files present on RAM disk
- [ ] `perl -c` syntax check is the only automated validation available in this environment

*(Note: All functional verification for this phase is manual-only due to LoxBerry module dependencies and RAM disk file system requirements. The `/gsd:verify-work` verifier will rely on code inspection rather than automated test execution.)*

---

## Sources

### Primary (HIGH confidence)

- `webfrontend/htmlauth/show.cgi` (read in full) — established CGI patterns: header output, query parsing, file reading, early-exit structure
- `data/json-schema.md` (Phase 1 output) — canonical file names: current.json, dailyforecast.json, hourlyforecast.json
- `.planning/phases/03-cgi-json-endpoint/03-CONTEXT.md` — all architectural decisions pre-locked
- `.planning/REQUIREMENTS.md` — CGI-01, CGI-02, CGI-03 definitions

### Secondary (MEDIUM confidence)

- CGI specification (RFC 3875) — `Status:` pseudo-header behavior for non-200 responses; verified against common knowledge of CGI protocol

### Tertiary (LOW confidence)

- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; entire implementation uses existing show.cgi patterns
- Architecture: HIGH — insertion point, block structure, and exit pattern all derived from existing code
- Pitfalls: HIGH — encoding, `$/` scoping, Status header, and path derivation are standard Perl CGI concerns with clear mitigations from codebase inspection

**Research date:** 2026-03-13
**Valid until:** This research is not time-sensitive — LoxBerry Perl CGI architecture is stable. Valid until the show.cgi file structure changes significantly.
