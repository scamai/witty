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

## Release (signed + notarized DMG)

- Full pipeline: `macos/scripts/release.sh`
  - Builds ReleaseFast via zig + xcodebuild, re-signs every Mach-O
    inside-out with Developer ID + secure timestamp, notarizes and staples
    the app, builds and signs `dist/Witty.dmg`, notarizes and staples the
    DMG, then runs `spctl` and `syspolicy_check distribution`.
  - Env overrides: `ZIG`, `WITTY_SIGN_IDENTITY`, `WITTY_NOTARY_PROFILE`.
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
  - Signing-helper tests: `macos/scripts/test_lib_signing.sh`.

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
