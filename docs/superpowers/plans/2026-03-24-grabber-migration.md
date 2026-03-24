# Grabber Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alle Grabber auf wetteronline-JSON-Standard (camelCase, nested objects, Envelope) migrieren, .dat entfernen, AQ/Pollen integrieren.

**Architecture:** Grabber-fuer-Grabber Migration. Jeder Grabber wird einzeln umgebaut (wetteronline als Vorlage), getestet und committed. Patch-Grabber werden auf JSON-Merge umgestellt. AQ/Pollen wird in alle 3 JSON-Dateien integriert. Consumer (ocean-live, datatoloxone, show.cgi) werden angepasst.

**Tech Stack:** Perl 5 (LoxBerry), JSON::PP, Config::Simple, JavaScript (ocean-live.html)

**Spec:** `docs/superpowers/specs/2026-03-24-grabber-migration-design.md`
**Referenz-Grabber:** `bin/grabber_wetteronline.pl` (lines 709-722 current, 917-930 daily, 1279-1292 hourly)
**Referenz-JSONs:** `2026_03_24/current.json`, `2026_03_24/dailyforecast.json`, `2026_03_24/hourlyforecast.json`

---

## File Structure

### Modified Files

| File | Responsibility | Phase |
|------|---------------|-------|
| `bin/grabber_openweather2.pl` (1221 lines) | Bereits JSON-Envelope, nur `refresh` hinzufuegen | 1 |
| `bin/grabber_visualcrossing.pl` (739 lines) | .dat + flat-JSON -> proper camelCase Envelope | 1 |
| `bin/grabber_weatherflow.pl` (702 lines) | .dat + flat-JSON -> proper camelCase Envelope | 1 |
| `bin/grabber_wttrin.pl` (1041 lines) | .dat + flat-JSON -> proper camelCase Envelope | 1 |
| `bin/grabber_wu.pl` (187 lines) | Fix `rain1Hr` -> `rain1hr`, add refresh | 2 |
| `bin/grabber_foshk.pl` (233 lines) | .dat-Patch -> JSON-Merge | 2 |
| `bin/grabber_loxone.pl` (223 lines) | .dat-Patch -> JSON-Merge | 2 |
| `bin/grabber_pwscatchupload.pl` (219 lines) | snake_case -> camelCase, .dat -> JSON-Merge | 2 |
| `bin/grabber_openmeteo_airquality.pl` (294 lines) | Rewrite: merge AQ+Pollen in alle 3 JSONs | 3 |
| `bin/grabber_utils.pl` (843 lines) | `pollenLevel()` auf 0-7, ggf. neue Helpers | 3 |
| `webfrontend/html/ocean-live.html` | Ersetzen durch ocean-live_new.html, camelCase-Anpassung | 4 |
| `bin/datatoloxone.pl` (947 lines) | `snow1hr` -> `snow1h` Fix | 4 |
| `webfrontend/htmlauth/show.cgi` (907 lines) | Feldnamen fixen | 4 |
| `webfrontend/htmlauth/index.cgi` | Pollen-Settings auf weather4lox.cfg umstellen | 4 |
| `config/weather4lox.cfg` | `[POLLEN]` + `CRON_PATCH` hinzufuegen | 3/4 |
| `postinstall.sh` | Default-Seeding fuer `[POLLEN]` | 3 |
| `data/json-schema.md` | AQ/Pollen-Schema dokumentieren | 3 |
| `DECISIONS.md` | Dual-Write -> clean break | 5 |

### Deleted Files (Phase 5)

| File | Reason |
|------|--------|
| `data/current.format` | Legacy .dat spec |
| `data/dailyforecast.format` | Legacy .dat spec |
| `data/hourlyforecast.format` | Legacy .dat spec |
| `data/hourlyhistory.format` | Legacy .dat spec |
| `data/dummies/current.dat` | Legacy dummy |
| `data/dummies/dailyforecast.dat` | Legacy dummy |
| `data/dummies/hourlyforecast.dat` | Legacy dummy |
| `data/dummies/hourlyhistory.dat` | Legacy dummy |
| `bin/grabber_openweather.pl` | Legacy v2 API |
| `bin/grabber_wetteronline_old.pl` | Legacy |
| `bin/grabber_wetteronline2.pl` | Legacy/Duplikat -- wird durch grabber_wetteronline.pl abgedeckt |
| `config/mapping_custom_mix_pollen.json` (runtime) | Ersetzt durch [POLLEN] in weather4lox.cfg |

---

## Phase 1 -- Haupt-Grabber Migration

### Task 1: grabber_openweather2.pl -- refresh hinzufuegen

**Files:**
- Modify: `bin/grabber_openweather2.pl`

Dieser Grabber hat bereits korrekten JSON-Output mit Envelope (writeJsonFile at lines 627-638, 835-846, 1197-1208). Kein .dat-Code vorhanden. Nur `refresh` fehlt.

