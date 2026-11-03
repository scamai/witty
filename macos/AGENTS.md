# macOS Ghostty Application

- Use `swiftlint` for formatting and linting Swift code.
- If code outside of `macos/` directory is modified, use
  `zig build -Demit-macos-app=false` before building the macOS app to update
  the underlying Ghostty library.
- Use `macos/build.nu` to build the macOS app, do not use `zig build`
  (except to build the underlying library as mentioned above).
  - Build: `macos/build.nu [--scheme Ghostty] [--configuration Debug] [--action build]`
  - Output: `macos/build/<configuration>/Witty.app` (e.g. `macos/build/Debug/Witty.app`)
- Run unit tests directly with `macos/build.nu --action test`
  - `zig build test` runs them only without `-Dtest-filter`: a filtered run
    reports success without building or running any Swift test.

## Release (signed + notarized DMG)

- Cutting release `witty-vX.Y.Z`:
  1. `python3 macos/scripts/release_checks.py bump
     macos/Ghostty.xcodeproj/project.pbxproj X.Y.Z` sets `MARKETING_VERSION =
     X.Y.Z` and raises `CURRENT_PROJECT_VERSION` by one, in the six build
     configurations of the app and the Dock tile plugin (not the test
     targets). Sparkle installs only a higher build number, so `release.sh`
     and `package_release.sh` refuse one that is not higher than the
     previous tag's and the published appcast's.
  2. In `CHANGELOG.md`, turn `## [Unreleased]` into `## [witty-vX.Y.Z] —
     <date>`, open a new empty `## [Unreleased]` above it, and add the link
     reference at the bottom.
  3. Commit (`chore(release): Witty X.Y.Z (build N)`), then tag that commit:
     `git tag -a witty-vX.Y.Z -m "Witty X.Y.Z"`.
  4. Run `macos/scripts/release.sh` at the tag, with
     `WITTY_UPDATE_FEED_URL=https://github.com/scamai/witty/releases/latest/download/appcast.xml`
     and `WITTY_UPDATE_PUBLIC_ED_KEY` set to Witty's public key (see
     Updater below); add `WITTY_CRITICAL_UPDATE=1` for a security fix. It
     stops before building without them, and `package_release.sh` stops
     before signing if the tag, the app's version and the changelog
     disagree. It writes `dist/Witty-vX.Y.Z-macos-<arch>.dmg` and
     `dist/appcast.xml`.
  5. Push the commit and the tag, and create the GitHub release from the tag
     as a draft, with notes that give the DMG's SHA-256:
     `gh release create witty-vX.Y.Z --repo scamai/witty --draft --title …
     --notes-file …`.
  6. `macos/scripts/publish_release.sh` (same `WITTY_UPDATE_FEED_URL`)
     uploads the DMG, checks GitHub's copy, then uploads `appcast.xml` last,
     so the feed never offers a DMG that is not there yet. Publish the draft,
     then run `macos/scripts/publish_release.sh --check`: it fails unless
     the live feed serves this appcast.

  The tag does not change the Ghostty core's version: `GitVersion.zig`
  skips `witty-v*` tags, so `ghostty +version` still reports
  `<core version>-<branch>+<commit>`, such as `1.3.2-main+e0e6136`.
- Full pipeline: `macos/scripts/release.sh`
  - Builds ReleaseFast via zig + xcodebuild, checks the app's updater,
    re-signs every Mach-O
    inside-out with Developer ID + secure timestamp, notarizes and staples
    the app, builds and signs `dist/Witty.dmg` (named for upload when
    tagged, see below), notarizes and staples the
    DMG, then runs `spctl` and `syspolicy_check distribution`. At a tag it
    then writes the signed `dist/appcast.xml`.
  - Env overrides: `ZIG`, `WITTY_SIGN_IDENTITY`, `WITTY_NOTARY_PROFILE`,
    `WITTY_UPDATE_FEED_URL`, `WITTY_UPDATE_PUBLIC_ED_KEY`,
    `WITTY_SPARKLE_KEY_ACCOUNT` (default `witty`), `WITTY_CRITICAL_UPDATE`.
  - Release asset: when HEAD carries a `witty-v*` tag (or `WITTY_RELEASE_TAG`
    names one), the DMG is `dist/Witty-<version>-macos-<arch>.dmg`, e.g.
    `Witty-v0.1.4-macos-universal.dmg`; `publish_release.sh` uploads that
    file, and `appcast.xml` after it. Never publish a
    `Ghostty-…` name: the v0.1.x `Ghostty-witty-…-macos-arm64.zip` assets
    were packaged outside this repository, not by these scripts.
