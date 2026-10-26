# LoxBerry-Plugin-Weather4Lox

A LoxBerry Plugin: https://wiki.loxberry.de/plugins/weather4loxone/start

https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/archive/refs/heads/master.zip

This is a fork for version 4 to fix bugs and keep this version separate from version 5.

## Plugin updates

Updates back up and restore `w4l-settings.json` from the public plugin web
directory so that saved pollen sensitivities survive replacement of that
directory. Existing user values take precedence over package defaults.
Backup or restore failures stop the upgrade with an error; a failed restore
retains the temporary backup for recovery.

Weather-service endpoint URLs are defined in their grabbers, not in
`weather4lox.cfg`. Saving settings removes legacy URL entries, including
WetterOnline URLs that are no longer used.

## Configuration import and export

At the bottom of **Server Settings**, **Import and export** → **Export
configuration** downloads saved settings from all tabs as `weather4lox-YYYY-MM-DD_HH-MM-SS.zip`. This includes
`weather4lox.cfg`, pollen sensitivities from `w4l-settings.json`, custom
new-style themes (`*.theme.html`), custom theme languages (`lang-*.json`) and
custom UI languages (`language_*.ini`). Files shipped with the plugin, unsaved
form changes, weather data and icons are not included. The archive contains
API keys and passwords in plain text; store it securely.

**Import configuration** opens the file selection directly. After confirming,
the selected ZIP (maximum 8 MiB) replaces the configuration and custom files
with the same names; other existing custom files are kept. Shipped themes and
language files are never overwritten.
The importer checks the ZIP structure, allowed filenames, decompressed size,
CRC, plugin identity, backup format, compatible plugin major version, SHA-256
checksums, INI structure, operational settings, pollen JSON and custom theme
and language files (UTF-8, theme HTML, JSON with `language`, INI structure)
before writing. Archives from earlier versions without custom files can still
be imported. Arbitrary ZIP files and plugin installation packages are not
configuration backups. Files are replaced atomically; failures restore the
previous files. The import also applies the weather retrieval cron link,
website redirect and cloud emulator settings. After a successful import the
settings page reloads automatically and shows the result at the bottom. Referenced icons must already exist on the target system;
the Miniserver selection refers to that system's configured Miniserver number.

The ZIP implementation requires `libarchive-zip-perl` (installed via `dpkg/apt`).
Run `prove tests/config_backup.t` with `Config::Simple`, `Archive::Zip`, `CGI`
and `HTML::Template` installed to check archive round trips, validation,
rollback and the CGI endpoint against an isolated LoxBerry test environment.

## Details to Grabbers