- [ ] **Step 1: `refresh` in alle 3 Envelope-Bloecke einfuegen**

```perl
my $cronMinutes = $pcfg->param("SERVER.CRON") // 15;
my $refresh = $cronMinutes * 60;

# In jedem der 3 Envelope-Hashref (lines 627, 835, 1197):
my $envelope = {
    refresh   => $refresh,
    location  => $location,
    $grabberKey => { ... },
    $weatherKey => ...,
};
```

- [ ] **Step 2: Verifizieren dass Envelope-Struktur dem wetteronline-Standard entspricht**

Pruefe camelCase-Feldnamen, verschachtelte Objekte (temperature.air, wind.speed, etc.). Falls noch flat/snake_case Felder vorhanden, anpassen.

- [ ] **Step 3: Commit**

```bash
git add bin/grabber_openweather2.pl
git commit -m "feat(openweather2): add refresh to JSON envelope"
```

---

### Task 2: grabber_visualcrossing.pl -- Migration auf camelCase Envelope

**Files:**
- Modify: `bin/grabber_visualcrossing.pl` (739 lines)

Dieser Grabber hat .dat-Output UND flat snake_case JSON (via `write_current_json`/`write_daily_json`/`write_hourly_json` -- Funktionen die nicht in grabber_utils.pl existieren, vermutlich aus frueherer Migration). Beides muss durch proper camelCase Envelope mit `writeJsonFile()` ersetzt werden.

- [ ] **Step 1: Referenz-Pattern aus wetteronline verstehen**

Lies `bin/grabber_wetteronline.pl` als Vorlage:
- Lines 583-724: Current-Block (API-Daten -> camelCase Hash -> Envelope -> writeJsonFile)
- Lines 730-932: Daily-Block
- Lines 938-1292: Hourly-Block

Beachte die Feld-Struktur:
```perl
my %currentData = (
    temperature => { air => $temp, feelsLike => $feels, windChill => $wc, heatIndex => $hi },
    wind        => { direction => $dir, dirLabel => $label, speed => $spd, gust => $gst },
    precipitation => { rainToday => $rt, rain1hr => $r1, probability => $pop, type => $type, snowToday => $st, snow1h => $s1 },
    weatherCode => { loxone => $lox, weather4lox => $w4l, description => $desc, image => $img, metar => $metar },
    moon        => { age => $age, percent => $pct, phase => $ph, direction => $dir },
    time        => { datetime => $dt, epoch => $ep, timezone => $tz, tzOffset => $tzo, tzShort => $tzs },
    # flat fields:
    humidity => $hum, pressure => $prs, dewpoint => $dew, visibility => $vis,
    solarRadiation => $sol, uvIndex => $uvi, cloudCover => $cc, ozone => $oz,
    isNight => $night, sunrise => $sr, sunset => $ss,
);
```

- [ ] **Step 2: Grabber-Variablen definieren**

Am Anfang des Grabbers (nach Config-Reads):
```perl
my $grabberKey   = "visualcrossing";
my $grabberLabel = "Visual Crossing";
my $grabberFile  = "grabber_visualcrossing.pl";
my $cronMinutes  = $pcfg->param("SERVER.CRON") // 15;
my $refresh      = $cronMinutes * 60;
```

- [ ] **Step 3: Location-Hash bauen**

```perl
my $location = {
    city        => $city,
    country     => $country,
    countryCode => $countryCode,
    elevation   => $elevation + 0,
    latitude    => $lat + 0,
    longitude   => $lon + 0,
    timezone    => $timezone,
    tzOffset    => $tzOffset,
    tzShort     => $tzShort,
};
```

- [ ] **Step 4: Current-Block umbauen**

Ersetze den .dat-Schreibblock (lines ~160-263 + move at ~520-523) durch:
1. API-Daten in camelCase-Hash `%currentData` mappen (Vorlage: wetteronline)
2. Envelope bauen mit `refresh`, `location`, `$grabberKey`-Metadaten, `$weatherKey => \%currentData`
3. `writeJsonFile($lbplogdir, "current", $envelope);`

- [ ] **Step 5: Daily-Block umbauen**

Ersetze den .dat-Schreibblock (lines ~284-370 + move at ~553-556) durch:
1. API-Daten in Array `@dailyData` aus camelCase-Hashes mappen
2. Jeder Tag bekommt `day => $i` (0-basiert), `temperature => {max => {air, feelsLike, heatIndex}, min => {air, feelsLike, windChill}}`, `wind => {avg => {...}, max => {...}}`, `humidity => {avg, max, min}`, etc.
3. Envelope + `writeJsonFile($lbplogdir, "dailyforecast", $envelope);`

- [ ] **Step 6: Hourly-Block umbauen**

Ersetze den .dat-Schreibblock (lines ~392-480 + move at ~586-589) durch:
1. API-Daten in Array `@hourlyData` aus camelCase-Hashes
2. Jede Stunde bekommt `hour => $i` (0-basiert), `temperature => {air, feelsLike, heatIndex, windChill}`, `wind => {direction, dirLabel, speed, gust}`, `isNight`, etc.
3. Envelope + `writeJsonFile($lbplogdir, "hourlyforecast", $envelope);`

