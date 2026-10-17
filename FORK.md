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
  - [Fixes not upstream](#fixes-not-upstream)
  - [Documentation](#documentation)
- [Deliberately not changed](#deliberately-not-changed)

## How to check this list

```sh
git diff --stat "$(git merge-base HEAD upstream/main)" HEAD
```

Every file that command prints should appear below. When this file was
written it printed 59 files against upstream `b32f20f3e` (2026-09-19, the last
sync). Witty's hunks inside shared files are marked with `Witty:` or
`witty (fork):` comments.

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
| `src/config/Config.zig` | Documents `altscreen:` under `keybind`; adds the macOS defaults `cmd+ctrl+=` (tmux `C-b E` on the alternate screen) and `cmd+left` (Home instead of `C-a`). |
| `include/ghostty.h` | `GHOSTTY_BINDING_FLAGS_ALTSCREEN` for the macOS app. |
| `macos/Sources/Ghostty/Ghostty.Input.swift` | Swift mirror of that flag. |
| `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | Gated bindings are not sent to menu key equivalents, which would bypass the gate. |

### Witty's own identity

| File | What and why |
| --- | --- |
| `macos/Ghostty.xcodeproj/project.pbxproj` | Product name `Witty`, bundle IDs `ai.scam.witty`, `ai.scam.witty.debug` and `ai.scam.witty-dock-tile`, display names, `PRODUCT_MODULE_NAME = Ghostty` (keeps the tests' `@testable import Ghostty`), `TEST_HOST` pointing at `Witty.app`, and code signing through `$(WITTY_CODE_SIGN_IDENTITY:default=-)`. The executable stays `ghostty`. |
| `macos/Ghostty.xcodeproj/xcshareddata/xcschemes/Ghostty.xcscheme` | `BuildableName = Witty.app`. |
| `macos/Ghostty-Info.plist` | Witty's surface UTType (`ai.scam.wittySurfaceId`) and the updater keys (see [Updater](#updater)). |
| `macos/Sources/Ghostty/Surface View/SurfaceView+Transferable.swift` | The same UTType in code. |
| `macos/Sources/Features/Custom App Icon/DockTilePlugin.swift` | Reads the app icon setting from Witty's defaults domain (`ai.scam.witty`). |
| `src/build/GhosttyXcodebuild.zig` | The built bundle is `macos/build/<config>/Witty.app`; passes the signing identity and updater settings to `xcodebuild`, which runs with an empty environment. |
| `src/build/Config.zig` | Build options `-Dmacos-sign-identity`, `-Dmacos-update-feed-url`, `-Dmacos-update-public-ed-key`, with `WITTY_*` environment defaults. |
| `src/cli/help.zig`, `src/main_ghostty.zig` | CLI help says `open -na Witty.app`. |
| `images/Ghostty.icon/`, `images/witty-icon-src/`, `macos/Assets.xcassets/AppIconImage.imageset/`, `macos/Assets.xcassets/Custom Icon/CustomIconGhost.imageset/` | Witty's four-leaf-clover icon, generated by `images/witty-icon-src/draw_clover.swift`. Upstream's CRT frame layers and ghost glyph are removed. The file keeps the name `Ghostty.icon` only because the Xcode project's app-icon name is `Ghostty`. On an upstream icon change, keep Witty's side. |

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
| `src/config/ghostty_import.zig` | Witty-only file. On first launch, if Witty has no config and Ghostty has one, copies Ghostty's config files, their relative `config-file` includes and `themes/` into Witty's directories. Never modifies Ghostty's files, never overwrites Witty's. |
| `src/config/Config.zig` | `loadDefaultFiles` runs that import before it would write the template config. |
| `macos/Sources/Ghostty/Ghostty.Config.swift` | The default `macos-custom-icon` is `~/.config/witty/Ghostty.icns`. |

### Updater

| File | What and why |
| --- | --- |
| `macos/Sources/Features/Update/UpdateController.swift` | Reads the feed URL and EdDSA key from the Info.plist. Without both, Sparkle is never started: no scheduled checks and no network requests. |
| `macos/Sources/Features/Update/UpdateDelegate.swift` | Returns Witty's feed instead of Ghostty's tip and release appcasts. `auto-update-channel` has no effect. |
| `macos/Ghostty-Info.plist` | `SUFeedURL = $(WITTY_UPDATE_FEED_URL)` and `SUPublicEDKey = $(WITTY_UPDATE_PUBLIC_ED_KEY)` instead of Ghostty's key. Both are empty unless the build sets them. |
| `macos/Sources/App/AppDelegate.swift` | Hides "Check for Updates…" and leaves Sparkle's settings alone while the updater is off. |
| `macos/Sources/Ghostty/Ghostty.Command.swift` | Drops "Check for Updates" from the command palette while the updater is off. |

### Release tooling

All Witty-only files.

| File | What and why |
| --- | --- |
| `macos/scripts/release.sh` | ReleaseFast build, Developer ID signing, DMG, notarization, stapling. Warns when the updater settings are missing. |
| `macos/scripts/package_release.sh` | Re-signs inside-out with a secure timestamp, notarizes and staples app and DMG. A `witty-v*` tag names the DMG `Witty-<version>-macos-<arch>.dmg`. |
| `macos/scripts/lib_signing.sh`, `macos/scripts/test_lib_signing.sh` | Signing identity resolution, certificate expiry checks, notarization, the release asset name, and their tests. |
| `macos/AGENTS.md` | Release prerequisites, pitfalls and settings. |
| `AGENTS.md` | Points at the release script. |
| `.gitignore` | Ignores the DMGs in `dist/`. |

### Fixes not upstream

| File | What and why |
| --- | --- |
| `src/shell-integration/bash/ghostty.bash`, `src/shell-integration/zsh/ghostty-integration`, `src/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish` | Each new prompt turns off mouse tracking left on by a full-screen app that died, such as tmux over a dropped SSH connection. |
| `src/terminal/stream_terminal.zig` | Test for that reset sequence. |
| `macos/Sources/Ghostty/Ghostty.App.swift` | Handles `size_limit` and `quit_timer` explicitly, so they no longer log "unknown action" on every new tab. |
| `macos/Tests/Ghostty/ActionDispatchCoverageTests.swift` | Fails if a core action that is sent unprompted falls into the dispatcher's `default:` branch. |

### Documentation

| File | What and why |
| --- | --- |
| `README.md` | Witty's README; Ghostty's original is kept in a collapsed section. |
| `FORK.md` | This file. |
| `CHANGELOG.md` | Witty's changes on top of upstream. |
| `docs/witty-altscreen.md` | The `altscreen:` prefix and the tmux setup it needs. |
| `LICENSE` | Ghostty's MIT notice unchanged, plus `Copyright (c) 2026 Reality Inc.` for Witty's modifications. |

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
- **`src/extra/vim.zig`** detects the `ghostty` filetype for `*/ghostty/config`
  but not `*/witty/config`. Files named `config.ghostty` are still detected.
- **Upstream's release workflows** (`.github/workflows/release-tag.yml`,
  `release-tip.yml`, `publish-tag.yml`). They publish Ghostty's own builds and
  do not run for Witty: `release-tag.yml` fires on `v1.2.3`-style tags, not
  `witty-v*`; `release-tip.yml` runs only in `ghostty-org`; `publish-tag.yml`
  is manual.
