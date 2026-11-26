"""Tests for scripts/fork/check_identity.py (run by scripts/ci_guard_checks.sh)."""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check_identity.py"
ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location("check_identity", SCRIPT)
check_identity = importlib.util.module_from_spec(_spec)
sys.modules["check_identity"] = check_identity
_spec.loader.exec_module(check_identity)

MANIFEST = "android/app/src/main/AndroidManifest.xml"
PLIST = "ios/Runner/Info.plist"
BUILD = ".github/workflows/build.yml"


def messages(rel: str, text: str) -> list[str]:
    return [str(v) for v in check_identity.apply_rules(rel, text)]


class RuleTest(unittest.TestCase):
    def test_forbidden_label_reports_file_and_line(self):
        out = messages(MANIFEST, '<application\n    android:label="Plezy">\n')
        self.assertEqual(len(out), 1)
        self.assertTrue(out[0].startswith(f"{MANIFEST}:2: "), out[0])

    def test_allowed_label(self):
        self.assertEqual(messages(MANIFEST, '<application android:label="Popkino">'), [])

    def test_display_name_containing_plezy_across_lines(self):
        text = "<key>CFBundleDisplayName</key>\n\t<string>Plezy Top Shelf</string>\n"
        out = messages("tvos/TopShelfExtension/Info.plist", text)
        self.assertEqual(len(out), 1)
        self.assertIn(":1: ", out[0])
        self.assertEqual(messages(PLIST, "<key>CFBundleName</key>\n<string>Popkino</string>"), [])

    def test_kotlin_package_and_import_allowed_but_string_forbidden(self):
        rel = "android/app/src/main/kotlin/com/edde746/plezy/Foo.kt"
        ok = "package com.edde746.plezy\nimport com.edde746.plezy.shared.X\nclass Y : com.edde746.plezy.shared.Z\n"
        self.assertEqual(messages(rel, ok), [])
        self.assertEqual(len(messages(rel, 'val id = "com.edde746.plezy"\n')), 1)

    def test_bundle_identifier_run_tests_target_allowed(self):
        rel = "tvos/Runner.xcodeproj/project.pbxproj"
        self.assertEqual(messages(rel, "PRODUCT_BUNDLE_IDENTIFIER = com.edde746.plezy.RunnerTests;"), [])
        self.assertEqual(len(messages(rel, "PRODUCT_BUNDLE_IDENTIFIER = com.edde746.plezy;")), 1)

    def test_module_name_allowed_product_name_forbidden(self):
        rel = "macos/Runner/Configs/AppInfo.xcconfig"
        self.assertEqual(messages(rel, "PRODUCT_MODULE_NAME = Plezy\nPRODUCT_NAME = Popkino\n"), [])
        self.assertEqual(len(messages(rel, "PRODUCT_NAME = Plezy\n")), 1)

    def test_artifact_name_forbidden_but_internal_temp_name_allowed(self):
        self.assertEqual(len(messages(BUILD, "  path: plezy-windows-installer.exe\n")), 1)
        self.assertEqual(messages(".github/workflows/ci.yml", "x > $RUNNER_TEMP/plezy-podfile-lock.sha256\n"), [])

    def test_upstream_repo_condition_allowed_inline_and_by_block(self):
        text = (
            "jobs:\n"
            "  a:\n"
            "    steps:\n"
            "      - name: Upload\n"
            "        if: github.repository == 'edde746/plezy'\n"
            "        with:\n"
            "          path: plezy-windows.msixbundle\n"
            "      - name: Other\n"
            "        run: echo plezy-windows.msixbundle\n"
        )
        out = messages(BUILD, text)
        self.assertEqual(len(out), 1)
        self.assertIn(":9: ", out[0])

    def test_whole_job_guarded_by_condition_is_exempt(self):
        text = (
            "jobs:\n"
            "  winget:\n"
            "    if: github.repository == 'edde746/plezy'\n"
            "    steps:\n"
            "      - run: echo plezy-windows-installer.exe\n"
            "  other:\n"
            "    steps:\n"
            "      - run: echo edde746/plezy\n"
        )
        out = messages(".github/workflows/update-packages.yml", text)
        self.assertEqual(len(out), 1)
        self.assertIn(":8: ", out[0])

    def test_repository_reference_without_condition_forbidden(self):
        self.assertEqual(len(messages(BUILD, "      - run: gh release view --repo edde746/plezy\n")), 1)

    def test_old_update_key_and_guid_forbidden_anywhere(self):
        self.assertEqual(len(messages("windows/runner/Runner.rc", f'EdDSAPub EDDSA {{"{check_identity.OLD_UPDATE_KEY}"}}')), 1)
        self.assertEqual(len(messages("scripts/x.py", f"GUID = '{check_identity.OLD_INNO_GUID}'")), 1)

    def test_excluded_paths(self):
        for rel in ("windows/build-msix.ps1", "windows/msix/AppxManifest.xml", "ios/fastlane/Fastfile", "docs/a.md",
                    "scripts/release/x.sh", "lib/a.dart", "test/a_test.dart", "scripts/fork/check_identity.py"):
            self.assertTrue(check_identity.is_excluded(rel), rel)
        for rel in ("windows/build-installer.ps1", MANIFEST, BUILD):
            self.assertFalse(check_identity.is_excluded(rel), rel)


