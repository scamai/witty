# Changelog — witty fork

All notable changes **made by the witty fork on top of upstream Ghostty** are
documented here. Upstream Ghostty changes are not duplicated; see
[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) for those.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [witty-v0.2.0] — 2026-10-17

The first release since witty-v0.1.1, and the first one signed with Reality
Inc.'s Developer ID and notarized by Apple. It also ships the changes listed
under witty-v0.1.3 and witty-v0.1.2, which were never released as builds.

### Changed

- **New app icon: a four-leaf clover on warm paper.** Its four leaves sit in the four quadrants,
  so the gap between them reads as a 2×2 split of terminal panes, and a `>_` prompt sits on the
  top-left leaf. It replaces the violet `W` on upstream's CRT frame. The in-app image and the
  tintable glyph of the custom Dock icon change with it, so no ghost remains in the default
  artwork. `images/witty-icon-src/draw_clover.swift` regenerates every piece.
- **The clover follows macOS icon appearances.** In Dark, the background turns deep forest
  green. In the Clear and Tinted appearances, the prompt becomes a cut-out so it stays legible on
  pale glass.
- **The eight `macos-icon` alternates are clover variants:** blueprint, chalkboard, glass,
  holographic, microchip, paper, retro and xray. They keep upstream's theme names, so existing
  config values still work, and no ghost artwork is left in the macOS app (the Linux icons are still upstream's).
- **Witty now has its own config, state and cache directories**, so it can be
  installed next to Ghostty without either app reading the other's files. The
  config lives in `~/.config/witty/` (was `~/.config/ghostty/`) and, on macOS,
  `~/Library/Application Support/<Witty's bundle ID>/`; crash reports and the
  SSH terminfo cache in `$XDG_STATE_HOME/witty/`; the Sentry cache in
  `$XDG_CACHE_HOME/witty/`. The default `macos-custom-icon` path is now
  `~/.config/witty/Ghostty.icns`.
- **On first launch Witty imports an existing Ghostty config.** If Witty has no
  config file and Ghostty has one, Witty copies Ghostty's config files into its
  own directories, including files pulled in with relative `config-file =`
  includes and the user `themes/` directory. Ghostty's files are only read,
  never changed; an existing Witty file is never overwritten; every copied
  file is logged. Includes given as absolute or `~/` paths are left in place
  and logged. Ghostty's config itself is untouched, so if it includes
  Witty-only `altscreen:` binds, remove that include from
  `~/.config/ghostty/config` by hand to make stock Ghostty validate again.
- **The bundle identifier is now `ai.scam.witty`** (was `dev.shenxingy.witty`),
  with `ai.scam.witty.debug` and `ai.scam.witty-dock-tile` for the debug build
  and the Dock tile plugin. macOS sees this as a new app: privacy grants such
  as Screen Recording and Accessibility have to be given again, and settings
  stored under the old identifier (UserDefaults) do not carry over.

### Fixed

- **"Check for Updates…" no longer offers Ghostty's builds.** The updater
  pointed at Ghostty's tip and release appcasts and trusted Ghostty's EdDSA
  key. The feed URL and key are now Witty build settings
  (`WITTY_UPDATE_FEED_URL`, `WITTY_UPDATE_PUBLIC_ED_KEY`) that default to
  empty, and until a build sets both, the updater is off: it never checks,
  makes no network requests, and the menu item and command palette entry are
  hidden. `auto-update-channel` has no effect, since Witty has one feed.

### Internal

- **A tagged commit builds again.** Upstream's build stops with "tagged
  releases must be in vX.Y.Z format matching build.zig" when the commit carries
  any other tag, which included every `witty-v*` tag. `src/build/GitVersion.zig`
  now skips Witty's tags; they version the app, not the Ghostty core.
- **`package_release.sh` refuses a release whose versions disagree.** For a
  `witty-vX.Y.Z` tag, the app's version must be `X.Y.Z` (`MARKETING_VERSION`
  in the Xcode project) and `CHANGELOG.md` must have a `## [witty-vX.Y.Z]`
  section. The check runs before anything is signed. At the v0.1.0 and v0.1.1
  tags the Xcode project still carried upstream's placeholder version, 0.1 (1).
