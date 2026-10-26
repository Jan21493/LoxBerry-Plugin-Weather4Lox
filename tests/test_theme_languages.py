import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "webfrontend/html"


def run_javascript(driver):
    if shutil.which("node"):
        driver += "\nrunTests().then(function(n) { console.log(n); }).catch(function(e) { console.error(e); process.exitCode = 1; });"
        command = ["node"]
    elif shutil.which("osascript"):
        # JXA drains Promise jobs between evaluating the script and calling run.
        driver += """
var outcome;
runTests().then(function(n) { outcome = n; }, function(e) { outcome = String(e); });
function run() {
    if (typeof outcome !== 'number') throw new Error(outcome || 'Tests did not finish');
    return String(outcome);
}
"""
        command = ["osascript", "-l", "JavaScript"]
    else:
        raise unittest.SkipTest("JavaScript tests require Node.js or macOS JavaScript for Automation")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".js") as script:
        script.write(driver)
        script.flush()
        result = subprocess.run(command + [script.name], text=True,
                                capture_output=True, check=True)
    return int(result.stdout.strip())


class ThemeLanguagesTest(unittest.TestCase):
    def test_native_language_names_are_first(self):
        names = {
            "cs": "Čeština", "de": "Deutsch", "en": "English",
            "es": "Español", "nl": "Nederlands", "sk": "Slovenčina",
        }
        for code, name in names.items():
            with self.subTest(code=code):
                data = json.loads((HTML / f"lang-{code}.json").read_text())
                self.assertEqual(next(iter(data)), "language")
                self.assertEqual(data["language"], name)

    def test_language_selector_discovers_files_and_preserves_selection(self):
        index = (ROOT / "webfrontend/htmlauth/index.cgi").read_text()
        block = index.split("    # Theme LANG\n", 1)[1].split("\n# Menu: Logfiles", 1)[0]
        program = r"""
use strict;
use warnings;
use Encode qw(encode);
use Weather4Lox::Languages qw(discover_languages);
package ConfigStub;
sub param { return $ENV{SELECTED_LANG}; }
package TemplateStub;
sub param {}
package CGIStub;
sub popup_menu {
    my ($self, %args) = @_;
    print "$args{-default}\n";
    for my $code (@{$args{-values}}) {
        print "$code=$args{-labels}{$code}\n";
    }
    return '';
}
package main;
my $cfg = bless {}, 'ConfigStub';
my $template = bless {}, 'TemplateStub';
my $cgi = bless {}, 'CGIStub';
my (@values, %labels);
my $lbphtmldir = $ENV{LANG_DIR};
""" + block
        with tempfile.TemporaryDirectory(prefix="w4l-languages-") as temp:
            folder = Path(temp)
            for code, name in (("en", "English"), ("pl", "Polski"), ("cs", "Čeština"),
                               ("pt-BR", "Português")):
                (folder / f"lang-{code}.json").write_text(
                    json.dumps({"language": name}, ensure_ascii=False)
                )
            (folder / "lang-fr.json").write_text("{}")
            (folder / "lang-it.json").write_text("{broken")
            (folder / "lang-de.json").mkdir()
            for selected, expected in (("pl", "pl"), ("pt-BR", "pt-BR"), ("missing", "en")):
                with self.subTest(selected=selected):
                    result = subprocess.run(
                        ["perl", "-I", str(ROOT / "bin/lib"), "-e", program],
                        text=True, capture_output=True, check=True,
                        env={**os.environ, "LANG_DIR": temp, "SELECTED_LANG": selected},
                    )
                    self.assertEqual(result.stdout.splitlines(), [
                        expected, "cs=Čeština", "en=English", "pl=Polski", "pt-BR=Português",
                    ])
                    self.assertIn("Missing language name", result.stderr)
                    self.assertIn("Invalid theme language file", result.stderr)
        self.assertIn('$cfg->param("WEB.LANG", "$R::themelang");', index)

    def test_javascript_language_loading(self):
        cases = []
        for path in sorted(HTML.glob("*.theme.html")):
            content = path.read_text()
            self.assertNotIn("SUPPORTED_LANGS", content)
            functions = []
            for name in ("getUrlParam", "checkOk", "loadLanguage"):
                match = re.search(r"function " + name + r"\([^)]*\) \{.*?\n\}", content, re.S)
                self.assertIsNotNone(match, f"{path.name}: {name}")
                functions.append(match.group())
            current = re.search(r"var currentLang = .*?\n\}\)\(\);", content, re.S)
            self.assertIsNotNone(current, path.name)
            scripts = re.findall(r"<script(?:\s[^>]*)?>(.*?)</script>", content, re.S)
            cases.append({
                "name": path.name,
                "scripts": scripts,
                "source": "var JSON_BASE = './';\n" + "\n".join(functions)
                          + "\n" + current.group(),
            })
            self.assertIn("loadLanguage()", content[content.index("function loadAllData"):])
        driver = "var themeCases = " + json.dumps(cases) + ";\n"
        driver += (ROOT / "tests/theme_languages.js").read_text()
        self.assertEqual(run_javascript(driver), len(cases) * 9)


