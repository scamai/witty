# The `altscreen:` keybind prefix

[← Back to README](../README.md)

witty adds a single keybind prefix, `altscreen:`, that gates a binding to the
terminal's **alternate screen**. This document covers the syntax, the fallback
semantics, the macOS `cmd+ctrl+=` default that ships with witty, and the
caveats you should know.

## Contents

- [Background: the two screens](#background-the-two-screens)
- [Syntax](#syntax)
- [Fallback semantics](#fallback-semantics)
- [The `cmd+ctrl+=` default](#the-cmdctrl-default)
- [Why `C-b E` and not `:select-layout`](#why-c-b-e-and-not-select-layout)
- [The `cmd+left` default](#the-cmdleft-default)
- [Gating on real tmux](#gating-on-real-tmux-not-just-the-alternate-screen)
- [Caveats](#caveats)
- [Examples](#examples)

## Background: the two screens

Terminals expose two screen buffers:

- The **primary** screen — your shell prompt and scrollback.
- The **alternate** screen — a separate buffer that fullscreen programs switch
  to while they run: `tmux`, `vim`/`nvim`, `less`, `htop`, `fzf`, and so on.
  When the program exits, the terminal switches back and your shell is exactly
  as you left it.

A keybinding that's useful at the shell is often useless (or wrong) inside a
fullscreen TUI, and vice-versa. The `altscreen:` prefix lets one physical key
serve both contexts.

## Syntax

Prefix any keybind trigger with `altscreen:`:

```ini
keybind = altscreen:<trigger>=<action>
```

The binding is only consulted while the terminal is on the alternate screen.
Like `performable:`, an `altscreen:` keybind is **not** registered as a global
shortcut and is matched only against live key events.

```ini
# Example from Ghostty's own docs for the prefix:
keybind = altscreen:cmd+d=text:\x01|
```

## Fallback semantics

The defining behavior of `altscreen:` is the **fallback**:

1. On a key event, witty first checks the alternate-screen table **if** the
   terminal is currently on the alternate screen.
2. If there's no alternate-screen match — or you're on the primary screen — the
   lookup **continues down the normal chain** and resolves to whatever that key
   was already bound to.

So `altscreen:` never *adds* a new key; it **overlays** an alternate-screen
behavior on top of an existing binding. This is what makes the pattern clean:

```ini
keybind = ctrl+r=reload_config           # primary screen: reload config
keybind = altscreen:ctrl+r=text:\x02[    # alt screen: send tmux C-b [
```

Press `ctrl+r` at the shell → config reloads. Press it inside tmux → tmux enters
copy-mode. One key, context-aware, with no loss of the original binding.

> Note on `physical:` — the macOS default below binds the **physical** `=` key
> (`physical:equal`) so the alternate-screen override and the primary-screen
> `equalize_splits` can coexist on the same physical key regardless of layout.

## The `cmd+ctrl+=` default

witty ships one default that uses the prefix (macOS):

```ini
keybind = super+ctrl+equal=equalize_splits          # primary screen
keybind = altscreen:super+ctrl+equal=text:\x02E     # alternate screen
```

- **Primary screen** → `equalize_splits` balances Ghostty's own split panes.
- **Alternate screen** → witty sends `\x02E` to the pty. That's tmux's default
  prefix `C-b` (`0x02`) followed by `E`, which is tmux's built-in
  `prefix E` binding for `select-layout -E` ("spread the current layout's panes
  out evenly"). The tmux prefix is intercepted by tmux regardless of what's
  running in the focused pane.

The reason for the split: when a single Ghostty surface is running tmux, the
panes you see belong to **tmux**, not Ghostty. `equalize_splits` would be a
no-op because Ghostty has exactly one surface. So on the alternate screen witty
asks tmux to even out *its* panes instead.

## Why `C-b E` and not `:select-layout`

An earlier version sent `\x02:select-layout -E\r` — the tmux **command prompt**
(`C-b :`) followed by the command and Enter. That turns out to be unreliable:
Ghostty delivers a `text:` action as a **single atomic write** to the pty, and
tmux's command prompt isn't ready for the bytes that follow `:` in that same
read, so the typed command gets dropped.

`C-b E` goes through tmux's normal **key-binding** path instead of the command
prompt, and acts on the whole atomic write reliably. It's also shorter (2 bytes)
and `select-layout -E` preserves your split structure (rather than forcing a
`tiled` grid), matching the spirit of Ghostty's own `equalize_splits`.

This was verified end-to-end against real tmux: feeding `\x02E` as one write to
a real tmux client evens out 2-, 3-, and 4-pane layouts; the atomic
command-prompt form does not.

## The `cmd+left` default

witty ships a second altscreen default (macOS) for "jump to the start of the
line":

```ini
keybind = super+arrow_left=text:\x01          # primary screen: C-a
keybind = altscreen:super+arrow_left=csi:H    # alternate screen: Home (CSI H)
```

The problem it solves: `cmd+left` normally sends **C-a** (`0x01`), which readline
treats as beginning-of-line. But `C-a` is also a very common **tmux prefix**
(`set -g prefix C-a`, screen-style). When tmux is running, your `cmd+left` C-a is
intercepted by tmux as its prefix and never reaches the shell — so the cursor
doesn't move (and the next key gets eaten as a tmux command).

On the alternate screen witty instead sends **Home** (`CSI H` = `ESC [ H`).
Unlike a control byte, Home isn't anybody's tmux prefix, so it passes straight
through to the shell, where readline/zle still map it to beginning-of-line. On
the primary screen (a bare shell) `cmd+left` keeps sending C-a, which is the most
universally understood "start of line".

This fix is **prefix-independent**: it works whether your tmux prefix is `C-a`,
`C-b`, or anything else. (`cmd+right` = C-e, `cmd+backspace` = C-u, and the
`alt+←/→` word motions don't use the prefix byte, so they already work in tmux
and are left unchanged.)

## Gating on real tmux (not just the alternate screen)

The alternate screen is shared by tmux, `vim`, `less`, `htop`, Claude Code, and
every other fullscreen TUI. The terminal can't tell them apart from the byte
stream — there is no "I am tmux" beacon. So witty gates `altscreen:` bindings on
a second condition: a private DEC mode, **`?8771`** (`tmux_active`), that tmux
itself turns on.

- A binding with the `altscreen:` prefix fires only when the terminal is on the
  alternate screen **AND** `?8771` is set.
- witty **auto-clears** `?8771` whenever it enters *or* leaves the alternate
  screen, so a stale value can't leak into the next TUI. Real tmux re-asserts it
  right after entry — from the inner shell's first prompt for a fresh session,
  and from the `client-attached` hook above when re-attaching to an existing one.
- If `?8771` is never set, `altscreen:` bindings never fire and every key keeps
  its normal binding everywhere. Setting up the signal is opt-in.

### Setting the signal from your shell

tmux passes unknown escapes to the outer terminal only through its
**passthrough** wrapper, and only if `allow-passthrough` is on:

```tmux
# ~/.tmux.conf
set -g allow-passthrough on

# Re-assert the signal on every (re)attach. witty clears ?8771 when the outer
# terminal enters the alternate screen, which a tmux client does on attach. On
# `tmux new -As <name>` re-attaching to an existing session the inner shell
# stays at its already-drawn prompt, so the per-prompt hook below never re-fires
# — without this the keybinds go dead until the next Enter. The hook writes
# ?8771h straight to the attaching client's tty (raw, not passthrough-wrapped,
# since it bypasses tmux), and fires after tmux's smcup so it survives the clear.
set-hook -g client-attached 'run-shell -b "printf \"\\033[?8771h\" > #{client_tty}"'
```

Then have your shell announce tmux on every prompt. For zsh:

```zsh
# ~/.zshrc
_witty_tmux_signal() {
  if [[ -n "$TMUX" ]]; then
    # inside tmux: wrap in tmux passthrough so it reaches the outer terminal
    printf '\033Ptmux;\033\033[?8771h\033\\'
  else
    printf '\033[?8771l'
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _witty_tmux_signal
```

For bash, append the equivalent to `PROMPT_COMMAND`:

```bash
# ~/.bashrc
_witty_tmux_signal() {
  if [[ -n "$TMUX" ]]; then printf '\033Ptmux;\033\033[?8771h\033\\'
  else printf '\033[?8771l'; fi
}
PROMPT_COMMAND="_witty_tmux_signal${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
```

This works the same locally and over SSH: the bytes ride the tmux output stream
through `ssh` to the outer witty, which sets the mode. Install the snippet on
every host where you run tmux (including remote boxes). On a non-witty terminal
the escape is an unknown mode and is harmlessly ignored.

> Note: the signal is sticky between prompts — while a long-running fullscreen
> program (e.g. Claude Code) runs inside a tmux pane, `?8771` stays set from the
> last prompt, so `cmd+d` keeps driving tmux. It only clears when the outer
> terminal leaves the alternate screen (tmux detaches/exits).

## Caveats

- **The `cmd+ctrl+=` default assumes tmux's default prefix `C-b`.** This is the
  one shipped default that is prefix-*dependent* — "even out panes" has to go
  through the tmux prefix, and `\x02` is `C-b`. If you remapped your prefix
  (e.g. screen-style `C-a`), the default `C-b E` is just sent to the shell and
  does nothing. Override it in your Witty config with the matching control
  byte (`\x01` = `C-a`, `\x02` = `C-b`, …):

  ```ini
  # ~/.config/witty/config — for a C-a tmux prefix
  keybind = altscreen:super+ctrl+equal=text:\x01E   # C-a E → even tmux panes
  ```

  (`cmd+left` does **not** need this — it sends Home, which is prefix-independent.)
- **Assumes tmux's default `E` binding** (`select-layout -E`). If you unbound or
  rebound `E` in tmux, adjust accordingly.
- **`altscreen:` now requires tmux to actually be running** (see
  [Gating on real tmux](#gating-on-real-tmux-not-just-the-alternate-screen)).
  Originally the prefix fired on *any* alternate-screen app, which meant
  pressing `cmd+d` inside `vim`/`less`/Claude Code sent tmux bytes into that
  app instead of splitting. The gate is now `alternate screen` **AND** the
  `tmux_active` signal, so outside tmux these keys fall back to their normal
  binding (e.g. `cmd+d` performs a native witty split). If you do **not** set
  up the signal, the `altscreen:` keys simply never fire and you keep the
  native bindings everywhere — a safe default.
- **Linux/GTK:** the prefix works the same, but witty ships no default binding
  that uses it on Linux — add your own.

## Examples

```ini
# tmux copy-mode from a shell-friendly key
keybind = ctrl+r=reload_config
keybind = altscreen:ctrl+r=text:\x02[

# even out tmux panes (witty's macOS default)
keybind = super+ctrl+equal=equalize_splits
keybind = altscreen:super+ctrl+equal=text:\x02E

# C-a prefix users: send C-a E instead of C-b E
keybind = altscreen:super+ctrl+equal=text:\x01E

# new tmux window on a key that opens a Ghostty tab on the primary screen
keybind = cmd+t=new_tab
keybind = altscreen:cmd+t=text:\x02c
```

---

[← Back to README](../README.md)