- **Release assets are named `Witty-<version>-macos-<arch>.dmg`.** When HEAD
  carries a `witty-v*` tag (or `WITTY_RELEASE_TAG` names one),
  `macos/scripts/package_release.sh` writes `dist/Witty-v0.1.4-macos-universal.dmg`
  instead of `dist/Witty.dmg`, with the architecture read from the app binary.
  The earlier `Ghostty-witty-v0.1.1-macos-arm64.zip` was packaged outside this
  repository: no script or workflow in its history produces that name.

### Docs

- Witty is an independent open-source project of Reality Inc., not affiliated
  with or endorsed by the Ghostty project. `LICENSE` keeps Ghostty's copyright
  notice unchanged and adds `Copyright (c) 2026 Reality Inc.` for Witty's
  modifications; the README says so and explains that Witty and Ghostty can be
  installed side by side.
- [`FORK.md`](FORK.md) lists every file where Witty differs from upstream
  Ghostty and why, with the rules an upstream merge must follow.

## [witty-v0.1.3] — 2026-09-19

_Never tagged or released as a build; these changes first shipped in
[witty-v0.2.0]._

Synced with upstream Ghostty at `b32f20f3e` (2026-09-19) — 793 commits since
the previous fork point (`94d775fef`, 2026-08-10), including the Kitty
clipboard protocol on macOS (OSC 52 writes, `?5522` paste events, permission
prompts, `ghostty_terminal_paste`), a terminal search C API
(`ghostty_search_*`), Kitty graphics fixes, a DECRPM report refactor (full
u16 query range), a bash shell-integration upgrade (bash-preexec 0.7.0), and
a `scrollback-pull-on-resize` option. See
[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) for details.

### Changed

- **Witty now has its own bundle identifier: `dev.shenxingy.witty`** (plus
  `-dock-tile` / `.debug` variants). This supersedes v0.1.2's note that the
  bundle ID was intentionally left as `com.mitchellh.ghostty` — ad-hoc signing
  meant every rebuild got a new cdhash and macOS silently revoked granted
  permissions (Screen Recording, Accessibility, ...). A stable bundle ID plus
  a named signing identity fix that. Set `WITTY_CODE_SIGN_IDENTITY` (build)
  or `$(WITTY_CODE_SIGN_IDENTITY)` (Xcode) to your signing identity; it
  defaults to ad-hoc signing (`-`) exactly as before. The config directory
  (`~/.config/ghostty`) and the `ghostty` CLI are still unchanged.