class TreeTest(unittest.TestCase):
    def write(self, root: Path, rel: str, text: str) -> None:
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def make_repo(self, root: Path, scheme: str = "popkino") -> None:
        feed = "https://example.org/appcast.xml"
        self.write(root, "lib/fork/fork_identity.dart", (
            f"static const String urlScheme = '{scheme}';\n"
            "static const String githubRepo = 'adrien24/popkino';\n"
            f"static const String updateFeedUrl = '{feed}';\n"
        ))
        self.write(root, MANIFEST, f'<data android:scheme="{scheme}"/><data android:scheme="https"/>')
        schemes = f"<key>CFBundleURLSchemes</key>\n<array>\n<string>{scheme}</string>\n</array>"
        for rel in ("ios/Runner/Info.plist", "macos/Runner/Info.plist", "tvos/Runner/Info.plist"):
            self.write(root, rel, schemes)
        self.write(root, "macos/Runner/Info.plist", f"{schemes}<key>SUFeedURL</key>\n<string>{feed}</string>")
        self.write(root, "android/app/src/main/kotlin/com/edde746/plezy/deeplink/DeepLinkPlugin.kt",
                   f'private const val SCHEME = "{scheme}"\n')
        self.write(root, "android/app/build.gradle.kts", f'applicationId = "{check_identity.APPLICATION_ID}"\n')

    def test_concordance_ok_then_scheme_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            self.assertEqual(check_identity.check_concordance(root), [])
            self.write(root, "android/app/src/main/kotlin/com/edde746/plezy/deeplink/DeepLinkPlugin.kt",
                       'private const val SCHEME = "other"\n')
            out = [str(v) for v in check_identity.check_concordance(root)]
            self.assertEqual(len(out), 1)
            self.assertIn("DeepLinkPlugin.kt:1:", out[0])

    def test_tree_reports_forbidden_and_skips_excluded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_repo(root)
            self.write(root, "docs/notes.md", "gh-html.edde746.dev")
            self.write(root, "windows/msix/AppxManifest.xml", "edde746/plezy")
            self.assertEqual(check_identity.check_tree(root), [])
            self.write(root, "linux/packaging/x.sh", "tar plezy-linux-x64.tar.gz\n")
            out = [str(v) for v in check_identity.check_tree(root)]
            self.assertEqual(out, ["linux/packaging/x.sh:1: nom d'artefact plezy-… interdit (popkino-…)"])


class RepositoryTest(unittest.TestCase):
    def test_repository_passes(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--root", str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