- [ ] **Step 7: .dat-Code UND alte flat-JSON-Aufrufe entfernen**

Entferne:
- `$currentnametmp`, `$dailynametmp`, `$hourlynametmp` Variablen
- Alle `open/print/close` fuer .dat, alle `move()` fuer .dat
- Alte `write_current_json()`, `write_daily_json()`, `write_hourly_json()` Aufrufe (diese Funktionen existieren nicht in grabber_utils.pl und sind Relikte)

- [ ] **Step 8: Funktionsnamen pruefen**

Pruefe ob interne Funktionen camelCase verwenden. Insbesondere `api_call()` -- diese ist eine shared Funktion aus `grabber_utils.pl`, daher erstmal beibehalten.

- [ ] **Step 9: Commit**

```bash
git add bin/grabber_visualcrossing.pl
git commit -m "feat(visualcrossing): migrate from .dat to JSON envelope output"
```

---

### Task 3: grabber_weatherflow.pl -- Migration auf camelCase Envelope

**Files:**
- Modify: `bin/grabber_weatherflow.pl` (702 lines)

Gleiches Pattern wie Task 2. .dat + flat-JSON -> proper camelCase Envelope.

- [ ] **Step 1: .dat-Bloecke identifizieren**

- Lines ~185-265: current.dat.tmp
- Lines ~288-362: dailyforecast.dat.tmp
- Lines ~383-463: hourlyforecast.dat.tmp
- Lines ~503-506, ~536-539, ~569-572: move .dat

- [ ] **Step 2: Grabber-Variablen + Location-Hash definieren**

```perl
my $grabberKey   = "weatherflow";
my $grabberLabel = "WeatherFlow";
my $grabberFile  = "grabber_weatherflow.pl";
```

- [ ] **Step 3: Current-, Daily-, Hourly-Bloecke umbauen**

Wie Task 2: API-Daten -> camelCase Hashes -> Envelope -> writeJsonFile. Beachte WeatherFlow-spezifische API-Felder und deren Mapping.

- [ ] **Step 4: .dat-Code entfernen + Commit**

```bash
git add bin/grabber_weatherflow.pl
git commit -m "feat(weatherflow): migrate from .dat to JSON envelope output"
```

---

### Task 4: grabber_wttrin.pl -- Migration auf camelCase Envelope

**Files:**
- Modify: `bin/grabber_wttrin.pl` (1041 lines)

Groesster der zu migrierenden Grabber. .dat + flat-JSON -> proper camelCase Envelope.

- [ ] **Step 1: .dat-Bloecke identifizieren**

- Lines ~186-296: current.dat.tmp
- Lines ~376-544: dailyforecast.dat.tmp
- Lines ~730-901: hourlyforecast.dat.tmp
- Lines ~942-945, ~976-979, ~1010-1013: move .dat

- [ ] **Step 2: Grabber-Variablen + Location-Hash**

```perl
my $grabberKey   = "wttrin";
my $grabberLabel = "wttr.in";
my $grabberFile  = "grabber_wttrin.pl";
```

- [ ] **Step 3: Current-, Daily-, Hourly-Bloecke umbauen**

wttr.in hat eigene Wettercodes (WWO-Codes). Beachte `wttr_to_lox()` Mapping fuer weatherCode-Felder.

- [ ] **Step 4: .dat-Code entfernen + Commit**

```bash
git add bin/grabber_wttrin.pl
git commit -m "feat(wttrin): migrate from .dat to JSON envelope output"
```

---

## Phase 2 -- Patch-Grabber Migration

### Task 5: Config -- CRON_PATCH Parameter hinzufuegen (VOR Patch-Grabbern)

**Files:**
- Modify: `config/weather4lox.cfg`
- Modify: `webfrontend/htmlauth/index.cgi` (Abschnitt SERVER-Settings)

Muss VOR den Patch-Grabbern erledigt werden, da diese `SERVER.CRON_PATCH` lesen.

- [ ] **Step 1: CRON_PATCH in weather4lox.cfg einfuegen**

Im `[SERVER]`-Abschnitt:
```ini
CRON_PATCH=1
```

- [ ] **Step 2: index.cgi -- CRON_PATCH Dropdown hinzufuegen**

Im Server-Einstellungen Formular ein Dropdown fuer CRON_PATCH (Minuten: 1, 2, 5, 10, 15).

- [ ] **Step 3: Commit**

```bash
git add config/weather4lox.cfg webfrontend/htmlauth/index.cgi
git commit -m "feat(config): add CRON_PATCH interval for patch grabbers"
```

---

### Task 6: grabber_wu.pl -- Inkonsistenzen fixen + refresh

**Files:**
- Modify: `bin/grabber_wu.pl` (187 lines)

