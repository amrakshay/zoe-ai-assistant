# Feasibility tests: summary

_Phase 0 run of 2026-11-16, on macOS 26.6.1 (Apple Silicon), Command Line Tools only (no Xcode), Claude Code 2.1.325, claude-agent-sdk 0.2.182._

> **About this public copy.** Work-specific names were replaced with placeholders before publishing: ticket keys (`PRJ-…`), a product (`ATLAS`), dev environments (`alpha`, `beta`, `gamma`), a repo (`acme-collector`), company plugins and MCP servers, and a colleague's name. The replacements were applied to references and transcripts alike, so a few speech-to-text examples read oddly (an engine hearing "average" for `alpha`). Every number was measured on the original material. Raw outputs (logs, per-run transcripts, score dumps), all audio including recordings of my voice, and downloaded models are **not in git** (see `.gitignore`). The spike scripts re-create them.

Seven tests ran in parallel. Each has a full report in this folder, and each test's code is kept under `spikes/<id>/` so it can be re-run.

I re-checked a sample of each report's key numbers against its raw output (see **Spot checks**). All test audio was synthetic (`say` voices), so every accuracy number is a proxy until it's re-run on my own voice.

## Results at a glance

| Test | Verdict | What it means for the plan |
|---|---|---|
| [F01 SDK on subscription](F01-sdk-subscription.md) | **PARTIAL** | Works on my Claude login (`apiKeySource: none`, `authMethod: claude.ai`), loading the same 38 MCP servers, 9 plugins and 90 skills as the CLI. In-process MCP works. **But:** the login is my **company Team plan**, which makes personal use an employer-policy question; each session costs about 250–325 MB plus about 240 MB of duplicated local MCP servers; my `SessionStart` hook adds about 11 s to a fresh connect. |
| [F02 Approval gate](F02-approval-gate.md) | **PASS** | The `PreToolUse` hook runs before allow rules (B1 reproduced and fixed). A hook "ask" reaches `can_use_tool`. `AskUserQuestion` and `ExitPlanMode` work when listed in `tools`. Interactive commands fail in < 0.3 s. Two writers split a conversation, so the handoff rule stands. **But:** a hook that throws **fails open** unless `on_failure="block"`. |
| [F03 Echo cancellation](F03-echo-cancellation.md) | **PASS with Zoe (Premium)**, barge-in untested (addendum) | The synthesised voice played through a player node on the voice-processing engine is cancelled: echo drops about 22–31 dB, to the noise floor. **But:** voice processing costs 9–12 % CPU and about 86 MB even when idle, so it must run only during conversations. Zoe (Premium) since installed: 28 dB. Barge-in is untested. |
| [F04 Speech-to-text](F04-speech-to-text.md) | **FAIL on my voice** | Fast: finals 50–70 ms after the last audio. On synthetic voices DictationTranscriber looked good (15 % word errors). **On my own voice:** the best engine, SpeechTranscriber en-US, has **32 % word errors with only 5–6 of 17 tech terms right** (Grafana → "Rapana", Kubernetes → "Cubanitis", CCB → "SUV"). DictationTranscriber drops whole spans (48–52 %). **Whisper large-v3-turbo** (addenda 2–3): on 30 phrases, including 15 held-out ones, Claude gets my intent fully right from Whisper's text 23/30 and wrong 3/30, against Apple's 13/30 and 10/30. A term prompt doesn't help intent and adds 0.4 s, so **no prompt: 0.49 s to the final text**, about 185 MB in-process. Ids and environment names still slip, so read them back before writes. |
| [F05 Wake word](F05-wake-word.md) | **PARTIAL; model FAILS on my voice** (3/36 detected, addendum) | Hand-ported to Swift on the official ONNX Runtime package; it matches Python to within 9e-5 and builds without Xcode. **But:** CPU is 3.2–6 % (budget 2 %) and RSS about 90 MB. `hey_claude.onnx` caught only **3 of 48** synthetic positives, and "hey cloud" or "hey clod" fired 6 of 32 times. livekit-wakeword v2 can't load openWakeWord models. |
| [F06 Rive floating window](F06-rive-floating-window.md) | **PASS** | Builds with SwiftPM and no Xcode. The transparent, floating, all-Spaces panel works (90.6 % transparent pixels), and state-machine inputs can be driven from code. CPU: 120 fps by default (10–13 %), 30 fps about 4 %, 10 fps about 2 %, paused 0 %. Footprint about 126 MB while animating. Transparency needs an artboard with no background. |
| [F07 macOS integration](F07-macos-integration.md) | **PASS after Accessibility** (addendum); Chromium selection unverified | Per-process **call detection works with no permission** (listeners on `prs#` and `pdv#`, plus a 2–5 s poll). Frontmost app works. Selected text, window title, push-to-talk and the paste keystroke **work since Accessibility was granted** (Chromium selection unverified). Paste safety logic is verified. The browser URL needs Automation permission. |

## What changes in the plan

These are applied in `PLAN.md` rev 6 (§12) and rev 7 (push-to-talk first).

1. **Gate.**
   - One catch-all `PreToolUse` hook with an explicit `timeout` and `on_failure="block"`. "Ask" goes to `can_use_tool`, which renders the card.
   - `AskUserQuestion` and `ExitPlanMode` are listed explicitly in `tools`.
   - Plan mode stays banned, because it auto-writes to `~/.claude/plans/`.
