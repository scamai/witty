#!/usr/bin/env python3
"""Tests for release_checks.py. Standard library only; runs on any OS.

Usage: python3 macos/scripts/test_release_checks.py
"""

from __future__ import annotations

import base64
import contextlib
import io
import plistlib
import re
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.dont_write_bytecode = True  # no __pycache__ next to the release scripts

import release_checks as rc  # noqa: E402

PROJECT = SCRIPT_DIR.parent / "Ghostty.xcodeproj" / "project.pbxproj"
FEED = "https://github.com/scamai/witty/releases/latest/download/appcast.xml"
KEY = base64.b64encode(bytes(range(32))).decode()
SIG = base64.b64encode(bytes(64)).decode()
TAG = "witty-v0.3.0"
DMG = "Witty-v0.3.0-macos-universal.dmg"


def problems(fn, *args, **kwargs) -> list[str]:
    try:
        fn(*args, **kwargs)
    except rc.CheckError as e:
        return e.problems
    return []


# ─── Update settings ───


class SettingsTests(unittest.TestCase):
    def test_witty_feed_and_key_pass(self):
        self.assertEqual(problems(rc.check_settings, FEED, KEY), [])

    def test_missing_settings_fail_and_name_both(self):
        found = problems(rc.check_settings, "", "")
        self.assertEqual(len(found), 2)
        self.assertIn("WITTY_UPDATE_FEED_URL is not set", found[0])
        self.assertIn("WITTY_UPDATE_PUBLIC_ED_KEY is not set", found[1])

    def test_ghostty_key_fails(self):
        found = problems(rc.check_settings, FEED, rc.GHOSTTY_PUBLIC_ED_KEY)
        self.assertEqual(len(found), 1)
        self.assertIn("Ghostty's EdDSA public key", found[0])

    def test_key_that_is_not_32_bytes_fails(self):
        for bad in ["not base64!", base64.b64encode(bytes(31)).decode(), base64.b64encode(bytes(33)).decode()]:
            with self.subTest(bad=bad):
                self.assertIn("not an EdDSA public key", " ".join(problems(rc.check_settings, FEED, bad)))

    def test_feed_outside_witty_releases_fails(self):
        for bad in [
            "https://release.files.ghostty.org/appcast.xml",
            "http://github.com/scamai/witty/releases/latest/download/appcast.xml",
            "https://github.com/scamai/witty-fork/releases/latest/download/appcast.xml",
            "https://github.com/ghostty-org/ghostty/releases/latest/download/appcast.xml",
        ]:
            with self.subTest(bad=bad):
                self.assertIn("must start with https://github.com/scamai/witty/",
                              " ".join(problems(rc.check_settings, bad, KEY)))

    def test_feed_url_is_the_latest_release_appcast(self):
        self.assertEqual(rc.FEED_URL, FEED)

    def test_feed_under_witty_that_no_later_release_replaces_fails(self):
        for bad in [
            # Pinned to one tag: that release's installs would never see the next.
            "https://github.com/scamai/witty/releases/download/witty-v0.2.1/appcast.xml",
            "https://github.com/scamai/witty/raw/main/appcast.xml",
        ]:
            with self.subTest(bad=bad):
                found = problems(rc.check_settings, bad, KEY)
                self.assertEqual(len(found), 1)
                self.assertIn(f"must be {FEED}", found[0])

    def test_feed_with_query_fails(self):
        self.assertIn("no query string", " ".join(problems(rc.check_settings, FEED + "?id=1", KEY)))

    def test_feed_not_named_appcast_xml_fails(self):
        bad = "https://github.com/scamai/witty/releases/latest/download/feed.xml"
        self.assertIn("must end in /appcast.xml", " ".join(problems(rc.check_settings, bad, KEY)))


# ─── Xcode project ───