Bereits JSON-Merge, aber mit Feldnamen-Bugs.

- [ ] **Step 1: `rain1Hr` -> `rain1hr` fixen**

Suche alle Vorkommen von `rain1Hr` und ersetze durch `rain1hr`.

- [ ] **Step 2: `refresh` hinzufuegen**

Beim Envelope-Write (line ~165-177) `refresh` einfuegen:
```perl
my $cronMinutes = $pcfg->param("SERVER.CRON_PATCH") // 1;
$envelope->{refresh} = $cronMinutes * 60;
```

- [ ] **Step 3: Restliche Feldnamen auf camelCase pruefen**

Vergleiche alle Hash-Key-Zuweisungen mit Referenz-Schema.

- [ ] **Step 4: Commit**

```bash
git add bin/grabber_wu.pl
git commit -m "fix(wu): fix rain1Hr->rain1hr, add refresh to envelope"
```

---

### Task 6: grabber_foshk.pl -- .dat-Patch auf JSON-Merge

**Files:**
- Modify: `bin/grabber_foshk.pl` (233 lines)

- [ ] **Step 1: .dat-Lese/Patch-Code verstehen**

Aktuell (lines ~150-160): Kopiert current.dat, liest Pipe-Felder, patcht einzelne Positionen, schreibt zurueck.

- [ ] **Step 2: Auf JSON-Merge umbauen**

```perl
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
unless ($envelope) {
    LOGWARN "No existing $weatherKey.json found, skipping";
    next;
}
my $cur = $envelope->{$weatherKey} // {};

# Felder patchen (Beispiel):
$cur->{temperature}{air}      = $foshkTemp     if defined $foshkTemp;
$cur->{humidity}              = $foshkHumidity  if defined $foshkHumidity;
$cur->{wind}{speed}           = $foshkWindSpeed if defined $foshkWindSpeed;
# ... weitere Felder

# Grabber-Metadaten hinzufuegen
$envelope->{foshk} = {
    filename      => "$lbplogdir/$weatherKey.json",
    generatedAt   => $generatedAt,
    grabberLabel  => "FOSHK",
    grabberScript => "grabber_foshk.pl",
    schemaVersion => "v1.0",
};

# Refresh
my $cronMinutes = $pcfg->param("SERVER.CRON_PATCH") // 1;
$envelope->{refresh} = $cronMinutes * 60;

writeJsonFile($lbplogdir, $weatherKey, $envelope);
```

- [ ] **Step 3: .dat-Code entfernen**

Entferne alle `split /\|/`, .dat open/read/write Bloecke, `$currentnametmp`, `$currentname`.

- [ ] **Step 4: Commit**

```bash
git add bin/grabber_foshk.pl
git commit -m "feat(foshk): migrate from .dat-patch to JSON-merge"
```

---

### Task 7: grabber_loxone.pl -- .dat-Patch auf JSON-Merge

**Files:**
- Modify: `bin/grabber_loxone.pl` (223 lines)

- [ ] **Step 1-4: Identisch zu Task 6**

Gleiche Umstellung: .dat-Patch -> JSON-Merge mit readJsonFile/writeJsonFile. grabberKey: `"loxone"`.

```bash
git commit -m "feat(loxone): migrate from .dat-patch to JSON-merge"
```

---

### Task 8: grabber_pwscatchupload.pl -- snake_case -> camelCase + JSON-Merge

**Files:**
- Modify: `bin/grabber_pwscatchupload.pl` (219 lines)

- [ ] **Step 1: Aktuelle snake_case Feldnamen identifizieren**

Suche alle Hash-Key-Zuweisungen: `wind_direction_desc`, `wind_direction_deg`, `wind_speed`, etc.

- [ ] **Step 2: Auf camelCase + nested Objects umstellen**

Ersetze flat snake_case durch nested camelCase:
```perl
# ALT:
$cur->{wind_direction_desc} = $windDir;
$cur->{wind_speed}          = $windSpeed;

# NEU:
$cur->{wind}{dirLabel}   = $windDir;
$cur->{wind}{speed}      = $windSpeed;
$cur->{wind}{direction}  = $windDeg;
$cur->{wind}{gust}       = $windGust;
```

- [ ] **Step 3: .dat-Code entfernen, JSON-Merge Pattern + Commit**

```bash
git commit -m "feat(pwscatchupload): migrate to camelCase JSON-merge"
```

---

## Phase 3 -- AQ + Pollen Integration

### Task 10: Pollen-Config in weather4lox.cfg + postinstall.sh

**Files:**
- Modify: `config/weather4lox.cfg`
- Modify: `postinstall.sh`

- [ ] **Step 1: [POLLEN] Abschnitt in weather4lox.cfg**

```ini
[POLLEN]
ALDER=0
BIRCH=0
GRASS=0
MUGWORT=0
OLIVE=0
RAGWEED=0
```

- [ ] **Step 2: Default-Seeding in postinstall.sh**