2. **Audio engine.**
   - While waiting for the wake word: a plain engine (about 0.5 % CPU, 29 MB).
   - Voice processing starts only for a conversation.
   - Connect the graph before enabling voice processing.
   - Warm the synthesiser up at launch; the first buffer takes 399 ms, later ones 31–35 ms.
   - Compute mouth levels from the buffers before playing them.
3. **Speech-to-text (changed after the own-voice tests):** Whisper large-v3-turbo via WhisperKit, **no prompt**, for the final transcript; SpeechTranscriber only for live partial captions; ids, names and environments read back before any write. Drop the SFSpeechRecognizer fallback.
4. **Wake word (rev 7): moved to a later phase (phase 9).** `hey_claude.onnx` caught 3 of 36 of my "Hey Claude"s. v1 starts with a push-to-talk hotkey (hold, or tap for hands-free) and a click; the mic and audio engine stay off when idle. For phase 9: keep the in-house Swift port on ONNX Runtime, retrain the model, add an energy gate with about 1.3 s of look-back, and re-run `spikes/f05-wake/scripts/record_wake.sh` as the gate.
5. **Character:** set fps explicitly (30 while active), pause when idle instead of running at 10 fps, use an asset with no background, and target Rive's data-binding API.
6. **SDK sessions:**
   - Pass an explicit, trimmed `mcp_servers` set, so local stdio servers (tradingview, web-search, voicemode) aren't duplicated per session.
   - Skip my user `SessionStart` hook for assistant sessions, or keep one warm session.
7. **Budget** rewritten from measured numbers (§12).

## Decisions and actions for me

| # | Item | Options | Recommendation |
|---|---|---|---|
| 1 | **Team plan login.** The SDK runs on my company Team seat. | (a) Confirm with IT that a self-hosted voice front-end on my seat is fine, since it's mostly work use. (b) Use a personal Pro/Max account. (c) Use an API key. | **Done 2026-11-17:** IT confirmed the Team seat can be used (reported by me; no written record in this folder). |
| 2 | **Wake-word model.** | (a) Run my own voice through `hey_claude.onnx` first. (b) Retrain now with real and synthetic data. (c) Click and push-to-talk only for v1. | **Done 2026-11-17:** my voice got 3/36 (8 %), 0 false fires. Phase 1 ships click + push-to-talk; next is retraining (F05 addendum lists 3 options). |
| 3 | Grant **Accessibility** to the Claude app, then re-run the F07 context, push-to-talk and paste steps. | **Done 2026-11-17.** Window title, native-app selection, paste and push-to-talk (right ⌥ and ⌃⌥Space) all work. Chromium selection unverified (F07 addendum). |
| 4 | Install a **Premium English voice** (System Settings → Accessibility → Spoken Content), then re-run F03. | **Done 2026-11-17** (Zoe). Echo removed 28 dB; first sentence 1.1 s cold (F03 addendum). |
| 5 | Run `spikes/f04-stt/record_and_test.sh` with my voice. | | **Done.** Apple failed (32 % word errors, 35 % of terms). Whisper with a prompt: 17 %, 94 % of terms. |
| 6 | **Cleanup.** | | **Done 2026-11-16.** (The Whisper models added later take 2.1 GB in `spikes/f04-stt/whisper_models/`; delete when done.) About 2.8 GB of build caches (`.build`, `.venv`) deleted; each spike rebuilds them on re-run (`swift build`, `uv sync`). The two F02 test plan files were moved from `~/.claude/plans/` to the Trash. |
| 7 | **Speech-to-text gate.** Held-out set done: Whisper with no prompt gets intent right or nearly right 27/30, wrong 3/30; word errors 19–24 %. | (a) Replace the word-error gate with an intent gate (≥ 90 % same-or-partial, ≤ 10 % wrong) and accept Whisper with no prompt. (b) Keep the word-error gate (< 15 %) and keep tuning. (c) Test a larger set (50+ phrases, noisy room) first. | **Decided 2026-11-17: (a).** Intent gate adopted; Whisper with no prompt passes, right on the 10 % line, so keep checking it with real use in phase 1. Read-back of ids and names is the safety net. |

## Spot checks

| Report claim | Checked by | Result |
|---|---|---|
| F01 auth via login | `grep apiKeySource spikes/f01-sdk/out` | 4 × `"none"` ✔ |
| F02 `AskUserQuestion` answer reaches Claude | `spikes/f02-gate/logs/q4_ask.log` | "You chose Green." ✔ |
| F03 echo reduction | Re-ran `analyze.py novp vp` on both runs | Excess-power 22.3 dB; linear-echo 30.6 / 26.5 dB. The report says 31–34 dB, **slightly high**, so I'm using 22–31 dB. |
| F04 word error rate table | Re-ran `wer.py results` | Matches the report ✔ |
| F05 detections | Recounted `results/{py,swift}_scores.json` | Positives 3/48, negatives fired 6/96 (all near misses), same in Python and Swift ✔ |
| F06 CPU / fps / footprint | `spikes/f06-rive/results/summary.txt` | Matches the report ✔ |
| F01 vs F02 on `AskUserQuestion` | Compared both reports | Not a contradiction. It's absent from the default tool list (F01) and works when listed in `tools` (F02). |

## Not yet tested

- **Barge-in:** talking over the assistant.
- **Two voice-processing apps at once:** needs a real call.
- **Waits over 70 s** in a hook or callback (the 4 h job auto-deny).
- **Login token refresh** in a long-lived core.
- **Dragging the character by hand.**
- **On all Spaces and over full-screen apps:** configured but not checked by eye.
- **Paste reliability** in Slack and IDEs.
- **Parallel-session limits** on the subscription.
- **Watcher APIs.**