class ProjectTests(unittest.TestCase):
    text = PROJECT.read_text()

    def witty_build_lines(self, text: str) -> list[str]:
        return [m.group(0) for c in rc.witty_configurations(text)
                for m in [rc.setting_re("CURRENT_PROJECT_VERSION").search(c.group("body"))]]

    def test_repository_project_is_consistent(self):
        version, build = rc.project_versions(self.text)
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        self.assertGreater(build, 0)

    def test_six_configurations_and_not_the_test_targets(self):
        configs = rc.witty_configurations(self.text)
        self.assertEqual(len(configs), 6)
        ids = {rc.setting_re("PRODUCT_BUNDLE_IDENTIFIER").search(c.group("body")).group(2) for c in configs}
        self.assertEqual(ids, {"ai.scam.witty", "ai.scam.witty.debug", "ai.scam.witty-dock-tile"})

    def test_one_configuration_with_another_build_number_fails(self):
        line = self.witty_build_lines(self.text)[-1]
        changed = self.text.replace(line, re.sub(r"\d+;$", "999;", line), 1)
        self.assertIn("CURRENT_PROJECT_VERSION differs", " ".join(problems(rc.project_versions, changed)))

    def test_one_configuration_with_another_marketing_version_fails(self):
        version, _ = rc.project_versions(self.text)
        changed = self.text.replace(f"MARKETING_VERSION = {version};", "MARKETING_VERSION = 9.9.9;", 1)
        self.assertIn("MARKETING_VERSION differs", " ".join(problems(rc.project_versions, changed)))

    def test_a_missing_configuration_fails(self):
        config = rc.witty_configurations(self.text)[0]
        changed = self.text[:config.start()] + self.text[config.end():]
        self.assertIn("expected 6", " ".join(problems(rc.project_versions, changed)))

    def test_build_must_beat_the_previous_release(self):
        _, build = rc.project_versions(self.text)
        self.assertIn("shipped build", " ".join(problems(rc.check_build_number, self.text, self.text, "witty-v0.0.1")))
        bumped, new_build = rc.bump(self.text, "0.3.0")
        self.assertEqual(rc.check_build_number(bumped, self.text, "witty-v0.0.1"), new_build)

    def test_previous_release_without_witty_configurations_is_skipped(self):
        # v0.1.x still had Ghostty's bundle identifiers.
        upstream = re.sub(r"ai\.scam\.witty[A-Za-z.-]*", "com.mitchellh.ghostty", self.text)
        _, build = rc.project_versions(self.text)
        self.assertEqual(rc.check_build_number(self.text, upstream), build)

    def test_build_must_beat_the_published_appcast(self):
        _, build = rc.project_versions(self.text)
        same = make_appcast(version=str(build))
        self.assertIn("already offers build", " ".join(problems(rc.check_build_number, self.text, previous_appcast=same)))
        older = make_appcast(version=str(build - 1))
        self.assertEqual(rc.check_build_number(self.text, previous_appcast=older), build)
        legacy_attribute = make_appcast(version=str(build), version_as_attribute=True)
        self.assertIn("already offers build",
                      " ".join(problems(rc.check_build_number, self.text, previous_appcast=legacy_attribute)))

    def test_bump_changes_only_the_six_configurations(self):
        version, build = rc.project_versions(self.text)
        bumped, new_build = rc.bump(self.text, "0.3.0")
        self.assertEqual(new_build, build + 1)
        self.assertEqual(rc.project_versions(bumped), ("0.3.0", build + 1))
        changed = [(a, b) for a, b in zip(self.text.splitlines(), bumped.splitlines()) if a != b]
        self.assertEqual(len(changed), 12)  # six build numbers, six marketing versions
        self.assertEqual(len(bumped.splitlines()), len(self.text.splitlines()))
        # The test targets keep upstream's placeholders.
        self.assertEqual(self.text.count("CURRENT_PROJECT_VERSION = 1;") - (6 if build == 1 else 0),
                         bumped.count("CURRENT_PROJECT_VERSION = 1;"))

    def test_bump_rejects_a_malformed_version(self):
        self.assertTrue(problems(rc.bump, self.text, "0.3"))

    def test_sparkle_version_is_pinned(self):
        self.assertRegex(rc.sparkle_version(self.text), r"^\d+\.\d+\.\d+$")


# ─── Built app ───


def make_app(root: Path, binary: bytes = b"\xcf\xfa\xed\xfe witty", **overrides) -> Path:
    app = root / "Witty.app"
    (app / "Contents" / "MacOS").mkdir(parents=True)
    (app / "Contents" / "Frameworks" / "Sparkle.framework").mkdir(parents=True)
    (app / "Contents" / "MacOS" / "ghostty").write_bytes(binary)
    (app / "Contents" / "Frameworks" / "Sparkle.framework" / "Sparkle").write_bytes(b"sparkle")
    (app / "Contents" / "Resources").mkdir()
    info = {
        "CFBundleVersion": "4",
        "SUFeedURL": FEED,
        "SUPublicEDKey": KEY,
        "SURequireSignedFeed": True,
        "SUVerifyUpdateBeforeExtraction": True,
        "SUScheduledCheckInterval": 86400,
    }
    for key, value in overrides.items():
        if value is None:
            info.pop(key, None)
        else:
            info[key] = value
    with (app / "Contents" / "Info.plist").open("wb") as f:
        plistlib.dump(info, f)
    return app


class AppTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_release_app_passes(self):
        self.assertEqual(problems(rc.check_app, make_app(self.root), FEED, KEY, 4), [])

    def test_each_wrong_key_fails(self):
        cases = {
            "SURequireSignedFeed": (None, "SURequireSignedFeed must be true"),
            "SUVerifyUpdateBeforeExtraction": (False, "SUVerifyUpdateBeforeExtraction must be true"),
            "SUEnableAutomaticChecks": (False, "still has SUEnableAutomaticChecks"),
            "SUEnableSystemProfiling": (True, "sets SUEnableSystemProfiling"),
            "SUSendProfileInfo": (True, "sets SUSendProfileInfo"),
            "SUAutomaticallyUpdate": (True, "sets SUAutomaticallyUpdate"),
            "SUScheduledCheckInterval": (3600, "at most daily"),
            "CFBundleVersion": ("3", "CFBundleVersion is '3'"),
            "SUFeedURL": ("https://release.files.ghostty.org/appcast.xml", "must start with"),
            "SUPublicEDKey": (rc.GHOSTTY_PUBLIC_ED_KEY, "Ghostty's EdDSA public key"),
        }
        for i, (key, (value, message)) in enumerate(cases.items()):
            with self.subTest(key=key):
                app = make_app(self.root / str(i), **{key: value})
                self.assertIn(message, " ".join(problems(rc.check_app, app, build=4)))

    def test_app_must_match_the_requested_settings(self):
        other_key = base64.b64encode(bytes(range(1, 33))).decode()
        found = " ".join(problems(rc.check_app, make_app(self.root / "key"), FEED, other_key, 4))
        self.assertIn("SUPublicEDKey is", found)
        self.assertIn("rebuild", found)
        other_feed = "https://github.com/scamai/witty/releases/download/witty-v0.3.0/appcast.xml"
        found = " ".join(problems(rc.check_app, make_app(self.root / "feed"), other_feed, KEY, 4))
        self.assertIn("SUFeedURL is", found)
        self.assertIn("rebuild", found)

    def test_app_with_a_feed_pinned_to_one_tag_fails(self):
        pinned = "https://github.com/scamai/witty/releases/download/witty-v0.3.0/appcast.xml"
        app = make_app(self.root, SUFeedURL=pinned)
        self.assertIn(f"the app's SUFeedURL must be {FEED}", " ".join(problems(rc.check_app, app, pinned, KEY, 4)))

    def test_ghostty_update_host_in_the_binary_fails(self):
        app = make_app(self.root, binary=b"...https://release.files.ghostty.org/appcast.xml...")
        self.assertIn("Contents/MacOS/ghostty mentions files.ghostty.org", " ".join(problems(rc.check_app, app, build=4)))
        self.assertTrue(problems(rc.check_no_ghostty_updater, app))

    def test_ghostty_update_host_in_a_framework_fails(self):
        app = make_app(self.root)
        (app / "Contents" / "Frameworks" / "Sparkle.framework" / "Sparkle").write_bytes(b"tip.files.ghostty.org")
        self.assertIn("Sparkle.framework/Sparkle", " ".join(problems(rc.check_no_ghostty_updater, app)))

    def test_ghostty_docs_link_in_resources_is_not_an_updater(self):
        app = make_app(self.root)
        (app / "Contents" / "Resources" / "notes.txt").write_bytes(b"see files.ghostty.org")
        self.assertEqual(problems(rc.check_no_ghostty_updater, app), [])

    def test_scan_refuses_a_path_that_is_not_an_app(self):
        self.assertIn("not an app bundle", " ".join(problems(rc.check_no_ghostty_updater, self.root / "missing.app")))


# ─── Appcast ───


def make_appcast(version: str = "4", short: str = "0.3.0", url: str | None = None, length: int = 1234,
                 signature: str | None = SIG, items: int = 1, feed_signed: bool = True,
                 critical: bool = False, deltas: bool = False, phased: bool = False,
                 version_as_attribute: bool = False) -> bytes:
    url = url or rc.download_prefix(TAG) + DMG
    sig_attr = f' sparkle:edSignature="{signature}"' if signature is not None else ""
    version_attr = f' sparkle:version="{version}"' if version_as_attribute else ""
    version_element = "" if version_as_attribute else f"<sparkle:version>{version}</sparkle:version>"
    extras = ""
    if critical:
        extras += "<sparkle:criticalUpdate></sparkle:criticalUpdate>"
    if deltas:
        extras += '<sparkle:deltas><enclosure url="x.delta" sparkle:deltaFrom="3" length="1"/></sparkle:deltas>'
    if phased:
        extras += "<sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>"
    item = (f"<item><title>{short}</title>{version_element}"
            f"<sparkle:shortVersionString>{short}</sparkle:shortVersionString>{extras}"
            f'<enclosure url="{url}" length="{length}" type="application/octet-stream"{sig_attr}{version_attr}/></item>')
    body = (f'<?xml version="1.0" encoding="utf-8"?>\n'
            f'<rss xmlns:sparkle="{rc.SPARKLE_NS}" version="2.0"><channel><title>Witty</title>'
            f"{item * items}</channel></rss>\n")
    if feed_signed:
        body += f"<!-- sparkle-signatures:\nedSignature: {SIG}\nlength: {len(body)}\n-->\n"
    return body.encode()


