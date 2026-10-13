#!/usr/bin/env python3
"""Build standalone tablet themes from Deep Ocean without forking its data logic."""

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEMES = {
    "arctic": {
        "layout": "arctic",
        "title": "Arctic Light",
        "dark": ("#15232f", "#1c303e", "#213847", "#294353", "#eef6fa", "#b8cbd6", "#a5bdca", "#67d4df"),
        "light": ("#f1f7fa", "#e4eef3", "#ffffff", "#f5fafc", "#142e3c", "#405d6c", "#526e7c", "#087581"),
        "radius": "18px",
        "accent": ("rgba(8,117,129,0.12)", "rgba(103,212,223,0.04)"),
        "shadow": "0 5px 22px -10px rgba(15,45,60,0.18)",
    },
    "desert": {
        "layout": "desert",
        "title": "Desert Sand",
        "dark": ("#29241f", "#463a2d", "rgba(65,54,43,0.96)", "#554534", "#fff8ed", "#ead8bd", "#d0bda2", "#d8b889"),
        "light": ("#faf5ec", "#eadbc4", "rgba(255,252,246,0.97)", "#f4ead9", "#382b1e", "#65513b", "#766046", "#876035"),
        "radius": "22px",
        "accent": ("rgba(216,184,137,0.28)", "rgba(234,219,196,0.12)"),
        "shadow": "0 6px 24px -10px rgba(18,45,29,0.18)",
    },
    "coastal": {
        "layout": "desert",
        "style": "coastal",
        "title": "Coastal Sky",
        "dark": ("#172d39", "#244451", "#284956", "#315866", "#f5fbfd", "#d3e5ed", "#b5d1de", "#8ad9ec"),
        "light": ("#edf6fa", "#d8edf3", "#f8fcfd", "#e7f4f8", "#163645", "#365969", "#466879", "#126f89"),
        "radius": "22px",
        "accent": ("rgba(74,175,206,0.24)", "rgba(124,207,224,0.12)"),
        "shadow": "0 6px 24px -10px rgba(30,85,105,0.20)",
    },
    "graphite": {
        "layout": "graphite",
        "title": "Graphite Focus",
        "dark": ("#151719", "#151719", "#22262a", "#2b3035", "#fafafa", "#d0d4d8", "#b6bfc7", "#85c9fa"),
        "light": ("#f1f2f3", "#f1f2f3", "#ffffff", "#f6f7f8", "#171b1f", "#414b55", "#56616c", "#176b9c"),
        "radius": "10px",
        "accent": ("transparent", "transparent"),
        "shadow": "none",
    },
}


