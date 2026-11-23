# Phase 5 acceptance: results

**Date:** 2026-11-24 · **Build:** `dist/Zoe.app` 0.1.0 from `feat/42-phase-5-context`, signed with a self-signed "Zoe Dev" identity (so permissions survive rebuilds), launched with `open` · **Issue:** #48

**Verdict: PASS, with three checks confirmed by me but not visible in Zoe's logs, and the memory peak still over budget** (Whisper is still in the app; the helper process is PR #49). Zoe understands "this" on screen, takes screenshots on a click, accepts drops, acts on the Mac with approval, drafts and pastes safely, and captures reminders.

No conversation content is kept here. Evidence comes from Zoe's log, the decision log in the index (tool, decision, how it was given, whether tainted) and `scripts/measure.py`.

## The phase 5 checks (PLAN.md §8)

| Check | Evidence | Result |
|---|---|---|
| "What's this error?" from the screen | confirmed by me (screen context is attached to the request, so it leaves no tool entry) | ✔ |
| Screenshot on request, click only, deleted after the turn | `take_screenshot` allowed by **click** (3×); no screenshot files left afterwards | ✔ |
| Drop a file, "summarise it" | `Read` of the dropped path after the drop | ✔ |
| Open Calculator (asks first) | `open_app` approved | ✔ |
| Reminder | `remind_me`; Reminders access granted once | ✔ |
| Draft into Slack, never sent | `show_draft` drawn; paste confirmed by me | ✔ (see below) |
| Clipboard read, then python.org needs a click | confirmed by me | ✔ (see below) |
| Note to the inbox | confirmed by me | ✔ (see below) |

**Not visible in the logs:** the decision log has no `get_clipboard`, `open_url` or `add_note` entry for the run, no `inbox.md` was created in Zoe's folder, and the app didn't log "draft pasted". I confirmed all three passed, so they may have gone a different way than scripted (for example Claude answering without the tool, or Copy rather than Paste). Worth a targeted re-run that watches the decision log.

## What the screen probe found (#42)

| App | Selected text | Page URL |
|---|---|---|
| Brave (Chromium) | ✔ via Accessibility (≤ 19 ms) | ✔ |
| Slack (Electron) | ✔ via Accessibility (≤ 19 ms) | — |
| iTerm2 | ✔ via Accessibility (≤ 16 ms) | — |
| Safari | ✘ (spoken requests fall back to ⌘C, clipboard restored) | ✔ |

Turning on `AXManualAccessibility` is what makes Chromium and Electron apps expose the selection (the phase 0 probe got nothing without it). VS Code and Chrome weren't tried; as Electron and Chromium apps they likely behave like Slack and Brave (unverified).

## Budgets (PLAN.md §12.2)

| Metric | Budget | Phase 5 | Phase 4 |
|---|---|---|---|
| App CPU, idle | ≈ 0 % | mean 0.37 % | 0.13 % |
| App CPU, in conversation | ≤ 20 % | mean 4.8 %, p90 11 % | mean 5.0 %, p90 12 % |
| App footprint, idle | ≤ 80 MB | 26–45 MB | 39–41 MB |
| App footprint, in conversation | ≤ 300 MB (app + Whisper helper once #49 lands) | mean 169 MB, **max 339 MB (over)** | max 325 MB |
| Core RSS | ≤ 80 MB | up to 80 MB | up to 81 MB |
| Claude Code (not budgeted) | — | up to 633 MB | up to 584 MB |

The peak is still Whisper (~185 MB while loaded) in the app alongside captions, the speaker and panels. PR #49 moves Whisper into a helper process; per the budget rule, app + helper are counted together, and that PR's own estimate (325–335 MB) is also over 300 MB, so the budget question remains open after it.

## Problems found and fixed during phase 5

- **CI couldn't build at all** (unrelated to phase 5): `download.onnxruntime.ai` has served a certificate for `*.azureedge.net` since 2026-11-20. The byte-identical archive is now hosted on this repo's pre-release `deps-onnxruntime-1.24.2`, with Microsoft's checksum unchanged (#50).
- **The VAD model download changed upstream:** the URL followed `master`, and silero-vad v6.3 put a new model there, which Zoe's checksum refused. Pinned to tag v6.2.3, the model Zoe was tested with (#51).
- **Permissions lost on every rebuild:** builds are now signed with a self-signed "Zoe Dev" identity; Accessibility was granted once and should stay.
- **A broken build was committed** once because a chained check read grep's output instead of the build's exit status (fixed before pushing; the checks now test the build's own status).

## Observations for later

- **Memory:** app + Whisper (helper or not) is ~325–339 MB at peak against 300 MB. Either trim (captions and Whisper not loaded together, smaller panels) or restate the budget with the measured number.
- **Re-check the three unlogged items** with the decision log open.
- **Safari selection** relies on the ⌘C fallback; typed requests can't use it (Zoe's own text box has the keyboard).