- Builds against Zig 0.16 (matching upstream's pinned toolchain).

### Internal

- **The `tmux_active` (`?8771`) bit moved from 42 to 43.** Upstream added
  `kitty_paste_events` (`?5522`) to the mode registry ahead of it. The binary
  snapshot's stable mode registry was widened accordingly (`u42` → `u43`) so
  upstream modes round-trip while witty's transient `tmux_active` stays
  excluded from snapshots (it must be re-announced by the live tmux client
  after restore).
- Witty branding (product name, bundle IDs, display names, signing, violet
  icon) was re-applied onto upstream's restructured Xcode project — upstream
  dropped the iOS app target and the file-system-synchronized exception list
  in this window, so the project file was taken from upstream and the Witty
  deltas replayed on top.

### Fixed

- **The macOS unit-test gate (`macos/build.nu --action test`, or the
  `xcodebuild test` step inside `zig build test`) works again.** It had been
  broken since the Witty.app rename: `TEST_HOST` in the Xcode project and the
  shared scheme's `BuildableName` still pointed at `Ghostty.app`, and — once
  the host resolved — the test target failed with "Unable to resolve module
  dependency: 'Ghostty'" because renaming `PRODUCT_NAME` to `Witty` also
  renamed the app target's Swift module out from under the tests'
  `@testable import Ghostty`. The scheme/`TEST_HOST` now reference
  `Witty.app` (the executable inside stays `ghostty`, per the target's
  explicit `EXECUTABLE_NAME`), and the app target sets
  `PRODUCT_MODULE_NAME = Ghostty` so its Swift module keeps its upstream name
  while the product is Witty.app.

## [witty-v0.1.2] — 2026-06-29

_Tagged, but no build was released; these changes first shipped in
[witty-v0.2.0]._

Synced with upstream Ghostty at `28f9367be` (2026-06-29) — 29 commits since the
previous fork point, including a GTK dbus-connection crash fix, a macOS
notification retain-cycle fix, a `PageList.scroll` row-offset type fix, a
macOS 27 tabs-frame fix, and the new `gtk-horizontal-tab-scroll` option. None of
the witty altscreen/`?8771` logic was touched by the merge.

### Added

- **witty now ships its own app identity.** The macOS app presents as **Witty**
  — menu bar, Dock, About, Finder, and the "New Witty Tab/Window Here" service
  menus — with a custom violet **W** app icon, instead of masquerading as
  Ghostty. The bundle identifier (`com.mitchellh.ghostty`), config directory
  (`~/.config/ghostty`), and the `ghostty` CLI are intentionally unchanged, so
  your existing config carries over and upstream merges stay trivial. The icon
  reuses Ghostty's Icon Composer frame with a witty glyph + violet colorway
  (source in `images/witty-icon-src/`).
- **`altscreen:` keybinds now require *real* tmux, not just the alternate
  screen.** The alternate screen is shared by tmux, Neovim, `less`, `htop`,
  Claude Code, and every other fullscreen TUI, so firing tmux control bytes at
  all of them was wrong (e.g. `cmd+ctrl+=` leaking `C-b E` into Neovim). An
  `altscreen:` binding now fires only when the terminal is on the alternate
  screen **AND** a private DEC mode, **`?8771`** (`tmux_active`), is set. tmux
  announces itself by setting `?8771` from the shell prompt (through its
  passthrough); witty clears it on every alternate-screen transition so a stale
  value can't leak into the next TUI. If you don't set up the signal, the
  `altscreen:` keys simply never fire and every key keeps its normal binding —
  a safe, opt-in default. See
  [`docs/witty-altscreen.md`](docs/witty-altscreen.md#gating-on-real-tmux-not-just-the-alternate-screen)
  for the one-time `~/.tmux.conf` + shell setup.

### Fixed

- **`?8771` is re-armed on tmux *re-attach*.** witty clears the signal when the
  outer terminal enters the alternate screen, which a tmux client does on every
  attach. With `tmux new -As <name>` re-attaching to an existing session, the
  inner shell stays at its already-drawn prompt, so the per-prompt shell hook
  never re-fires and the `altscreen:` keybinds went dead until the next Enter.
  The documented setup now adds a tmux `client-attached` hook that re-emits
  `?8771h` straight to the attaching client's tty on every attach (raw, not
  passthrough-wrapped, since it bypasses tmux; it fires after tmux's smcup so it
  survives the enter-screen clear).
- **`?8771` is cleared on alternate-screen *entry* too, not only exit.** A
  stale or spoofed `?8771h` set while on the primary screen can no longer leak
  into a non-tmux fullscreen app launched directly (vim/less/Claude Code over
  plain SSH). Real tmux re-asserts the signal right after entry, so the gate
  re-arms on its own.
- **App-scope keybinds are looked up with `altscreen=false` so the tmux gate
  isn't bypassed.** Otherwise an app-scope lookup could match an `altscreen:`
  binding without the gate, firing tmux bytes outside tmux.
- **Stuck mouse tracking is cleared at each new shell prompt.** A fullscreen
  program that exited without disabling mouse reporting no longer leaves the
  shell in a state where clicks emit escape sequences.

### Docs

- Documented the `?8771` (`tmux_active`) gating, the `~/.tmux.conf` +
  shell-prompt setup, and the `client-attached` re-attach hook in
  [`docs/witty-altscreen.md`](docs/witty-altscreen.md), and folded the signal
  setup into the README's recommended remote-tmux workflow.

## [witty-v0.1.1] — 2026-06-19

### Fixed

- **`cmd+left` now jumps to the start of the line inside tmux.** It used to send
  C-a (`0x01`), which collides with a `C-a` tmux prefix and gets swallowed
  before reaching the shell. On the alternate screen it now sends Home
  (`CSI H`), which is independent of whatever tmux prefix is configured and is
  still "beginning of line" in readline/zle. On the primary screen it still
  falls back to C-a. (`cmd+right`/`cmd+backspace`/`alt+left`/`alt+right` were
  unaffected — they don't use the prefix byte.)

### Docs

- Added a "Recommended workflow" (persistent remote dev over ssh + tmux) and a
  "Platform support" section (including Windows) to the README.
- Clarified that the `cmd+ctrl+=` default is prefix-*dependent* (targets the
  C-b default prefix) and documented the one-line override for other prefixes
  such as `C-a`.

### Internal

- `cmd+ctrl+=` is now encoded as the escaped `\x02E` form to match the
  surrounding natural-text-editing bindings (identical bytes on the wire).

## [witty-v0.1.0] — 2026-06-19

Forked from upstream Ghostty at `49a91815`.

### Added

- **`altscreen:` keybind prefix.** Gate any keybinding to the terminal's
  alternate screen. On the primary screen the lookup falls back to whatever the
  key was already bound to, so the prefix overlays behavior rather than
  replacing it. See [`docs/witty-altscreen.md`](docs/witty-altscreen.md).
- **Default macOS `cmd+ctrl+=`.** `equalize_splits` on the primary screen;
  sends tmux `C-b E` (`select-layout -E`) to even out tmux panes on the
  alternate screen, where Ghostty can't resize tmux-owned panes.

### Fixed

- **Atomic-safe tmux sequence.** `cmd+ctrl+=` now sends `\x02E` (prefix + key)
  instead of `\x02:select-layout -E\r` (command prompt). Ghostty delivers a
  `text:` action as a single atomic pty write, which tmux's command prompt
  drops; the key-binding path handles it reliably. Verified end-to-end against
  real tmux (2-, 3-, and 4-pane layouts even out).
- **macOS menu key equivalents.** Altscreen-gated bindings are no longer
  dispatched to macOS menu key equivalents.
- **Trigger-chain continuation.** A non-matching altscreen gate continues the
  trigger lookup chain instead of aborting it, so the primary-screen fallback
  resolves correctly.
- **Key-table stack.** The key-table stack stores `Set` pointers directly
  rather than taking the address of a temporary.

### Commits

```
26a47fe fix(input): altscreen cmd+ctrl+= sends tmux prefix-E (atomic-safe), not command-prompt
9271e18 feat(input): altscreen cmd+ctrl+= sends tmux even-out, falls back to equalize_splits
9c3c459 fix(macos): don't dispatch altscreen-gated bindings to menu key equivalents
d972d63 fix(input): altscreen gate continues the trigger chain instead of aborting lookup
1805adb fix(surface): key table stack stores Set pointers — don't take their address
15e4d78 feat(input): altscreen bindings fall back to the replaced binding on primary screen
8103116 feat(input): add altscreen: keybind prefix
```

[witty-v0.2.0]: https://github.com/scamai/witty/releases/tag/witty-v0.2.0
[witty-v0.1.1]: https://github.com/scamai/witty/releases/tag/witty-v0.1.1
[witty-v0.1.0]: https://github.com/scamai/witty/releases/tag/witty-v0.1.0