class WeatherCodesLanguagesTest(unittest.TestCase):
    def test_language_endpoint(self):
        with tempfile.TemporaryDirectory(prefix="w4l-language-endpoint-") as temp:
            folder = Path(temp)
            mock = folder / "LoxBerry"
            mock.mkdir()
            (mock / "System.pm").write_text("""
package LoxBerry::System;
use Exporter 'import';
our @EXPORT = qw($lbphtmldir $lbpbindir);
our $lbphtmldir = $ENV{LANG_DIR};
our $lbpbindir = $ENV{PLUGIN_BIN};
1;
""")
            (folder / "lang-pl.json").write_text('{"language": "Polski"}')
            (folder / "lang-cs.json").write_text('{"language": "Čeština"}')
            (folder / "lang-en.json").write_text('{"language": "English"}')
            (folder / "lang-xx.json").write_text('{"language": []}')
            (folder / "lang-fr.json").write_text('{invalid')
            command = ["perl", "-I", temp, str(HTML / "languages.cgi")]
            env = {**os.environ, "LANG_DIR": temp, "PLUGIN_BIN": str(ROOT / "bin")}
            result = subprocess.run(command, env=env, text=True, capture_output=True, check=True)
            headers, body = result.stdout.split("\n\n", 1)
            self.assertIn("Content-Type: application/json; charset=utf-8", headers)
            self.assertIn("Cache-Control: no-store", headers)
            self.assertEqual(json.loads(body), [
                {"code": "cs", "language": "Čeština"},
                {"code": "en", "language": "English"},
                {"code": "pl", "language": "Polski"},
            ])
            self.assertIn("Invalid theme language file", result.stderr)
            self.assertIn("Missing language name", result.stderr)
            env["LANG_DIR"] = str(folder / "missing")
            result = subprocess.run(command, env=env, text=True, capture_output=True, check=True)
            self.assertIn("Status: 500 Internal Server Error", result.stdout)
            self.assertEqual(json.loads(result.stdout.split("\n\n", 1)[1]),
                             {"error": "Cannot list theme languages"})
            self.assertIn("Cannot list theme languages", result.stderr)

    def test_weathercodes_language_loading(self):
        self.check_language_loading("weathercodes.html")

    def test_weathericon_language_loading(self):
        self.check_language_loading("weathericon.html")
        content = (HTML / "weathericon.html").read_text()
        self.assertIn("const urlIcon = normalizeIconName(urlParams.get('icon'));", content)

    def check_language_loading(self, page):
        content = (HTML / page).read_text()
        selector = content.split('<select id="lang-select">', 1)[1].split("</select>", 1)[0]
        self.assertNotIn("<option", selector)
        source = content.split("function languageCode(value)", 1)[1].split("\nfunction t(key)", 1)[0]
        source = "function languageCode(value)" + source
        driver = "var languageSource = " + json.dumps(source) + ";\n"
        driver += "var pageScript = " + json.dumps(re.search(r"<script>(.*?)</script>", content, re.S).group(1)) + ";\n"
        driver += (ROOT / "tests/weathercodes_languages.js").read_text()
        self.assertEqual(run_javascript(driver), 10)
        self.assertIn("await loadLanguageOptions();", content)
        self.assertIn("await loadLang(urlLang);", content)
        self.assertIn("const urlLang = languageCode(urlParams.get('lang'));", content)
        self.assertIn("init().catch(showLanguageError);", content)