Fuege Logik hinzu die [POLLEN]-Defaults setzt falls nicht vorhanden (analog zu bestehenden Config-Checks).

- [ ] **Step 3: Commit**

```bash
git add config/weather4lox.cfg postinstall.sh
git commit -m "feat(config): add [POLLEN] sensitivity settings (0-7 scale)"
```

---

### Task 11: pollenLevel() auf 0-7 erweitern + calculatePersonalMix()

**Files:**
- Modify: `bin/grabber_openmeteo_airquality.pl` (pollenLevel lebt bereits dort, line 119; calculatePersonalMix wird dort hinzugefuegt)

- [ ] **Step 1: pollenLevel() Schwellwert-Tabelle implementieren**

```perl
sub pollenLevel {
    my ($type, $value) = @_;
    return 0 unless defined $value && $value ne '' && $value > 0;
    $value = 0 + $value;

    if ($type eq 'alder' || $type eq 'birch' || $type eq 'olive') {
        return 1 if $value <= 5;
        return 2 if $value <= 15;
        return 3 if $value <= 30;
        return 4 if $value <= 60;
        return 5 if $value <= 100;
        return 6 if $value <= 200;
        return 7;
    } elsif ($type eq 'grass' || $type eq 'mugwort' || $type eq 'ragweed') {
        return 1 if $value <= 2;
        return 2 if $value <= 5;
        return 3 if $value <= 10;
        return 4 if $value <= 20;
        return 5 if $value <= 35;
        return 6 if $value <= 50;
        return 7;
    }
    return 0;
}
```

- [ ] **Step 2: personalMix Berechnung implementieren**

```perl
sub calculatePersonalMix {
    my ($pollenLevels, $sensitivities) = @_;
    # $pollenLevels: { alder => 2, birch => 3, ... }
    # $sensitivities: { ALDER => 3, BIRCH => 5, ... }

    my $weightedSum = 0;
    my $totalWeight = 0;

    for my $type (keys %$pollenLevels) {
        my $configKey = uc($type);
        my $weight = $sensitivities->{$configKey} // 0;
        next unless $weight > 0;

        $weightedSum += $pollenLevels->{$type} * $weight;
        $totalWeight += $weight;
    }

    return 0 unless $totalWeight > 0;
    return int($weightedSum / $totalWeight + 0.5);
}
```

- [ ] **Step 3: Commit**

```bash
git add bin/grabber_openmeteo_airquality.pl
git commit -m "feat(pollen): pollenLevel 0-7 scale + personalMix calculation"
```

---

### Task 12: AQ-Grabber Rewrite -- Merge in alle 3 JSONs

**Files:**
- Modify: `bin/grabber_openmeteo_airquality.pl` (294 lines -- kompletter Rewrite der Output-Logik)

- [ ] **Step 1: Pollen-Config aus weather4lox.cfg lesen**

```perl
my %pollenSensitivity = (
    ALDER   => $pcfg->param("POLLEN.ALDER")   // 0,
    BIRCH   => $pcfg->param("POLLEN.BIRCH")    // 0,
    GRASS   => $pcfg->param("POLLEN.GRASS")    // 0,
    MUGWORT => $pcfg->param("POLLEN.MUGWORT")  // 0,
    OLIVE   => $pcfg->param("POLLEN.OLIVE")    // 0,
    RAGWEED => $pcfg->param("POLLEN.RAGWEED")  // 0,
);
```

- [ ] **Step 2: Current AQ in current.json mergen**

```perl
my $weatherKey = "current";
my $envelope = readJsonFile($lbplogdir, $weatherKey);
if ($envelope) {
    my $cur = $envelope->{$weatherKey};

    # AirQuality
    $cur->{airQuality} = {
        aqiEu => $europeanAqi + 0,
        aqiUs => $usAqi + 0,
        pm10  => $pm10 + 0,
        pm25  => $pm2_5 + 0,
    };

    # Pollen (aktuelle Stunde)
    my $nowIdx = ...; # Index der aktuellen Stunde in API-Daten
    my %curPollen;
    for my $type (@pollenTypes) {
        $curPollen{$type} = pollenLevel($type, $hourlyPollen{$type}[$nowIdx]);
    }
    $curPollen{personalMix} = calculatePersonalMix(\%curPollen, \%pollenSensitivity);
    $cur->{pollen} = \%curPollen;

    # Grabber-Metadaten
    $envelope->{openmeteoAq} = { ... };
    writeJsonFile($lbplogdir, $weatherKey, $envelope);
}
```

- [ ] **Step 3: Hourly Pollen in hourlyforecast.json mergen**

