# Security policy

Witty is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) for macOS, maintained by
Reality Inc. Because most of its code comes from Ghostty, this policy also says when a report
belongs to Ghostty instead. For this repository it replaces
[Reality Inc.'s organization-wide policy](https://github.com/scamai/.github/blob/main/SECURITY.md)
and keeps that policy's response targets and safe harbor.

## Supported versions

| Version                                                                          | Supported |
| -------------------------------------------------------------------------------- | --------- |
| The [latest `witty-v*` release](https://github.com/scamai/witty/releases/latest) | Yes       |
| Any earlier release                                                              | No        |

Fixes ship only in a new release. Please check that you run the latest one before you report.

v0.1.0 and v0.1.1 are not supported. They were ad-hoc signed and not notarized, installed as
`Ghostty.app` with Ghostty's bundle ID, and pointed "Check for Updates…" at Ghostty's update
feed. Replace them with the latest release:
[Upgrading from v0.1.x](https://github.com/scamai/witty/blob/main/docs/witty-install.md#upgrading-from-v01x).

## Reporting a vulnerability

**Please do not report security vulnerabilities in public issues, discussions or pull
requests.** Report them privately, in one of two ways:

- **GitHub private vulnerability reporting (preferred).** Use **Report a vulnerability** on this
  repository's Security tab, or go straight to
  <https://github.com/scamai/witty/security/advisories/new>.
- **Email.** Write to contact@scam.ai with the subject line `[SECURITY][Witty]`.

Please include:

- what the problem is, and what an attacker could do with it;
- how to reproduce it: a proof of concept, the bytes a program has to print, or a config snippet;
- your Witty version (**Witty → About Witty**), your macOS version and your Mac;
- whether it also happens in stock Ghostty, and which Ghostty version you tried (see below);
- how we can reach you.

## Witty or Ghostty?

Witty merges upstream Ghostty regularly, and [FORK.md](https://github.com/scamai/witty/blob/main/FORK.md)
lists every place where it differs. Terminal emulation, rendering, config parsing, shell
integration and most of the macOS app come from Ghostty. Stock Ghostty installs next to Witty, so
you can check where a problem comes from.

- **It also happens in stock Ghostty.** Then it is a Ghostty vulnerability. Report it to Ghostty
  privately at <https://github.com/ghostty-org/ghostty/security/advisories/new>. You may also
  tell us through the channels above, or ask us to forward your report to Ghostty. We keep it
  private until Ghostty has disclosed it.
- **It happens only in Witty, or you are not sure.** Report it to us. If it turns out to be
  Ghostty's, we will tell you and, with your permission, forward it to Ghostty.

When Ghostty publishes a security advisory that affects Witty, we ship a Witty release with the
fix as soon as we can, and its release notes link the advisory. Until that release is out, Witty
is still affected. Ghostty lists its published advisories at
<https://github.com/ghostty-org/ghostty/security/advisories>.

## What only Witty has

These parts, and every other change FORK.md lists, exist only in Witty, so reports about them come
to us.

- **The `altscreen:` keybind gate and private mode `?8771`.** An `altscreen:` binding fires only
  while the terminal is on the alternate screen and private mode `?8771` is on (Witty's tmux setup
  turns it on). Witty clears the mode whenever the terminal enters or leaves the alternate
  screen. Any program that writes to the terminal can turn the mode on, and the mode only chooses
  between bindings from your own config (or Witty's two defaults). Reports that go further are in scope: for
  example, a binding that fires after Witty should have cleared the mode, or a way to make a key
  send text that your config does not bind it to.
- **The one-time Ghostty config import.** On first launch, if Witty has no config and Ghostty
  has one, Witty copies Ghostty's config files, their relative `config-file` includes and the
  `themes/` folder from `~/.config/ghostty` and `~/Library/Application Support/com.mitchellh.ghostty`
  into its own folders. It must only read Ghostty's files, only write inside Witty's folders and
  never overwrite a file. A way to make it read or write anywhere else is in scope.
- **Release signing, notarization and the DMG.** From v0.2.0 on, releases ship as a DMG signed
  with Reality Inc.'s Developer ID and notarized by Apple, and the release notes give the DMG's
  SHA-256. Problems with how a release is built, signed or published, or a DMG whose hash does
  not match its release notes, are in scope.
- **The updater, which is off.** Shipped builds set no update feed, so Witty's updater never
  starts, Witty makes no update checks, and **Check for Updates…** is hidden. Current builds never
  use Ghostty's update feed or update-signing key. A shipped build that checks for, downloads or
  installs updates is in scope.

<!-- When scamai/homebrew-tap exists and has been tested on a Mac, add this
     bullet to the list above:
- **The Homebrew cask in `scamai/homebrew-tap`.** It installs the released DMG. A cask that
  installs anything else, or a tap change that did not come from this project, is in scope.
-->

## Out of scope

- Vulnerabilities in tmux, your shell or other programs that run inside Witty. Please report
  those to their own projects.
- Denial-of-service testing against Reality Inc.'s online services, social engineering of
  Reality Inc. staff, physical attacks, and third-party services we do not control.

Crashes are not excluded. A crash, hang or memory error caused by bytes a program prints, or by a
config or file Witty reads, is in scope. Report it privately (to Ghostty if stock Ghostty also
crashes).

## What to expect

- **Acknowledgment within 2 business days, and an initial assessment within 5 business days.**
  These are the same targets as in
  [Reality Inc.'s security policy](https://github.com/scamai/.github/blob/main/SECURITY.md).
- We will keep you informed while we work on a fix. We don't promise a date for the fix itself:
  Witty is maintained by a small team, and a fix that belongs in Ghostty follows Ghostty's
  schedule and then reaches Witty as described in [Witty or Ghostty?](#witty-or-ghostty).
- We credit reporters in the release notes of the fix and in any advisory, unless you prefer to
  stay anonymous.
- There is no bug bounty.

## Safe harbor

We will not pursue legal action against researchers who make a good-faith effort to follow this
policy, avoid privacy violations and service disruption, and allow us reasonable time to
remediate before public disclosure.

This is the safe harbor from
[Reality Inc.'s security policy](https://github.com/scamai/.github/blob/main/SECURITY.md#safe-harbor),
applied to Witty.

## Getting fixes

Witty does not update itself yet. To hear about new releases, including security fixes, choose
**Watch → Custom → Releases** on this repository, or subscribe to
<https://github.com/scamai/witty/releases.atom>. To update, download the new DMG and replace
Witty in your Applications folder.
<!-- When scamai/homebrew-tap exists and has been tested on a Mac, add:
Homebrew users: `brew upgrade --cask witty`.
-->
