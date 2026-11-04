# Witty fork notes

[Back to README](README.md)

Witty is an independent fork of [Ghostty](https://github.com/ghostty-org/ghostty),
maintained by Reality Inc. Upstream is merged in regularly (the
`chore: sync Ghostty upstream through <date>` commits). This file lists every
place where Witty's tree differs from upstream, and why, so that a merge keeps
what Witty needs.

## Contents

- [How to check this list](#how-to-check-this-list)
- [Merge rules](#merge-rules)
- [Divergences](#divergences)
  - [The `altscreen:` keybind prefix](#the-altscreen-keybind-prefix)
  - [Witty's own identity](#wittys-own-identity)
  - [Witty's own config, state and cache directories](#wittys-own-config-state-and-cache-directories)
  - [Updater](#updater)
  - [Release tooling](#release-tooling)
  - [Repository automation](#repository-automation)
  - [Fixes not upstream](#fixes-not-upstream)
  - [Documentation](#documentation)
  - [Community files](#community-files)
- [Deliberately not changed](#deliberately-not-changed)

## How to check this list

```sh
git remote add upstream https://github.com/ghostty-org/ghostty  # once
git fetch upstream && git diff --stat "$(git merge-base HEAD upstream/main)" HEAD
```

Every file that command prints should appear below. On 2026-10-24 it printed 112
files against upstream `d2865b8f5`. Each one is listed here by its full path or
by the directory that holds it. Witty's hunks inside shared files are marked
with `Witty:` or `witty (fork):` comments.

## Merge rules

1. **Keep upstream's compatibility identifiers.** Remote hosts' terminfo and
   shell integration depend on them: the `ghostty` executable name,
   `TERM=xterm-ghostty`, the `GHOSTTY_*` environment variables, the resources
   layout (`share/ghostty`, `Contents/Resources/ghostty`), the Zig module
   names, the `config.ghostty` file name, and `build_config.bundle_id`.
2. **Route every new per-user path through `build_config.user_dir`.** If
   upstream adds a file under the XDG directories or `~/Library/...`, a literal
   `"ghostty"` or `bundle_id` there would make Witty read or write Ghostty's
   files. The test `ghostty import: Witty's per-user paths are its own` in
   `src/config/ghostty_import.zig` fails if a known call site goes back to
   Ghostty's names; extend it for new ones.
3. **Never take upstream's updater URLs or EdDSA key.** If
   `UpdateDelegate.swift` or the Info.plist `SU*` keys conflict, keep Witty's
   side.
4. **On a conflict in a file listed here, keep the Witty hunk and re-apply it
   to upstream's new code** rather than taking either side whole.

## Divergences

### The `altscreen:` keybind prefix

The fork's feature: a keybind that fires only while tmux owns the alternate
screen, and otherwise falls back to the binding it replaced. See
[docs/witty-altscreen.md](docs/witty-altscreen.md).

| File | What and why |
| --- | --- |
| `src/input/Binding.zig` | Parses the `altscreen:` flag, stores the binding it replaces, and resolves the lookup against the gate (`getEventAltscreen`, `putFlags`). |
| `src/Surface.zig` | Computes the gate per surface (alternate screen **and** `tmux_active`) and passes it to every keybind lookup, including key tables and sequences. |
| `src/App.zig` | App-scope lookups pass `altscreen=false`, so a gated binding cannot fire app-wide without a surface to check. |
| `src/terminal/modes.zig` | Private mode `?8771` (`tmux_active`), which tmux sets from its shell prompt to say it is attached. |
| `src/terminal/Terminal.zig` | Clears `tmux_active` on every alternate-screen transition so a stale or spoofed value cannot reach a non-tmux app; tests. |
| `src/terminal/snapshot/terminal.zig` | Snapshots store only upstream's stable mode bits (`SnapshotModeBits = u43`), so the transient `tmux_active` is never saved or restored and the format stays upstream's. This relies on `tmux_active` being the last entry in `modes.zig`: when upstream adds a mode, keep `tmux_active` last and raise `SnapshotModeBits` to upstream's count. The `TERMINAL mode bit layout` test fails until both are done. |
| `src/config/Config.zig` | Documents `altscreen:` under `keybind`; adds the macOS defaults `cmd+ctrl+=` (tmux `C-b E` inside tmux) and `cmd+left` (Home instead of `C-a` inside tmux). |
| `include/ghostty.h` | `GHOSTTY_BINDING_FLAGS_ALTSCREEN` for the macOS app. |
| `macos/Sources/Ghostty/Ghostty.Input.swift` | Swift mirror of that flag. |
| `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | Gated bindings are not sent to menu key equivalents, which would bypass the gate. |

### Witty's own identity

| File | What and why |
| --- | --- |
| `macos/Ghostty.xcodeproj/project.pbxproj` | Product name `Witty`, bundle IDs `ai.scam.witty`, `ai.scam.witty.debug` and `ai.scam.witty-dock-tile`, display names, `PRODUCT_MODULE_NAME = Ghostty` (keeps the tests' `@testable import Ghostty`), `TEST_HOST` pointing at `Witty.app`, and code signing through `$(WITTY_CODE_SIGN_IDENTITY:default=-)`. The executable stays `ghostty`. The privacy usage descriptions that macOS shows in permission prompts say "A program running within Witty". `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are Witty's release version and build number; upstream keeps placeholders there and stamps its versions in CI. |
| `macos/Ghostty.xcodeproj/xcshareddata/xcschemes/Ghostty.xcscheme` | `BuildableName = Witty.app`. |
| `macos/Ghostty-Info.plist` | Witty's surface UTType (`ai.scam.wittySurfaceId`) and the updater keys (see [Updater](#updater)). |
| `macos/Sources/Ghostty/Surface View/SurfaceView+Transferable.swift` | The same UTType in code. |
| `macos/Sources/Features/Custom App Icon/DockTilePlugin.swift` | Reads the app icon setting from Witty's defaults domain (`ai.scam.witty`). |
| `src/build/GhosttyXcodebuild.zig` | The built bundle is `macos/build/<config>/Witty.app`; passes the signing identity and updater settings to `xcodebuild`, which runs with an empty environment. |
| `src/build/Config.zig` | Build options `-Dmacos-sign-identity`, `-Dmacos-update-feed-url`, `-Dmacos-update-public-ed-key`, with `WITTY_*` environment defaults. |
| `src/cli/help.zig`, `src/main_ghostty.zig` | CLI help says `open -na Witty.app`. |
| `macos/Sources/App/MainMenu.xib`, the window `.xib` files in `macos/Sources/Features/Terminal/Window Styles/`, `macos/Sources/Features/QuickTerminal/QuickTerminal.xib`, `TitlebarTabsVenturaTerminalWindow.swift`, `TitlebarTabsTahoeTerminalWindow.swift`, `BaseTerminalController.swift`, `SurfaceView_AppKit.swift` | The app names itself Witty in its menus (About, Hide, Quit, Help, "Make Witty the Default Terminal") and in the default window title, `🍀 Witty`. A window or tab with no title shows `🍀` where upstream shows `👻`. |
| `macos/Sources/Features/About/AboutView.swift`, `CyclingIconView.swift` | The About window says Witty. Its GitHub button and version link open `scamai/witty` and the `witty-v<version>` release; Docs still opens ghostty.org. |
| `macos/Sources/App/AppDelegate.swift`, `main.swift`, `Helpers/UntrustedURLAlert.swift`, `Features/Terminal/ErrorView.swift`, `TerminalView.swift`, `App Intents/GhosttyIntentError.swift`, `IntentPermission.swift`, `AppleScript/AppDelegate+AppleScript.swift`, `Update/UpdatePopoverView.swift`, `Command Palette/TerminalCommandPalette.swift` | Alerts, errors and prompts say Witty. |
| `macos/Ghostty.sdef` | The AppleScript dictionary's title and descriptions say Witty. Its terms, four-letter codes and Cocoa classes are upstream's, so existing scripts keep working. |
| `images/Ghostty.icon/`, `images/witty-icon-src/`, `macos/Assets.xcassets/AppIconImage.imageset/`, `macos/Assets.xcassets/Custom Icon/CustomIconGhost.imageset/`, `macos/Assets.xcassets/Alternate Icons/*` | Witty's four-leaf-clover icon, with dark and monochrome appearance specialisations, and eight clover alternates under upstream's `macos-icon` theme names. `images/witty-icon-src/draw_clover.swift` generates all of it. Upstream's CRT frame layers, ghost glyph and ghost alternates are removed. The file keeps the name `Ghostty.icon` only because the Xcode project's app-icon name is `Ghostty`. On an upstream icon change, keep Witty's side. |

### Witty's own config, state and cache directories

So that Witty and Ghostty can be installed side by side and stock Ghostty
never sees Witty-only syntax.

| File | What and why |
| --- | --- |
| `src/build_config.zig` | `user_dir.xdg = "witty"` and `user_dir.macos = "ai.scam.witty"`, the single source for every per-user path below. `bundle_id` itself is unchanged; see [Deliberately not changed](#deliberately-not-changed). |
| `src/config/file_load.zig` | Default config paths: `$XDG_CONFIG_HOME/witty/config.ghostty` and `.../witty/config`. |
| `src/os/macos.zig` | `~/Library/Application Support/ai.scam.witty` and `~/Library/Caches/ai.scam.witty`. |
| `src/config/theme.zig` | User themes in `$XDG_CONFIG_HOME/witty/themes`. |
| `src/crash/dir.zig`, `src/crash/sentry.zig` | Crash reports in `$XDG_STATE_HOME/witty/crash`, the Sentry cache in `$XDG_CACHE_HOME/witty/sentry`. |
| `src/cli/ssh.zig`, `src/cli/ssh_cache.zig` | The SSH terminfo cache in `$XDG_STATE_HOME/witty/ssh_cache`. |
| `src/config/ghostty_import.zig` | Witty-only file. On first launch, if Witty has no config and Ghostty has one, copies Ghostty's config files, their relative `config-file` includes and `themes/` into Witty's directories, commenting out each `auto-update` line under a note (see [Updater](#updater)). Never modifies Ghostty's files, never overwrites Witty's. |
| `src/config/Config.zig` | `loadDefaultFiles` runs that import before it would write the template config. |
| `macos/Sources/Ghostty/Ghostty.Config.swift` | The default `macos-custom-icon` is `~/.config/witty/Ghostty.icns`. |

### Updater

A release asks before its first automatic check (unless the config sets
`auto-update`), then, if allowed, checks one signed, static `appcast.xml` on
Witty's GitHub Releases at most once a day. The request carries no install ID,
system profile or query string, and no cookie from an earlier check: cookies
GitHub sets during a check's redirects are deleted when it ends.

An `auto-update` line counts as the answer. `src/config/ghostty_import.zig`
comments out the ones in the files it copies from Ghostty, so a setting
written for Ghostty does not answer for Witty. A file both configs include by
absolute or `~/` path is read where it is and cannot be rewritten, so a line
there still counts for both apps; the docs say so.

| File | What and why |
| --- | --- |
| `macos/Sources/Features/Update/UpdateController.swift` | Reads the feed URL and EdDSA key from the Info.plist. Without both, Sparkle is never started: no scheduled checks and no network requests. Refuses a feed that is not `https` (plain `http` only to a loopback host, for `update_probe.py`) or has a query string or credentials, and deletes the update hosts' cookies before starting Sparkle. |
| `macos/Sources/Features/Update/UpdateDelegate.swift` | Returns Witty's feed instead of Ghostty's tip and release appcasts. `auto-update-channel` has no effect. Keeps a check to one request: no system profile keys, no release-notes download, the cookies of github.com, githubusercontent.com and the feed's host deleted before and after every check (`UpdateCookies`), and none sent or stored with the DMG download. The hooks spell out their Objective-C selectors, the names Sparkle looks for. |
| `macos/Ghostty-Info.plist` | `SUFeedURL = $(WITTY_UPDATE_FEED_URL)` and `SUPublicEDKey = $(WITTY_UPDATE_PUBLIC_ED_KEY)` instead of Ghostty's key; both are empty unless the build sets them. `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction` and `SUScheduledCheckInterval = 86400` are Witty's. `SUEnableAutomaticChecks` stays `false` as upstream's, so development builds never check on their own; `package_release.sh` deletes it from a release, as upstream's `release-tag.yml` does, so Sparkle asks on the second launch. |
| `macos/Sources/App/AppDelegate.swift` | Hides "Check for Updates…" and leaves Sparkle's settings alone while the updater is off. |
| `macos/Sources/Ghostty/Ghostty.Command.swift` | Drops "Check for Updates" from the command palette while the updater is off. |
| `macos/Sources/Features/Update/UpdateViewModel.swift` | "View Release Notes" opens the version's `witty-v<version>` GitHub release, not Ghostty's release notes for the same number. |
| `macos/Sources/Features/Update/UpdatePopoverView.swift` | No **Skip** button for an update the appcast marks critical, as in Sparkle's own alert. |
| `src/config/Config.zig` | The `auto-update` docs say that `download` installs a downloaded update when the app quits, without asking (upstream's say it never installs), that release builds ask on the second launch, that setting it counts as the answer, and that the Ghostty import comments it out but a file both apps include still sets it. |
| `macos/Tests/Update/UpdatePrivacyTests.swift`, `macos/Tests/Update/ReleaseNotesTests.swift` | The feed URL rule, the profile and release-notes hooks, two of the four cookie clears (no test reaches the other two; on a Mac, `update_probe.py` checks what the four do together), the DMG download's cookie setting, and the Witty release-notes link. The first file is Witty-only. |

### Release tooling

All Witty-only files.

| File | What and why |
| --- | --- |
| `macos/scripts/release.sh` | ReleaseFast build, Developer ID signing, DMG, notarization, stapling, appcast. A `witty-v*` tag build stops before building unless `WITTY_UPDATE_FEED_URL` is exactly `https://github.com/scamai/witty/releases/latest/download/appcast.xml` (the shipped app can never change its feed, and every later release replaces the appcast there), `WITTY_UPDATE_PUBLIC_ED_KEY` is an EdDSA public key other than Ghostty's, the Sparkle tools match the framework, and the build number is higher than the previous tag's and the published appcast's. An untagged build only warns when the updater settings are missing. |
| `macos/scripts/package_release.sh` | Re-signs inside-out with a secure timestamp, notarizes and staples app and DMG. Before signing, deletes `SUEnableAutomaticChecks` from the app (see [Updater](#updater)) and refuses an app any of whose code or `Info.plist` mentions `files.ghostty.org`. A `witty-v*` tag names the DMG `Witty-<version>-macos-<arch>.dmg`, is refused unless the app's version and a `CHANGELOG.md` section match it, its updater keys are right, and its build number is higher than the previous tag's and the published appcast's (the check `release.sh` makes, repeated for a repackaged app), and writes the signed `appcast.xml` next to the DMG after stapling. |
| `macos/scripts/publish_release.sh` | Uploads a tag's DMG to its GitHub release, checks GitHub's copy against the local file, uploads `appcast.xml` last, and checks that the live feed serves it. |
| `macos/scripts/lib_signing.sh`, `macos/scripts/test_lib_signing.sh` | Signing identity resolution, certificate expiry checks, notarization, the release tag, the release asset name, the tag/version/changelog check, and their tests. |
| `macos/scripts/lib_update.sh`, `macos/scripts/test_lib_update.sh` | The tag build's updater checks, the Sparkle tools (from the release the Xcode project pins, checked by SHA-256), `generate_appcast` with one version and no deltas, `sign_update --verify` of the feed and the DMG, and their tests with stub tools, including runs of `release.sh` itself that must stop a bad tag build before it builds. |
| `macos/scripts/release_checks.py`, `macos/scripts/test_release_checks.py` | The rules those scripts apply, in the Python standard library so their tests run on any OS: the feed URL and key, the six `CURRENT_PROJECT_VERSION` entries (`bump X.Y.Z` raises them), the built app's updater keys and the Ghostty update host, and the generated appcast. |
| `macos/scripts/update_probe.py` | A loopback stand-in for the feed that prints what each check sends and fails if a request is not a GET or sends a query string, a body, a cookie the probe never set or one set during an earlier check; it redirects the first request, as github.com does, and reports a cookie sent back within one check. `--self-test` proves it catches each of the five and passes a client that clears cookies between checks. |
| `src/build/GitVersion.zig` | Skips `witty-v*` tags when it detects the core's version. Upstream's `Config.zig` panics when the built commit carries any tag other than a `vX.Y.Z` matching `build.zig.zon`, so without this a tagged Witty release cannot be built. |
| `macos/AGENTS.md` | Release prerequisites, pitfalls and settings. |
| `AGENTS.md` | Upstream's file, with two Witty hunks: it points at the release script, and it replaces upstream's "Issue and PR Guidelines" section, which tells agents to refuse to open issues or PRs, with Witty's rule: never open issues, PRs or discussions on ghostty-org/ghostty, and open them on scamai/witty only when the user asks. Keep the hunks that small: upstream changed this file 11 times in the 12 months to 2026-10-24. |
| `.gitignore` | Ignores the DMGs and `appcast.xml` that `release.sh` writes to `dist/`. |

### Repository automation

| File | What and why |
| --- | --- |
| `.github/dependabot.yml` | Removed. In this repository Dependabot opened PRs that bump the actions in upstream's workflows. Witty takes those bumps with each upstream sync instead, so its copies of upstream's workflows differ from upstream's only by the two guards below. If a merge brings the file back or conflicts on it, keep it deleted. Dependabot's security alerts and security-update PRs do not need this file and stay on in the repository settings. |
| `.github/workflows/witty-macos.yml` | Witty-only: Witty's CI. On GitHub-hosted `macos-26` runners with Xcode 26.6 and the Zig that `build.zig.zon` names, it builds a Debug `Witty.app` for the runner's architecture, checks its bundle ID and that the updater is off, runs `zig build test` (the Zig unit tests, then the Swift tests) and reads the Swift test counts from the result bundle, and runs the four release-script tests. It runs for pull requests, and for pushes to `main` or a `ci/` branch, that change a file it lists, and uses no secrets: the app is signed ad hoc. Witty is public, so GitHub-hosted runners cost nothing here. |
| `.github/workflows/test.yml`, `.github/workflows/release-tag.yml` | One `if:` each, marked `Witty:`, so that the `required` job of `test.yml` and the `setup` job of `release-tag.yml` run only in `ghostty-org/ghostty`. Every job in both files runs on Ghostty's Namespace runners (`namespace-profile-ghostty-*`), which this repository does not have, so a job that starts here waits for a runner until GitHub cancels it after 24 hours. Upstream already guards the other jobs of `test.yml`, directly or through `needs:` on a guarded job, but `required` escaped through `if: always()`: in the `Test` run of 2026-06-19 (`27838703787`) every other job was skipped and it alone was cancelled after 24 hours. `release-tag.yml` had no guard, so pushing one of upstream's `vX.Y.Z` tags here would have queued its `setup` job, which the other five need, for a runner that never comes. On a merge that changes these workflows, keep both guards and look for a new job that escapes them: one with no `needs:` and no guard, or one whose `if:` uses `always()`. |

### Fixes not upstream

| File | What and why |
| --- | --- |
| `src/shell-integration/bash/ghostty.bash`, `src/shell-integration/zsh/ghostty-integration`, `src/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish` | Each new prompt turns off mouse tracking left on by a full-screen app that died, such as tmux over a dropped SSH connection. |
| `src/terminal/stream_terminal.zig` | Test for that reset sequence. |
| `macos/Sources/Ghostty/Ghostty.App.swift` | Handles `size_limit` and `quit_timer` explicitly, so they no longer log "unknown action" on every new tab. |
| `macos/Tests/Ghostty/ActionDispatchCoverageTests.swift` | Fails if a core action that is sent unprompted falls into the dispatcher's `default:` branch. |
| `src/termio/stream_handler.zig` | Logs tmux control-mode notifications and viewer actions at debug instead of upstream's info (the three `log` calls in `dcsCommand`). They carry pane output, command output and the `capture-pane` commands sent to tmux, and the Zig core's macOS unified logging is on by default and logs every message as a public string (`pkg/macos/os/zig_macos.c`), so at info a release build wrote them to the system log unredacted. Release builds compile debug logs out (`std_options` in `src/main_ghostty.zig`); Debug builds still log them. On a conflict, keep `log.debug`. |

### Documentation

| File | What and why |
| --- | --- |
| `README.md` | Witty's README, a landing page for the macOS app. It links to Ghostty's README upstream instead of keeping a copy. |
| `FORK.md` | This file. |
| `CHANGELOG.md` | Witty's changes on top of upstream. |
| `docs/witty-altscreen.md` | The `altscreen:` prefix and the tmux setup it needs. |
| `docs/witty-remote-workflow.md` | The persistent remote-dev setup with tmux, moved out of the README, plus the note for Windows users. |
| `docs/witty-install.md` | Download, first launch and the Ghostty config import, living next to Ghostty, updates, the `ghostty` CLI, upgrading from v0.1.x, platform support and building from source, moved out of the README. |
| `images/witty/` | The README's hero illustration (`one-key-two-jobs.svg`, a diagram, not a screenshot) and its Download button (`download-macos.svg`). |
| `LICENSE` | Ghostty's MIT notice unchanged, plus `Copyright (c) 2026 Reality Inc.` for Witty's modifications. |

### Community files

Witty's own contributing and community files. Most live in `.github/`:
GitHub reads `.github/` before the repository root, so they take the place of
the Ghostty files at the root without editing them. Unless its row says
otherwise, upstream has never had a file at a path listed here.

| File | What and why |
| --- | --- |
| `.github/CONTRIBUTING.md` | Witty's contributing guide. GitHub links to it instead of upstream's root `CONTRIBUTING.md`, which describes Ghostty's process (vouching, Issue Triage discussions, Discord). |
| `.github/CODEOWNERS` | `* @shenxingy`. GitHub uses the first `CODEOWNERS` it finds in `.github/`, the root and `docs/`, so this replaces upstream's root file, whose `@ghostty-org` teams are unknown in this repository. |
| `.github/PULL_REQUEST_TEMPLATE.md` | The fork checklist (`Witty:` comments, FORK.md rows, compatibility identifiers, CHANGELOG) and the AI disclosure for pull requests. |
| `.github/SECURITY.md`, `.github/SUPPORT.md`, `.github/CODE_OF_CONDUCT.md` | Witty's own. For this repository they replace the `scamai/.github` organization defaults (GitHub uses the repository's own file first). Upstream has no file at these paths. `CODE_OF_CONDUCT.md` is the Contributor Covenant 2.1 with only the contact filled in. Keep the rest verbatim so GitHub keeps detecting it. |
| `.github/ISSUE_TEMPLATE/config.yml` | Witty's issue chooser: blank issues off, links to Q&A, Witty's bug form for bugs that also happen in stock Ghostty, Ghostty's docs and the security policy. It links no Ghostty form: Ghostty's Issue Triage form asks for screen recordings, a screenshot of the inspector's key log and logs, in public. Witty's bug form still links that form for bugs that also happen in stock Ghostty, next to a note to redact first and send anything private to Witty's private channel. Upstream deleted its own `config.yml` in `4a516fa39`; if a merge re-adds it, keep Witty's version. |
| `.github/ISSUE_TEMPLATE/witty-bug.yml`, `.github/ISSUE_TEMPLATE/witty-feature.yml` | Witty's own issue forms. The `witty-` prefix keeps them from colliding with any template upstream adds. |
| `.github/DISCUSSION_TEMPLATE/issue-triage.yml` | Upstream's Issue Triage discussion form with two Witty hunks, marked `# Witty:`: the recommendations in the Issue Description field, and the logs field. Upstream's ask for an asciinema cast, a screenshot of the inspector's key log, a Sentry UUID and logs; Witty's ask for a minimal script or shell snippet with secrets removed, warn that the key log also shows a password typed while the inspector is open, point at Witty's log commands, and send crash files and anything private to the private channel in `.github/SECURITY.md`. The rest of the form is upstream's. This repository has no Issue Triage discussion category (on 2026-11-04 it had Announcements, Q&A and Show and tell), so GitHub shows the form only if one is added. On a conflict, keep Witty's hunks. |

**Never edit these upstream files.** They describe how Ghostty is run, and
Witty keeps them identical to upstream's so that merges stay clean;
`.github/CONTRIBUTING.md` says which of them apply here. In brackets, the
upstream commits that touched each one in the 12 months to 2026-10-24:
`.github/VOUCHED.td` (348), `CONTRIBUTING.md` (26), `CODEOWNERS` (17),
`po/README_TRANSLATORS.md` (12), `HACKING.md` (11),
`.github/DISCUSSION_TEMPLATE/vouch-request.yml` (3), `PACKAGING.md` (3), `AI_POLICY.md` (2),
`po/README_CONTRIBUTORS.md` (2), `.github/issue-unvouched-message` (1).

## Deliberately not changed

- **`build_config.bundle_id` stays `com.mitchellh.ghostty`.** Besides the macOS
  directories (now `user_dir.macos`), it names the gettext domain (the
  `com.mitchellh.ghostty.mo` files, `src/os/i18n.zig`), the GTK window icon
  name (`src/apprt/gtk/class/window.zig`, `inspector_window.zig`), and the
  unified-logging subsystem of the Zig core (`src/main_ghostty.zig`,
  `src/benchmark/Benchmark.zig`). Changing it would break translations and GTK
  icons unless the resources were renamed too. The Swift side already logs
  under Witty's bundle ID.
- **GTK application ID** (`src/apprt/gtk/build/info.zig`,
  `com.mitchellh.ghostty`). Witty ships no Linux packages. A Linux build from
  source registers the same application ID as Ghostty (the D-Bus name used for
  `gtk-single-instance`, the desktop file and the icon names), so it should
  not be installed next to Ghostty until the ID is changed together with
  `dist/linux/` and the resources.
- **In-process identifiers** such as the `com.mitchellh.ghostty.*` Swift
  notification names, menu item identifiers and the Shortcuts permission key.
  They never leave Witty's process or its own defaults domain.
- **Test bundle IDs** `com.mitchellh.GhosttyTests` and
  `com.mitchellh.GhosttyUITests`. Test bundles are not installed.
- **Upstream documentation that names Ghostty's paths**: the doc comments in
  `src/config/Config.zig` (themes, `config-default-files`, `macos-custom-icon`,
  `loadDefaultFiles`), `src/cli/edit_config.zig`, `src/cli/list_themes.zig`,
  `src/cli/ssh-cache/DiskCache.zig`, and the man page sources in
  `src/build/mdgen/`. They feed `+help`, `+show-config --docs` and the man
  pages, which therefore still say `~/.config/ghostty`. Editing each one would
  conflict with upstream on every merge; a substitution in the docs generator
  would cover all of them at once.
- **`macos/Sources/Features/Settings/SettingsView.swift`** still names
  `~/.config/ghostty/config.ghostty`. Nothing shows this view; it is only used
  by its own preview.
- **User-visible text in the GTK app and the Zig core**: the GTK app's
  dialogs, the command palette's `Ghostty` entry that types a `👻`
  (`src/input/command.zig`), and messages of the `ghostty` CLI such as the
  `+list-themes` preview title. The GTK and palette strings go through
  gettext, where a new msgid drops every translation of it; the CLI keeps
  Ghostty's name along with its executable name. Witty ships no Linux
  packages.
- **`src/extra/vim.zig`** detects the `ghostty` filetype for `*/ghostty/config`
  but not `*/witty/config`. Files named `config.ghostty` are still detected.
- **Upstream's release workflows** (`.github/workflows/release-tag.yml`,
  `release-tip.yml`, `publish-tag.yml`). They publish Ghostty's own builds and
  do not run for Witty: `release-tag.yml` fires on `v1.2.3`-style tags, not
  `witty-v*`, and its one Witty hunk (see
  [Repository automation](#repository-automation)) keeps it from starting even
  for those; `release-tip.yml` starts after a `Test` run on `main`, and then
  its `setup` job, which every other job needs, runs only in `ghostty-org`;
  `release-tip.yml` started by hand and `publish-tag.yml`, which is manual,
  would still wait for runners here.
- **Upstream's community workflows** (`vouch-*.yml`, `milestone.yml`). The
  files stay as upstream has them, but the workflows are disabled in this
  repository's Actions settings (2026-10-18): they run on Ghostty's own runners
  with Ghostty's app secrets, so here every issue, comment or PR left a run
  queued that never started. `test.yml` has been disabled the same way since
  2026-06-19, when each of its runs here waited 24 hours for a runner and was
  cancelled. With its `Witty:` guard none of its jobs starts here, so enabling
  it would only add a skipped run to every push; `witty-macos.yml` is Witty's
  CI instead. Re-enable one with `gh workflow enable <file> -R scamai/witty`.