```perl
my $hfcKey = "hourlyforecast";
my $hfcEnvelope = readJsonFile($lbplogdir, $hfcKey);
if ($hfcEnvelope) {
    my $hours = $hfcEnvelope->{$hfcKey};
    for my $h (@$hours) {
        my $hDatetime = $h->{time}{datetime};
        my $matchIdx = findTimestampIndex($times, $hDatetime);
        if (defined $matchIdx) {
            my %hPollen;
            for my $type (@pollenTypes) {
                $hPollen{$type} = pollenLevel($type, $hourlyPollen{$type}[$matchIdx]);
            }
            $hPollen{personalMix} = calculatePersonalMix(\%hPollen, \%pollenSensitivity);
            $h->{pollen} = \%hPollen;
        } else {
            $h->{pollen} = undef; # null fuer Stunden ohne Pollen-Daten
        }
        $h->{airQuality} = undef; # keine hourly AQ-Daten
    }
    writeJsonFile($lbplogdir, $hfcKey, $hfcEnvelope);
}
```

- [ ] **Step 4: Daily Pollen in dailyforecast.json mergen**

Aggregiere Stundenwerte pro Tag (avg + max):
```perl
my $dfcKey = "dailyforecast";
my $dfcEnvelope = readJsonFile($lbplogdir, $dfcKey);
if ($dfcEnvelope) {
    my $days = $dfcEnvelope->{$dfcKey};
    for my $d (@$days) {
        my $dayDate = substr($d->{time}{datetime}, 0, 10);
        # Sammle alle Stundenwerte fuer diesen Tag
        my %dayLevels;
        for my $i (0 .. $#$times) {
            next unless substr($times->[$i], 0, 10) eq $dayDate;
            for my $type (@pollenTypes) {
                push @{$dayLevels{$type}}, pollenLevel($type, $hourlyPollen{$type}[$i]);
            }
        }
        if (%dayLevels) {
            my %dPollen;
            for my $type (@pollenTypes) {
                my @levels = @{$dayLevels{$type} // []};
                next unless @levels;
                my $sum = 0; my $max = 0;
                for my $l (@levels) { $sum += $l; $max = $l if $l > $max; }
                $dPollen{$type} = { avg => int($sum / scalar(@levels) + 0.5), max => $max };
            }
            # personalMix fuer avg und max separat
            my %avgLevels = map { $_ => $dPollen{$_}{avg} } keys %dPollen;
            my %maxLevels = map { $_ => $dPollen{$_}{max} } keys %dPollen;
            $dPollen{personalMix} = {
                avg => calculatePersonalMix(\%avgLevels, \%pollenSensitivity),
                max => calculatePersonalMix(\%maxLevels, \%pollenSensitivity),
            };
            $d->{pollen} = \%dPollen;
        } else {
            $d->{pollen} = undef;
        }
        $d->{airQuality} = undef;
    }
    writeJsonFile($lbplogdir, $dfcKey, $dfcEnvelope);
}
```

- [ ] **Step 5: Legacy airquality_pollen.json Output entfernen**

Entferne den alten Standalone-Write-Block (lines ~248-280).

- [ ] **Step 6: Commit**

```bash
git add bin/grabber_openmeteo_airquality.pl
git commit -m "feat(aq): merge airQuality+pollen into all 3 JSON files with personalMix"
```

---

### Task 13: json-schema.md um AQ/Pollen erweitern

**Files:**
- Modify: `data/json-schema.md`

- [ ] **Step 1: airQuality + pollen Felder dokumentieren**

Fuege in jedem der 3 Abschnitte (current, daily, hourly) die neuen Felder hinzu:
- `airQuality`: `{aqiEu, aqiUs, pm10, pm25}` (nur current, sonst null)
- `pollen`: current/hourly mit flat Levels, daily mit avg/max Objekten
- `personalMix`: Berechnungsformel referenzieren

- [ ] **Step 2: Commit**

```bash
git add data/json-schema.md
git commit -m "docs: add airQuality and pollen fields to JSON schema"
```

---

## Phase 4 -- Consumer-Anpassung

### Task 14: ocean-live.html -- Neue Version mit camelCase-Anpassung

**Files:**
- Modify: `webfrontend/html/ocean-live.html` (ersetzen durch `2026_03_24/ocean-live_new.html`)

- [ ] **Step 1: ocean-live_new.html als Basis kopieren**

```bash
cp 2026_03_24/ocean-live_new.html webfrontend/html/ocean-live.html
```

- [ ] **Step 2: Envelope-Zugriff anpassen**

Aendere `loadAllData()` (ab line ~377):

```javascript
// ALT:
liveData.current = (results[0] && results[0].data) || results[0] || {};
var hourlyRaw = (results[1] && results[1].data) || results[1] || [];
var dailyRaw = (results[2] && results[2].data) || results[2] || [];

// NEU:
var currentEnvelope = results[0] || {};
liveData.current = currentEnvelope.current || {};
liveData.location = currentEnvelope.location || {};
liveData.refreshInterval = (currentEnvelope.refresh || 300) * 1000;

var hourlyEnvelope = results[1] || {};
var hourlyRaw = hourlyEnvelope.hourlyforecast || [];

var dailyEnvelope = results[2] || {};
var dailyRaw = dailyEnvelope.dailyforecast || [];
```

