# Contributing to Zoe

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Before you start

- **Every change starts with a GitHub issue.** Search the existing ones first. If none fits, open one describing the problem, the proposed change and how we'll know it's done.
- **Work on a branch and open a pull request.** Nothing is committed to `main` directly. Name branches `<type>/<issue>-<slug>` (e.g. `feat/12-push-to-talk`) and put `Closes #<issue>` in the PR description.
- Zoe has four design rules. Please keep them:
  - **Never act on a write without approval.** Every tool goes through the `PreToolUse` gate (PLAN.md §7).
  - **Stay fast and light.** Budgets are in PLAN.md §2.1 and §12.2.
  - **Audio stays on the Mac.** No cloud speech services.
  - **Nothing private in the repo:** no audio or recordings, raw transcripts, logs, tokens, or work-specific names. `scripts/ci-checks.sh` checks the obvious cases.
- Read [CLAUDE.md](CLAUDE.md) and [PLAN.md](PLAN.md).

## Build and test

There's no app yet. Until phase 1, CI runs the repo checks:

```bash
./scripts/ci-checks.sh
```

The feasibility spikes each have a "How to re-run" section in their report under `feasibility/`.

## Pull requests

- **Title:** use [Conventional Commits](https://www.conventionalcommits.org/), for example `feat: hold right option to talk`, `fix: …`, `docs: …`, `chore: …`.
  - PRs are squash-merged, so the title becomes the commit message.
  - The title drives the changelog and version numbers: `feat` bumps minor, `fix` bumps patch, and `feat!` or a `BREAKING CHANGE:` footer bumps major. Before 1.0, `feat` bumps the minor version only.
- Keep each PR focused on one change.
- Update README.md and PLAN.md in the same PR for anything user-visible or any design change.
- CI (`build-and-test`) must pass.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
