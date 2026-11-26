#!/usr/bin/env python3
"""Native identity guard of the Popkino fork (task T15 of nouvelle-identite).

Fails with `file:line: message` when a native/CI file brings back an identity
of the upstream project (Plezy): bundle ids, URL scheme, display names, release
artifact names, update key, installer GUID...

Scope: everything except `lib/**` and `test/**` (covered by `test/fork/`) and the
store/website tooling we do not use (see EXCLUDES).
Run: python3 scripts/fork/check_identity.py [--root DIR]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

APPLICATION_ID = "io.github.adrien24.popkino"
OLD_UPDATE_KEY = "q7t6eu1txRrqv1PeWDCRV95rFxnmD/D3GZWbUPMwUyU="
OLD_INNO_GUID = "4213385e-f7be-4f2b-95f9-54082a28bb8f"
UPSTREAM_REPO_CONDITION = "github.repository == 'edde746/plezy'"

# Upstream store tooling (unused by the fork), website, docs, and code covered
# by other guards. This script and its test quote the forbidden values.
EXCLUDES = [
    "windows/build-msix.ps1",
    "windows/msix/**",
    "scripts/release/**",
    "ios/fastlane/**",
    "website/**",
    "server/**",
    "docs/**",
    "test/**",
    "lib/**",
    "scripts/fork/**",
    "**/__pycache__/**",
    "**/*.pyc",
    "build/**",
    "**/build/**",
    ".dart_tool/**",
    "**/Pods/**",
    ".git/**",
    ".claude/**",
]

MAX_FILE_BYTES = 2_000_000


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    out = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
            continue
        if pattern.startswith("**", i):
            out.append(".*")
            i += 2
            continue
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("".join(out) + r"\Z")


@dataclass(frozen=True)
class Rule:
    globs: tuple[str, ...]
    pattern: str
    message: str
    flags: int = re.MULTILINE
    # A match is ignored when its line matches this expression.
    allow_line: str | None = None

    def regex(self) -> re.Pattern[str]:
        return re.compile(self.pattern, self.flags)


@dataclass(frozen=True)
class Violation:
    path: str
    line: int
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.message}"


WORKFLOWS = (".github/workflows/*.yml",)
PLISTS = ("**/Info.plist",)
ENTITLEMENTS = ("**/*.entitlements",)
# Unit-test fixtures (android/app/src/test) are not shipped, like test/** for Dart.
KOTLIN = ("android/app/src/main/**/*.kt",)
LINUX_PACKAGING = ("linux/packaging/**",)
ALL = ("**",)

RULES: list[Rule] = [
    # --- Application identifiers -------------------------------------------
    Rule(("android/app/src/main/AndroidManifest.xml",), r"com\.edde746\.plezy",
         "identifiant com.edde746.plezy interdit dans le manifeste"),
    # Only string literals: `package`/`import` lines and fully qualified code
    # references keep the internal Kotlin package (decision D3).
    Rule(KOTLIN, r'"[^"\n]*com\.edde746\.plezy[^"\n]*"',
         "identifiant com.edde746.plezy interdit dans une chaîne Kotlin"),
    Rule(("android/app/build.gradle.kts",), r'applicationId\s*=\s*"[^"]*com\.edde746\.plezy',
         "applicationId com.edde746.plezy interdit"),
    Rule(("**/*.pbxproj", "**/*.xcconfig"),
         r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*\"?com\.edde746\.plezy(?!\.RunnerTests\b)",
         "PRODUCT_BUNDLE_IDENTIFIER com.edde746.plezy interdit (sauf .RunnerTests)"),
    Rule(PLISTS + ENTITLEMENTS + ("linux/CMakeLists.txt",) + LINUX_PACKAGING, r"com\.edde746\.plezy",
         "identifiant com.edde746.plezy interdit"),
    Rule(ALL, r"group\.com\.edde746", "App Group group.com.edde746 interdit"),
    # --- URL scheme ---------------------------------------------------------
    Rule(PLISTS + ENTITLEMENTS, r"<string>plezy</string>", "schéma d'URL plezy interdit"),
    Rule(("android/**/*.xml",), r'android:scheme="plezy"', "schéma d'URL plezy interdit"),
    Rule(("android/**/DeepLinkPlugin.kt", "android/**/WatchNextProvider.kt", "tvos/**/TopShelfProvider.swift"),
         r'"plezy"', 'schéma d\'URL "plezy" interdit'),
    # --- Display names --------------------------------------------------------
    Rule(("android/**/*.xml",), r'android:label="[^"]*Plezy', "android:label contenant Plezy interdit"),
    Rule(PLISTS, r"<key>CFBundle(?:Display)?Name</key>\s*<string>[^<]*Plezy[^<]*</string>",
         "CFBundleDisplayName/CFBundleName contenant Plezy interdit", re.MULTILINE | re.DOTALL),
    Rule(("**/*.pbxproj", "**/*.xcconfig"), r"INFOPLIST_KEY_CFBundleDisplayName\s*=\s*\"?[^;\n]*Plezy",
         "INFOPLIST_KEY_CFBundleDisplayName contenant Plezy interdit"),
    # PRODUCT_MODULE_NAME = Plezy stays allowed (internal Swift module, T10b).
    Rule(("macos/Runner/Configs/AppInfo.xcconfig",), r"^PRODUCT_NAME\s*=\s*Plezy\b",
         "PRODUCT_NAME = Plezy interdit"),
    Rule(("windows/runner/Runner.rc", "windows/runner/main.cpp"), r'"Plezy"', 'nom "Plezy" interdit'),
    Rule(("**/*.desktop",), r"^Name(?:\[[^\]]+\])?=Plezy\b", "Name=Plezy interdit dans un .desktop"),
    # --- Release artifacts and repository --------------------------------------
    # Internal temp names (plezy-write-probe.tmp...) are not artifacts: only the
    # `plezy-<platform>` release names are targeted.
    Rule(WORKFLOWS + ("windows/build-installer.ps1",) + LINUX_PACKAGING,
         r"(?<![\w.-])plezy-(?:android|ios|macos|windows|linux)\b",
         "nom d'artefact plezy-… interdit (popkino-…)"),
    Rule(WORKFLOWS + ("windows/build-installer.ps1",) + LINUX_PACKAGING + PLISTS, r"edde746/plezy",
         "dépôt edde746/plezy interdit (sauf condition github.repository == 'edde746/plezy')",
         allow_line=re.escape(UPSTREAM_REPO_CONDITION)),
    Rule(ALL, r"gh-html\.edde746\.dev", "lien gh-html.edde746.dev interdit"),
    Rule(ALL, re.escape(OLD_UPDATE_KEY), "clé publique de mise à jour de Plezy interdite"),
    Rule(ALL, re.escape(OLD_INNO_GUID), "GUID d'installeur Inno de Plezy interdit"),
]


def is_excluded(rel: str) -> bool:
    return any(glob_to_regex(pattern).match(rel) for pattern in EXCLUDES)


def list_files(root: Path) -> list[str]:
    """Tracked and untracked-but-not-ignored files; falls back to a walk."""
    try:
        out = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            cwd=root, check=True, capture_output=True,
        ).stdout.decode("utf-8", "replace")
        names = [n for n in out.split("\0") if n]
    except (OSError, subprocess.CalledProcessError):
        names = [p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()]
    return sorted(n for n in names if (root / n).is_file())


def read_text(path: Path) -> str | None:
    try:
        if path.stat().st_size > MAX_FILE_BYTES:
            return None
        return path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def line_text(text: str, line: int) -> str:
    return text.splitlines()[line - 1] if text else ""


def exempt_condition_lines(rel: str, text: str) -> set[int]:
    """Lines (1-based) of workflow jobs/steps guarded by the upstream-only `if:`.

    Such a block never runs in the fork, so upstream names inside it are fine.
    """
    if not rel.startswith(".github/workflows/"):
        return set()
    lines = text.splitlines()

    def indent(s: str) -> int:
        return len(s) - len(s.lstrip(" "))

    exempt: set[int] = set()
    for i, raw in enumerate(lines):
        stripped = raw.strip()
        if not (stripped.startswith("if:") and UPSTREAM_REPO_CONDITION in stripped):
            continue
        n = indent(raw)
        start = i
        while start > 0 and (not lines[start].strip() or indent(lines[start]) > n - 2 or start == i):
            start -= 1
        base = indent(lines[start])
        end = i + 1
        while end < len(lines) and (not lines[end].strip() or indent(lines[end]) > base):
            end += 1
        exempt.update(range(start + 1, end + 1))
    return exempt


def apply_rules(rel: str, text: str, rules: list[Rule] = RULES) -> list[Violation]:
    found: list[Violation] = []
    exempt = exempt_condition_lines(rel, text)
    for rule in rules:
        if not any(glob_to_regex(g).match(rel) for g in rule.globs):
            continue
        for match in rule.regex().finditer(text):
            line = line_of(text, match.start())
            if line in exempt:
                continue
            if rule.allow_line and re.search(rule.allow_line, line_text(text, line)):
                continue
            found.append(Violation(rel, line, rule.message))
    return found


# --- Concordance with lib/fork/fork_identity.dart --------------------------------

def dart_const(source: str, name: str) -> str | None:
    match = re.search(rf"static\s+const\s+String\s+{name}\s*=\s*'([^']*)'", source)
    return match.group(1) if match else None


def check_concordance(root: Path) -> list[Violation]:
    found: list[Violation] = []
    identity_rel = "lib/fork/fork_identity.dart"
    identity = read_text(root / identity_rel)
    if identity is None:
        return [Violation(identity_rel, 1, "fichier illisible ou absent")]
    values = {name: dart_const(identity, name) for name in ("urlScheme", "githubRepo", "updateFeedUrl")}
    for name, value in values.items():
        if value is None:
            found.append(Violation(identity_rel, 1, f"constante {name} introuvable"))
    scheme, feed = values["urlScheme"], values["updateFeedUrl"]

    def source(rel: str) -> str | None:
        text = read_text(root / rel)
        if text is None:
            found.append(Violation(rel, 1, "fichier illisible ou absent"))
        return text

    if scheme:
        manifest_rel = "android/app/src/main/AndroidManifest.xml"
        manifest = source(manifest_rel)
        if manifest is not None:
            seen = False
            for m in re.finditer(r'android:scheme="([^"]*)"', manifest):
                if m.group(1) in ("http", "https"):
                    continue
                seen = True
                if m.group(1) != scheme:
                    found.append(Violation(manifest_rel, line_of(manifest, m.start()),
                                           f"schéma {m.group(1)!r} différent de urlScheme {scheme!r}"))
            if not seen:
                found.append(Violation(manifest_rel, 1, f"aucun schéma {scheme!r} déclaré"))

        for rel in ("ios/Runner/Info.plist", "macos/Runner/Info.plist", "tvos/Runner/Info.plist"):
            plist = source(rel)
            if plist is None:
                continue
            blocks = list(re.finditer(r"<key>CFBundleURLSchemes</key>\s*<array>(.*?)</array>", plist, re.S))
            if not blocks:
                found.append(Violation(rel, 1, f"CFBundleURLSchemes absent (schéma {scheme!r} attendu)"))
            for block in blocks:
                for s in re.finditer(r"<string>([^<]*)</string>", block.group(1)):
                    if s.group(1) != scheme:
                        found.append(Violation(rel, line_of(plist, block.start(1) + s.start()),
                                               f"schéma {s.group(1)!r} différent de urlScheme {scheme!r}"))

        plugin_rel = "android/app/src/main/kotlin/com/edde746/plezy/deeplink/DeepLinkPlugin.kt"
        plugin = source(plugin_rel)
        if plugin is not None:
            m = re.search(r'\bSCHEME\s*=\s*"([^"]*)"', plugin)
            if m is None:
                found.append(Violation(plugin_rel, 1, "constante SCHEME introuvable"))
            elif m.group(1) != scheme:
                found.append(Violation(plugin_rel, line_of(plugin, m.start()),
                                       f"SCHEME {m.group(1)!r} différent de urlScheme {scheme!r}"))

    if feed:
        plist_rel = "macos/Runner/Info.plist"
        plist = source(plist_rel)
        if plist is not None:
            m = re.search(r"<key>SUFeedURL</key>\s*<string>([^<]*)</string>", plist)
            if m is None:
                found.append(Violation(plist_rel, 1, "SUFeedURL introuvable"))
            elif m.group(1) != feed:
                found.append(Violation(plist_rel, line_of(plist, m.start()),
                                       f"SUFeedURL {m.group(1)!r} différent de updateFeedUrl"))

    gradle_rel = "android/app/build.gradle.kts"
    gradle = source(gradle_rel)
    if gradle is not None:
        m = re.search(r'\bapplicationId\s*=\s*"([^"]*)"', gradle)
        if m is None:
            found.append(Violation(gradle_rel, 1, "applicationId introuvable"))
        elif m.group(1) != APPLICATION_ID:
            found.append(Violation(gradle_rel, line_of(gradle, m.start()),
                                   f"applicationId {m.group(1)!r} différent de {APPLICATION_ID!r}"))
    return found


def check_tree(root: Path) -> list[Violation]:
    found: list[Violation] = []
    for rel in list_files(root):
        if is_excluded(rel):
            continue
        text = read_text(root / rel)
        if text is None:
            continue
        found.extend(apply_rules(rel, text))
    found.extend(check_concordance(root))
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    violations = check_tree(args.root.resolve())
    for v in violations:
        print(v, file=sys.stderr)
    if violations:
        print(f"check_identity: {len(violations)} violation(s)", file=sys.stderr)
        return 1
    print("check_identity: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
