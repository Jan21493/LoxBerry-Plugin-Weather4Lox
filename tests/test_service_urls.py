import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
URL_KEYS = {
    "OPENWEATHER.URL",
    "WUNDERGROUND.URL",
    "FOSHK.URL",
    "WEATHERFLOW.URL",
    "VISUALCROSSING.URL",
    "WTTRIN.URL",
    "WETTERONLINE.URL-CURRENT",
    "WETTERONLINE.URL-DAILY",
    "WETTERONLINE.URL-HOURLY",
    "OPENMETEOAIRQUALITY.URL",
}


class ServiceUrlTest(unittest.TestCase):
    def test_grabbers_use_fixed_urls_without_changing_variable_names(self):
        expected = {
            "grabber_openweather.pl": ("url", "https://api.openweathermap.org/data"),
            "grabber_wttrin.pl": ("url", "https://wttr.in"),
            "grabber_foshk.pl": ("url", "observations/current/json/units=m"),
            "grabber_weatherflow.pl": ("url", "https://swd.weatherflow.com/swd/rest"),
            "grabber_visualcrossing.pl": (
                "url",
                "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline",
            ),
            "grabber_wu.pl": (
                "wuurl",
                "https://api.weather.com/v2/pws/observations/current",
            ),
            "grabber_wu_pws.pl": (
                "wuurl",
                "https://api.weather.com/v2/pws/observations/current",
            ),
        }
        for filename, (variable, url) in expected.items():
            with self.subTest(grabber=filename):
                source = (ROOT / "bin" / filename).read_text(encoding="utf-8")
                self.assertRegex(
                    source,
                    rf'my \${variable}\s*=\s*"{re.escape(url)}";',
                )
                self.assertNotRegex(source, r'\$pcfg->param\("[A-Z]+\.URL"\)')
                self.assertNotRegex(source, r'\$pcfg->param\("[A-Z]+\.URL-[A-Z]+"\)')

    def test_defaults_and_settings_page_do_not_recreate_url_config(self):
        config = (ROOT / "config/weather4lox.cfg").read_text(encoding="utf-8")
        self.assertNotRegex(config, r"(?m)^URL(?:-[A-Z]+)?=")
        index = (ROOT / "webfrontend/htmlauth/index.cgi").read_text(encoding="utf-8")
        self.assertNotRegex(index, r'\$cfg->param\("[A-Z]+\.URL')

    def test_saving_settings_deletes_all_legacy_url_keys(self):
        source = (ROOT / "webfrontend/htmlauth/ajax-save.cgi").read_text(encoding="utf-8")
        deleted = set(re.findall(r"\$cfg->delete\('([^']+)'\)", source))
        deleted.update(re.findall(r"^\s+([A-Z][A-Z0-9_.-]+)$", source, re.M))
        for key in URL_KEYS:
            with self.subTest(key=key):
                self.assertIn(key, deleted)
        self.assertNotRegex(source, r'\$cfg->param\("[A-Z]+\.URL')

    def test_wetteronline_endpoints_remain_in_their_grabber(self):
        grabber = (ROOT / "bin/grabber_wetteronline.pl").read_text(encoding="utf-8")
        self.assertIn('"https://www.wetteronline.de/wetter/"', grabber)
        self.assertIn('"https://api-web.wo-cloud.com/weather/nowcast/v10?"', grabber)
        self.assertIn('"https://api-app.wetteronline.de/app/weather/forecast?"', grabber)
        self.assertIn('"https://api-app.wetteronline.de/app/weather/hourcast?"', grabber)


if __name__ == "__main__":
    unittest.main()
