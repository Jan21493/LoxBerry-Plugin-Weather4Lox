import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("builder", ROOT / "bin/build_weather_themes.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class WeatherThemesTest(unittest.TestCase):
    def test_theme_names(self):
        original = (ROOT / "webfrontend/html/ocean.theme.html").read_text()
        self.assertIn('name="title" content="Deep Ocean"', original)
        self.assertIn("<title>Weather4Lox -- Deep Ocean</title>", original)
        self.assertIn("desert", BUILDER.THEMES)
        self.assertEqual(BUILDER.THEMES["coastal"]["layout"], "desert")
        self.assertTrue((ROOT / "templates/themes/desert.css").is_file())
        self.assertFalse((ROOT / "templates/themes/forest.css").exists())
        self.assertFalse((ROOT / "webfrontend/html/forest.theme.html").exists())

    def test_generated_files_are_current(self):
        for name, theme in BUILDER.THEMES.items():
            with self.subTest(theme=name):
                content = (ROOT / f"webfrontend/html/{name}.theme.html").read_text()
                self.assertEqual(content, BUILDER.render(theme))
                self.assertIn(f'name="title" content="{theme["title"]}"', content)

    def test_data_logic_and_parameters_are_preserved(self):
        original = (ROOT / "webfrontend/html/ocean.theme.html").read_text()
        original_scripts = re.findall(r"<script>(.*?)</script>", original, re.S)
        for name, theme in BUILDER.THEMES.items():
            with self.subTest(theme=name):
                rendered = BUILDER.render(theme)
                scripts = re.findall(r"<script>(.*?)</script>", rendered, re.S)
                self.assertEqual(len(scripts), len(original_scripts))
                for before, after in zip(original_scripts, scripts):
                    before = BUILDER.display_logic(before, theme["layout"])
                    if name == "coastal" and "// ===== BOOT =====" in before:
                        script = (ROOT / "templates/themes/coastal.js").read_text()
                        before = before.replace("// ===== BOOT =====", script + "\n// ===== BOOT =====", 1)
                    if name == "coastal":
                        if "  heroIcon.src = src;" in before:
                            before = before.replace("  heroIcon.src = src;", "  heroIcon.src = src;\n  document.querySelector('.hero').classList.toggle('is-night', !!e.isNight);", 1)
                        if "    card.setAttribute('data-idx', i);" in before:
                            before = before.replace("    card.setAttribute('data-idx', i);", "    card.classList.toggle('is-night', !!dataArray[i].isNight);\n    card.setAttribute('data-idx', i);", 1)
                    # Only appearance and keyboard-accessible controls may differ.
                    after = after.replace(theme["light"][0], "#f0f4f8")
                    after = after.replace(theme["dark"][0], "#0f172a")
                    after = after.replace(
                        "var card = document.createElement('button');\n    card.type = 'button';",
                        "var card = document.createElement('div');",
                    )
                    after = re.sub(
                        r"    row\.tabIndex = 0;.*?    };\n", "", after, count=1, flags=re.S,
                    )
                    if name == "arctic":
                        for stat_id in ("statDewpoint", "statVisibility"):
                            before = re.sub(
                                rf"^  document\.getElementById\('{stat_id}'\)\.[^\n]+\n",
                                "", before, flags=re.M,
                            ).replace(f"'{stat_id}',", "", 1)
                    self.assertEqual(before, after)
                self.assertEqual(re.findall(r'getUrlParam\((.*?)\)', original),
                                 re.findall(r'getUrlParam\((.*?)\)', rendered))
                expected_ids = re.findall(r'\bid="([^"]+)"', original)
                if name == "arctic":
                    expected_ids = [i for i in expected_ids if i not in ("statDewpoint", "statVisibility", "statClouds", "extraStatsRow")]
                self.assertCountEqual(expected_ids, re.findall(r'\bid="([^"]+)"', rendered))

    def test_individual_layouts(self):
        arctic = BUILDER.render(BUILDER.THEMES["arctic"])
        hero = BUILDER.div_with_opening(arctic, '<div class="glass hero accent-bg">')
        for stat_id in ("statPrecip", "statPressure", "statSunrise", "statSunset", "statHumidity", "statUVI"):
            self.assertIn(f'id="{stat_id}"', hero)
        self.assertNotIn("statDewpoint", arctic)
        self.assertNotIn("statVisibility", arctic)
        self.assertNotIn('id="statClouds"', arctic)
        self.assertNotIn('id="extraStatsRow"', arctic)
        self.assertIn("describeCloudCover(d.desc, d.clouds)", arctic)
        self.assertIn("family=Nunito+Sans", arctic)
        head_stats = BUILDER.div_with_opening(arctic, '<div class="head-stats">')
        positions = [head_stats.index(f'id="{stat_id}"') for stat_id in
                     ("statSunrise", "statSunset", "statPrecip", "statPressure", "statHumidity", "statUVI")]
        self.assertEqual(positions, sorted(positions))
        desert = BUILDER.render(BUILDER.THEMES["desert"])
        self.assertNotIn('id="heroWind"', BUILDER.div_with_opening(desert, '<div class="glass hero accent-bg">'))
        wind_card = BUILDER.div_with_opening(desert, '<div class="glass stat wind-card">')
        for wind_id in ("heroWind", "heroGust", "heroWindIcon"):
            self.assertIn(f'id="{wind_id}"', wind_card)
        self.assertNotIn('data-i18n="theme.wind"', wind_card)
        self.assertIn("""(d.rainAmount != null ? d.rainAmount : '--') + ' mm</span>""", desert)
        for rendered in (arctic, desert):
            self.assertIn("""'<div class="hcard-temp">' + (d.temp != null ? d.temp.toFixed(1) : '--')""", rendered)
        graphite = BUILDER.render(BUILDER.THEMES["graphite"])
        self.assertIn('id="statHumidity"', BUILDER.div_with_opening(graphite, '<div class="side-stats">'))
        self.assertNotIn('id="statHumidity"', BUILDER.div_with_opening(graphite, '<div class="extra-row" id="extraStatsRow">'))

    def test_template_drift_is_not_silent(self):
        with self.assertRaises(ValueError):
            BUILDER.replace_once("new template", "missing anchor", "replacement")

    def test_coastal_uses_desert_layout(self):
        coastal = BUILDER.render(BUILDER.THEMES["coastal"])
        self.assertIn('name="title" content="Coastal Sky"', coastal)
        side = BUILDER.div_with_opening(coastal, '<div class="side-stats">')
        for stat_id in ("statPrecip", "heroWind", "heroGust"):
            self.assertIn(f'id="{stat_id}"', side)
        self.assertNotIn('id="statPressure"', side)
        self.assertIn('id="statPressure"', BUILDER.div_with_opening(coastal, '<div class="extra-row" id="extraStatsRow">'))
        self.assertIn("object-fit: contain;", coastal)
        self.assertIn("text-align: right;", coastal)
        self.assertIn("background: var(--hero-overlay);", coastal)

    def test_landscape_layouts(self):
        desert_css = (ROOT / "templates/themes/desert.css").read_text()
        coastal_css = (ROOT / "templates/themes/coastal.css").read_text()
        for css in (desert_css, coastal_css):
            self.assertIn("@media (orientation: landscape)", css)
            self.assertIn("grid-template-columns: minmax(0, 2fr) minmax(0, 1fr)", css)
        self.assertIn("grid-template-rows: repeat(3, minmax(0, 1fr))", desert_css)
        self.assertIn("overflow-x: hidden; overflow-y: auto", coastal_css)
        self.assertIn('.coastal-hour-rail[data-active-tab="morgen"]', coastal_css)
        self.assertIn(".hcard-time { grid-column: 1; grid-row: 1;", coastal_css)
        self.assertIn(".hcard-temp { grid-column: 2; grid-row: 1;", coastal_css)
        self.assertIn(".hcard-rainProb { grid-column: 2; grid-row: 2;", coastal_css)
        coastal = BUILDER.render(BUILDER.THEMES["coastal"])
        self.assertIn("window.matchMedia('(orientation: landscape)')", coastal)
        self.assertIn("entry.anchor.after(entry.wrap)", coastal)
        self.assertIn("landscape.addEventListener('change', syncLayout)", coastal)
        self.assertIn("new MutationObserver(syncTab)", coastal)

    def test_daily_details_are_shared(self):
        original = (ROOT / "webfrontend/html/ocean.theme.html").read_text()
        for content in [original] + [BUILDER.render(theme) for theme in BUILDER.THEMES.values()]:
            self.assertIn("dewpoint: d.dewpoint", content)
            self.assertIn("visibility: d.visibility", content)
            self.assertIn("clouds: d.cloudCover", content)
            self.assertIn("d.visibility.toFixed(1)", content)
            self.assertIn("dailyDetail('humidity'", content)
            self.assertNotIn(">Feuchte</div>", content)
            self.assertIn(".page.daily-view .extra-row { display: none; }", content)
            self.assertIn("repeat(auto-fit, minmax(min(100%, 165px), 1fr))", content)

    def test_sun_times_follow_active_tab(self):
        original = (ROOT / "webfrontend/html/ocean.theme.html").read_text()
        for content in [original] + [BUILDER.render(theme) for theme in BUILDER.THEMES.values()]:
            self.assertEqual(content.count("document.getElementById('statSunrise').textContent ="), 1)
            self.assertEqual(content.count("document.getElementById('statSunset').textContent ="), 1)
            self.assertIn("selectedTab === 'morgen' ? liveData.daily[1] : liveData.current", content)
            self.assertIn("updateSunTimesForActiveTab();\n  if (selectedTab === 'tage') return;", content)

    def test_chart_labels_are_responsive(self):
        original = (ROOT / "webfrontend/html/ocean.theme.html").read_text()
        for content in [original] + [BUILDER.render(theme) for theme in BUILDER.THEMES.values()]:
            self.assertIn("var showDecimals = maxT - minT < 5;", content)
            self.assertIn("showDecimals ? tv.toFixed(1) : Math.round(tv)", content)
            self.assertIn("var W = svg.parentElement.clientWidth;", content)
            self.assertIn("var stepX = (W - padL - padR) / 24;", content)
            self.assertIn("Number(svg.dataset.stepX)", content)
            self.assertIn("new ResizeObserver", content)
            self.assertNotIn('font-size="9"', content)


if __name__ == "__main__":
    unittest.main()
