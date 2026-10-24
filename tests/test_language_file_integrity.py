import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANG_DIR = ROOT / "templates/lang"
JSON_DIR = ROOT / "webfrontend/html"


def parse_ini(path):
    data = path.read_bytes()
    text = data.decode("utf-8")
    if b"\r" in data:
        raise AssertionError(f"{path.name} must use LF line endings")
    if data.startswith(b"\xef\xbb\xbf"):
        raise AssertionError(f"{path.name} must not have a UTF-8 BOM")
    if not data.endswith(b"\n"):
        raise AssertionError(f"{path.name} must end with an LF newline")
    sections = {}
    current = None
    for number, line in enumerate(text.splitlines(), 1):
        section = re.fullmatch(r"\[([^]]+)\]", line)
        if section:
            current = section.group(1)
            if current in sections:
                raise AssertionError(f"{path.name}:{number}: duplicate section {current}")
            sections[current] = []
            continue
        if not line or line.startswith(("#", ";")):
            continue
        if current is None:
            raise AssertionError(f"{path.name}:{number}: parameter outside a section")
        parameter = re.fullmatch(r'([A-Z0-9_]+)="(.*)"', line)
        if not parameter:
            raise AssertionError(f"{path.name}:{number}: invalid parameter formatting")
        key = parameter.group(1)
        if key in sections[current]:
            raise AssertionError(f"{path.name}:{number}: duplicate {current}.{key}")
        sections[current].append(key)
    return sections


def parse_ini_values(path):
    sections = {}
    current = None
    for line in path.read_text(encoding="utf-8").splitlines():
        section = re.fullmatch(r"\[([^]]+)\]", line)
        if section:
            current = section.group(1)
            sections[current] = {}
            continue
        parameter = re.fullmatch(r'([A-Z0-9_]+)="(.*)"', line)
        if parameter:
            sections[current][parameter.group(1)] = parameter.group(2)
    return sections


def flatten_json(value, prefix=""):
    if isinstance(value, dict):
        output = {}
        for key, item in value.items():
            path = f"{prefix}.{key}" if prefix else key
            output.update(flatten_json(item, path))
        return output
    return {prefix: value}


class LanguageFileIntegrityTest(unittest.TestCase):
    def test_ini_files_match_english_parameter_order_and_completeness(self):
        reference = parse_ini(LANG_DIR / "language_en.ini")
        self.assertEqual(list(reference), ["SETTINGS", "GRABBER"])
        for path in sorted(LANG_DIR.glob("language_*.ini")):
            if path.name == "language_en.ini":
                continue
            with self.subTest(language=path.name):
                self.assertEqual(parse_ini(path), reference)

    def test_ini_html_markup_and_placeholders_match_english(self):
        reference = parse_ini_values(LANG_DIR / "language_en.ini")
        for path in sorted(LANG_DIR.glob("language_*.ini")):
            with self.subTest(language=path.name):
                actual = parse_ini_values(path)
                for section, values in reference.items():
                    for key, expected in values.items():
                        translated = actual[section][key]
                        self.assertEqual(
                            re.findall(r"<[^>]+>", translated),
                            re.findall(r"<[^>]+>", expected),
                            f"{section}.{key} HTML markup",
                        )
                        self.assertEqual(
                            re.findall(r"%[A-Za-z0-9_]+|\{[^}]+\}", translated),
                            re.findall(r"%[A-Za-z0-9_]+|\{[^}]+\}", expected),
                            f"{section}.{key} placeholders",
                        )

    def test_settings_reference_uses_the_shared_translation_key(self):
        settings = (ROOT / "templates/settings.html").read_text(encoding="utf-8")
        self.assertIn("SETTINGS.HINT_CONFIGUREWEATHERSERVICE", settings)
        self.assertNotIn("SETTINGS.HINT_CONFIGURE_WEATHERSERVICE", settings)

    def test_default_interval_has_short_and_full_labels_in_every_language(self):
        for path in sorted(LANG_DIR.glob("language_*.ini")):
            with self.subTest(language=path.name):
                values = parse_ini_values(path)["SETTINGS"]
                self.assertNotEqual(
                    values["LABEL_SAME_AS_DEFAULT"],
                    values["LABEL_SAME_AS_DEFAULT_SHORT"],
                )

    def test_json_languages_are_valid_utf8_and_match_english(self):
        reference_path = JSON_DIR / "lang-en.json"
        reference_bytes = reference_path.read_bytes()
        reference_bytes.decode("utf-8")
        reference_has_final_newline = reference_bytes.endswith(b"\n")
        reference = json.loads(reference_bytes)
        reference_flat = flatten_json(reference)
        self.assertEqual(next(iter(reference)), "language")
        for path in sorted(JSON_DIR.glob("lang-*.json")):
            with self.subTest(language=path.name):
                data_bytes = path.read_bytes()
                data_bytes.decode("utf-8")
                self.assertFalse(data_bytes.startswith(b"\xef\xbb\xbf"))
                self.assertNotIn(b"\r", data_bytes)
                self.assertEqual(data_bytes.endswith(b"\n"), reference_has_final_newline)
                data = json.loads(data_bytes)
                self.assertEqual(next(iter(data)), "language")
                flat = flatten_json(data)
                self.assertEqual(flat.keys(), reference_flat.keys())
                for key in reference_flat.keys():
                    expected, actual = reference_flat[key], flat[key]
                    self.assertIs(type(actual), type(expected), key)
                    if isinstance(expected, list):
                        self.assertEqual(len(actual), len(expected), key)
                    if isinstance(expected, str):
                        self.assertEqual(
                            set(re.findall(r"\{[A-Za-z_][A-Za-z0-9_]*\}", actual)),
                            set(re.findall(r"\{[A-Za-z_][A-Za-z0-9_]*\}", expected)),
                            key,
                        )
