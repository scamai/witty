#!/usr/bin/env python3
"""Checks that keep a Witty release from shipping a broken or borrowed updater.

The release scripts (release.sh, package_release.sh, publish_release.sh) call this
file; each subcommand exits non-zero with an "error:" line per problem. It needs
only the Python standard library, so it runs, and its tests run, on any OS:

    python3 macos/scripts/test_release_checks.py

Subcommands:
    settings FEED KEY        the WITTY_UPDATE_FEED_URL / _PUBLIC_ED_KEY of a tag build
    feed FEED                only the feed URL, which must be FEED_URL
    project PBXPROJ          prints the build number the six app and Dock tile
                             configurations share; with --previous-project and
                             --previous-appcast, also requires it to be higher
    bump PBXPROJ X.Y.Z       sets MARKETING_VERSION and raises the build number by one
    sparkle-version PBXPROJ  prints the Sparkle version the Xcode project pins
    app APP                  the built Witty.app's updater keys, build number, and no
                             trace of Ghostty's update host
    scan APP                 only the Ghostty update host check
    appcast FILE             a generated appcast against the DMG it describes; prints
                             the DMG's EdDSA signature
    download-prefix TAG      prints the URL prefix of the tag's release assets
"""

from __future__ import annotations

import argparse
import base64
import binascii
import os
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# ─── Constants ───

REPO_URL = "https://github.com/scamai/witty/"
FEED_FILE = "appcast.xml"
# The one feed a release may carry. An app's SUFeedURL never changes after it
# ships, and GitHub serves the newest release's appcast here, so each release
# replaces the previous one's; a feed pinned to one tag or branch would leave
# every install of that release on a feed no later release updates.
FEED_URL = f"{REPO_URL}releases/latest/download/{FEED_FILE}"
# Ghostty's EdDSA public key. Witty's v0.1.x builds carried it with Ghostty's
# feeds; a Witty release must never trust it again.
GHOSTTY_PUBLIC_ED_KEY = "wsNcGf5hirwtdXMVnYoxRIX/SqZQLMOsYlD3q3imeok="
# The host of Ghostty's tip and release appcasts.
GHOSTTY_UPDATE_HOST = b"files.ghostty.org"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
# The app (ai.scam.witty, ai.scam.witty.debug) and the Dock tile plugin
# (ai.scam.witty-dock-tile), each in ReleaseLocal, Debug and Release.
WITTY_BUNDLE_ID_RE = re.compile(r"ai\.scam\.witty([.-][A-Za-z0-9.-]+)?")
WITTY_CONFIGURATIONS = 6
# The README promises at most one automatic check a day.
MIN_CHECK_INTERVAL = 86400
TAG_RE = re.compile(r"witty-v(\d+\.\d+\.\d+)")
VERSION_RE = re.compile(r"\d+\.\d+\.\d+")


class CheckError(Exception):
    """One or more problems, one per line."""

    def __init__(self, problems: list[str] | str):
        self.problems = [problems] if isinstance(problems, str) else problems
        super().__init__("\n".join(self.problems))


def tag_version(tag: str) -> str:
    match = TAG_RE.fullmatch(tag)
    if not match:
        raise CheckError(f"release tag {tag!r} is not of the form witty-vX.Y.Z")
    return match.group(1)


def download_prefix(tag: str) -> str:
    tag_version(tag)
    return f"{REPO_URL}releases/download/{tag}/"


# ─── Update settings ───


def feed_problems(feed: str, name: str = "WITTY_UPDATE_FEED_URL") -> list[str]:
    if not feed:
        return [f"{name} is not set; a release needs Witty's update feed"]
    problems = []
    if not feed.startswith(REPO_URL):
        problems.append(f"{name} must start with {REPO_URL}, got {feed!r}")
    if any(c in feed for c in "?#") or any(c.isspace() for c in feed):
        problems.append(f"{name} must have no query string, fragment or spaces, got {feed!r}")
    if not feed.endswith("/" + FEED_FILE):
        problems.append(f"{name} must end in /{FEED_FILE}, the asset publish_release.sh uploads, got {feed!r}")
    if feed != FEED_URL:
        problems.append(f"{name} must be {FEED_URL}, the feed every later release replaces, got {feed!r}")
    return problems


