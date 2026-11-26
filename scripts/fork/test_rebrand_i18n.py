"""Tests for scripts/fork/rebrand_i18n.py (run by scripts/ci_guard_checks.sh)."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "rebrand_i18n.py"
ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location("rebrand_i18n", SCRIPT)
rebrand_i18n = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rebrand_i18n)

RULES = {
    "general": {"from": "Plezy", "to": "Popkino"},
    "skipTopLevel": ["fork"],
    "languages": {
        "hu": [["Plezy-t", "Popkinót"], ["Plezy", "XX"], ["Plezyt", "Popkinót"]],
        "tr": [["Plezy'de", "Popkino'da"], ["Plezy'den", "Popkino'dan"]],
    },
    "keys": {"settings.servicesDescription": [["MyAnimeList", "Simkl"]]},
}


class RebrandNodeTest(unittest.TestCase):
    def test_keys_are_never_modified(self):
        node = {"profiles": {"addPlezyProfile": "Add Plezy profile"}, "startup": {"quitPlezy": "Quit Plezy"}}
        out = rebrand_i18n.rebrand_node(node, RULES, "en")
        self.assertEqual(
            out,
            {"profiles": {"addPlezyProfile": "Add Popkino profile"}, "startup": {"quitPlezy": "Quit Popkino"}},
        )

    def test_language_rules_longest_first(self):
        out = rebrand_i18n.rebrand_node({"a": "Plezy'den ve Plezy'de"}, RULES, "tr")
        self.assertEqual(out, {"a": "Popkino'dan ve Popkino'da"})

    def test_language_rule_order_in_file_does_not_matter(self):
        # "Plezyt" must win over the shorter "Plezy" even though it is listed last.
        out = rebrand_i18n.rebrand_node({"a": "Plezyt és Plezy-t"}, RULES, "hu")
        self.assertEqual(out, {"a": "Popkinót és Popkinót"})

    def test_language_rules_apply_to_their_locale_only(self):
        out = rebrand_i18n.rebrand_node({"a": "Plezy'de"}, RULES, "en")
        self.assertEqual(out, {"a": "Popkino'de"})

    def test_fork_branch_is_skipped(self):
        node = {"fork": {"about": {"basedOn": "Based on Plezy"}}, "x": {"fork": "Plezy"}}
        out = rebrand_i18n.rebrand_node(node, RULES, "en")
        self.assertEqual(out["fork"]["about"]["basedOn"], "Based on Plezy")
        self.assertEqual(out["x"]["fork"], "Popkino")

    def test_per_key_rule(self):
        node = {"settings": {"servicesDescription": "Trakt, MyAnimeList", "other": "MyAnimeList"}}
        out = rebrand_i18n.rebrand_node(node, RULES, "en")
        self.assertEqual(out["settings"]["servicesDescription"], "Trakt, Simkl")
        self.assertEqual(out["settings"]["other"], "MyAnimeList")

    def test_idempotent(self):
        node = {"settings": {"servicesDescription": "Plezy, MyAnimeList"}, "n": 1}
        once = rebrand_i18n.rebrand_node(node, RULES, "hu")
        self.assertEqual(rebrand_i18n.rebrand_node(once, RULES, "hu"), once)

    def test_key_order_is_preserved(self):
        node = {"b": "Plezy", "a": "Plezy"}
        self.assertEqual(list(rebrand_i18n.rebrand_node(node, RULES, "en")), ["b", "a"])


class MergeOverlayTest(unittest.TestCase):
    def test_overlay_wins_and_adds_keys(self):
        base = {"a": {"x": "1", "y": "2"}, "b": "3"}
        overlay = {"a": {"y": "9"}, "fork": {"k": "v"}}
        out = rebrand_i18n.merge_overlay(base, overlay)
        self.assertEqual(out, {"a": {"x": "1", "y": "9"}, "b": "3", "fork": {"k": "v"}})
        self.assertEqual(list(out), ["a", "b", "fork"])
        self.assertEqual(base["a"]["y"], "2")


class DerivedFilesTest(unittest.TestCase):
    def _make_root(self, directory: str) -> Path:
        root = Path(directory)
        (root / "scripts" / "checks").mkdir(parents=True)
        (root / "scripts" / "checks" / "clean_translations.py").write_text(
            (ROOT / "scripts" / "checks" / "clean_translations.py").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        (root / "lib" / "i18n").mkdir(parents=True)
        (root / "lib" / "fork" / "i18n").mkdir(parents=True)
        (root / "lib" / "fork" / "i18n" / "rebrand_rules.json").write_text(json.dumps(RULES), encoding="utf-8")
        en = {"app": {"title": "Plezy"}, "k": "Plezy"}
        tr = {"app": {"title": "Plezy"}, "k": "Plezy'de"}
        for name, data in (("en", en), ("tr", tr)):
            (root / "lib" / "i18n" / f"{name}.i18n.json").write_text(
                json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
        return root

    def test_run_rewrites_then_check_is_clean(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._make_root(directory)
            self.assertTrue(rebrand_i18n.run(root, check_only=True))
            self.assertIn("Plezy", (root / "lib/i18n/en.i18n.json").read_text(encoding="utf-8"))
            self.assertTrue(rebrand_i18n.run(root))
            tr = json.loads((root / "lib/i18n/tr.i18n.json").read_text(encoding="utf-8"))
            self.assertEqual(tr, {"app": {"title": "Popkino"}, "k": "Popkino'da"})
            self.assertFalse(rebrand_i18n.run(root, check_only=True))
            self.assertFalse(rebrand_i18n.run(root))

    def test_overlay_missing_keys_become_empty_in_other_locales(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._make_root(directory)
            (root / "lib/fork/i18n/en.json").write_text(json.dumps({"fork": {"a": "A"}}), encoding="utf-8")
            rebrand_i18n.run(root)
            en = json.loads((root / "lib/i18n/en.i18n.json").read_text(encoding="utf-8"))
            tr = json.loads((root / "lib/i18n/tr.i18n.json").read_text(encoding="utf-8"))
            self.assertEqual(en["fork"], {"a": "A"})
            self.assertEqual(tr["fork"], {"a": ""})

    def test_repository_is_up_to_date(self):
        # Same as `python3 scripts/fork/rebrand_i18n.py --check` on the repo.
        self.assertFalse(
            rebrand_i18n.run(ROOT, check_only=True),
            "lib/i18n is stale: run `python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh`",
        )


if __name__ == "__main__":
    unittest.main()
