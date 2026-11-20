# Phase 3 acceptance: results

**Date:** 2026-11-20 · **Build:** `dist/Zoe.app` 0.1.0 from `feat/24-phase-3-sessions` (ad-hoc signed), launched with `open` · **Issue:** #31

**Verdict: PASS.** Zoe picks the right Claude Code session for what I say: it continues the current one, starts one in the repo I name, resumes an earlier one by description, and always does so in that session's own folder. Idle sessions close and come back with their context.

No conversation content is kept here. The numbers come from Zoe's log (routes and timings) and `scripts/measure.py`. The index (`zoe.db`) lives in Application Support, outside the repo.

## The phase 3 checks (PLAN.md §8)

| Check | How | Result |
|---|---|---|
| "In the <repo> repo…" opens a session there | Live (voice) and automated: "In the zoe repo, what's the first heading in the README?" | ✔ a new session in that repo's folder; the bubble showed "in zoe-ai-assistant" |
| Follow-ups continue the same session | "And the second heading?" | ✔ `route: continue … (used in the last 30 minutes)` |
| "Continue the <topic> from earlier" resumes that session in its own folder | Live: the code-word session; automated: the Portugal question | ✔ the Claude router picked the right session (2.8–4.0 s) and Zoe answered from its context |
| Recent Sessions → Continue Here | Live: the Lisbon session, then "Which city were we talking about?" | ✔ resumed in 0.38 s; answered Lisbon |
| Recent Sessions → Open in Terminal | Live | ✔ handed off; Terminal opened that conversation |
| A session idle for 10 min closes and resumes intact | Automated with a 10 s limit (`ZOE_IDLE_CLOSE_S`), and live: two sessions closed on their own | ✔ closed while idle; the next turn resumed by id and remembered the code word |

## Timings

| Step | Measured | Note |
|---|---|---|
| Local routing | well under 20 ms (tested at 200 projects, 50 sessions) | no model call |
| Seeding projects at start | 21 projects in 0.24–0.69 s | background; only the `cwd` lines of session files are read |
| Claude router (resume / ambiguous) | 2.8–4.0 s | Haiku, no tools, no settings; only for those requests |
| Title and summary | 2.3–2.7 s | background, when Zoe leaves a session |
| Connect a **new** session | ~11.5 s | a SessionStart hook in my user settings registers each new session with an outside service |
| **Resume** a session (after idle close, Continue Here, the router) | 0.38–0.41 s | that hook doesn't slow resumes |

## Budgets (PLAN.md §12.2)

| Metric | Budget | Phase 3 | Phase 2 |
|---|---|---|---|
| App CPU, idle | ≈ 0 % | mean 0.21 % | 0.13 % |
| App CPU, in conversation | ≤ 20 % | mean 2.9 %, p90 10 % | mean 3.4 %, p90 10.5 % |
| App footprint, idle | ≤ 80 MB | 49–59 MB | 40–45 MB |
| App footprint, in conversation | ≤ 300 MB | mean 91 MB, max 217 MB | mean 110 MB, max 227 MB |
| Core RSS | ≤ 80 MB | 59–80 MB (at the limit) | up to 80 MB |
| Claude Code (not budgeted) | — | up to 1.45 GB across 12 processes with 2 sessions live | up to 615 MB (1 session) |

## Observations for later

- **Two live sessions cost ~1.45 GB in Claude Code processes,** most of it the MCP servers each session starts from my settings. Zoe keeps at most two live and closes idle ones after 10 min; one live session might be the better default, now that resuming takes only 0.4 s.
- **New sessions take ~11.5 s to connect** because of my own SessionStart hook; resumes don't. Naming a repo for the first time pays it once.
- **The core is at its 80 MB budget.** The index, router and projects added little; the Agent SDK is most of it.
- **Asking Claude to "remember" something triggers a write to its memory file,** which needs approval like any write. That's the gate working, but it may be noisy in practice.