def key_problems(key: str, name: str = "WITTY_UPDATE_PUBLIC_ED_KEY") -> list[str]:
    if not key:
        return [f"{name} is not set; a release needs the public half of Witty's EdDSA key"]
    if key == GHOSTTY_PUBLIC_ED_KEY:
        return [f"{name} is Ghostty's EdDSA public key; use Witty's own (generate_keys --account witty -p prints it)"]
    try:
        raw = base64.b64decode(key, validate=True)
    except (binascii.Error, ValueError):
        raw = b""
    if len(raw) != 32:
        return [f"{name} is not an EdDSA public key (the base64 of 32 bytes), got {key!r}"]
    return []


def check_settings(feed: str, key: str) -> None:
    problems = feed_problems(feed) + key_problems(key)
    if problems:
        raise CheckError(problems)


# ─── Xcode project ───

CONFIG_RE = re.compile(
    r"^\t\t[0-9A-F]{24} /\* (?P<name>[^*]+) \*/ = \{\n"
    r"\t\t\tisa = XCBuildConfiguration;\n"
    r"(?P<body>.*?)"
    r"^\t\t\};\n",
    re.M | re.S,
)


def setting_re(key: str) -> re.Pattern[str]:
    return re.compile(rf'^(\t\t\t\t{key} = )"?([^";\n]*)"?;$', re.M)


def witty_configurations(text: str) -> list[re.Match[str]]:
    """The build configurations of the app and the Dock tile plugin: those whose
    bundle identifier is Witty's. The test targets keep upstream's."""
    found = []
    for match in CONFIG_RE.finditer(text):
        bundle = setting_re("PRODUCT_BUNDLE_IDENTIFIER").search(match.group("body"))
        if bundle and WITTY_BUNDLE_ID_RE.fullmatch(bundle.group(2)):
            found.append(match)
    return found


def project_versions(text: str, *, source: str = "project.pbxproj") -> tuple[str, int] | None:
    """(MARKETING_VERSION, CURRENT_PROJECT_VERSION) shared by Witty's six build
    configurations, or None if the project has none (releases before v0.2.0)."""
    configs = witty_configurations(text)
    if not configs:
        return None
    problems = []
    if len(configs) != WITTY_CONFIGURATIONS:
        problems.append(f"{source}: expected {WITTY_CONFIGURATIONS} app and Dock tile build configurations, found {len(configs)}")
    marketing, builds = set(), set()
    for config in configs:
        body = config.group("body")
        mv = setting_re("MARKETING_VERSION").search(body)
        cv = setting_re("CURRENT_PROJECT_VERSION").search(body)
        if not mv or not cv:
            problems.append(f"{source}: build configuration {config.group('name')} lacks MARKETING_VERSION or CURRENT_PROJECT_VERSION")
            continue
        marketing.add(mv.group(2))
        builds.add(cv.group(2))
    if len(marketing) > 1:
        problems.append(f"{source}: MARKETING_VERSION differs between configurations: {sorted(marketing)}")
    if len(builds) > 1:
        problems.append(f"{source}: CURRENT_PROJECT_VERSION differs between configurations: {sorted(builds)}; set all six to the same number")
    if problems:
        raise CheckError(problems)
    (build,) = builds
    if not build.isdigit():
        raise CheckError(f"{source}: CURRENT_PROJECT_VERSION must be a whole number, got {build!r}")
    (version,) = marketing
    return version, int(build)


def appcast_items(data: bytes, *, source: str) -> list[ET.Element]:
    try:
        root = ET.fromstring(data)
    except ET.ParseError as e:
        raise CheckError(f"{source} is not valid XML: {e}") from None
    channel = root.find("channel")
    return [] if channel is None else channel.findall("item")


def item_version(item: ET.Element) -> str | None:
    """An item's sparkle:version: the element Sparkle 2 writes, or the older
    enclosure attribute."""
    element = item.find(f"{{{SPARKLE_NS}}}version")
    if element is not None and element.text:
        return element.text.strip()
    enclosure = item.find("enclosure")
    return None if enclosure is None else enclosure.get(f"{{{SPARKLE_NS}}}version")


