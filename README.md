<!-- LOGO -->
<h1 align="center">witty</h1>

<p align="center">
  A <a href="https://github.com/ghostty-org/ghostty">Ghostty</a> fork with
  <b>altscreen-aware keybindings</b>.
  <br />
  Bind one key to do one thing normally — and something else the moment a
  fullscreen TUI (tmux, Neovim, less) takes over the screen.
</p>

<p align="center">
  <a href="#what-witty-adds">What witty adds</a>
  ·
  <a href="#quick-example">Quick example</a>
  ·
  <a href="docs/witty-altscreen.md">Docs</a>
  ·
  <a href="#install">Install</a>
  ·
  <a href="#built-on-ghostty">Upstream</a>
</p>

---

witty is [Ghostty](https://github.com/ghostty-org/ghostty) — the fast, native,
feature-rich terminal emulator — plus **one** focused addition: the
`altscreen:` keybind prefix. Everything else is stock Ghostty, merged from
upstream regularly. If you don't use the new prefix, witty behaves exactly like
Ghostty.

## Contents

- [What witty adds](#what-witty-adds)
- [Quick example](#quick-example)
- [How it works](#how-it-works)
- [Recommended workflow: persistent remote dev](#recommended-workflow-persistent-remote-dev)
- [Install](#install)
- [Platform support](#platform-support)
- [Built on Ghostty](#built-on-ghostty)
- [License](#license)

## What witty adds

A terminal has two screens: the **primary** screen (your shell, scrollback) and
the **alternate** screen, which fullscreen programs like tmux, Neovim, `less`,
or `htop` switch to while running. witty lets a single keybinding behave
differently depending on which one is active.

| Addition | What it does |
| --- | --- |
| **`altscreen:` keybind prefix** | Gate any binding to the **alternate screen** only. On the primary screen the lookup falls back to whatever that key was bound to before, so you lose nothing. |
| **Default `cmd+ctrl+=` (macOS)** | On the primary screen: `equalize_splits` (balance Ghostty's own splits). On the alternate screen: send tmux `C-b E` (`select-layout -E`) so the **tmux panes** get evened out instead — because Ghostty can't resize panes that belong to tmux. |
| **Default `cmd+left` (macOS)** | Jump to the start of the line. On the alternate screen it sends **Home** (`CSI H`) instead of C-a, so it isn't swallowed by a `C-a` tmux prefix — `cmd+left` works the same inside tmux as at a bare shell. |

## Quick example

```ini
# ~/.config/witty/config

# ctrl+r reloads the config on the normal screen,
# but enters tmux copy-mode (C-b [) when tmux is in the foreground:
keybind = ctrl+r=reload_config
keybind = altscreen:ctrl+r=text:\x02[

# The macOS default that ships with witty — one key, two behaviors:
keybind = super+ctrl+equal=equalize_splits
keybind = altscreen:super+ctrl+equal=text:\x02E   # C-b E → even out tmux panes
```

`\x02` is tmux's default prefix (`C-b`). See
**[docs/witty-altscreen.md](docs/witty-altscreen.md)** for the full syntax,
fallback rules, the why-not-`:select-layout` story, and caveats (custom tmux
prefixes, non-tmux fullscreen apps).

## How it works

The `altscreen:` prefix registers a binding on a separate, alternate-screen key
table. On a key event, witty first consults that table when the terminal is on
the alternate screen; if there's no match (or you're on the primary screen) it
continues the normal lookup chain and falls back to the binding the key already
had. The prefix never *adds* a key — it overlays behavior on a key you've
already bound, which is what makes the tmux/non-tmux split clean.

Full design notes, fallback semantics, and edge cases live in
**[docs/witty-altscreen.md](docs/witty-altscreen.md)**.

## Recommended workflow: persistent remote dev

witty's altscreen bindings pay off most in a remote, persistent setup: keep the
real work in **tmux on a server** and treat the local terminal as a disposable,
reconnectable view.

1. **SSH in and attach tmux** — the session lives on the server, not your laptop:

   ```sh
   ssh myserver -t 'tmux new -A -s main'
   ```

   `new -A -s main` attaches the `main` session if it exists, otherwise creates
   it. Close the lid, drop Wi-Fi, or quit witty — the session and everything
   running in it survive. Run the same command to reconnect and you're back
   exactly where you left off.

2. **Split panes and run Claude Code per pane** — split with witty's native
   gestures, which keep working even while Claude or tmux owns the altscreen:

   ```
   cmd+d         split right
   cmd+shift+d   split down
   cmd+ctrl+=    equalize panes
   cmd+w         close the pane
   ```

   In each new pane, repeat the SSH + attach from step 1 with its own session
   name (`agent2`, `agent3`, …) and run `claude`. Each pane is an independent
   agent you can glance across — the split grid is local, so you rebuild it on
   reconnect, but every agent keeps running server-side and re-attaching drops
   you right back in.

3. **Keep shortcuts consistent** — point tmux's pane keys at the same gestures
   you use in Ghostty, and let witty's altscreen bindings cover the keys tmux
   would otherwise swallow. A minimal `~/.tmux.conf`:

   ```tmux
   # screen-style prefix (closer to the home row)
   set -g prefix C-a
   unbind C-b
   bind C-a send-prefix

   # Ghostty-like pane navigation: Shift+Alt+arrow, no prefix needed
   bind -n M-S-Left  select-pane -L
   bind -n M-S-Right select-pane -R
   bind -n M-S-Up    select-pane -U
   bind -n M-S-Down  select-pane -D

   # modern key reporting so Ghostty's modified keys arrive intact
   set -s extended-keys always

   # tell witty a real tmux is live so altscreen: keybinds fire, and re-arm that
   # signal on every (re)attach — step 1's `tmux new -A` re-attaches an existing
   # session without redrawing a prompt, which would otherwise leave the keys dead
   set -g allow-passthrough on
   set-hook -g client-attached 'run-shell -b "printf \"\\033[?8771h\" > #{client_tty}"'
   ```

   Pair the tmux config above with the matching **per-prompt shell signal** (a
   few lines in `~/.zshrc`/`~/.bashrc`) — see
   [docs/witty-altscreen.md](docs/witty-altscreen.md#setting-the-signal-from-your-shell).
   Without the signal, the `altscreen:` keybinds never fire and every key keeps
   its normal binding (a safe, opt-in default).

   `cmd+left` already works under **any** prefix — on the alternate screen witty
   sends **Home** (`CSI H`), which no tmux prefix can intercept.

   `cmd+ctrl+=` is different: "even out panes" *must* go through the tmux prefix,
   and the shipped default targets tmux's **default** prefix (`C-b`). With the
   `C-a` prefix above, the default `C-b E` never reaches tmux — add one line to
   your Witty config to retarget it (and any other prefix-based keys) at `C-a`:

   ```ini
   # ~/.config/witty/config — use C-a (0x01) instead of the C-b default
   keybind = altscreen:super+ctrl+equal=text:\x01E   # C-a E → even tmux panes
   ```

   See [docs/witty-altscreen.md](docs/witty-altscreen.md) for the prefix caveat
   and more bindings you can mirror this way. Same muscle memory whether or not
   tmux is in the loop.

## Install

witty is currently macOS-focused (the shipped default binding is macOS). Linux
(GTK) builds the same way as upstream Ghostty.

**Prebuilt macOS app** — grab the latest `Witty.app` (Apple Silicon,
ad-hoc signed) from the [Releases](https://github.com/shenxingy/witty/releases)
page, unzip, and drop it into `/Applications`. (The app installs the same
`ghostty` CLI but reads its own config, `~/.config/witty/config`. On first
launch it copies an existing Ghostty config there, so your setup carries
over.)

**Build from source** — requires [Zig](https://ziglang.org) `0.15.2` (see
`.zig-version` / `minimum_zig_version` in `build.zig.zon`):

```sh
# core build (and the underlying library)
zig build

# run the test suite (prefer a filter; the full suite is slow)
zig build test -Dtest-filter="<name>"
```

macOS app bundle (needs Xcode + gettext on `PATH` for `msgfmt`):

```sh
# 1) rebuild the xcframework with your changes
zig build -Demit-xcframework=true -Demit-macos-app=false -Dapp-runtime=none -Doptimize=ReleaseFast
# 2) build the app
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal SYMROOT="$PWD/macos/build" build
# -> macos/build/ReleaseLocal/Ghostty.app
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`HACKING.md`](HACKING.md) (from
upstream) for the full developer workflow.

## Platform support

| Platform | witty app | Notes |
| --- | --- | --- |
| **macOS** (Apple Silicon) | ✅ | Primary target. The shipped altscreen defaults are macOS keybinds. |
| **Linux** (GTK) | ✅ | Builds like upstream Ghostty. The `altscreen:` prefix works; no default binding uses it, so add your own. |
| **Windows** | ❌ no app | Ghostty/witty have **no native Windows application** — the GUI runtimes are GTK (Linux) and SwiftUI (macOS) only. The core `libghostty` / `libghostty-vt` engine *does* compile for Windows (with ConPTY support) and can be embedded, but there is no `witty.exe` to run. |

**On Windows?** The [recommended workflow](#recommended-workflow-persistent-remote-dev)
above still works — the real session lives in **tmux on a Linux server**, and the
local terminal is just an SSH client. Use **Windows Terminal** or a **WSL** shell
to `ssh` in and `tmux attach`. You won't get witty's altscreen keybindings
locally (those are a witty feature), but you can reproduce the important ones as
Windows Terminal or tmux bindings. Everything server-side — panes, Claude Code,
reconnect-after-disconnect — is identical.

## Built on Ghostty

witty is a fork of **[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)**
by Mitchell Hashimoto and the Ghostty contributors. All of Ghostty's
documentation, downloads, and terminal behavior apply unchanged:

- 🌐 Website & downloads: <https://ghostty.org>
- 📚 Documentation: <https://ghostty.org/docs>
- 💬 About Ghostty: <https://ghostty.org/docs/about>

The complete original project README is preserved below.

<details>
<summary><b>Original Ghostty README</b></summary>

## About

Ghostty is a terminal emulator that differentiates itself by being
fast, feature-rich, and native. While there are many excellent terminal
emulators available, they all force you to choose between speed,
features, or native UIs. Ghostty provides all three.

**`libghostty`** is a cross-platform, zero-dependency C and Zig library
for building terminal emulators or utilizing terminal functionality
(such as style parsing). Anyone can use `libghostty` to build a terminal
emulator or embed a terminal into their own applications. See
[Ghostling](https://github.com/ghostty-org/ghostling) for a minimal complete project
example or the [`examples` directory](https://github.com/ghostty-org/ghostty/tree/main/example)
for smaller examples of using `libghostty` in C and Zig.

For more details, see [About Ghostty](https://ghostty.org/docs/about).

### Download

See the [download page](https://ghostty.org/download) on the Ghostty website.

### Documentation

See the [documentation](https://ghostty.org/docs) on the Ghostty website.

### Contributing and Developing

If you have any ideas, issues, etc. regarding Ghostty, or would like to
contribute to Ghostty through pull requests, please check out our
["Contributing to Ghostty"](CONTRIBUTING.md) document. Those who would like
to get involved with Ghostty's development as well should also read the
["Developing Ghostty"](HACKING.md) document for more technical details.

### Roadmap and Status

Ghostty is stable and in use by millions of people and machines daily.

The high-level ambitious plan for the project, in order:

|  #  | Step                                                    | Status |
| :-: | ------------------------------------------------------- | :----: |
|  1  | Standards-compliant terminal emulation                  |   ✅   |
|  2  | Competitive performance                                 |   ✅   |
|  3  | Rich windowing features -- multi-window, tabbing, panes |   ✅   |
|  4  | Native Platform Experiences                             |   ✅   |
|  5  | Cross-platform `libghostty` for Embeddable Terminals    |   ✅   |
|  6  | Ghostty-only Terminal Control Sequences                 |   ❌   |

For the full roadmap detail, crash-reporter docs, and everything else, see the
upstream README at
[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty#readme).

</details>

## License

Same as upstream Ghostty — see [LICENSE](LICENSE) (MIT).
