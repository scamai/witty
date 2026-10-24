# The `altscreen:` keybind prefix

[← Back to README](../README.md)

Witty adds a single keybind prefix, `altscreen:`, that gates a binding to the
terminal's **alternate screen** while tmux is running there. This document
covers the syntax, the fallback semantics, the two macOS defaults that ship
with Witty (`cmd+ctrl+=` and `cmd+left`), the tmux setup they need, and the
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

The binding is only consulted while the terminal is on the alternate screen
and tmux has announced itself (see
[Gating on real tmux](#gating-on-real-tmux-not-just-the-alternate-screen)).
Like `performable:`, an `altscreen:` keybind is **not** registered as a menu
shortcut (a menu shortcut would bypass the tmux check) and is matched only
against live key events.

```ini
# Assumes a C-a tmux prefix and a ~/.tmux.conf that binds | to a split.
keybind = altscreen:cmd+d=text:\x01|
```

That is the example in Witty's built-in keybind reference
(`ghostty +show-config --docs`). The reference's description of `altscreen:`
predates the tmux check: it still says the binding matches on any alternate
screen. This guide describes the current behavior.

Keep comments on their own line, as above. A `#` after the binding is not a
comment: it becomes part of the action, so `text:` would send it along with
the keys.

## Fallback semantics

The defining behavior of `altscreen:` is the **fallback**:

1. On a key event, Witty uses an `altscreen:` binding **only if** the terminal
   is inside tmux (the alternate screen plus tmux's `?8771` signal).
2. Outside tmux, a key with an `altscreen:` binding resolves to the binding
   that line replaced. If it replaced nothing, the lookup **continues down the
   normal chain** as if the line weren't there.

So `altscreen:` never _takes away_ a key; it **overlays** an inside-tmux
behavior on top of an existing binding. This is what makes the pattern clean:

```ini
# outside tmux: cmd+t keeps Ghostty's default, a new Witty tab
# inside tmux: send C-b c, a new tmux window
keybind = altscreen:cmd+t=text:\x02c
```

Press `cmd+t` at the shell → a new Witty tab opens. Press it inside tmux → tmux
opens a new window. One key, context-aware, with no loss of the original
binding. A Cmd key such as `cmd+t` is a good choice: it is an app shortcut,
not a key your shell uses, so the overlay takes nothing away from the shell.
A key like `ctrl+r` would: inside tmux it would stop reaching your shell's
reverse history search.

> Note on trigger forms — the gated `cmd+ctrl+=` default below is on the
> **physical** `equal` key, while `equalize_splits` stays on the `=`
> **character**. Outside tmux the lookup skips the gated binding and finds the
> `=` one (`getEventAltscreen` in `src/input/Binding.zig`).

## The `cmd+ctrl+=` default

Witty ships two defaults that use the prefix, both on macOS. The first is
`cmd+ctrl+=`:

```ini
# outside tmux (on the = character)
keybind = super+ctrl+==equalize_splits
# inside tmux (on the physical equal key)
keybind = altscreen:super+ctrl+equal=text:\x02E
```

- **Outside tmux** → `equalize_splits` balances Witty's own split panes.
- **Inside tmux** → Witty sends `\x02E` to the pty. That's tmux's default
  prefix `C-b` (`0x02`) followed by `E`, which is tmux's built-in
  `prefix E` binding for `select-layout -E` ("spread the current layout's panes
  out evenly"). The tmux prefix is intercepted by tmux regardless of what's
  running in the focused pane.

The reason for the split: when a single Witty surface is running tmux, the
panes you see belong to **tmux**, not Witty. `equalize_splits` would be a
no-op because there is exactly one surface. So inside tmux Witty asks tmux to
even out _its_ panes instead.

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

Witty ships a second altscreen default (macOS) for "jump to the start of the
line":

```ini
# outside tmux: C-a
keybind = super+arrow_left=text:\x01
# inside tmux: Home (CSI H)
keybind = altscreen:super+arrow_left=csi:H
```

The problem it solves: `cmd+left` normally sends **C-a** (`0x01`), which readline
treats as beginning-of-line. But `C-a` is also a very common **tmux prefix**
(`set -g prefix C-a`, screen-style). When tmux is running, your `cmd+left` C-a is
intercepted by tmux as its prefix and never reaches the shell — so the cursor
doesn't move (and the next key gets eaten as a tmux command).

Inside tmux Witty instead sends **Home** (`CSI H` = `ESC [ H`).
Unlike a control byte, Home isn't anybody's tmux prefix, so it passes straight
through: tmux reads it as the Home key and hands it to the shell in the pane as
`ESC [ 1 ~` (checked with tmux 3.4). bash maps that to beginning-of-line out of
the box. zsh does once Home is bound, as Oh My Zsh and Debian's and Ubuntu's
system zshrc do; with a plain `zsh -f` setup, add
`bindkey '^[[1~' beginning-of-line` to `~/.zshrc`. Outside
tmux (a bare shell) `cmd+left` keeps sending C-a, which is the most universally
understood "start of line".

This fix is **prefix-independent**: it works whether your tmux prefix is `C-a`,
`C-b`, or anything else. (`cmd+right` = C-e, `cmd+backspace` = C-u, and the
`alt+←/→` word motions don't use the prefix byte, so they already work in tmux
and are left unchanged.)

## Gating on real tmux (not just the alternate screen)

The alternate screen is shared by tmux, `vim`, `less`, `htop`, Claude Code, and
every other fullscreen TUI. The terminal can't tell them apart from the byte
stream — there is no "I am tmux" beacon. So Witty gates `altscreen:` bindings on
a second condition: a private DEC mode, **`?8771`** (`tmux_active`), that tmux
itself turns on.

- A binding with the `altscreen:` prefix fires only when the terminal is on the
  alternate screen **AND** `?8771` is set.
- Witty **auto-clears** `?8771` whenever it enters _or_ leaves the alternate
  screen, so a stale value can't leak into the next TUI. Real tmux re-asserts it
  right after entry — from the inner shell's first prompt for a fresh session,
  and from the `client-attached` hook below when re-attaching to an existing one.
- If `?8771` is never set, `altscreen:` bindings never fire and every key keeps
  its normal binding everywhere. Setting up the signal is opt-in.

### Setting the signal from your shell

tmux passes unknown escapes to the outer terminal only through its
**passthrough** wrapper. tmux 3.3 added the `allow-passthrough` option, off by
default, to control that wrapper (tmux's `CHANGES` file, under "CHANGES FROM
3.2a TO 3.3": "Add an option (default off) to control the passthrough escape
sequence"), so on 3.3 or later turn it on. tmux 3.2 and older always pass the
wrapper through and don't know the option: leave the `allow-passthrough` line
out there, and keep the hook.

```tmux
# ~/.tmux.conf
# tmux 3.3 or later only:
set -g allow-passthrough on

# Re-assert the signal on every (re)attach. Witty clears ?8771 when the outer
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

For bash, add the equivalent to the front of `PROMPT_COMMAND`:

```bash
# ~/.bashrc
_witty_tmux_signal() {
  if [[ -n "$TMUX" ]]; then printf '\033Ptmux;\033\033[?8771h\033\\'
  else printf '\033[?8771l'; fi
}
PROMPT_COMMAND="_witty_tmux_signal${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
```

tmux starts login shells (its `default-command` is empty by default), and a
login bash reads `~/.bash_profile`, `~/.bash_login` or `~/.profile`, not
`~/.bashrc`. If the one you have doesn't source `~/.bashrc`, the hook never
loads inside tmux. Ubuntu's default `~/.profile` sources it.

This works the same locally and over SSH: the bytes ride the tmux output stream
through `ssh` to the outer Witty, which sets the mode. Install the snippet on
every host where you run tmux (including remote boxes). On a non-Witty terminal
the escape is an unknown mode and is harmlessly ignored.

> Note: the signal is sticky between prompts — while a long-running fullscreen
> program (e.g. Claude Code) runs inside a tmux pane, `?8771` stays set from the
> last prompt, so the `altscreen:` keys keep driving tmux. It only clears when
> the outer terminal leaves the alternate screen (tmux detaches/exits).

## Caveats

- **The `cmd+ctrl+=` default assumes tmux's default prefix `C-b`.** This is the
  one shipped default that is prefix-_dependent_ — "even out panes" has to go
  through the tmux prefix, and `\x02` is `C-b`. If you remapped your prefix
  (e.g. screen-style `C-a`), the default `C-b E` reaches the program in the
  pane instead of tmux: at a shell prompt, `C-b` moves the cursor back one
  character and an `E` is typed. Override it in your Witty config with the
  matching control byte (`\x01` = `C-a`, `\x02` = `C-b`, …):

  ```ini
  # Witty config, for a C-a tmux prefix: C-a E evens out tmux's panes
  keybind = altscreen:super+ctrl+equal=text:\x01E
  ```

  (`cmd+left` does **not** need this — it sends Home, which is prefix-independent.)

- **Assumes tmux's default `E` binding** (`select-layout -E`). If you unbound or
  rebound `E` in tmux, adjust accordingly.
- **`altscreen:` now requires tmux to actually be running** (see
  [Gating on real tmux](#gating-on-real-tmux-not-just-the-alternate-screen)).
  Originally the prefix fired on _any_ alternate-screen app, which meant
  pressing `cmd+d` inside `vim`/`less`/Claude Code sent tmux bytes into that
  app instead of splitting. The gate is now `alternate screen` **AND** the
  `tmux_active` signal, so outside tmux these keys fall back to their normal
  binding (e.g. an `altscreen:cmd+d` binding falls back to a native Witty
  split). If you do **not** set up the signal, the `altscreen:` keys simply
  never fire and you keep the native bindings everywhere — a safe default.
- **Gating a menu key removes its menu shortcut.** When an `altscreen:`
  binding replaces a key that a menu item shows, such as `cmd+t` (New Tab) or
  `cmd+d` (Split Right), that menu item stops showing the shortcut, because a
  menu shortcut would bypass the tmux check (`src/input/Binding.zig`). Outside
  tmux the key still runs the replaced action as its fallback, and the menu
  item still works when clicked.
- **Linux/GTK:** the prefix lives in the shared core, but no Linux build of
  Witty has been tested, and Witty ships no default binding that uses it on
  Linux — add your own.

## Examples

```ini
# even out tmux panes (Witty's macOS default)
keybind = super+ctrl+==equalize_splits
keybind = altscreen:super+ctrl+equal=text:\x02E

# C-a prefix users: send C-a E instead of C-b E
keybind = altscreen:super+ctrl+equal=text:\x01E

# new tmux window on a key that opens a Witty tab outside tmux
keybind = cmd+t=new_tab
keybind = altscreen:cmd+t=text:\x02c
```

---

[← Back to README](../README.md)