class UpgradeAssetsTest(unittest.TestCase):
    def run_upgrade(self, script):
        return subprocess.run(
            ["bash", str(ROOT / script), self.tag, "weather4lox", "weather4lox",
             "4.0", str(self.home), str(self.home / "package")],
            cwd=ROOT, env=self.env, text=True, capture_output=True, check=True,
        )

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="w4l-upgrade-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.tag = self.home.name
        self.backup = Path("/tmp") / f"{self.tag}_upgrade"
        self.addCleanup(lambda: shutil.rmtree(self.backup) if self.backup.exists() else None)
        self.html = self.home / "webfrontend/html/plugins/weather4lox"
        self.lang = self.home / "templates/plugins/weather4lox/lang"
        self.config = self.home / "config/plugins/weather4lox"
        self.log = self.home / "log/plugins/weather4lox"
        self.cron = self.home / "system/cron/cron.01min"
        self.legacy = self.lang.parent / "themes/dark"
        for folder in (self.html, self.lang, self.config, self.log, self.cron, self.legacy):
            folder.mkdir(parents=True)
        self.env = {**os.environ, "LBHOMEDIR": str(self.home)}
        for key, relative in {
            "LBPCGI": "webfrontend/htmlauth/plugins",
            "LBPHTML": "webfrontend/html/plugins", "LBPTEMPL": "templates/plugins",
            "LBPDATA": "data/plugins", "LBPLOG": "log/plugins",
            "LBPCONFIG": "config/plugins", "LBPSBIN": "sbin/plugins",
            "LBPBIN": "bin/plugins",
        }.items():
            self.env[key] = str(self.home / relative)

    def test_custom_files_survive_and_release_files_win(self):
        assets = {
            self.html / "my custom.theme.html": "user theme",
            self.html / "ocean.theme.html": "old shipped theme",
            self.html / "lang-pl.json": '{"language": "Polski"}',
            self.html / "lang-en.json": '{"language": "Old English"}',
            self.lang / "language_pl.ini": "user UI translation",
            self.lang / "language_en.ini": "old UI translation",
            self.legacy / "custom.user.html": "legacy user theme",
            self.log / "current.json": '{"current": {}}',
        }
        for path, content in assets.items():
            path.write_text(content)
        self.run_upgrade("preupgrade.sh")
        for path in assets:
            path.unlink()
        shipped = {
            self.html / "ocean.theme.html": "new shipped theme",
            self.html / "lang-en.json": '{"language": "English"}',
            self.lang / "language_en.ini": "new UI translation",
        }
        for path, content in shipped.items():
            path.write_text(content)
        result = self.run_upgrade("postupgrade.sh")
        for path, content in assets.items():
            with self.subTest(path=path.name):
                self.assertEqual(path.read_text(), shipped.get(path, content))
        warnings = "\n".join(line for line in result.stdout.splitlines()
                             if "additional language file" in line)
        self.assertIn("lang-pl.json", warnings)
        self.assertIn("language_pl.ini", warnings)
        self.assertNotIn("lang-en.json", warnings)
        self.assertNotIn("language_en.ini", warnings)
        self.assertNotIn("WARNUNG", warnings)
        self.assertFalse(self.backup.exists())
        self.assertTrue((self.cron / "weather4lox").is_symlink())

    def test_pollen_settings_survive_replaced_web_directory(self):
        settings = self.html / "w4l-settings.json"
        content = json.dumps({"pollen": {
            "alder": 5, "birch": 6, "grass": 7,
            "mugwort": 4, "olive": 1, "ragweed": 2,
        }})
        for package_defaults in (None, '{"pollen": {}}'):
            with self.subTest(package_defaults=package_defaults):
                settings.write_text(content)
                settings.chmod(0o640)
                self.run_upgrade("preupgrade.sh")
                self.assertEqual(
                    (self.backup / "settings/w4l-settings.json").read_text(), content)
                shutil.rmtree(self.html)
                if package_defaults is not None:
                    self.html.mkdir(parents=True)
                    settings.write_text(package_defaults)
                self.run_upgrade("postupgrade.sh")
                self.assertEqual(settings.read_text(), content)
                self.assertEqual(settings.stat().st_mode & 0o777, 0o640)
                self.assertFalse(self.backup.exists())

    def test_pollen_backup_failure_aborts_upgrade(self):
        settings = self.html / "w4l-settings.json"
        settings.write_text('{"pollen": {"grass": 7}}')
        self.backup.mkdir()
        (self.backup / "settings").write_text("not a directory")
        with self.assertRaises(subprocess.CalledProcessError) as error:
            self.run_upgrade("preupgrade.sh")
        self.assertEqual(error.exception.returncode, 2)
        self.assertIn("<ERROR>", error.exception.stdout)
        self.assertTrue(settings.exists())

    def test_pollen_restore_failure_retains_backup(self):
        settings = self.html / "w4l-settings.json"
        content = '{"pollen": {"grass": 7}}'
        settings.write_text(content)
        self.run_upgrade("preupgrade.sh")
        shutil.rmtree(self.html)
        self.html.write_text("not a directory")
        with self.assertRaises(subprocess.CalledProcessError) as error:
            self.run_upgrade("postupgrade.sh")
        self.assertEqual(error.exception.returncode, 2)
        self.assertIn("Cannot restore w4l-settings.json", error.exception.stdout)
        self.assertEqual(
            (self.backup / "settings/w4l-settings.json").read_text(), content)

    def test_no_optional_assets_and_existing_symlinks(self):
        (self.html / "mine.theme.html").write_text("old theme")
        self.run_upgrade("preupgrade.sh")
        (self.html / "mine.theme.html").unlink()
        (self.html / "mine.theme.html").symlink_to("not-yet-present.theme.html")
        result = self.run_upgrade("postupgrade.sh")
        self.assertTrue((self.html / "mine.theme.html").is_symlink())
        self.assertNotIn("additional language file", result.stdout)
        self.assertFalse(self.backup.exists())
        self.assertFalse((self.html / "w4l-settings.json").exists())


if __name__ == "__main__":
    unittest.main()
