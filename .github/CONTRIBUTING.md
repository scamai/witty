# Contributing to Witty

This is Witty's contributing guide. The `CONTRIBUTING.md` at the repository
root is Ghostty's, kept unchanged so that upstream merges stay clean. Its
process (vouching, Issue Triage discussions, Ghostty's Discord) does not apply
to Witty.

Witty is [Ghostty](https://github.com/ghostty-org/ghostty) plus one feature,
the `altscreen:` keybind prefix, and its own app identity. Reality Inc.
maintains it. Bug reports, docs fixes, tests and code are all welcome, and you
don't need anyone's approval before you open an issue or a pull request.

## Contents

- [Which documents apply here](#which-documents-apply-here)
- [Witty or Ghostty?](#witty-or-ghostty)
- [Reporting bugs and asking questions](#reporting-bugs-and-asking-questions)
- [Your first contribution](#your-first-contribution)
- [Build and test Witty](#build-and-test-witty)
- [Sending a pull request](#sending-a-pull-request)
- [AI-assisted contributions](#ai-assisted-contributions)
- [Sending work upstream](#sending-work-upstream)
- [Translations and packaging](#translations-and-packaging)
- [No vouching](#no-vouching)
- [License](#license)
- [Who maintains Witty](#who-maintains-witty)
- [Code of conduct, security and support](#code-of-conduct-security-and-support)

## Which documents apply here

Witty carries Ghostty's files, including the ones that describe how Ghostty
is run. This table says which ones govern Witty.

| Document                                                                                                               | Applies to Witty?                       | What it is                                                                                                                                                                           |
| ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.github/CONTRIBUTING.md` (this file)                                                                                  | Yes                                     | How to contribute to Witty.                                                                                                                                                          |
| [`FORK.md`](../FORK.md)                                                                                                | Yes                                     | Every place Witty differs from upstream Ghostty, and the merge rules.                                                                                                                |
| [`CHANGELOG.md`](../CHANGELOG.md)                                                                                      | Yes                                     | Witty's changes on top of upstream.                                                                                                                                                  |
| [`docs/witty-*.md`](../docs)                                                                                           | Yes                                     | The `altscreen:` guide, installing Witty, and the remote tmux workflow.                                                                                                              |
| [`macos/AGENTS.md`](../macos/AGENTS.md)                                                                                | Yes                                     | Building and testing the macOS app, and cutting a release.                                                                                                                           |
| [`AGENTS.md`](../AGENTS.md)                                                                                            | Partly                                  | Its build, test and formatting commands apply. Its "Issue and PR Guidelines" section is upstream's and does not apply to Witty; if your agent adds a file because of it, remove it.  |
| [`HACKING.md`](../HACKING.md)                                                                                          | Partly                                  | Clone `scamai/witty` instead of Ghostty; the build and test commands are the same. Its log command covers only the Zig core (see [Logs and crash reports](#logs-and-crash-reports)). |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) at the root                                                                    | No                                      | Ghostty's process: vouching, Issue Triage discussions, Discord.                                                                                                                      |
| [`AI_POLICY.md`](../AI_POLICY.md)                                                                                      | No, except for work you send to Ghostty | Ghostty's AI rules. Witty's are under [AI-assisted contributions](#ai-assisted-contributions).                                                                                       |
| [`CODEOWNERS`](../CODEOWNERS) at the root                                                                              | No                                      | Ghostty's maintainers. Witty's code owners are in [`.github/CODEOWNERS`](CODEOWNERS).                                                                                                |
| [`PACKAGING.md`](../PACKAGING.md)                                                                                      | No                                      | Ghostty's source tarballs and distro packaging.                                                                                                                                      |
| [`.github/VOUCHED.td`](VOUCHED.td), [`.github/DISCUSSION_TEMPLATE/`](DISCUSSION_TEMPLATE)                              | No                                      | Ghostty's vouch list and discussion forms. Neither is used here.                                                                                                                     |
| [`po/README_CONTRIBUTORS.md`](../po/README_CONTRIBUTORS.md), [`po/README_TRANSLATORS.md`](../po/README_TRANSLATORS.md) | No                                      | Ghostty's translation process.                                                                                                                                                       |

The files marked "No" are identical to upstream's, so that upstream merges
stay clean. Please don't edit them in a Witty pull request.

## Witty or Ghostty?

Witty takes changes to what it adds to Ghostty:

- the `altscreen:` keybind prefix and the `?8771` tmux signal it waits for
  ([docs/witty-altscreen.md](../docs/witty-altscreen.md));
- its app identity: the name, icon, bundle ID, menus and messages, and its own
  config, state and cache directories;
- the one-time import of a Ghostty config;
- packaging and releases: the DMG, signing, notarization and the release
  scripts;
- Witty's docs: the README, FORK.md, CHANGELOG.md and `docs/witty-*.md`.

Anything that also happens in stock Ghostty belongs upstream, under Ghostty's
rules (see [Sending work upstream](#sending-work-upstream)). On macOS, stock
Ghostty installs next to Witty, so you can check. Witty merges upstream Ghostty
regularly (the `chore: sync Ghostty upstream through <date>` commits), and
upstream's fixes reach Witty that way.

You can also open a Witty issue for a bug that happens in stock Ghostty; link
the upstream report, and we'll label it `upstream`. Witty carries its own fix
only when such a bug hurts Witty users and can't wait for a sync
([FORK.md, "Fixes not upstream"](../FORK.md#fixes-not-upstream)). Each one is
extra work at every merge, so they are the exception.

## Reporting bugs and asking questions

- **Bugs and feature ideas:**
  [open an issue](https://github.com/scamai/witty/issues/new/choose). For a
  bug, say whether it also happens in stock Ghostty.
- **Setup questions**, such as the tmux lines, the shell hook or "is this
  expected?": ask in [Q&A](https://github.com/scamai/witty/discussions/categories/q-a).
- **Security vulnerabilities:** never in public. Follow the
  [security policy](SECURITY.md).
- **Ghostty's own features** (config options, themes, fonts) work as they do
  in Ghostty, and [ghostty.org/docs](https://ghostty.org/docs) documents them.

Please don't take Witty problems to Ghostty's issue tracker, Discussions or
Discord. Witty is not affiliated with or endorsed by the Ghostty project, so
Witty's problems are not theirs to solve. If a bug also happens in stock
Ghostty, report it to Ghostty as a Ghostty bug, reproduced in Ghostty (see
[Witty or Ghostty?](#witty-or-ghostty)).

## Your first contribution

- The [contribute page](https://github.com/scamai/witty/contribute) lists
  issues that are a good place to start. You can also browse the
  [`good first issue`](https://github.com/scamai/witty/labels/good%20first%20issue)
  and [`help wanted`](https://github.com/scamai/witty/labels/help%20wanted)
  labels.
- Say in the issue that you are working on it, so that two people don't do
  the same work. For anything bigger than a small fix, agree on the approach
  in the issue first.
- Docs count. If a step in the `altscreen:` guide tripped you up, a pull
  request that fixes the guide is welcome.

## Build and test Witty

You need [Zig](https://ziglang.org) 0.16: 0.16.0 or a later 0.16.x patch
release. `build.zig.zon` sets `minimum_zig_version`, and the build rejects
other minor versions. The macOS app also needs Xcode
([HACKING.md](../HACKING.md#macos) has the details) and gettext's `msgfmt` on
your `PATH`.

```sh
git clone https://github.com/scamai/witty
cd witty
zig build        # a debug build; on macOS it includes macos/build/Debug/Witty.app
zig build run    # build a debug app and launch it
```

`zig build -Doptimize=ReleaseFast` builds `macos/build/ReleaseLocal/Witty.app`
instead.

### Witty's own tests

The full `zig build test` suite is slow. Witty's own tests can be selected by
name. This command runs every Zig test that Witty adds, and the upstream tests
that Witty extends:

```sh
zig build test --summary all \
  -Dtest-filter=altscreen \
  -Dtest-filter=getEventAltscreen \
  -Dtest-filter="set: unbind clears fallback" \
  -Dtest-filter="set: clone preserves fallbacks" \
  -Dtest-filter="parse: triggers" \
  -Dtest-filter="ghostty import" \
  -Dtest-filter=tmux_active \
  -Dtest-filter="TERMINAL mode bit layout" \
  -Dtest-filter="TERMINAL header excludes transient modes" \
  -Dtest-filter="TERMINAL header decoding normalizes semantic values" \
  -Dtest-filter="mouse tracking reset"
```

- The first five filters cover the `altscreen:` prefix, `ghostty import` the
  Ghostty config import, `tmux_active` the `?8771` tmux mode, the three
  `TERMINAL` filters the snapshot mode bits, and `mouse tracking reset` the
  fix listed in [FORK.md, "Fixes not upstream"](../FORK.md#fixes-not-upstream).
  While you work on one area, its filters alone are enough.
- A filter is a case-sensitive substring of the test name: `altscreen` does
  not match `getEventAltscreen`. Name a new Witty test so that one of these
  filters matches it, for example by putting `altscreen` in its name, or add
  a filter to this list.
- On Linux, add `-Dapp-runtime=none` so that the tests build without GTK, as
  upstream's CI does. `none` is already the default on macOS.
- Some tests run whatever the filter, so a filter that matches nothing still
  passes. `--summary all` shows how many tests ran; compare it with a run
  whose filter matches nothing.
- A filtered `zig build test` builds and runs no Swift tests. Run those with
  `macos/build.nu --action test` (it needs [Nushell](https://www.nushell.sh));
  see [macos/AGENTS.md](../macos/AGENTS.md).

The formatters and linters are listed in [AGENTS.md](../AGENTS.md) under
"Commands", and [HACKING.md](../HACKING.md) covers the rest of the developer
workflow.

### Logs and crash reports

The Swift side of the app logs under its bundle ID, `ai.scam.witty`
(`ai.scam.witty.debug` for a Debug build). The Zig core logs under
`com.mitchellh.ghostty`, as in Ghostty, so a running Ghostty logs there too.

```sh
sudo log stream --level debug --predicate 'subsystem=="ai.scam.witty"'
sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'
```

Crash reports are saved in `$XDG_STATE_HOME/witty/crash`, which is
`~/.local/state/witty/crash` by default. The `ghostty` command inside the app
bundle lists them:

```sh
/Applications/Witty.app/Contents/MacOS/ghostty +crash-report
macos/build/Debug/Witty.app/Contents/MacOS/ghostty +crash-report   # a debug build
```

## Sending a pull request

1. **Keep it small:** one change per pull request.
2. **Follow [FORK.md's merge rules](../FORK.md#merge-rules)**, which keep
   upstream merges working:
   - In a file that upstream also has, mark each hunk you add with a `Witty:`
     comment (in files that take comments, such as Zig, Swift and Markdown).
   - List every file that your change makes differ from upstream in FORK.md,
     by its path or its directory, with what you changed and why. FORK.md's
     check prints the files to list. It needs Ghostty as a remote named
     `upstream`; if you already use that name for `scamai/witty`, pick
     another name and change the command to match.

     ```sh
     git remote add upstream https://github.com/ghostty-org/ghostty   # once
     git fetch upstream && git diff --stat "$(git merge-base HEAD upstream/main)" HEAD
     ```

   - Never rename a compatibility identifier (merge rule 1): the `ghostty`
     executable, `TERM=xterm-ghostty`, the `GHOSTTY_*` environment variables,
     `config.ghostty` and the others listed there. Remote hosts' terminfo and
     shell integration depend on them.
   - Route any new per-user path through `build_config.user_dir` (merge rule
     2), so that Witty never reads or writes Ghostty's files.
   - Leave Ghostty's community files alone (the "No" rows in
     [Which documents apply here](#which-documents-apply-here)).
3. **Add a CHANGELOG entry.** If users will notice the change, describe it
   under `## [Unreleased]` in [CHANGELOG.md](../CHANGELOG.md).
4. **Say how you tested it**, including your macOS version and Mac if you
   tested on one. The [pull request template](PULL_REQUEST_TEMPLATE.md) has
   the checklist.
5. **Run [Witty's tests](#wittys-own-tests) yourself.** Today the only
   automatic check on a pull request is the Nix job inherited from upstream,
   which always reports "skipped". A maintainer builds and tests each pull
   request locally.

The maintainers do the upstream merges, so please don't open a pull request
that merges upstream Ghostty.

## AI-assisted contributions

This is Witty's rule:

- AI-assisted contributions are welcome. Say which tool you used and for
  what; the pull request template has a checkbox for it.
- You must understand every line you submit and be able to explain it in
  review.
- If a tool helped you write an issue or a comment, edit it down to what
  matters before you post it.
- Witty keeps no denouncement list.

[`AI_POLICY.md`](../AI_POLICY.md) at the root is Ghostty's. It applies when
you contribute to Ghostty, including when you send a Witty fix upstream.

## Sending work upstream

If a change would help every Ghostty user, propose it to Ghostty rather than
here. Ghostty's process applies there: read its
[CONTRIBUTING.md](https://github.com/ghostty-org/ghostty/blob/main/CONTRIBUTING.md),
get vouched before you open a pull request, and follow its
[AI_POLICY.md](https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md).
Once Ghostty has merged it, Witty gets it at its next upstream sync. If Witty
carried its own version of the change, its FORK.md row goes away then.

## Translations and packaging

- **Translations** go to Ghostty, whose guide for translators is
  [po/README_TRANSLATORS.md](../po/README_TRANSLATORS.md). A pull request to
  Ghostty needs a vouch first (see [Sending work upstream](#sending-work-upstream)).
  Witty picks translations up at its next upstream sync. A translation changed
  here would conflict with upstream's.
- **Packaging:** Witty's only builds are the macOS releases on
  [GitHub Releases](https://github.com/scamai/witty/releases) (signed and
  notarized DMGs since v0.2.0). It has no source tarballs and no Linux
  packages, and [PACKAGING.md](../PACKAGING.md) is Ghostty's. Please don't
  package Witty for Linux: a Linux build keeps Ghostty's GTK application ID
  (`com.mitchellh.ghostty`), so it shouldn't be installed next to Ghostty
  ([FORK.md, "Deliberately not changed"](../FORK.md#deliberately-not-changed)).

## No vouching

Witty does not use Ghostty's vouch system. `.github/VOUCHED.td` and the
`vouch-*` workflows are upstream files kept for merges; the workflows are
disabled here. You don't need a vouch to open an issue or a pull request in
this repository.

## License

Contributions are accepted under the [MIT license](../LICENSE) of this
repository (inbound = outbound): what you contribute is licensed under the
same terms as the rest of Witty. There is no CLA, and no sign-off is required.

## Who maintains Witty

Witty is maintained by a small team at Reality Inc.
[CODEOWNERS](CODEOWNERS) asks [@shenxingy](https://github.com/shenxingy) to
review every pull request. We read every issue and pull request, but a reply
can take a few days or longer.

## Code of conduct, security and support

- [Code of conduct](CODE_OF_CONDUCT.md): everyone who takes part in Witty's
  issues, discussions and pull requests is expected to follow it.
- [Security policy](SECURITY.md): how to report a vulnerability privately.
- [Support](SUPPORT.md): where to get help with Witty.