def check_build_number(
    text: str,
    previous_project: str | None = None,
    previous_name: str = "the previous release",
    previous_appcast: bytes | None = None,
) -> int:
    current = project_versions(text)
    if current is None:
        raise CheckError("project.pbxproj has no build configuration with Witty's bundle identifier")
    _, build = current
    if previous_project is not None:
        # Only the highest number matters for what was shipped, so the previous
        # release is not held to this release's consistency rules.
        previous = [int(m.group(2)) for c in witty_configurations(previous_project)
                    for m in [setting_re("CURRENT_PROJECT_VERSION").search(c.group("body"))]
                    if m and m.group(2).isdigit()]
        if previous and build <= max(previous):
            raise CheckError(
                f"CURRENT_PROJECT_VERSION is {build}, but {previous_name} shipped build {max(previous)}; "
                f"Sparkle installs only a higher build, so raise it (release_checks.py bump)")
    if previous_appcast is not None:
        published = []
        for item in appcast_items(previous_appcast, source="the published appcast"):
            version = item_version(item)
            if version is None or not version.isdigit():
                raise CheckError(f"the published appcast has an item whose sparkle:version is {version!r}, not a whole number")
            published.append(int(version))
        if published and build <= max(published):
            raise CheckError(
                f"CURRENT_PROJECT_VERSION is {build}, but the published appcast already offers build {max(published)}; "
                f"Sparkle installs only a higher build, so raise it (release_checks.py bump)")
    return build


def bump(text: str, version: str) -> tuple[str, int]:
    """Set MARKETING_VERSION to `version` and raise CURRENT_PROJECT_VERSION by one
    in the six configurations. Returns the new text and the new build number."""
    if not VERSION_RE.fullmatch(version):
        raise CheckError(f"version {version!r} is not of the form X.Y.Z")
    current = project_versions(text)
    if current is None:
        raise CheckError("project.pbxproj has no build configuration with Witty's bundle identifier")
    build = current[1] + 1
    parts, last = [], 0
    for config in witty_configurations(text):
        body = config.group("body")
        body = setting_re("MARKETING_VERSION").sub(lambda m: f"{m.group(1)}{version};", body)
        body = setting_re("CURRENT_PROJECT_VERSION").sub(lambda m: f"{m.group(1)}{build};", body)
        parts.append(text[last:config.start("body")])
        parts.append(body)
        last = config.end("body")
    parts.append(text[last:])
    return "".join(parts), build


def sparkle_version(text: str) -> str:
    match = re.search(
        r'XCRemoteSwiftPackageReference "Sparkle" \*/ = \{.*?repositoryURL = "https://github\.com/sparkle-project/Sparkle";'
        r'.*?kind = exactVersion;\s*version = ([0-9.]+);',
        text, re.S)
    if not match:
        raise CheckError("project.pbxproj does not pin Sparkle to an exact version")
    return match.group(1)


# ─── Built app ───


def ghostty_update_host_problems(app: Path) -> list[str]:
    """One problem per file of the bundle that can make or configure a network
    request (code and the Info.plist) and mentions Ghostty's update host."""
    contents = app / "Contents"
    candidates = [contents / "Info.plist"]
    for folder in ("MacOS", "Frameworks", "PlugIns"):
        for root, _dirs, files in os.walk(contents / folder):
            candidates += [Path(root) / f for f in sorted(files)]
    return [f"{app.name}/{p.relative_to(app)} mentions {GHOSTTY_UPDATE_HOST.decode()}, Ghostty's update host"
            for p in candidates
            if p.is_file() and not p.is_symlink() and GHOSTTY_UPDATE_HOST in p.read_bytes()]


def check_no_ghostty_updater(app: Path) -> None:
    if not (app / "Contents" / "MacOS").is_dir():
        raise CheckError(f"{app} is not an app bundle")
    problems = ghostty_update_host_problems(app)
    if problems:
        raise CheckError(problems)


