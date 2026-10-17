# Persistent remote dev with tmux

[← Back to README](../README.md)

Witty's altscreen bindings pay off most in a remote, persistent setup: keep the
real work in **tmux on a server** and treat the local terminal as a disposable,
reconnectable view. This page sets that up in three steps.

## Contents

- [1. SSH in and attach tmux](#1-ssh-in-and-attach-tmux)
- [2. Split panes and run Claude Code per pane](#2-split-panes-and-run-claude-code-per-pane)
- [3. Keep shortcuts consistent](#3-keep-shortcuts-consistent)

## 1. SSH in and attach tmux

The session lives on the server, not your laptop:

```sh
ssh myserver -t 'tmux new -A -s main'
```

`new -A -s main` attaches the `main` session if it exists, otherwise creates
it. Close the lid, drop Wi-Fi, or quit Witty — the session and everything
running in it survive. Run the same command to reconnect and you're back
exactly where you left off.

## 2. Split panes and run Claude Code per pane

Split with Witty's native gestures, which keep working even while Claude or
tmux owns the alternate screen:

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

## 3. Keep shortcuts consistent

Point tmux's pane keys at the same gestures you use in Witty, and let Witty's
altscreen bindings cover the keys tmux would otherwise swallow. A minimal
`~/.tmux.conf`:

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
[Setting the signal from your shell](witty-altscreen.md#setting-the-signal-from-your-shell).
Without the signal, the `altscreen:` keybinds never fire and every key keeps
its normal binding (a safe, opt-in default).

`cmd+left` already works under **any** prefix — on the alternate screen Witty
sends **Home** (`CSI H`), which no tmux prefix can intercept.

`cmd+ctrl+=` is different: "even out panes" *must* go through the tmux prefix,
and the shipped default targets tmux's **default** prefix (`C-b`). With the
`C-a` prefix above, the default `C-b E` never reaches tmux — add one line to
your Witty config to retarget it (and any other prefix-based keys) at `C-a`:

```ini
# ~/.config/witty/config — use C-a (0x01) instead of the C-b default
keybind = altscreen:super+ctrl+equal=text:\x01E   # C-a E → even tmux panes
```

See [witty-altscreen.md](witty-altscreen.md) for the prefix caveat and more
bindings you can mirror this way. Same muscle memory whether or not tmux is in
the loop.