def palette(theme):
    keys = (
        "bg-primary", "bg-secondary", "bg-card", "bg-card-hover",
        "text-primary", "text-secondary", "text-muted", "ui-accent",
    )
    rules = []
    for mode, selector in (("dark", ":root"), ("light", "html.light")):
        declarations = [f"  --{key}: {value};" for key, value in zip(keys, theme[mode])]
        declarations += [
            f"  --border: {'rgba(255,255,255,0.16)' if mode == 'dark' else 'rgba(20,40,50,0.18)'};",
            f"  --border-hover: {'rgba(255,255,255,0.28)' if mode == 'dark' else 'rgba(20,40,50,0.30)'};",
            f"  --shadow: {theme['shadow']};",
            f"  --shadow-hover: {theme['shadow']};",
            "  --glow: none;",
            "  --grain-opacity: 0;",
            f"  --accent-from: {theme['accent'][0]};",
            f"  --accent-to: {theme['accent'][1]};",
            f"  --tab-from: {theme['accent'][0]};",
            f"  --tab-to: {theme['accent'][1]};",
            "  --tab-border: var(--ui-accent);",
            f"  --card-radius: {theme['radius']};",
            f"  color-scheme: {mode};",
        ]
        if mode == "light":
            declarations += [
                "  --sky: #0875a4;",
                "  --amber: #926200;",
                "  --emerald: #16734f;",
                "  --violet: #7540ba;",
                "  --indigo: #4f51ba;",
                "  --orange: #b94e0a;",
                "  --rose: #c32748;",
            ]
        rules.append(selector + " {\n" + "\n".join(declarations) + "\n}")
    if theme["title"] == "Graphite Focus":
        rules.append("""
* { font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
.mono { font-family: inherit; }
.glass, .theme-btn { backdrop-filter: none; -webkit-backdrop-filter: none; }
.hero-icon-box { background: none; }
*, *::before, *::after { animation: none !important; transition: none !important; }
""")
    if theme["title"] == "Desert Sand":
        rules.append("""
.hero.accent-bg, .hero.accent-bg:hover { background: linear-gradient(135deg, #514231, #65513b); }
.hero.accent-bg.is-night, .hero.accent-bg.is-night:hover { background: linear-gradient(135deg, #302920, #403429); }
.hcard:not(.selected) { background: #4b3e30; }
.hcard.is-night:not(.selected) { background: #302920; }
.hcard.selected { background: linear-gradient(135deg, #705839, #5e4b34); }
.hcard.is-night.selected { background: linear-gradient(135deg, #493a29, #3c3024); }
html.light .hero.accent-bg, html.light .hero.accent-bg:hover { background: linear-gradient(135deg, #f2e2c9, #ead4b3); }
html.light .hero.accent-bg.is-night, html.light .hero.accent-bg.is-night:hover { background: linear-gradient(135deg, #c6ae8d, #d2bc9e); }
html.light .hcard:not(.selected) { background: #fff8ec; }
html.light .hcard.is-night:not(.selected) { background: #deceb7; }
html.light .hcard.selected { background: linear-gradient(135deg, #efd6af, #f5e4cb); }
html.light .hcard.is-night.selected { background: linear-gradient(135deg, #c7ac84, #d6bd99); }
""")
    return "\n".join(rules)


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"Deep Ocean template changed: expected one occurrence of {old!r}")
    return source.replace(old, new, 1)


def div_at(source, start):
    """Return a complete nested div without interpreting embedded SVG markup."""
    depth = 0
    for match in re.finditer(r"</?div\b[^>]*>", source[start:]):
        depth += -1 if match.group().startswith("</") else 1
        if depth == 0:
            return source[start:start + match.end()]
    raise ValueError("Unclosed div in Deep Ocean template")


def div_with_opening(source, opening):
    if source.count(opening) != 1:
        raise ValueError(f"Expected one layout anchor: {opening}")
    return div_at(source, source.index(opening))


def extra_card(source, stat_id):
    marker = f'id="{stat_id}"'
    if source.count(marker) != 1:
        raise ValueError(f"Expected one statistic: {stat_id}")
    start = source.rfind('<div class="glass extra">', 0, source.index(marker))
    if start < 0:
        raise ValueError(f"Missing extra card for {stat_id}")
    return div_at(source, start)


