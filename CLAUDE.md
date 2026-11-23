# CLAUDE.md

Guidance for AI coding assistants working on Zoe. User-facing documentation lives in README.md. The design lives in PLAN.md (where §12 overrides earlier sections), and the measured findings in `feasibility/`.

## What this is

Zoe is a macOS voice assistant that does its work through Claude Code:
- **App:** Swift 6 / SwiftUI + AppKit, macOS 26+, Apple Silicon, SwiftPM only (builds with the Command Line Tools).
- **Core:** Python 3.11+ (uv), a child process of the app, JSON lines over stdin/stdout. It owns the Claude Agent SDK, router, approval gate, session index, jobs and watchers.
- **Status:** phases 0–4 are done (feasibility; voice loop; safety: approvals, questions, Terminal handoff; sessions: router, index, repo aliases, resume; panels, quiet mode, typing, calls); results in `docs/phase-*-results.md`. Phase 5 (context and hands) is next. See PLAN.md §8.

## Layout

| Path | Contents |
|---|---|
| `PLAN.md` | Plan, decisions, architecture, phases, budgets |
| `REVIEW.md` | Adversarial design review and its findings |
| `feasibility/` | Phase 0 reports (`F01`–`F07`), summary, and spike code under `spikes/` |
| `mock/` | Interactive HTML mock of the flows |
| `scripts/ci-checks.sh` | Repo checks run by CI (privacy, syntax, version) |
| `Package.swift`, `app/Sources/` | Swift: `ZoeKit` (UI-free logic: JSON-lines framing, core supervision), `Zoe` (menu-bar app), `SelfTest` (`zoe-selftest`) |
| `core/` | Python core (uv): `src/zoe_core/` (`main.py` stdio loop, `protocol.py`), `tests/` (pytest) |

## Commands

```bash
cd core && uv sync && uv run pytest -q
```

```bash
swift build && swift run zoe-selftest
```

```bash
swift run Zoe --smoke "hello"
```

- App bundle: `./scripts/build-app.sh && ./scripts/package-release.sh && ./scripts/check-version.sh`. Resource use while Zoe runs: `python3 scripts/measure.py`. Without speaking: `swift run Zoe --ui-demo`, `--speak-test`, `--stt-bench <wav>`, `--listen-test N`.
- Run the self-test and the core tests after any change; the self-test must print `ALL CHECKS PASSED`.
- The core writes protocol messages only to stdout; logs go to stderr.

## Rules that must not regress

- **Approval gate:** every tool call goes through the catch-all `PreToolUse` hook with `on_failure="block"`. Allow rules in settings must never bypass it. Exact tool names only. Tainted turns (screen, clipboard, drop, connector content) ask before any network egress. Approval cards are rendered by the core from the raw tool input, never from Claude's description.
- **Audio stays on the Mac;** nothing is recorded or stored. The mic and audio engine are off when idle.
- **Fast and light:** keep to the budgets in PLAN.md §12.2. Measure, don't guess.
- **Honest data:** don't present unverified numbers as fact; label estimates.
- **Nothing private in git:** no audio, recordings, raw transcripts, logs, tokens, emails, or work-specific names (employer, ticket keys, internal environments, colleagues). `.gitignore` and `scripts/ci-checks.sh` cover the obvious cases.

## Workflow (mandatory)

1. **Issue first.** Before starting any work, check GitHub for an issue covering it:

   ```bash
   gh issue list -R amrakshay/zoe-ai-assistant --state all --search "<keywords>"
   ```

   If there isn't one, create it with `gh issue create`. Give it a Conventional-Commit-style title, the problem, the proposal and acceptance criteria.
2. **Never commit or push to `main`.** Branch from an up-to-date `main` as `<type>/<issue>-<slug>`. Open a PR with `gh pr create` and `Closes #N` in the body. The PR title is a Conventional Commit, since it becomes the squash commit and the changelog entry.
3. **CI must pass before merge** (`build-and-test`). The maintainer merges, with squash. CodeQL runs weekly and on demand.
4. **Don't merge release-please's release PRs yourself.** The maintainer merges them.

## Releases and commits

- Commit messages and PR titles are [Conventional Commits](https://www.conventionalcommits.org/). release-please derives the version and CHANGELOG from them.
- **Never edit `version.txt` or released CHANGELOG sections by hand.**
- Commits use the personal GitHub identity set in this clone's git config, never a work email.
- Full flow and one-time setup: [docs/RELEASING.md](docs/RELEASING.md).
