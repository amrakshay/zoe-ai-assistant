# Phase 2 acceptance: results

**Date:** 2026-11-20 · **Build:** `dist/Zoe.app` from `feat/14-phase-2-safety` (ad-hoc signed), launched with `open` · **Issue:** #22

**Verdict: PASS.** Every safety check in PLAN.md §8 (phase 2) holds with the real Claude session, by automated checks and by live voice and click tests. The live run found eight problems; all were fixed on the branch and re-tested (see "Problems found").

No message text, transcripts or audio are kept here. The decision log (`~/Library/Application Support/Zoe/actions.jsonl`, outside the repo) holds tool names, decisions and input hashes only.

## The phase 2 checks (PLAN.md §8)

| Check | How | Result |
|---|---|---|
| A Slack send waits for approval | Live: "send a Slack message to myself…"; the card showed the recipient's name and ID and the exact text; said "no" | ✔ denied by voice, nothing sent (log: `slack_send_message deny voice`) |
| An allow rule in settings can't skip the gate | Automated: a folder whose `.claude/settings.json` allows `Write`, `Edit` and `Bash`, used as Zoe's working folder; asked to create a file and to `touch` it | ✔ both still asked; denied; no file |
| Injected or outside content can't fetch a URL without asking | Automated: a web search (taints the session), then a fetch of a site I hadn't named | ✔ asked ("this conversation has read outside content (the web)"); a site I named myself runs without asking, by design |
| A password prompt opens Terminal | Live: "run sudo true" → **Run in Terminal** on the command card; and automated: approve → the command fails fast → a Terminal card | ✔ Terminal came to the front with the exact command; Zoe didn't run it (log: `Bash deny terminal`); Claude never asked for a password |
| Voice approval on an ask card; a click-only card refuses voice | Live: a file write approved by "yes"; a command card said "This one needs a click" and didn't listen | ✔ |
| Budgets still hold | `scripts/measure.py` every 2 s over the live run (1,080 samples) | ✔ (below) |

Also checked: approve → the action runs, deny → it doesn't (`Write allow click` / `Write deny click`); Claude's question answered by voice and by click, and the answer used; Open Conversation in Terminal → a line typed in Terminal was saved to the original session, and Zoe's next turn forked it and knew it; the original session never got Zoe's later turns.

## Budgets (PLAN.md §12.2)

| Metric | Budget | Phase 2 | Phase 1 |
|---|---|---|---|
| App CPU, idle | ≈ 0 % | mean 0.13 % (spikes up to 3.5 %) | 0.2–0.5 % |
| App CPU, in conversation | ≤ 20 % | mean 3.4 %, p90 10.5 % (max 50 %, a single sample during transcription) | mean 6–8 %, p90 11–14 % |
| App footprint, idle | ≤ 80 MB | 40–45 MB | 29–39 MB |
| App footprint, in conversation | ≤ 300 MB | mean 110 MB, max 227 MB | mean ~105 MB, max 190 MB |
| Core RSS | ≤ 80 MB | up to 80 MB (at the limit; was 58–78 MB) | 58–78 MB |
| Claude Code (not budgeted) | — | up to 615 MB across its processes | up to 559 MB |

The core is now at its 80 MB budget (the gate, renderers, names and taint added little each; the SDK is most of it). Watch it in phase 3.

## Problems found and fixed

1. **Slack cards showed a bare user ID.** Claude knew my ID from context, so no Slack result existed to take a name from. Now the persona asks Claude to look a recipient up first, the core learns ID → name pairs **only from Slack's own results** (never Claude's words), and an unknown ID is labelled as one. Slack's read-only tools joined the allowlist (exact names).
2. **"This one needs a click" was spoken twice** (the card's summary and the voice prompt both said it).
3. **A question was spoken twice** when its text already named the options ("teal or orange? Teal, or Orange?").
4. **`sudo -n true; echo …` didn't get a Terminal card:** it printed "a password is required" but exited 0, and that wording wasn't in the patterns.
5. **Typing in the handed-off Terminal session wasn't saved.** Zoe had been started from a Claude Code terminal; the variables it inherited reached the `claude` in Terminal, which ran as a "child session" with transcript saving off. The Terminal script now clears `CLAUDE*` and `ANTHROPIC*` first.
6. **Speech-to-text heard "ls" as "is",** and Claude went exploring for a "command file" to run (every command still needed a click). The persona now says to state what it understood and ask when a run/change/send request is unclear.
7. **The terminal button on a command card handed off the whole conversation** instead of running that command. Command cards now have **Run in Terminal** (that exact command, in its folder; Claude is told the user runs it); other cards still hand off.
8. **Terminal opened behind other windows,** because Zoe never takes focus. Zoe now hands focus to Terminal.

## Observations for later

- **Ad-hoc signing loses Accessibility (and sometimes the mic) on every rebuild,** even though System Settings still shows the switch on; `tccutil reset` then a fresh grant fixes it. A self-signed "Zoe Dev" identity (`ZOE_SIGN_IDENTITY`, docs/RELEASING.md) would end this for development builds.
- **Spoken option answers:** "teal" was heard as "Heel"; it didn't match an option, so it went to Claude as my own words and Claude guessed right. A small fuzzy match for one-word answers (edit distance) would catch this; not done.
- **Claude's first sentence after an approval can take long** (35 s once, with a Slack lookup and my voice answer inside the turn); approvals and lookups are inside Claude's turn, so the "On it." at ~1.4 s is the only early cue.
