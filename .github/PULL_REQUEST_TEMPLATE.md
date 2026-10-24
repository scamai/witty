<!-- Thanks for contributing to Witty. .github/CONTRIBUTING.md explains what belongs here and what belongs upstream in Ghostty. -->

## What and why

<!-- What does this change, and what problem does it solve? Link the issue, for example "Fixes #12". -->

## Witty or upstream?

- [ ] This change is Witty-specific (the `altscreen:` prefix, the tmux signal, app identity, packaging, release tooling or Witty's docs), or it fixes something that does not happen in stock Ghostty.
- [ ] This carries a fix for a bug that also happens in stock Ghostty, because it can't wait for an upstream sync. Ghostty report: <!-- link -->

<!-- If the problem also happens in stock Ghostty, the fix belongs in Ghostty first, under Ghostty's own contribution rules. See "Witty or Ghostty?" and "Sending work upstream" in .github/CONTRIBUTING.md. -->

## Fork checklist

- [ ] In files that upstream also has, each hunk I added is marked with a `Witty:` comment (where the file takes comments).
- [ ] Every file this PR makes differ from upstream is listed in FORK.md. To see them: `git fetch upstream && git diff --stat "$(git merge-base HEAD upstream/main)" HEAD` (with Ghostty as the `upstream` remote).
- [ ] No compatibility identifier from FORK.md merge rule 1 is renamed (such as the `ghostty` executable, `TERM=xterm-ghostty`, the `GHOSTTY_*` variables or `config.ghostty`).
- [ ] If users will notice the change, CHANGELOG.md has an entry under `[Unreleased]`.

## Testing

<!-- For example: zig build test -Dtest-filter=altscreen, a macOS build with zig build, and the manual steps you followed. -->

- macOS version and Mac (if you tested on a Mac):
- What I ran:

## AI assistance

<!-- AI-assisted contributions are welcome when they are disclosed and you understand every line. Tick one. -->

- [ ] I did not use AI tools for this PR.
- [ ] I used AI tools: <!-- which ones, and for what -->
