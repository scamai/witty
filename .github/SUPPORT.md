# Getting help with Witty

Witty is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) for macOS, maintained by
Reality Inc. This page says where to look first and where to ask.

## Start with the docs

- **[Quick start](https://github.com/scamai/witty/blob/main/README.md#quick-start)** in the
  README: the tmux config lines and the shell hook that switch on Witty's tmux keys. Until they
  are in place on every machine where you run tmux, every key does exactly what it does in
  Ghostty.
- **[The `altscreen:` prefix](https://github.com/scamai/witty/blob/main/docs/witty-altscreen.md)**:
  the syntax, the two keys Witty ships, how the tmux signal works, and the caveats.
- **[Installing Witty](https://github.com/scamai/witty/blob/main/docs/witty-install.md)**:
  download, the one-time import of your Ghostty config, running next to Ghostty, updates,
  upgrading from v0.1.x, platform support and building from source.
- **[tmux over SSH](https://github.com/scamai/witty/blob/main/docs/witty-remote-workflow.md)**:
  the same keys in tmux on a remote server, and a note for Windows users.
- **[FORK.md](https://github.com/scamai/witty/blob/main/FORK.md)**: every way Witty differs from
  Ghostty.

For config options, themes, fonts and keybind actions, use
[Ghostty's documentation](https://ghostty.org/docs). It applies to Witty, except for `altscreen:`,
updates and installation. Where it says `~/.config/ghostty` or `com.mitchellh.ghostty`, Witty uses
`~/.config/witty` and `ai.scam.witty`.

## Ask or report here

| You have                                   | Go to                                                                                           |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| A question, or trouble with the tmux setup | [Q&A](https://github.com/scamai/witty/discussions/categories/q-a) in Discussions                |
| A bug in Witty                             | [New issue](https://github.com/scamai/witty/issues/new/choose) → **Bug report**                 |
| An idea for Witty                          | [New issue](https://github.com/scamai/witty/issues/new/choose) → **Feature request**            |
| A security vulnerability                   | The [security policy](https://github.com/scamai/witty/security/policy). Never post it in public |

When you ask about Witty's tmux keys, these help us answer quickly:

- your Witty version (**Witty → About Witty**) and your macOS version;
- the output of `tmux -V` and, on tmux 3.3 or later, `tmux show -g allow-passthrough`;
- which shell you use, and whether you added the tmux config lines and the shell hook from the
  Quick start, on every machine where tmux runs;
- whether tmux runs on your Mac or over SSH, and your tmux prefix if it isn't `C-b`.

## Witty problems stay here

Please don't take Witty problems to Ghostty's issue tracker, Discussions or Discord. Ghostty's
maintainers don't support Witty.

If a bug also happens in stock Ghostty, which installs next to Witty, it is a Ghostty bug. Report
it to Ghostty with steps that use Ghostty, following Ghostty's
[contributing guide](https://github.com/ghostty-org/ghostty/blob/main/CONTRIBUTING.md).

## Who answers

Witty is maintained by a small team at Reality Inc. We read every question and report, but a
reply can take a few days. There is no paid support for Witty, and Reality Inc.'s product support
for scam.ai does not cover it.

## Hearing about new versions

Witty does not update itself yet, so new versions appear only on
[Releases](https://github.com/scamai/witty/releases). To hear about them, choose
**Watch → Custom → Releases** on this repository, or subscribe to
<https://github.com/scamai/witty/releases.atom>.
<!-- When scamai/homebrew-tap exists and has been tested on a Mac, add:
Homebrew users: `brew upgrade --cask witty`.
-->
