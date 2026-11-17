# Phase 1 acceptance: results

**Date:** 2026-11-17 · **Build:** `dist/Zoe.app` 0.0.0 (builds 11 and 12, ad-hoc signed), launched with `open` · **Issue:** #8

**Verdict: PASS.** A spoken conversation of more than 5 turns, started with the hotkey, without headphones, using the Google Calendar connector, within the CPU and memory budgets. The mic was off whenever Zoe was idle. Two problems were found and fixed during the run (see below).

No audio, recordings or transcripts are kept or committed. The numbers come from Zoe's own `[metrics]` log lines (turn numbers and timings only) and from `scripts/measure.py`.

## What was run

- **Machine:** MacBook (Apple Silicon), macOS 26.6.1, built-in mic and speakers, no headphones.
- **Run 1:** 12 turns over 3 conversations (the longest 8 turns), started by tapping right ⌥, mostly calendar questions with follow-ups.
- **Run 2** (after the bubble fix): 7 more turns over 2 conversations, plus the hands-on checks.
- Sampling: `scripts/measure.py 2` (every 2 s) throughout both runs; 382 samples.

## Budgets (PLAN.md §12.2)

| Metric | Budget | Measured | |
|---|---|---|---|
| App CPU, idle | ≈ 0 % | mean 0.2–0.5 %, brief spikes up to 8 % (status updates, Whisper unload) | ✔ (near zero) |
| App CPU, in conversation | ≤ 20 % | mean 6–8 %, p90 11–14 %, max 42 % (a single sample while Whisper ran) | ✔ |
| App footprint, idle | ≤ 80 MB | 29–39 MB (57 MB while Whisper is still loaded after a conversation) | ✔ |
| App footprint, in conversation | ≤ 300 MB | mean 102–108 MB, max 190 MB | ✔ |
| Core RSS | ≤ 80 MB | 58–78 MB | ✔ |
| Claude Code (not budgeted, F01: ~250–325 MB per session) | — | 161–559 MB across its processes (CLI + MCP servers) | for the record |
| Mic off when idle | off | released after all 6 conversations (`mic held: false`), orange indicator gone | ✔ |

## Latency (19 turns with a transcript)

"End of turn" is when Zoe decided the turn was over: the release of the key, or in a hands-free conversation **0.7 s after I stopped speaking** (the VAD's silence window, which comes on top of every number below).

| Step | p50 | p90 | Range | Note |
|---|---|---|---|---|
| Trigger → listening (engine running) | 134 ms | — | 105–134 ms | 3.1 s once: the first trigger after install, while macOS asked for the microphone |
| End of turn → visual cue (orb switches to thinking) | ~0 ms | | | the instant acknowledgement |
| End of turn → transcript (Whisper) | 524 ms | 730 ms | 413–1141 ms | budget ≤ 600 ms: met at p50, not at p90 |
| End of turn → "On it." | 1.42 s | 1.59 s | 1.29–2.03 s | plays only if the reply hasn't started 0.8 s after the transcript |
| End of turn → first reply sentence | 2.9 s | 8.0 s | 1.6–11.5 s | almost all Claude: the core's own first-sentence time was 1.1–11 s; calendar tool calls are the slow ones |
| First sentence → first audio | 50–90 ms | | | target ≤ 150 ms ✔ |

## Hands-on checks

| Check | Result |
|---|---|
| Bubble shows the whole reply (after the fix) | ✔ |
| Tap right ⌥ while Zoe speaks: stops at once, keeps listening | ✔ |
| Click the orb: starts a conversation; click again: ends it | ✔ |
| Drag the orb: the position is saved and restored after a relaunch | ✔ |
| Orb visible over a full-screen app | ✔ |

## Problems found

1. **The bubble clipped long replies** (the last lines were cut off). It was sized from the text's one-line width, so wrapped text ran past the panel. Fixed: the bubble now measures the wrapped height at its width and becomes a scrolling card past ~340 pt.
2. **A rebuilt app lost its Accessibility grant,** and removing and re-adding it in System Settings didn't help. An ad-hoc signature identifies one exact build. What worked: `tccutil reset Accessibility io.github.amrakshay.zoe`, relaunch, grant at the prompt, relaunch. Released updates will likely hit the same thing once per update (documented in `docs/RELEASING.md`). For my own builds, a self-signed identity (`ZOE_SIGN_IDENTITY`) avoids it.
3. **The metrics logged "first reply audio" more than once per turn.** Fixed (only a reply's first sentence is timed).

Also corrected along the way: PLAN.md had said a per-turn chime was the ≤ 300 ms acknowledgement. There is no per-turn chime; the instant cue is visual.

## Observations for later phases

- **Time to the first spoken word is Claude's, not Zoe's:** Zoe's own part (Whisper + speech) is about 0.6 s; the rest is the model and its tool calls. Routing simple turns to a faster model, or speaking a short progress line while tools run, is phase 2+ work.
- **"On it." sometimes lands just before the reply** (fast turns start at 1.6–1.9 s, "On it." plays at ~1.4 s). It sounds slightly redundant; a longer delay or skipping it when a reply is already streaming are options.
- **Whisper p90 is over its 600 ms budget** (730 ms). Longer turns (10–13 s of audio) were not slower, so it's not length; unverified why.
- **Whisper's first-load compile** (about 2 minutes, once) recurred for every rebuilt *development* binary, but a rebuilt app bundle reused it in one test.
