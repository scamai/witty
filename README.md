<p align="center">
  <img src="macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-256px-128pt@2x.png" width="128" alt="The Witty icon: a four-leaf clover on warm paper" />
</p>

<h1 align="center">Witty</h1>

<p align="center">
  A <a href="https://github.com/ghostty-org/ghostty">Ghostty</a> fork with
  <b>altscreen-aware keybindings</b>.
  <br />
  Bind one key to do one thing normally — and something else the moment a
  fullscreen TUI (tmux, Neovim, less) takes over the screen.
</p>

<p align="center">
  <a href="#install">Install</a>
  ·
  <a href="#what-witty-adds">What Witty adds</a>
  ·
  <a href="#quick-example">Quick example</a>
  ·
  <a href="docs/witty-altscreen.md">Docs</a>
  ·
  <a href="https://github.com/scamai/witty/releases">Releases</a>
</p>

---

Witty is [Ghostty](https://github.com/ghostty-org/ghostty) — the fast, native,
feature-rich terminal emulator — plus one feature: the `altscreen:` keybind
prefix. It also has what a separately installed app needs: its own name, icon,
bundle identifier, config directory and signature. Everything else is Ghostty,
merged from upstream regularly; [FORK.md](FORK.md) lists every difference. If
you don't use the new prefix, Witty behaves like Ghostty.

Witty is an independent open-source project of Reality Inc. It is not
affiliated with or endorsed by the Ghostty project.

## Contents

- [Install](#install)
  - [Upgrading from v0.1.x](#upgrading-from-v01x)
  - [Next to Ghostty](#next-to-ghostty)
  - [Build from source](#build-from-source)
- [What Witty adds](#what-witty-adds)
- [Quick example](#quick-example)
- [How it works](#how-it-works)
- [Recommended workflow: persistent remote dev](#recommended-workflow-persistent-remote-dev)
- [Platform support](#platform-support)
- [Built on Ghostty](#built-on-ghostty)
- [License](#license)

## Install

Witty needs macOS 13 or later, on Apple silicon or Intel. Download the latest
`Witty-<version>-macos-<arch>.dmg` from
[Releases](https://github.com/scamai/witty/releases), open it and drag Witty to
Applications. From v0.2.0 on, releases are signed with Reality Inc.'s
Developer ID and notarized by Apple, so they open like any other downloaded
app.

On first launch Witty copies your Ghostty config, if you have one, to
`~/.config/witty/config`. Ghostty's files are only read, never changed. The
command-line tool inside the app keeps Ghostty's name, `ghostty`.

### Upgrading from v0.1.x

v0.1.0 and v0.1.1 were zip files whose app was named `Ghostty.app` and used
Ghostty's bundle identifier, so macOS cannot tell them apart from Ghostty.
After installing Witty:

1. Open `/Applications/Ghostty.app` and choose **Ghostty → About Ghostty**. If
   the version is **0.1**, it is the old Witty: quit it and move it to the
   Trash. Any other version is the real Ghostty; keep it if you use it.
2. Grant Witty again whatever you had allowed the old app, such as
   Accessibility, Screen Recording or notifications. macOS treats Witty as a
   new app.

Your config comes along: the old build read `~/.config/ghostty`, which Witty
imports on its first launch.

### Next to Ghostty

Witty and Ghostty can be installed side by side. Each has its own bundle
identifier and config directories (`~/.config/witty` and
`~/Library/Application Support/ai.scam.witty` for Witty, `~/.config/ghostty`
and `~/Library/Application Support/com.mitchellh.ghostty` for Ghostty), so
Witty-only settings such as `altscreen:` binds never reach Ghostty.

### Build from source

You need [Zig](https://ziglang.org) 0.16.0 or later (`minimum_zig_version` in
`build.zig.zon`) and, for the macOS app, Xcode and gettext (`msgfmt`) on
`PATH`.

```sh
zig build -Doptimize=ReleaseFast        # on macOS: macos/build/ReleaseLocal/Witty.app
zig build run                           # build a debug app and launch it
zig build test -Dtest-filter="<name>"   # prefer a filter; the full suite is slow
```

`macos/scripts/release.sh` makes the signed, notarized DMG; its prerequisites
are in [`macos/AGENTS.md`](macos/AGENTS.md). Upstream's
[`CONTRIBUTING.md`](CONTRIBUTING.md) and [`HACKING.md`](HACKING.md) cover the
rest of the developer workflow.

## What Witty adds

A terminal has two screens: the **primary** screen (your shell, scrollback) and
the **alternate** screen, which fullscreen programs like tmux, Neovim, `less`,
or `htop` switch to while running. Witty lets a single keybinding behave
differently depending on which one is active.

| Addition | What it does |
| --- | --- |
| **`altscreen:` keybind prefix** | Gate any binding to the **alternate screen** only. On the primary screen the lookup falls back to whatever that key was bound to before, so you lose nothing. |
| **Default `cmd+ctrl+=` (macOS)** | On the primary screen: `equalize_splits` (balance Witty's own splits). On the alternate screen: send tmux `C-b E` (`select-layout -E`) so the **tmux panes** get evened out instead — because the terminal can't resize panes that belong to tmux. |
| **Default `cmd+left` (macOS)** | Jump to the start of the line. On the alternate screen it sends **Home** (`CSI H`) instead of C-a, so it isn't swallowed by a `C-a` tmux prefix — `cmd+left` works the same inside tmux as at a bare shell. |

## Quick example

```ini
# ~/.config/witty/config

# ctrl+r reloads the config on the normal screen,
# but enters tmux copy-mode (C-b [) when tmux is in the foreground:
keybind = ctrl+r=reload_config
keybind = altscreen:ctrl+r=text:\x02[

# The macOS default that ships with Witty — one key, two behaviors:
keybind = super+ctrl+equal=equalize_splits
keybind = altscreen:super+ctrl+equal=text:\x02E   # C-b E → even out tmux panes
```

`\x02` is tmux's default prefix (`C-b`). See
**[docs/witty-altscreen.md](docs/witty-altscreen.md)** for the full syntax,
fallback rules, the why-not-`:select-layout` story, and caveats (custom tmux
prefixes, non-tmux fullscreen apps).

## How it works

The `altscreen:` prefix registers a binding on a separate, alternate-screen key
table. On a key event, Witty first consults that table when the terminal is on
the alternate screen; if there's no match (or you're on the primary screen) it
continues the normal lookup chain and falls back to the binding the key already
had. The prefix never *adds* a key — it overlays behavior on a key you've
already bound, which is what makes the tmux/non-tmux split clean.

A binding fires only while a real tmux has said it is attached, not on every
alternate screen, so Neovim or `less` running outside tmux keep the key's
normal binding. Full design notes, fallback semantics, and edge cases live in
**[docs/witty-altscreen.md](docs/witty-altscreen.md)**.

## Recommended workflow: persistent remote dev

Witty's altscreen bindings pay off most when the real work lives in **tmux on a
server** and the local terminal is a disposable view you can reconnect:

```sh
ssh myserver -t 'tmux new -A -s main'
```

`new -A -s main` attaches the `main` session, or creates it. Close the lid,
drop Wi-Fi or quit Witty, and everything keeps running; the same command picks
up where you left off. Split with Witty's own keys (`cmd+d`, `cmd+shift+d`,
`cmd+ctrl+=` to equalize, `cmd+w`), attach a session per pane, and run an agent
such as Claude Code in each.

[docs/witty-remote-workflow.md](docs/witty-remote-workflow.md) walks through the
whole setup: the `~/.tmux.conf` that tells Witty tmux is running, pane keys
that match Witty's, and the one-line change `cmd+ctrl+=` needs when your tmux
prefix is `C-a`.

## Platform support

| Platform | Witty app | Notes |
| --- | --- | --- |
| **macOS** 13 or later | ✅ | Primary target; releases are universal (Apple silicon and Intel). The shipped altscreen defaults are macOS keybinds. |
| **Linux** (GTK) | ✅ from source | Builds like upstream Ghostty; no packages are published. The `altscreen:` prefix works; no default binding uses it, so add your own. The GTK app still uses Ghostty's application ID, so don't install it next to Ghostty ([FORK.md](FORK.md#deliberately-not-changed)). |
| **Windows** | ❌ no app | Ghostty and Witty have **no native Windows application** — the GUI runtimes are GTK (Linux) and SwiftUI (macOS) only. The core `libghostty` / `libghostty-vt` engine *does* compile for Windows (with ConPTY support) and can be embedded, but there is no `witty.exe` to run. |

**On Windows?** The [recommended workflow](#recommended-workflow-persistent-remote-dev)
still works — the real session lives in **tmux on a Linux server**, and the
local terminal is just an SSH client. Use **Windows Terminal** or a **WSL** shell
to `ssh` in and `tmux attach`. You won't get Witty's altscreen keybindings
locally, but you can reproduce the important ones as Windows Terminal or tmux
bindings. Everything server-side — panes, Claude Code,
reconnect-after-disconnect — is identical.

## Built on Ghostty

Witty is an independent fork of
**[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)** by Mitchell
Hashimoto and the Ghostty contributors, maintained by Reality Inc. What Witty
changes, and why, is listed in [FORK.md](FORK.md). Ghostty's documentation and
terminal behavior otherwise apply unchanged:

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

MIT, the same as upstream Ghostty — see [LICENSE](LICENSE). It keeps Ghostty's
copyright notice and adds Reality Inc.'s for Witty's modifications.
