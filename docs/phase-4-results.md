# Phase 4 acceptance: results

**Date:** 2026-11-20 to 2026-11-23 · **Build:** `dist/Zoe.app` 0.1.0 from `feat/34-phase-4-panels` (ad-hoc signed), launched with `open` · **Issue:** #39

**Verdict: PASS, with one budget overshoot and one bug found and fixed.** Claude draws tables, cards and choices; quiet mode, typing and calls all work. Zoe sometimes answered its own voice; that's fixed (below). The app's memory briefly peaked 25 MB over its conversation budget once (below).

No conversation content is kept here. The numbers come from Zoe's log, the decision log in the index (tool names only) and `scripts/measure.py`, which happened to run for about two days, so this run doubles as a first soak test.

## The phase 4 checks (PLAN.md §8)

| Check | How | Result |
|---|---|---|
| "Show my meetings this week" opens a table | Live, and automated (16 rows, two spoken sentences) | ✔ `show_table` allowed by exact name; sort and Copy work |
| Choices | Live: "three lunch ideas as choices", then a click | ✔ `show_choices`; the click became the next request |
| Quiet mode: nothing spoken, everything shown | Live: menu toggle and "quiet mode" | ✔ no speech, replies on screen, muted mark on the character |
| Typing works | Live: ⌃⌥T, a calendar question | ✔ same reply as spoken; works in quiet mode and during a call |
| Silent during a call | Live: another app recording from the mic | ✔ headphones on the character, triggers refused, typed replies shown and not spoken; back to normal after |

## Budgets (PLAN.md §12.2)

| Metric | Budget | Phase 4 | Phase 3 |
|---|---|---|---|
| App CPU, idle | ≈ 0 % | mean 0.13 % over ~2 days | 0.21 % |
| App CPU, in conversation | ≤ 20 % | mean 5.0 %, p90 12 % | mean 2.9 %, p90 10 % |
| App footprint, idle | ≤ 80 MB | 39–41 MB, flat for ~2 days (no growth) | 49–59 MB |
| App footprint, in conversation | ≤ 300 MB | mean 175 MB, **max 325 MB (over, once)** | max 217 MB |
| Core RSS | ≤ 80 MB | up to 81 MB (on the line); 1–5 MB when idle for hours (macOS compresses it) | up to 80 MB |
| Claude Code (not budgeted) | — | up to 584 MB | up to 1.45 GB (2 sessions) |

**What the panels cost** (UI demo, physical footprint): 13 MB idle → 17 MB talking → 30 MB with a table panel; SwiftUI keeps ~11 MB of it afterwards. The `ui` tool server adds nothing measurable to the core (67.2 MB with and without).

**The 325 MB peak** came from Whisper (~185 MB while loaded), live captions, the speaker and a panel being in memory at the same moment; it was back to 209 MB at the next sample and Whisper unloads 2 min after a conversation. The fix that removes it for good is the one already proposed: run Whisper in a helper process, taking its 185 MB out of the app.

## Problem found and fixed

**Zoe sometimes answered its own voice** (reported during the run). Half-duplex already ignored the mic while Zoe spoke, but listening resumed the moment the last buffer was "played", while the speakers (more so over Bluetooth) were still sounding its last words; and a typed request or clicked choice during a hands-free conversation was spoken while the mic listened. Now:
- listening resumes only after the output device's latency + 0.3 s (at least 0.4 s);
- a transcript that is mostly what Zoe said in the last 15 s is dropped as echo (one- or two-word phrases only if they match the end of the reply, so a real "yes" survives); self-tested;
- a typed or clicked request pauses the mic until its reply has been spoken.
Re-tested with the listen test: two spoken turns, two spoken replies, no echo turns.

## Observations for later

- **Run Whisper in a helper process** (also removes the 2-minute recompile on every development build).
- **The core sits at its 80 MB budget**; worth a look before phase 5 adds screen context and Mac tools.
- **Two-day soak:** no memory growth in the app while idle; CPU flat at ~0.13 %.