def check_app(app: Path, feed: str | None = None, key: str | None = None, build: int | None = None) -> None:
    """The packaged app's updater. Runs after package_release.sh removed
    SUEnableAutomaticChecks and before it signs anything."""
    plist_path = app / "Contents" / "Info.plist"
    try:
        with plist_path.open("rb") as f:
            info = plistlib.load(f)
    except (OSError, plistlib.InvalidFileException) as e:
        raise CheckError(f"cannot read {plist_path}: {e}") from None

    problems = []
    app_feed = info.get("SUFeedURL", "")
    app_key = info.get("SUPublicEDKey", "")
    problems += feed_problems(app_feed, "the app's SUFeedURL")
    problems += key_problems(app_key, "the app's SUPublicEDKey")
    if feed is not None and app_feed != feed:
        problems.append(f"the app's SUFeedURL is {app_feed!r} but WITTY_UPDATE_FEED_URL is {feed!r}; rebuild")
    if key is not None and app_key != key:
        problems.append(f"the app's SUPublicEDKey is {app_key!r} but WITTY_UPDATE_PUBLIC_ED_KEY is {key!r}; rebuild")

    for required in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
        if info.get(required) is not True:
            problems.append(f"the app's {required} must be true, got {info.get(required)!r}")
    if "SUEnableAutomaticChecks" in info:
        problems.append("the app still has SUEnableAutomaticChecks; a release lets Sparkle ask before its first check")
    # Nothing that would identify the user or install without a click.
    for forbidden in ("SUEnableSystemProfiling", "SUSendProfileInfo", "SUAutomaticallyUpdate"):
        if info.get(forbidden) is True:
            problems.append(f"the app sets {forbidden}; Witty's update checks send no profile and install only on a click")
    interval = info.get("SUScheduledCheckInterval")
    if interval is not None and (not isinstance(interval, int) or interval < MIN_CHECK_INTERVAL):
        problems.append(f"the app's SUScheduledCheckInterval is {interval!r}; checks must be at most daily ({MIN_CHECK_INTERVAL})")
    if build is not None and info.get("CFBundleVersion") != str(build):
        problems.append(f"the app's CFBundleVersion is {info.get('CFBundleVersion')!r} but the project's build number is {build}; rebuild")

    problems += ghostty_update_host_problems(app)
    if problems:
        raise CheckError(problems)


# ─── Appcast ───

FEED_SIGNATURE_RE = re.compile(
    rb"<!-- sparkle-signatures:\nedSignature: (?P<sig>[A-Za-z0-9+/=]+)\nlength: (?P<length>\d+)\n-->\s*\Z")


def signature_problem(value: str | bytes | None, what: str) -> str | None:
    try:
        raw = base64.b64decode(value or b"", validate=True)
    except (binascii.Error, ValueError):
        raw = b""
    return None if len(raw) == 64 else f"{what} is not an EdDSA signature (the base64 of 64 bytes)"