- Updater: Sparkle runs only when the build gets both Witty's appcast URL
  and the EdDSA public key that verifies it: `WITTY_UPDATE_FEED_URL` and
  `WITTY_UPDATE_PUBLIC_ED_KEY` (env, or `-Dmacos-update-feed-url` /
  `-Dmacos-update-public-ed-key`), written to the Info.plist `SUFeedURL` and
  `SUPublicEDKey`. With either missing the updater is off: no checks, no
  network requests, and "Check for Updates…" is hidden. Never reuse
  Ghostty's appcast or key; a tag build refuses them.
  - A check is one GET of the static, signed `appcast.xml`, at most once a
    day: no query string, install ID or system profile
    (`SUEnableSystemProfiling` stays off, no feed parameters), and no cookie
    from an earlier check. `UpdateCookies` deletes the update hosts' cookies
    before and after each check; a cookie github.com sets on a check's first
    redirect may still go out on that check's next hop. Releases ask first:
    `package_release.sh` deletes `SUEnableAutomaticChecks`, as Ghostty's
    release workflow does, so Sparkle asks on the second launch. A config
    `auto-update` counts as the answer: `src/config/ghostty_import.zig`
    comments it out of the files it copies from Ghostty, and a file both
    apps include by absolute or `~/` path still sets it (documented, not a
    bug). Development builds keep `SUEnableAutomaticChecks` `false` and
    never check on their own. Updates install on a click, or on quit with
    `auto-update = download` or after the
    **Automatically download and install updates** box in Sparkle's dialog
    is ticked; never set `SUAutomaticallyUpdate`. No forced updates and no
    phased rollout.
  - Witty's EdDSA key: created once on the release Mac with Sparkle's
    `generate_keys --account witty` (in the Sparkle release's `bin/`); it
    lives in the login keychain, never in the repository or CI. `-p` prints
    the public key for `WITTY_UPDATE_PUBLIC_ED_KEY`; back the private key up
    with `-x <file>` to wherever the owner keeps it.
  - Proving what a check sends: before the first release with the
    updater, and after a Sparkle upgrade, run
    `python3 macos/scripts/update_probe.py` and build Witty with the zig
    path, which passes both values to xcodebuild as build settings:
    `zig build -Demit-macos-app -Dmacos-update-feed-url=http://127.0.0.1:8765/latest/download/appcast.xml -Dmacos-update-public-ed-key=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=`
    (the same two variables in `zig build`'s environment also work).
    `macos/build.nu` cannot: it runs xcodebuild under `env -i`, so the
    updater stays off. Plain http is accepted only for loopback, and the key
    can be any well-formed EdDSA public key (base64 of 32 bytes), such as
    the one above; Sparkle refuses to start with anything else. Open
    `macos/build/Debug/Witty.app` and choose **Check for Updates…** twice.
    The probe answers the first request with a 302, as github.com does, and
    sets a cookie on every response. It fails if a request is not a GET or
    sends a query string, a body, a cookie the probe never set, or a cookie
    from an earlier check, reports whether a
    check's second request sends back the cookie its first got, and prints
    each request's headers. Docs may say a check sends no cookie at all only
    after a capture shows none.
  - Pitfall: a ReleaseLocal build with the feed and key that was not
    packaged keeps `SUEnableAutomaticChecks = false`, and running it writes
    "no automatic checks" into `ai.scam.witty`'s defaults, so a release run
    later never asks. `defaults delete ai.scam.witty SUEnableAutomaticChecks`
    brings the question back.
- Signing identity: `WITTY_SIGN_IDENTITY`, else the keychain's only
  "Developer ID Application" identity. With several (e.g. a personal and a
  company team) the scripts stop and list them instead of guessing.
  The certificate's team decides the publisher name users see, and changing
  team changes the designated requirement, which resets every user's
  Screen Recording / Accessibility grants once.
- One-time prereqs: Developer ID Application cert in the login keychain,
  and a notarytool profile for the same team (`xcrun notarytool
  store-credentials "AC_NOTARY" --apple-id <id> --team-id <TEAMID>`, which
  prompts for an app-specific password).
- Pitfalls:
  - `~/.local/bin/zig` is a 0.15.2 shim; `release.sh` auto-selects a zig
    meeting `build.zig.zon`'s `minimum_zig_version` (currently brew's 0.16.0).
  - Never notarize the xcodebuild product directly: manual signing adds no
    secure timestamp and the notary rejects it. `package_release.sh` re-signs
    inside-out (Sparkle XPCs first, `Downloader.xpc` keeps its entitlements).
  - Staple the app, not just the DMG: a DMG ticket does not travel with the
    app once it is dragged to /Applications, so an offline first launch fails.
  - Both scripts warn when the signing certificate expires within 120 days
    (`WITTY_CERT_WARN_DAYS`) and fail once it has expired.
  - `release.sh` rebuilds `macos/build/ReleaseLocal/Witty.app` in place. If
    the installed app is that bundle (or a symlink to it), quit Witty first.
  - Repackaging an already-built app without rebuilding:
    `macos/scripts/package_release.sh`; set `WITTY_APP` to package a copy.
    At a tag it makes the same build-number check as `release.sh`, against
    `WITTY_UPDATE_FEED_URL` or else the app's `SUFeedURL`.
  - Release-script tests, which run on any OS:
    `macos/scripts/test_lib_signing.sh`, `macos/scripts/test_lib_update.sh`,
    `python3 macos/scripts/test_release_checks.py` and
    `python3 macos/scripts/update_probe.py --self-test`.

## AppleScript

- The AppleScript scripting definition is in `macos/Ghostty.sdef`.
- Guard AppleScript entry points and object accessors with the
  `macos-applescript` configuration (use `NSApp.isAppleScriptEnabled`
  and `NSApp.validateScript(command:)` where applicable).
- In `macos/Ghostty.sdef`, keep top-level definitions in this order:
  1. Classes
  2. Records
  3. Enums
  4. Commands
- Test AppleScript support:
  (1) Build with `macos/build.nu`
  (2) Launch and activate the app via osascript using the absolute path
      to the built app bundle:
      `osascript -e 'tell application "<absolute path to build/Debug/Witty.app>" to activate'`
  (3) Wait a few seconds for the app to fully launch and open a terminal.
  (4) Run test scripts with `osascript`, always targeting the app by
      its absolute path (not by name) to avoid calling the wrong
      application.
  (5) When done, quit via:
      `osascript -e 'tell application "<absolute path to build/Debug/Witty.app>" to quit'`
