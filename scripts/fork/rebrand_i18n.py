#!/usr/bin/env python3
"""
Derive lib/i18n/*.i18n.json (Popkino) from the upstream Plezy translations.

The files in lib/i18n/ are never edited by hand in the fork: they are produced
by this script from the upstream version, the rules in
lib/fork/i18n/rebrand_rules.json and the overlay lib/fork/i18n/<locale>.json.

  python3 scripts/fork/rebrand_i18n.py           # rewrite lib/i18n/*.i18n.json
  python3 scripts/fork/rebrand_i18n.py --check   # exit 1 if a file would change

Then run scripts/codegen.sh to regenerate lib/i18n/strings*.g.dart.

Order of operations per locale: per-language rules (longest first), general
rule, per-key rules, overlay merge, canonical normalization on the structure of
`en` (same as clean_translations.py). Rules only touch values, never keys, and
skip the top-level branches listed in "skipTopLevel" (fork.*).
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_LOCALE = "en"


def load_clean_translations(root: Path = ROOT):
    """Import scripts/checks/clean_translations.py by path (not on sys.path)."""
    path = root / "scripts" / "checks" / "clean_translations.py"
    spec = importlib.util.spec_from_file_location("_fork_clean_translations", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_rules(root: Path = ROOT) -> dict:
    return load_json(root / "lib" / "fork" / "i18n" / "rebrand_rules.json")


def apply_pairs(text: str, pairs) -> str:
    """Apply (from, to) pairs, longest `from` first (stable for equal length)."""
    for src, dst in sorted(pairs, key=lambda pair: -len(pair[0])):
        text = text.replace(src, dst)
    return text


def rebrand_node(node, rules: dict, locale: str, path: str = ""):
    """Return a copy of `node` with the rules applied to string values only."""
    if isinstance(node, dict):
        skip = set(rules.get("skipTopLevel", [])) if not path else set()
        out = {}
        for key, value in node.items():
            if key in skip:
                out[key] = value
            else:
                out[key] = rebrand_node(value, rules, locale, f"{path}.{key}" if path else key)
        return out
    if isinstance(node, list):
        return [rebrand_node(item, rules, locale, path) for item in node]
    if isinstance(node, str):
        text = apply_pairs(node, rules.get("languages", {}).get(locale, []))
        general = rules.get("general")
        if general:
            text = text.replace(general["from"], general["to"])
        return apply_pairs(text, rules.get("keys", {}).get(path, []))
    return node


def merge_overlay(base, overlay):
    """Deep-merge `overlay` into `base`; overlay values win, new keys are appended."""
    if not isinstance(base, dict) or not isinstance(overlay, dict):
        return overlay
    out = dict(base)
    for key, value in overlay.items():
        out[key] = merge_overlay(out[key], value) if key in out else value
    return out


def load_overlay(root: Path, locale: str) -> dict:
    path = root / "lib" / "fork" / "i18n" / f"{locale}.json"
    return load_json(path) if path.exists() else {}


def derive_outputs(root: Path = ROOT) -> dict[Path, str]:
    """Compute the expected content of every lib/i18n/<locale>.i18n.json."""
    clean = load_clean_translations(root)
    rules = load_rules(root)
    i18n_dir = root / "lib" / "i18n"

    en_path = i18n_dir / f"{SOURCE_LOCALE}.i18n.json"
    en = rebrand_node(load_json(en_path), rules, SOURCE_LOCALE)
    en = merge_overlay(en, load_overlay(root, SOURCE_LOCALE))

    outputs: dict[Path, str] = {en_path: clean.dump_json(en)}
    for path in sorted(p for p in i18n_dir.glob("*.i18n.json") if p != en_path):
        locale = path.name.split(".")[0]
        loc = rebrand_node(load_json(path), rules, locale)
        loc = merge_overlay(loc, load_overlay(root, locale))
        # Same call as clean_translations.clean_pass().
        stats = {"added": 0, "removed": 0, "type_fixed": 0, "unchanged": 0}
        normalized = clean.normalize(en, loc, "", stats, clean.locale_plural_categories(en, loc))
        outputs[path] = clean.dump_json(normalized)
    return outputs


def run(root: Path = ROOT, check_only: bool = False) -> bool:
    """Write (or only compare) the files. Returns True if any file changed."""
    changed_any = False
    for path, new_text in derive_outputs(root).items():
        old_text = path.read_text(encoding="utf-8")
        if new_text == old_text:
            continue
        changed_any = True
        rel = path.relative_to(root)
        if check_only:
            print(f"would rewrite {rel}")
        else:
            path.write_text(new_text, encoding="utf-8")
            print(f"rewrote {rel}")
    return changed_any


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="dry-run; exit 1 if a file would change")
    args = parser.parse_args()
    changed = run(ROOT, check_only=args.check)
    if args.check and changed:
        print("\n(--check) run `python3 scripts/fork/rebrand_i18n.py && scripts/codegen.sh`.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
