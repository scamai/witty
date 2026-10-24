# Persistent remote dev with tmux

[← Back to README](../README.md)

Witty's altscreen bindings pay off most in a remote, persistent setup: keep the
real work in **tmux on a server** and treat the local terminal as a disposable,
reconnectable view. This page sets that up in three steps.

## Contents

- [1. SSH in and attach tmux](#1-ssh-in-and-attach-tmux)
- [2. Split panes and run Claude Code per pane](#2-split-panes-and-run-claude-code-per-pane)
- [3. Keep shortcuts consistent](#3-keep-shortcuts-consistent)
- [On Windows](#on-windows)

## 1. SSH in and attach tmux

The session lives on the server, not your laptop:

```sh
ssh myserver -t 'tmux new -A -s main'
```

`new -A -s main` attaches the `main` session if it exists, otherwise creates
it. Close the lid, drop Wi-Fi, or quit Witty — the session and everything
running in it survive. Run the same command to reconnect and you're back
exactly where you left off.

If tmux on the server stops with
`missing or unsuitable terminal: xterm-ghostty`, the server lacks the terminfo
entry Witty shares with Ghostty (Witty keeps `TERM=xterm-ghostty`). Copy it
once, from a Witty window on your Mac:

```sh
infocmp -x xterm-ghostty | ssh myserver -- tic -x -
```

On macOS 13, use Homebrew's ncurses `infocmp` instead of the system one;
Ghostty's [terminfo help](https://ghostty.org/docs/help/terminfo) has the
details.

## 2. Split panes and run Claude Code per pane

Split with Witty's native gestures, which keep working even while Claude or
tmux owns the alternate screen:

```
cmd+d         split right
cmd+shift+d   split down
cmd+w         close the pane
```

`cmd+ctrl+=` evens out Witty's splits whenever the focused split isn't inside
tmux. Once a split runs tmux and the signal from step 3 is set up, the
same key evens out the tmux panes inside that split instead. To even out
Witty's own splits then, choose **Window → Resize Split → Equalize Splits**, or
**Equalize Splits** in the command palette (`cmd+shift+p`).

In each new pane, repeat the SSH + attach from step 1 with its own session
name (`agent2`, `agent3`, …) and run `claude`. Each pane is an independent
agent you can glance across — the split grid is local, so you rebuild it on
reconnect, but every agent keeps running server-side and re-attaching drops
you right back in.

## 3. Keep shortcuts consistent

Give tmux's pane keys gestures close to Witty's, and let Witty's altscreen
bindings cover the keys tmux would otherwise swallow. A minimal tmux config
(`~/.tmux.conf`, or `~/.config/tmux/tmux.conf`):

```tmux
# screen-style prefix (closer to the home row)
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# pane navigation without the prefix: Shift+Option+arrow
# (Witty's own split focus is cmd+option+arrow)
bind -n M-S-Left  select-pane -L
bind -n M-S-Right select-pane -R
bind -n M-S-Up    select-pane -U
bind -n M-S-Down  select-pane -D

# modern key reporting so Ghostty's modified keys arrive intact
set -s extended-keys always
```

Add to the same file the two lines from step 1 of the README's
[Quick start](../README.md#quick-start) (`allow-passthrough` and the
`client-attached` hook), and put step 2's per-prompt shell hook in `~/.zshrc`
or `~/.bashrc`. Together they tell Witty a real tmux is live, including after
`tmux new -A` (step 1 above) re-attaches without drawing a new prompt. Without them
the `altscreen:` keybinds never fire and every key keeps its normal binding (a
safe, opt-in default).

`cmd+left` already works under **any** prefix — inside tmux Witty sends
**Home** (`CSI H`), which no tmux prefix can intercept.

`cmd+ctrl+=` is different: "even out panes" _must_ go through the tmux prefix,
and the shipped default targets tmux's **default** prefix (`C-b`). With the
`C-a` prefix above, the default `C-b E` never reaches tmux — add one line to
your Witty config to retarget it (and any other prefix-based keys) at `C-a`:

```ini
# Witty config (cmd+, opens it): use C-a (0x01) instead of the C-b default.
# C-a E evens out tmux's panes. Keep comments on their own line: a # after
# the binding would be sent along with the keys.
keybind = altscreen:super+ctrl+equal=text:\x01E
```

See [witty-altscreen.md](witty-altscreen.md) for the prefix caveat and more
bindings you can mirror this way. Same muscle memory whether or not tmux is in
the loop.

## On Windows

There is no Witty app for Windows, and Ghostty has none either: their apps run
on macOS and, through GTK, Linux. The workflow above still works from Windows,
because the real session lives in tmux on a Linux server and the local
terminal is only an SSH client. Use Windows Terminal or a WSL shell to `ssh` in
and run the same `tmux new -A -s main`. You won't get Witty's `altscreen:` keys
locally, but you can reproduce the ones you use as Windows Terminal or tmux
bindings. Everything on the server (panes, Claude Code, reconnecting after a
disconnect) works the same.

---

[← Back to README](../README.md)