- [ ] **Step 3: Current-Felder auf camelCase nested umstellen**

In `renderAll()` und allen current-Zugriffen:

```javascript
// ALT -> NEU:
c.temperature          -> c.temperature.air
c.feelslike            -> c.temperature.feelsLike
c.wind_speed           -> c.wind.speed
c.wind_direction_desc  -> c.wind.dirLabel
c.wind_gust            -> c.wind.gust
c.weather_code         -> c.weatherCode.weather4lox
c.weather_description  -> c.weatherCode.description
c.precip_today_mm      -> c.precipitation.rainToday
c.uv_index             -> c.uvIndex
c.cloud_cover          -> c.cloudCover
c.datetime             -> c.time.datetime
c.epoch                -> c.time.epoch
c.city                 -> liveData.location.city
```

- [ ] **Step 4: Hourly-Felder umstellen**

In `transformHourly()`:

```javascript
// ALT -> NEU:
h.temperature          -> h.temperature.air
h.feels_like           -> h.temperature.feelsLike
h.precip_probability   -> h.precipitation.probability
h.precip_amount        -> h.precipitation.rainHigh
h.wind_speed           -> h.wind.speed
h.wind_direction_desc  -> h.wind.dirLabel
h.uv_index             -> h.uvIndex
h.cloud_cover          -> h.cloudCover
h.weather_code         -> h.weatherCode.weather4lox
h.weather_description  -> h.weatherCode.description
h.datetime             -> h.time.datetime
```

- [ ] **Step 5: Daily-Felder umstellen**

In der `dailyRaw.map()` Transformation:

```javascript
// ALT -> NEU:
d.weather_code         -> d.weatherCode.weather4lox
d.high_temp            -> d.temperature.max.air
d.low_temp             -> d.temperature.min.air
d.precip_probability   -> d.precipitation.probability
d.weather_description  -> d.weatherCode.description
d.wind_speed           -> d.wind.avg.speed
d.wind_gust            -> d.wind.max.gust
d.wind_direction_desc  -> d.wind.avg.dirLabel
d.humidity             -> d.humidity.avg
d.humidity_max         -> d.humidity.max
d.humidity_min         -> d.humidity.min
d.precip_amount        -> d.precipitation.rainHigh
d.snow_amount          -> d.precipitation.snowHigh
d.uv_index             -> d.uvIndex
```

- [ ] **Step 6: Dynamisches Refresh-Intervall**

```javascript
// ALT:
var REFRESH_INTERVAL_MS = 5 * 60 * 1000;

// NEU: als Default beibehalten, aber nach Load ueberschreiben
var REFRESH_INTERVAL_MS = 5 * 60 * 1000; // Default fallback

// In loadAllData(), nach Envelope-Parse:
REFRESH_INTERVAL_MS = liveData.refreshInterval || REFRESH_INTERVAL_MS;
```

- [ ] **Step 7: Stadt-Anzeige aus location**

```javascript
// ALT:
document.getElementById('hdrCity').textContent = c.city || c.location || '--';

// NEU:
document.getElementById('hdrCity').textContent = liveData.location.city || '--';
```

- [ ] **Step 8: Commit**

```bash
git add webfrontend/html/ocean-live.html
git commit -m "feat(ocean-live): update to camelCase JSON structure with dynamic refresh"
```

---

### Task 15: datatoloxone.pl -- snow1hr Bug fixen

**Files:**
- Modify: `bin/datatoloxone.pl` (947 lines)

- [ ] **Step 1: snow1hr -> snow1h fixen**

Suche alle `snow1hr` Referenzen und ersetze durch `snow1h`.

- [ ] **Step 2: Weitere Feld-Zugriffe pruefen**

Vergleiche alle `$cur->{...}`, `$dfcEntry->{...}`, `$hfcEntry->{...}` Zugriffe mit dem Referenz-JSON. Insbesondere `rain1Hr` vs `rain1hr`.

- [ ] **Step 3: Commit**

```bash
git add bin/datatoloxone.pl
git commit -m "fix(datatoloxone): fix snow1hr->snow1h field name"
```

---

### Task 16: show.cgi -- Feldnamen fixen

**Files:**
- Modify: `webfrontend/htmlauth/show.cgi` (907 lines)

- [ ] **Step 1: Alle falschen Feldnamen identifizieren und fixen**

Bekannte Fehler:
- `rain_today_mm` -> `rainToday`
- `rain_1hr_mm` -> `rain1hr`
- `snow_today_cm` -> `snowToday`
- Ggf. weitere snake_case Reste

- [ ] **Step 2: Commit**

```bash
git add webfrontend/htmlauth/show.cgi
git commit -m "fix(show.cgi): fix snake_case field names to camelCase"
```

---

### Task 17: index.cgi -- Pollen-Settings auf Config umstellen

**Files:**
- Modify: `webfrontend/htmlauth/index.cgi`