class AppcastTests(unittest.TestCase):
    def check(self, data: bytes, critical: bool | None = None) -> list[str]:
        return problems(rc.check_appcast, data, DMG, 1234, TAG, 4, critical)

    def test_generated_appcast_passes_and_returns_the_dmg_signature(self):
        self.assertEqual(rc.check_appcast(make_appcast(), DMG, 1234, TAG, 4), SIG)

    def test_each_problem_fails(self):
        cases = {
            "two releases": (make_appcast(items=2), "exactly one release"),
            "no releases": (make_appcast(items=0), "exactly one release"),
            "another build": (make_appcast(version="3"), "sparkle:version is '3'"),
            "another version": (make_appcast(short="0.2.9"), "the tag says 0.3.0"),
            "another tag's download": (make_appcast(url=rc.download_prefix("witty-v0.2.1") + DMG), "expected"),
            "Ghostty's download": (make_appcast(url="https://release.files.ghostty.org/1.2.0/Ghostty.dmg"), "expected"),
            "another length": (make_appcast(length=99), "the DMG has 1234 bytes"),
            "an unsigned DMG": (make_appcast(signature=None), "sparkle:edSignature"),
            "a short signature": (make_appcast(signature=base64.b64encode(bytes(32)).decode()), "sparkle:edSignature"),
            "an unsigned feed": (make_appcast(feed_signed=False), "no feed signature"),
            "deltas": (make_appcast(deltas=True), "delta updates"),
            "a phased rollout": (make_appcast(phased=True), "phased rollout"),
        }
        for name, (data, message) in cases.items():
            with self.subTest(name):
                self.assertIn(message, " ".join(self.check(data)))

    def test_critical_must_match_the_request(self):
        self.assertEqual(self.check(make_appcast(critical=True), critical=True), [])
        self.assertIn("does not mark the release critical", " ".join(self.check(make_appcast(), critical=True)))
        self.assertIn("marks the release critical", " ".join(self.check(make_appcast(critical=True), critical=False)))
        # Without a request either way (publish_release.sh), both are accepted.
        self.assertEqual(self.check(make_appcast(critical=True)), [])

    def test_malformed_tag_and_xml_fail(self):
        self.assertTrue(problems(rc.check_appcast, make_appcast(), DMG, 1234, "v0.3.0", 4))
        self.assertIn("not valid XML", " ".join(self.check(b"<rss>")))


# ─── Command line ───


def quiet_main(argv: list[str]) -> int:
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return rc.main(argv)


class CommandLineTests(unittest.TestCase):
    def test_exit_codes(self):
        self.assertEqual(quiet_main(["settings", FEED, KEY]), 0)
        self.assertEqual(quiet_main(["settings", FEED, rc.GHOSTTY_PUBLIC_ED_KEY]), 1)
        self.assertEqual(quiet_main(["project", str(PROJECT)]), 0)
        self.assertEqual(quiet_main(["download-prefix", "nope"]), 1)
        self.assertEqual(quiet_main(["feed", FEED]), 0)
        self.assertEqual(quiet_main(["feed", "https://release.files.ghostty.org/appcast.xml"]), 1)
        self.assertEqual(quiet_main(["feed", "https://github.com/scamai/witty/releases/download/witty-v0.2.1/appcast.xml"]), 1)
        self.assertEqual(quiet_main(["feed", ""]), 1)

    def test_bump_writes_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "project.pbxproj"
            copy.write_text(PROJECT.read_text())
            _, build = rc.project_versions(copy.read_text())
            self.assertEqual(quiet_main(["bump", str(copy), "0.3.0"]), 0)
            self.assertEqual(rc.project_versions(copy.read_text()), ("0.3.0", build + 1))


if __name__ == "__main__":
    unittest.main(verbosity=1)
