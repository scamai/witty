# Installing Witty

[← Back to README](../README.md)

Getting Witty onto a Mac, running it next to Ghostty, upgrading from the first
releases, other platforms, and building from source. The tmux setup that
switches on Witty's `altscreen:` keys is in the README's
[Quick start](../README.md#quick-start).

## Contents

- [Download](#download)
- [First launch and your Ghostty config](#first-launch-and-your-ghostty-config)
- [Next to Ghostty](#next-to-ghostty)
- [Updates and privacy](#updates-and-privacy)
- [The `ghostty` command-line tool](#the-ghostty-command-line-tool)
- [Upgrading from v0.1.x](#upgrading-from-v01x)
- [Platform support](#platform-support)
- [Build from source](#build-from-source)

## Download

Witty needs macOS 13 or later. Each release on
[GitHub Releases](https://github.com/scamai/witty/releases/latest) from v0.2.0
on has one universal DMG for Apple silicon and Intel, named
`Witty-v<version>-macos-universal.dmg`. Open it and drag Witty into your
Applications folder, for example onto **Applications** in the Finder sidebar.

The release notes of v0.2.0 and v0.2.1 give the DMG's SHA-256. To check your
download, compare it with the output of
`shasum -a 256 Witty-v<version>-macos-universal.dmg`.

From v0.2.0 on, releases are signed with Reality Inc.'s Developer ID and
notarized by Apple; the v0.2.0 release notes record that the
`xattr -dr com.apple.quarantine` step v0.1.x needed is gone. v0.1.0 and v0.1.1
were not signed with a Developer ID or notarized; see
[Upgrading from v0.1.x](#upgrading-from-v01x).

## First launch and your Ghostty config

If Witty has no config file yet and Ghostty has one, Witty copies Ghostty's on
first launch, keeping the file names (`config`, `config.ghostty`):

| From (Ghostty)                                         | To (Witty)                                     |
| ------------------------------------------------------ | ---------------------------------------------- |
| `~/.config/ghostty/`                                   | `~/.config/witty/`                             |
| `~/Library/Application Support/com.mitchellh.ghostty/` | `~/Library/Application Support/ai.scam.witty/` |

Files pulled in with relative `config-file` includes, and your `themes/`
folder, come along. Includes given as absolute or `~/` paths stay where they
are, and Witty logs each one. The copy happens once. It never changes
Ghostty's files and never overwrites Witty's, and later edits to Ghostty's
config don't carry over.

With no Ghostty config, Witty writes its starter config to
`~/Library/Application Support/ai.scam.witty/config.ghostty`.

Press `cmd+,` to open your config and `cmd+shift+,` to reload it. Witty loads
`~/.config/witty/config`, then `~/.config/witty/config.ghostty` (under
`$XDG_CONFIG_HOME` if you set it), then, on macOS, the same two names in
`~/Library/Application Support/ai.scam.witty/`.

macOS treats Witty as a new app, so grant it again anything you allowed your
previous terminal, such as Accessibility or Screen Recording. To make Witty
your default terminal, choose **Witty → Make Witty the Default Terminal**.

## Next to Ghostty

Witty and Ghostty install side by side on macOS:

|                | Witty                                                              | Ghostty                                                                      |
| -------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| Bundle ID      | `ai.scam.witty`                                                    | `com.mitchellh.ghostty`                                                      |
| Config folders | `~/.config/witty/`, `~/Library/Application Support/ai.scam.witty/` | `~/.config/ghostty/`, `~/Library/Application Support/com.mitchellh.ghostty/` |

Because the config folders are separate, Witty-only settings such as
`altscreen:` binds stay out of Ghostty, whose config validation would reject
them, unless you put them in a file both configs include by absolute or `~/`
path. State, caches and crash reports are separate too.

Ghostty's [documentation](https://ghostty.org/docs) applies to Witty's
terminal, config options and keybinds, except `altscreen:`, updates and
installation. Where it says `~/.config/ghostty` or `com.mitchellh.ghostty`,
Witty uses `~/.config/witty` and `ai.scam.witty`.

## Updates and privacy

Witty doesn't update itself yet. Its updater stays off until Witty has an
update feed of its own, so it makes no update checks and **Check for
Updates…** is hidden. New versions appear on
[Releases](https://github.com/scamai/witty/releases); on GitHub,
**Watch → Custom → Releases** tells you when one is out. To update, download
the new DMG and replace the app in Applications. There is no Homebrew cask.

Crash reports stay on your machine, in `$XDG_STATE_HOME/witty/crash`.

## The `ghostty` command-line tool

The command-line tool inside the app keeps Ghostty's name:
`/Applications/Witty.app/Contents/MacOS/ghostty`. Inside Witty, `ghostty` is
already on your `PATH`: Witty appends that folder to the `PATH` of every shell
it starts, and its shell integration adds it back if your shell config resets
`PATH`. In other terminals, call it by its full path. The tool's help says
`open -na Witty.app`. Some of its built-in help and man pages still say
`~/.config/ghostty`; Witty reads the folders
[above](#first-launch-and-your-ghostty-config).

Witty also keeps `TERM=xterm-ghostty` and the `GHOSTTY_*` environment
variables, so remote hosts need the same terminfo entry as for Ghostty. If
tmux or another program on a server reports
`missing or unsuitable terminal: xterm-ghostty`, copy the entry once from a
Witty window: `infocmp -x xterm-ghostty | ssh myserver -- tic -x -` (on
macOS 13, use Homebrew's ncurses `infocmp`; see Ghostty's
[terminfo help](https://ghostty.org/docs/help/terminfo)).

## Upgrading from v0.1.x

v0.1.0 and v0.1.1 were zip files whose app was named `Ghostty.app` and used
Ghostty's bundle identifier, so macOS cannot tell them apart from Ghostty.
After [installing the current Witty](../README.md#install):

1. Open `/Applications/Ghostty.app` and choose **Ghostty → About Ghostty**. If
   the version is **0.1**, it is either the old Witty or a Ghostty you built
   yourself from source, which reports 0.1 too. If you didn't build Ghostty
   yourself, it is the old Witty: quit it and move it to the Trash. Any other
   version is the real Ghostty; keep it if you use it.
2. Grant Witty again whatever you had allowed the old app, such as
   Accessibility, Screen Recording or notifications. macOS treats Witty as a
   new app, and settings stored under the old app's identifier do not carry
   over.

Your config comes along: the old build read `~/.config/ghostty`, which Witty
imports on its first launch.

**If you still use Ghostty:** Witty never edits Ghostty's config. If your
`~/.config/ghostty/config` (or a file it includes) still contains `altscreen:`
keybinds from the v0.1.x days, stock Ghostty rejects them, because the prefix
exists only in Witty. Remove those lines, or the include that pulls them in,
from Ghostty's config by hand. Witty's own copy can keep them.

## Platform support

| Platform              | Witty                                                                                                                                                                                                                                                                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **macOS** 13 or later | The app: one universal build for Apple silicon and Intel. Both shipped `altscreen:` defaults are macOS keys.                                                                                                                                                                                                                                             |
| **Linux**             | No packages, and no Linux build of Witty has been tested. The `altscreen:` prefix lives in the shared core, but no Linux default binding uses it. A GTK build from this source keeps Ghostty's application ID (`com.mitchellh.ghostty`) and Ghostty's Linux icons, so don't install it next to Ghostty ([FORK.md](../FORK.md#deliberately-not-changed)). |
| **Windows**           | No app: the app runs on macOS, and its GTK build targets Linux. Upstream Ghostty describes its `libghostty-vt` library as compatible with Windows, but that is a library for building terminals, not an app you can run. To work in tmux on a server from Windows, see [On Windows](witty-remote-workflow.md#on-windows).                                |

## Build from source

You need [Zig](https://ziglang.org) 0.16: 0.16.0 or a later 0.16.x patch
release (`minimum_zig_version` in `build.zig.zon`; the build rejects other
minor versions). For the macOS app you also need Xcode, and gettext (`msgfmt`)
on `PATH`.

```sh
zig build -Doptimize=ReleaseFast        # on macOS: macos/build/ReleaseLocal/Witty.app
zig build run                           # build a debug app and launch it
zig build test -Dtest-filter="<name>"   # prefer a filter; the full suite is slow
```

`macos/scripts/release.sh` makes the signed, notarized DMG; its prerequisites
are in [`macos/AGENTS.md`](../macos/AGENTS.md).
[`HACKING.md`](../HACKING.md) covers building, testing and debugging.
[`.github/CONTRIBUTING.md`](../.github/CONTRIBUTING.md) explains how to
contribute to Witty. The `CONTRIBUTING.md` at the repository root is Ghostty's,
and its process (vouching, Discussions) does not apply here. Before changing a
file that upstream also changes, read the [merge rules](../FORK.md#merge-rules)
in FORK.md.

Upstream's `test.yml` workflow is disabled in this repository (its jobs only
run in `ghostty-org`), so run the tests locally before opening a pull request.

---

[← Back to README](../README.md)
