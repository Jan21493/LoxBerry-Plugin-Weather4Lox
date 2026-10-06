# LoxBerry-Plugin-Weather4Lox

A LoxBerry Plugin: https://wiki.loxberry.de/plugins/weather4loxone/start

https://github.com/mschlenstedt/LoxBerry-Plugin-Weather4Lox/archive/refs/heads/master.zip

This is a fork for version 4 to fix bugs and keep this version separate from version 5.

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