- [ ] **Step 1: Save-Handler aendern (lines ~248-261)**

```perl
# ALT: JSON-Datei schreiben
open(my $fh, '>', "$lbpconfigdir/mapping_custom_mix_pollen.json");
print $fh encode_json(\%pollen_data);

# NEU: In weather4lox.cfg schreiben
$pcfg->param("POLLEN.ALDER",   $R::pollen_alder + 0);
$pcfg->param("POLLEN.BIRCH",   $R::pollen_birch + 0);
$pcfg->param("POLLEN.GRASS",   $R::pollen_grasses + 0);
$pcfg->param("POLLEN.MUGWORT", $R::pollen_mugwort + 0);
$pcfg->param("POLLEN.OLIVE",   $R::pollen_olive + 0);
$pcfg->param("POLLEN.RAGWEED", $R::pollen_ragweed + 0);
$pcfg->save();
```

- [ ] **Step 2: Read-Defaults aendern (lines ~554-566)**

```perl
# ALT: JSON lesen
open(my $pfh, '<', "$lbpconfigdir/mapping_custom_mix_pollen.json");

# NEU: Aus Config lesen
my %pollen_defaults = (
    grasses => $pcfg->param("POLLEN.GRASS")   // 0,
    birch   => $pcfg->param("POLLEN.BIRCH")   // 0,
    alder   => $pcfg->param("POLLEN.ALDER")   // 0,
    mugwort => $pcfg->param("POLLEN.MUGWORT") // 0,
    olive   => $pcfg->param("POLLEN.OLIVE")   // 0,
    ragweed => $pcfg->param("POLLEN.RAGWEED") // 0,
);
```

- [ ] **Step 3: Commit**

```bash
git add webfrontend/htmlauth/index.cgi
git commit -m "feat(index.cgi): move pollen settings from JSON to weather4lox.cfg"
```

---

## Phase 5 -- Cleanup

### Task 18: Legacy-Dateien entfernen

**Files:**
- Delete: `data/current.format`
- Delete: `data/dailyforecast.format`
- Delete: `data/hourlyforecast.format`
- Delete: `bin/grabber_openweather.pl`
- Delete: `bin/grabber_wetteronline_old.pl`

- [ ] **Step 1: Dateien loeschen**

```bash
git rm data/current.format data/dailyforecast.format data/hourlyforecast.format data/hourlyhistory.format
git rm data/dummies/current.dat data/dummies/dailyforecast.dat data/dummies/hourlyforecast.dat data/dummies/hourlyhistory.dat
git rm bin/grabber_openweather.pl bin/grabber_wetteronline_old.pl bin/grabber_wetteronline2.pl
```

Hinweis: `mapping_custom_mix_pollen.json` ist eine Runtime-Datei in `$lbpconfigdir`, nicht im Repo. Wird durch die Config-Umstellung in Task 17 obsolet.

- [ ] **Step 2: Referenzen pruefen**

Pruefe ob `fetch.pl`, `cronjob.pl` oder andere Dateien auf die geloeschten Grabber verweisen.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: remove legacy .dat format files and deprecated grabbers"
```

---

### Task 19: DECISIONS.md aktualisieren

**Files:**
- Modify: `DECISIONS.md`

- [ ] **Step 1: Dual-Write -> clean break dokumentieren**

Ersetze die Dual-Write-Beschreibung durch:
- JSON-only Output (kein .dat mehr)
- AQ/Pollen Integration in alle 3 JSONs
- `[POLLEN]` Config-Abschnitt
- `CRON_PATCH` fuer Patch-Grabber
- `refresh`-Feld im Envelope

- [ ] **Step 2: Commit**

```bash
git add DECISIONS.md
git commit -m "docs: update DECISIONS.md for JSON-only output and AQ/pollen integration"
```

---

### Task 20: postinstall.sh -- .dat Symlinks entfernen

**Files:**
- Modify: `postinstall.sh`

- [ ] **Step 1: Dummy .dat-Kopier-Logik entfernen**

Entferne die Kopier-Logik fuer .dat-Dummy-Dateien (lines ~40-51): `current.dat`, `dailyforecast.dat`, `hourlyforecast.dat`, `hourlyhistory.dat`. Behalte JSON-Symlinks (lines ~80-82).

- [ ] **Step 2: airquality_pollen.json Symlink entfernen**

Entferne den Symlink fuer `airquality_pollen.json` (line ~83).

- [ ] **Step 3: Dummy JSON-Dateien hinzufuegen**

Erstelle JSON-Dummy-Dateien in `data/dummies/` (current.json, dailyforecast.json, hourlyforecast.json) mit leerem aber validem Schema, damit frische Installationen funktionieren. Kopier-Logik in postinstall.sh hinzufuegen.

- [ ] **Step 4: Commit**

```bash
git add postinstall.sh
git commit -m "chore: remove .dat symlinks and dummy files from postinstall"
```