def individual_layout(source, layout):
    if layout == "arctic":
        source = replace_once(source, "family=Outfit:wght@", "family=Nunito+Sans:wght@")
        side = div_with_opening(source, '<div class="side-stats">')
        cards = side[len('<div class="side-stats">'):-len("</div>")]
        source = replace_once(source, side, "")
        sun_cards = ""
        for stat_id in ("statSunrise", "statSunset", "statHumidity", "statUVI"):
            card = extra_card(source, stat_id)
            source = replace_once(source, card, "")
            if stat_id in ("statSunrise", "statSunset"):
                sun_cards += "\n" + card
            else:
                cards += "\n" + card
        cards = sun_cards + cards
        for stat_id in ("statDewpoint", "statVisibility"):
            source = replace_once(source, extra_card(source, stat_id), "")
            # These values no longer have a view; remove their DOM writes, not the data.
            source, count = re.subn(
                rf"^  document\.getElementById\('{stat_id}'\)\.[^\n]+\n",
                "", source, flags=re.M,
            )
            if count != 2:
                raise ValueError(f"Expected current and hourly writes for {stat_id}")
            source = replace_once(source, f"'{stat_id}',", "")
        hero = div_with_opening(source, '<div class="glass hero accent-bg">')
        source = replace_once(source, hero, hero[:-len("</div>")] +
                              '\n<div class="head-stats">' + cards + "</div>\n</div>")
    elif layout == "desert":
        wind = div_with_opening(
            source, '<div class="hero-wind-group" style="display:flex;gap:8px;align-items:center;margin-top:4px">',
        )
        source = replace_once(source, wind, "")
        side = div_with_opening(source, '<div class="side-stats">')
        wind_card = (
            '<div class="glass stat wind-card">'
            '<div class="stat-content">'
            + wind + "</div></div>"
        )
        source = replace_once(source, side, side[:-len("</div>")] + wind_card + "</div>")
    elif layout == "graphite":
        humidity = extra_card(source, "statHumidity")
        source = replace_once(source, humidity, "")
        humidity = replace_once(humidity, 'class="glass extra"', 'class="glass stat"')
        side = div_with_opening(source, '<div class="side-stats">')
        source = replace_once(source, side, side[:-len("</div>")] + humidity + "</div>")
    return source


def display_logic(source, layout):
    if "// Global state" in source:
        helpers = (ROOT / "templates/themes/display.js").read_text()
        source = replace_once(source, "// Global state", helpers + "\n// Global state")
    for old, new in (
        ("(cPrecip.rain1hr != null ? cPrecip.rain1hr : 0) + ' mm'",
         "formatPrecipitation(cPrecip.rain1hr, cPrecip.probability)"),
        ("(d.rainAmount != null ? d.rainAmount : 0) + ' mm'",
         "formatPrecipitation(d.rainAmount, d.rainProb)"),
    ):
        if old in source:
            source = replace_once(source, old, new)
    if layout in ("arctic", "desert"):
        old = """'<div class="hcard-temp">' + Math.round(d.temp) + '&deg;</div>'"""
        if old in source:
            source = replace_once(source, old,
                                 """'<div class="hcard-temp">' + (d.temp != null ? d.temp.toFixed(1) : '--') + '&deg;</div>'""")
    if layout == "arctic":
        for old, new in (
            ("document.getElementById('heroDesc').textContent = cWx.description || '--';",
             "document.getElementById('heroDesc').textContent = describeCloudCover(cWx.description, c.cloudCover);"),
            ("document.getElementById('heroDesc').textContent = d.desc || '--';",
             "document.getElementById('heroDesc').textContent = describeCloudCover(d.desc, d.clouds);"),
        ):
            if old in source:
                source = replace_once(source, old, new)
        source = re.sub(r"^  document\.getElementById\('statClouds'\)\.[^\n]+\n", "", source, flags=re.M)
        source = source.replace("'statClouds',", "")
    elif layout == "desert":
        old = """(d.rainProb != null ? '<div class="hcard-rainProb">' + d.rainProb + '%</div>' : '')"""
        if old in source:
            source = replace_once(source, old,
                                 """'<div class="hcard-rainProb"><span>' + (d.rainProb != null ? d.rainProb : '--') +
      '%</span><span>' + (d.rainAmount != null ? d.rainAmount : '--') + ' mm</span></div>'""")
    return source