def check_appcast(data: bytes, dmg_name: str, dmg_size: int, tag: str, build: int,
                  critical: bool | None = None) -> str:
    """A freshly generated appcast for one release: exactly one item, for this
    build, pointing at this DMG in this tag's release, signed, and the feed itself
    signed. Returns the DMG's EdDSA signature for `sign_update --verify`.
    `critical` True or False requires the item to be marked critical or not."""
    version = tag_version(tag)
    items = appcast_items(data, source="the appcast")
    if len(items) != 1:
        raise CheckError(f"the appcast must list exactly one release, found {len(items)}")
    (item,) = items
    ns = f"{{{SPARKLE_NS}}}"
    problems = []

    if item_version(item) != str(build):
        problems.append(f"the appcast's sparkle:version is {item_version(item)!r}, the app's build number is {build}")
    short = item.findtext(f"{ns}shortVersionString")
    if short != version:
        problems.append(f"the appcast's sparkle:shortVersionString is {short!r}, the tag says {version}")

    enclosure = item.find("enclosure")
    signature = ""
    if enclosure is None:
        problems.append("the appcast item has no enclosure")
    else:
        url = enclosure.get("url")
        expected = download_prefix(tag) + dmg_name
        if url != expected:
            problems.append(f"the appcast downloads {url!r}, expected {expected!r}")
        if enclosure.get("length") != str(dmg_size):
            problems.append(f"the appcast's length is {enclosure.get('length')!r}, the DMG has {dmg_size} bytes")
        signature = enclosure.get(f"{ns}edSignature") or ""
        problem = signature_problem(signature, "the DMG's sparkle:edSignature")
        if problem:
            problems.append(problem + "; is SUPublicEDKey the public half of the keychain key generate_appcast used?")

    if item.find(f"{ns}deltas") is not None:
        problems.append("the appcast offers delta updates; Witty publishes only the full DMG")
    if item.find(f"{ns}phasedRolloutInterval") is not None:
        problems.append("the appcast has a phased rollout; Witty does not stage releases")
    is_critical = item.find(f"{ns}criticalUpdate") is not None or item.find(f"{ns}tags/{ns}criticalUpdate") is not None
    if critical is True and not is_critical:
        problems.append("WITTY_CRITICAL_UPDATE=1 but the appcast does not mark the release critical")
    if critical is False and is_critical:
        problems.append("the appcast marks the release critical, but WITTY_CRITICAL_UPDATE is not 1")

    feed_signature = FEED_SIGNATURE_RE.search(data)
    if not feed_signature:
        problems.append("the appcast carries no feed signature; SURequireSignedFeed makes the app reject it")
    else:
        problem = signature_problem(feed_signature.group("sig"), "the feed's edSignature")
        if problem:
            problems.append(problem)

    if problems:
        raise CheckError(problems)
    return signature


# ─── Command line ───


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("settings")
    p.add_argument("feed")
    p.add_argument("key")

    p = sub.add_parser("feed")
    p.add_argument("feed")

    p = sub.add_parser("project")
    p.add_argument("pbxproj", type=Path)
    p.add_argument("--previous-project", type=Path)
    p.add_argument("--previous-name", default="the previous release")
    p.add_argument("--previous-appcast", type=Path)

    p = sub.add_parser("bump")
    p.add_argument("pbxproj", type=Path)
    p.add_argument("version")

    p = sub.add_parser("sparkle-version")
    p.add_argument("pbxproj", type=Path)

    p = sub.add_parser("app")
    p.add_argument("app", type=Path)
    p.add_argument("--feed")
    p.add_argument("--key")
    p.add_argument("--build", type=int)

    p = sub.add_parser("scan")
    p.add_argument("app", type=Path)

    p = sub.add_parser("appcast")
    p.add_argument("appcast", type=Path)
    p.add_argument("--dmg", type=Path, required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--build", type=int, required=True)
    group = p.add_mutually_exclusive_group()
    group.add_argument("--critical", dest="critical", action="store_const", const=True)
    group.add_argument("--not-critical", dest="critical", action="store_const", const=False)

    p = sub.add_parser("download-prefix")
    p.add_argument("tag")

    args = parser.parse_args(argv)
    try:
        if args.command == "settings":
            check_settings(args.feed, args.key)
        elif args.command == "feed":
            if feed_problems(args.feed):
                raise CheckError(feed_problems(args.feed))
        elif args.command == "project":
            print(check_build_number(
                args.pbxproj.read_text(),
                args.previous_project.read_text() if args.previous_project else None,
                args.previous_name,
                args.previous_appcast.read_bytes() if args.previous_appcast else None))
        elif args.command == "bump":
            text, build = bump(args.pbxproj.read_text(), args.version)
            args.pbxproj.write_text(text)
            print(f"MARKETING_VERSION = {args.version}, CURRENT_PROJECT_VERSION = {build}")
        elif args.command == "sparkle-version":
            print(sparkle_version(args.pbxproj.read_text()))
        elif args.command == "app":
            check_app(args.app, args.feed, args.key, args.build)
        elif args.command == "scan":
            check_no_ghostty_updater(args.app)
        elif args.command == "appcast":
            print(check_appcast(args.appcast.read_bytes(), args.dmg.name, args.dmg.stat().st_size,
                                args.tag, args.build, args.critical))
        elif args.command == "download-prefix":
            print(download_prefix(args.tag))
    except CheckError as e:
        for problem in e.problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