Grabbers identify their contribution with `role` in their existing provider
metadata in `current.json`, `dailyforecast.json`, and `hourlyforecast.json`.
See the [JSON schema's role and provider table](data/json-schema.md#grabber-roles)
for the complete assignment. Use each provider's own `generatedAt` to check when
it contributed to that file, rather than the file's top-level timestamp.
Run `prove -v tests/grabber_roles.t` to check all grabber metadata write paths
and the bundled example JSON files without requiring a LoxBerry installation.

The wttr.in station ID accepts city names or latitude/longitude pairs. In the
`[WTTRIN]` section of `weather4lox.cfg`, both `STATIONID="50.84", "7.01"` and
`STATIONID="50.84,7.01"` are supported. The settings page displays `50.84,7.01`,
and the grabber requests `https://wttr.in/50.84,7.01?lang=...&M&3&format=j1`.
Run `prove -v tests/wttrin_stationid_template.t` with `Config::Simple` and
`HTML::Template` installed to check configuration parsing, display, and URL construction.

`weatherdata.html` uses UTF-8 and HTML-escapes text values while retaining the
`name@value<br>` layout. Localized weather descriptions, wind directions,
calendar names, and location names are encoded once at output; MQTT, UDP, and
classic theme output also remain UTF-8. Run `prove -v tests/datatoloxone_output.t`
on a LoxBerry with the plugin installed to check these outputs using temporary
files and intercepted MQTT/UDP sends, without publishing test data.

The wttr.in grabber derives `isNight` for current conditions and every hourly
forecast (including interpolated hours) from that date's local sunrise/sunset
and the entry's local time. As in the OpenWeather and Visual Crossing grabbers,
night is `1` and daytime is `null`; sunrise and sunset themselves count as day.
Missing or ambiguous astronomy data leaves `isNight` as `null` with a warning.
Run `prove -v tests/wttrin_isnight.t` on a LoxBerry with the plugin installed
to check boundaries, date/timezone handling, and isolated grabber output.

Grabbers, `datatoloxone.pl`, `fetch.pl`, and `cronjob.pl` share one log file per
existing log group per day. At debug level (including `--verbose`), they use one
file per group per hour instead. `cloudemu.sh` always uses one daily `Emulator`
log file. Logging disabled in LoxBerry remains disabled.

Each file has a single `LOGSTART` header with its start date; individual runs
have `START OF` and `END OF` messages. When a new file starts, the previous
existing log for that group receives `LOGEND`. Existing log group names and
LoxBerry's log retention settings are unchanged.

On a LoxBerry with the plugin installed, run `prove -v tests/log_rotation.t` from
this repository to check rotation against the installed logging SDK. The tests
use temporary log files and a separate log database.

## Tablet weather themes

### Custom themes and languages

Place your own new-style `*.theme.html` files in
`/opt/loxberry/webfrontend/html/plugins/weather4lox/`. Give them unique filenames
and a `<meta name="title" content="My theme">` title for the theme selector.
Updates back up these files and restore only filenames not supplied by the new
release. Weather4Loxone's shipped themes always take precedence.
Classic themes are deprecated, will be removed soon, and refresh only at the
configured interval.

To add a theme language, copy and translate `lang-en.json` in that same directory
to `lang-XX.json`. Make its first JSON entry `"language": "Native language name"`
(for example, `"language": "Polski"` for `lang-pl.json`).
Keep all existing keys, arrays, and placeholders. The website settings discover
these files automatically and display their native language names. The selected
code is saved in `WEB.LANG`, independently of the LoxBerry UI and weather-service
languages. New-style themes load the file selected by `?lang=XX` without a fixed
language list; missing or unreadable files fall back to `lang-en.json`.
The weather code reference (`weathercodes.html`) uses the same discovery rules
via `languages.cgi`, displays native names in its language selector, and accepts
`?lang=XX` with the same English fallback. New language files become available
without regenerating a list or restarting the plugin.
The symbol test page (`weathericon.html`) shows a single symbol enlarged on a
background 1.5 times its size and accepts the same parameters plus
`?icon=NAME` (for example `haze_day` or `cloudy_shower_1_night_4q`).
Codes use two or three lowercase letters, optionally followed by region/script
segments separated by `-` or `_` (for example, `pt-BR`).

For the plugin's administration UI, add
`/opt/loxberry/templates/plugins/weather4lox/lang/language_XX.ini` using
`language_en.ini` as the translation template. LoxBerry's existing
[`lblanguage` / `readlanguage` implementation](https://github.com/mschlenstedt/Loxberry/blob/master/libs/perllib/LoxBerry/System.pm)
automatically selects this file when language `XX` is configured in
`myloxberry.cgi`; missing UI phrases fall back to English. No additional plugin
language switch is needed.

Updates also back up `lang-*.json` and `language_*.ini`, restoring only files not
already present in the new release. Each restored additional language file
produces an installer warning to check for new parameters or changed content.
Changes to a shipped theme or language filename are **not** preserved over the
new release's file; use a distinct filename/code for custom versions.

### Included themes

Alongside Deep Ocean, four tablet-first themes use the same weather data,
translations, icon sets, refresh intervals, and forecast interactions:

| File | Theme | Appearance |
| --- | --- | --- |
| `arctic.theme.html` | Arctic Light | Ice-white/petrol or cool slate; Nunito Sans, an unframed weather icon, and six measurements integrated into the main panel. Cloud cover follows the weather description; no separate cloud, dew point, or visibility card. |
| `desert.theme.html` | Desert Sand | Warm sand accents (`#d8b889`) with pale beige (`#eadbc4`) companions and warm brown dark surfaces; unframed weather icon and a separate wind card beside precipitation and pressure, including direction, speed, gusts, and the wind symbol. Enlarged hourly cards show precipitation probability and millimeters side by side. |
| `coastal.theme.html` | Coastal Sky | Desert Sand's layout in warm, vivid blues. The hero follows the live weather icon's aspect ratio, with compact right-aligned readings on a transparent light/dark panel. Precipitation always stays inside; wind moves inside at a hero height of 500 CSS pixels or more and otherwise spans the full width below. Pressure is in the extra statistics. |

Coastal's temperature panel shares the hero's aspect ratio. Its inset precipitation
card has the same width and right alignment; wind uses twice that width (capped
at the available space). The hero and hourly cards darken for
`isNight` independently of appearance mode; light-mode statistics and unselected
hourly cards use slightly darker blue surfaces.
Coastal's main readings use larger typography. Inset precipitation remains a
horizontal text/icon card with right-aligned text and the symbol on the right
at every breakpoint; wind likewise places its symbol to the right and its
text matches the weather description's 1.2rem size.
The Coastal background icon occupies 70% of the hero width, leaving 10% on the
left and 20% on the right. Hero height is reduced proportionally to 70% of the
original icon-ratio height; the temperature panel retains the icon's proportions.
On small displays, compact reading panels and a content-based minimum hero
height prevent clipping. Wind and precipitation use compact 72-pixel cards with matching heights,
whether wind is inside or below the hero. Wind typography and spacing are
compact enough to accommodate wrapped text.
Below 750 CSS pixels, wind stays inside the hero regardless of its height.
Reading panels and typography become more compact, with 60-pixel precipitation
and wind cards, while retaining the temperature panel's aspect ratio and the
matching precipitation width.
Inside the hero, wind text is right-aligned and matches the weather description
size (1.2rem, or 1rem on small displays); the card remains right-aligned.
The hero reserves the inset cards' measured height plus a 20-pixel gap, so
temperature, precipitation, and wind panels do not overlap on tablets.
| `graphite.theme.html` | Graphite Focus | Neutral, high-contrast cards without glass effects or animations; enlarged feels-like/wind readings, weather symbol, and hourly summaries. Wind text stays to the right of its symbol and wraps as needed. |

All support `?mode=auto&iconset=naturalistic&lang=de`, just like Deep Ocean.
All four precipitation readings show millimeters and probability together;
missing values are displayed as `--`, not silently interpreted as zero.
Desert Sand uses the `desert` theme key and `desert.theme.html` URL.
Arctic and Desert Sand use larger main weather symbols and show hourly temperatures
to one decimal place. Arctic orders its integrated measurements as sunrise,
sunset, precipitation, pressure, humidity, and UV index. Desert Sand uses 64-pixel
hourly symbols and a wind card without a redundant heading. Graphite groups
humidity with precipitation and pressure above the hourly forecast.
Graphite's and Desert Sand's extra statistics use three columns above 700 and below 900 CSS pixels,
two columns at 700 pixels or less, and four columns at 900 pixels or more.
Desert Sand places the windsock to the left of the wind text, vertically centered,
matching the precipitation and pressure cards.
In landscape orientation, Desert Sand stacks precipitation, pressure, and wind
beside the hero in a one-third-width column. Coastal Sky instead places today's
or tomorrow's hourly cards in that column, with vertical scrolling and the same
height as the hero. Wind always stays inside Coastal's hero in landscape,
with compact reading panels on displays up to 1000 CSS pixels wide.
Each card groups time and icon on the left, and temperature above precipitation
probability and millimeters (on one line) on the right. Portrait orientation
retains the horizontal hourly strip; changing orientation preserves selection.
Desert Sand uses lighter day and darker night backgrounds for the hero and
hourly cards in both appearance modes, following each entry's `isNight` value.
In portrait orientation wider than 700 CSS pixels, Desert Sand moves the wind
card into the hero below the weather readings, without a border. Readings and
wind use about three fifths of the hero width; the enlarged weather icon uses
the remaining two fifths at a square height. Precipitation and pressure stay
side by side below. Narrower portrait and all landscape layouts keep wind with
the other statistics.
In landscape orientation, Graphite Focus stacks its three side statistics to
the right of the hero. Arctic Light places its six integrated measurements in
a two-column, three-row grid to the right of the weather readings and icon,
separated by a vertical line. Deep Ocean splits the main area equally between
the hero and a three-by-three grid containing all nine statistics; the separate
extra-statistics row returns in portrait orientation.
Graphite Focus and Arctic Light use day/night backgrounds for the hero and
hourly cards in both orientations. Light mode retains its existing daytime
card color and darkens nighttime cards; dark mode retains its nighttime card
color and lightens daytime cards.
Graphite Focus splits its hero into about three fifths for readings and wind
and two fifths for an enlarged square weather icon. In portrait orientation at
600 CSS pixels or narrower, wind becomes the first full-width card below the hero. If the German humidity
label cannot fit on one line, it is shortened from "Luftfeuchtigkeit" to
"Luftfeuchte"; other languages keep their translated label. Selecting an hour changes only its accent
border, not its day/night background, including on hover.
In all five weather themes (including Deep Ocean), the X-day view hides the
additional cards below the forecast. Expanded days include dew point, visibility
(in kilometers, matching the grabber output), cloud cover, and pressure alongside
the existing values. Each parameter has a weather icon and a localized label
(including "Luftfeuchtigkeit" in German). The detail grid adapts its column count
to the available width. Unknown dew point, visibility, and cloud cover are shown
as `--` rather than borrowing current conditions.
Sunrise and sunset follow the active today/tomorrow tab, including background
data refreshes. If tomorrow's daily data is unavailable, its times remain `--:--`
instead of reverting to today's values.
Daily wind, sunrise, and sunset details reuse the symbols from the today/tomorrow
cards rather than a separate icon set.
Wind symbols use the same per-period rule everywhere: red strong-wind windsock
at wind speeds of at least 30 km/h or gusts of at least 40 km/h, otherwise the
normal windsock. Daily symbols use that day's wind and gusts, not the selected hour.
Temperature charts render 12-pixel axis labels at the actual container width,
reserving wider left/right margins. Temperature ticks use one decimal place
when the displayed temperature spread is below 5 degrees (integer ticks otherwise).
Phone charts label every sixth hour; wider charts label every third hour.
`mode=light` and `mode=dark` force an appearance; absent/auto mode follows the
browser's color preference. Portrait tablets stack the main weather card above
the statistics; wide tablets and desktops place them side by side. Phones use
two-column statistics and a swipeable hourly forecast. Controls have at least
44-pixel touch targets and support keyboard activation.

The plugin automatically discovers these files in its theme selection.
Deploy the generated HTML files to
`/opt/loxberry/webfrontend/html/plugins/weather4lox/`; no configuration change
or restart is required. For example, open
`http://loxberry/plugins/weather4lox/arctic.theme.html?mode=light&iconset=naturalistic&lang=de`.

The committed standalone HTML files are generated from `ocean.theme.html`,
the palettes/layout transformations in `bin/build_weather_themes.py`,
`templates/themes/tablet.css`, and the individual `arctic.css`, `desert.css`,
and `graphite.css` stylesheets plus `coastal.css`, `coastal.js`, `desert.js`, `graphite.js`, and `display.js` in the same directory.
Do not edit generated files directly.
After changing the source, run `python3 bin/build_weather_themes.py`.
Run `python3 bin/build_weather_themes.py --check` to check reproducibility and
`python3 -m unittest discover -s tests -p 'test_weather_themes.py'` for the
theme regression checks. Deep Ocean itself remains unchanged.

`datatoloxone.pl` decodes input files with JSON::XS (provided by
`libjson-xs-perl`), preserving JSON::PP boolean values. Other grabbers keep their
existing decoder. The HTML weather database is written through one buffered
handle to `weatherdata.html.tmp` and atomically published as `weatherdata.html`
after a successful close. A separate writer lock serializes overlapping runs,
so readers continue to see the previous complete file during generation.
On a LoxBerry with current weather JSON files, `prove tests/datatoloxone_output.t`
checks decoder compatibility, complete output publication, and write failure
handling using temporary output files and a mocked MQTT connection (no live
MQTT or UDP sends).