def render(theme):
    source = (ROOT / "webfrontend/html/ocean.theme.html").read_text()
    css = (ROOT / "templates/themes/tablet.css").read_text()
    css += "\n" + (ROOT / f"templates/themes/{theme['layout']}.css").read_text()
    if theme.get("style"):
        css += "\n" + (ROOT / f"templates/themes/{theme['style']}.css").read_text()
    source = replace_once(
        source, "<!DOCTYPE html>",
        "<!DOCTYPE html>\n<!-- Generated by bin/build_weather_themes.py; edit the builder/tablet.css, not this file. -->",
    )
    source = source.replace("Deep Ocean", theme["title"])
    source = replace_once(source, "</style>", "</style>\n  <style>\n" + palette(theme) + "\n" + css + "\n  </style>")
    source = replace_once(source, 'content="#0f172a"', f'content="{theme["dark"][0]}"')
    source = replace_once(source, ".content = '#f0f4f8';", f".content = '{theme['light'][0]}';")
    source = replace_once(source, ".content = '#0f172a';", f".content = '{theme['dark'][0]}';")
    source = replace_once(source, 'class=""hero-wind-message"', 'class="hero-wind-message"')
    source = individual_layout(source, theme["layout"])
    if theme.get("style") == "coastal":
        side = div_with_opening(source, '<div class="side-stats">')
        pressure_position = side.index('id="statPressure"')
        pressure_start = side.rfind('<div class="glass stat">', 0, pressure_position)
        pressure = div_at(side, pressure_start)
        source = replace_once(source, pressure, "")
        pressure = replace_once(pressure, 'class="glass stat"', 'class="glass extra"')
        extra = div_with_opening(source, '<div class="extra-row" id="extraStatsRow">')
        source = replace_once(source, extra, extra[:-len("</div>")] + pressure + "</div>")
    if theme["layout"] == "arctic":
        source = replace_once(source, extra_card(source, "statClouds"), "")
        extra = div_with_opening(source, '<div class="extra-row" id="extraStatsRow">')
        source = replace_once(source, extra, "")
    source = display_logic(source, theme["layout"])
    if theme.get("style") == "coastal":
        script = (ROOT / "templates/themes/coastal.js").read_text()
        source = replace_once(source, "// ===== BOOT =====", script + "\n// ===== BOOT =====")
    if theme["layout"] == "desert":
        source = night_logic(source)
    # Native buttons retain the existing click handlers and add keyboard activation.
    source = replace_once(source, "var card = document.createElement('div');", "var card = document.createElement('button');\n    card.type = 'button';")
    source = replace_once(source, "var row = document.createElement('div');", """var row = document.createElement('div');
    row.tabIndex = 0;
    row.setAttribute('role', 'button');
    row.onkeydown = function(event) {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        this.click();
      }
    };""")
    for chart in ("tempChartHeute", "tempChartMorgen"):
        source = replace_once(source, f'<span class="precip-toggle" id="precipToggle-{chart}"',
                              f'<button type="button" class="precip-toggle" id="precipToggle-{chart}"')
        source = replace_once(source, f"onclick=\"toggleChartPrecipMode('{chart}')\">Niederschlagswahrscheinlichkeit</span>",
                              f"onclick=\"toggleChartPrecipMode('{chart}')\">Niederschlagswahrscheinlichkeit</button>")
    return source


def night_logic(source):
    source = replace_once(
        source, "  heroIcon.src = src;",
        "  heroIcon.src = src;\n  document.querySelector('.hero').classList.toggle('is-night', !!e.isNight);",
    )
    return replace_once(
        source, "    card.setAttribute('data-idx', i);",
        "    card.classList.toggle('is-night', !!dataArray[i].isNight);\n    card.setAttribute('data-idx', i);",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if generated themes are out of date.")
    args = parser.parse_args()
    stale = []
    for key, theme in THEMES.items():
        target = ROOT / f"webfrontend/html/{key}.theme.html"
        content = render(theme)
        if args.check:
            if not target.exists() or target.read_text() != content:
                stale.append(str(target.relative_to(ROOT)))
        else:
            target.write_text(content)
            print(target.relative_to(ROOT))
    if stale:
        parser.exit(1, "Out-of-date themes: " + ", ".join(stale) + "\nRun python3 bin/build_weather_themes.py\n")


if __name__ == "__main__":
    main()
