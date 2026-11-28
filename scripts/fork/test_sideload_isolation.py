#!/usr/bin/env python3
"""Static guard: the sideload APK installer must stay isolated in the sideload source sets.

Play Store builds (nosideload) must never carry the install permission or the
installer APIs. Run directly or through scripts/ci_guard_checks.sh.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / "android"
SIDELOAD_DIR = ANDROID / "app" / "src" / "sideload"

SKIPPED_DIRS = {"build", ".gradle", ".idea", ".cxx", ".kotlin"}
SOURCE_SUFFIXES = {".xml", ".kt", ".java", ".kts", ".gradle", ".properties", ".pro", ".txt"}
FORBIDDEN_OUTSIDE_SIDELOAD = (
    "ACTION_INSTALL_PACKAGE",
    "PackageInstaller",
    "MANAGE_UNKNOWN_APP_SOURCES",
    "canRequestPackageInstalls",
)


def _android_files():
    for path in ANDROID.rglob("*"):
        rel = path.relative_to(ANDROID).parts
        if any(part in SKIPPED_DIRS for part in rel):
            continue
        if path.is_file() and path.suffix in SOURCE_SUFFIXES:
            yield path


def _in_sideload_source_set(path):
    src = ANDROID / "app" / "src"
    try:
        top = path.relative_to(src).parts[0]
    except ValueError:
        return False
    return top.startswith("sideload")


class SideloadIsolationTest(unittest.TestCase):
    def test_install_permission_only_in_sideload_manifest(self):
        offenders = []
        for path in _android_files():
            if path.name != "AndroidManifest.xml":
                continue
            if SIDELOAD_DIR in path.parents:
                continue
            if "REQUEST_INSTALL_PACKAGES" in path.read_text(encoding="utf-8"):
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [], "REQUEST_INSTALL_PACKAGES outside android/app/src/sideload/")

    def test_installer_apis_only_in_sideload_source_sets(self):
        offenders = []
        for path in _android_files():
            if _in_sideload_source_set(path):
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for token in FORBIDDEN_OUTSIDE_SIDELOAD:
                if token in text:
                    offenders.append(f"{path.relative_to(ROOT)}: {token}")
        self.assertEqual(offenders, [], "installer APIs outside android/app/src/sideload*/")

    def test_gradle_fork_block_present(self):
        text = (ANDROID / "app" / "build.gradle.kts").read_text(encoding="utf-8")
        self.assertIn("FORK: bouton-mise-a-jour", text)

    def test_activity_registers_fork_plugins(self):
        path = ANDROID / "app" / "src" / "main" / "kotlin" / "com" / "edde746" / "plezy" / "PlezyActivity.kt"
        self.assertIn("ForkPlugins.register(flutterEngine)", path.read_text(encoding="utf-8"))

    def test_both_fork_plugins_declare_register(self):
        pattern = re.compile(r"fun\s+register\(engine:\s*FlutterEngine\)")
        for variant in ("sideload", "nosideload"):
            path = ANDROID / "app" / "src" / variant / "kotlin" / "com" / "edde746" / "plezy" / "fork" / "ForkPlugins.kt"
            self.assertTrue(path.is_file(), f"missing {path.relative_to(ROOT)}")
            self.assertRegex(path.read_text(encoding="utf-8"), pattern, str(path.relative_to(ROOT)))


if __name__ == "__main__":
    unittest.main()
