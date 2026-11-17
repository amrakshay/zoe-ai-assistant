# F05: "hey claude" wake word in Swift

**Test:** F05 · **Date:** 2026-11-16 · **Plan:** PLAN.md rev 5, §2, §2.1, §6; REVIEW.md C3
**Spike folder:** `feasibility/spikes/f05-wake/`

## Verdict: PARTIAL

The **Swift runtime works**, but the **CPU budget and the model's accuracy both fail**.

- **Runtime: works.** A hand port of the openWakeWord pipeline (mel → embedding → `hey_claude` head) builds with SwiftPM on the Command Line Tools only, using Microsoft's official `onnxruntime-swift-package-manager` 1.24.2. Its scores match Python `openwakeword` 0.6.0 to within **8.9e-5 per frame** over 17,204 frames.
- **CPU: fails the ≤ 2 % budget.** Fed in 80 ms frames at real-time pace for 60 s, the always-on pipeline used **3.2–6.0 % of one core** across runs. That is about half of Python's 7.2 %, but still over budget.
  - The embedding CNN takes about 2.5 ms of CPU per frame. Paced like this it costs about 4× more than in a tight loop (0.96 ms), probably because the core idles between frames (low clocks or efficiency cores; unverified).
  - The Core ML execution provider was worse (6.5 %), and so was XNNPACK (4.7 %).
- **Accuracy: not usable as is.** On `say` voices, `hey_claude.onnx` caught only **3 of 48** positives at threshold 0.5. It fired on **6 of 32** near-miss negatives ("hey cloud" or "hey clod").
  - The pipeline itself is sound: the official `hey_jarvis_v0.1.onnx`, run through the same pipeline, scored 0.995 or higher on 4 of 4 `say` clips.
  - The audio is synthetic, so this is a warning sign, not a verdict on real speech.
- **livekit-wakeword doesn't fit.** Its current release (v2.x, Apache-2.0) no longer uses openWakeWord and **cannot load `hey_claude.onnx`**. The older v0.2.3 does bundle the same mel and embedding models, but it hard-codes tensor names that `hey_claude.onnx` doesn't use. That version is also deprecated.

## Environment

| Item | Value |
|---|---|
| Machine | Apple M4 Pro, 12 cores, 24 GB RAM, macOS 26 (Darwin 25.6.0) |
| Background load during runs | load average 2.6–4.1. Other work was running, which likely explains the spread in CPU figures. |
| Swift | Apple Swift 6.2 (swiftlang-6.2.0.19.9), Command Line Tools at `/Library/Developer/CommandLineTools`, no Xcode |
| ONNX Runtime (Swift) | `onnxruntime-swift-package-manager` tag `1.24.2`. Its binaries come from `download.onnxruntime.ai`, as the official package specifies. |
| Python | 3.11 (uv venv), `openwakeword==0.6.0`, `onnxruntime==1.32.0`, `numpy==2.4.6` |
| Base models | `melspectrogram.onnx` and `embedding_model.onnx` from the openWakeWord GitHub release v0.5.1 (the URLs the 0.6.0 package itself lists). SHA-256: `ba2b0e0f…fa26` (mel), `70d16429…c1f` (embedding). These are byte-identical to the copies bundled in livekit-wakeword v0.2.3. |
| Head | `hey_claude.onnx` (205 KB, SHA-256 `a40319c9…8951`). Input `onnx::Flatten_0` [1,16,96]; output `39` [1,1]. |

## Results

### 1. Python baseline: scores (`hey_claude.onnx`, openwakeword 0.6 ONNX)

**How the clips were made and scored:**
- **Voices:** 8 `say` voices: en-IN (Aman, Rishi, Tara), en-US (Samantha, Ralph), en-GB (Daniel, Flo), and en-AU (Karen).
- **Rates:** 150 and 210 words per minute, so 16 variants of each phrase.
- **Padding:** each clip was padded with 1 s of silence before and after.
- **Scoring:** clips were fed in 80 ms frames to a freshly reset model, and the table reports each clip's peak score.

| Kind | Phrase | n | min | median | max | ≥ 0.5 |
|---|---|---|---|---|---|---|
| positive | hey claude | 16 | 0.001 | 0.004 | 0.972 | **1** |
| positive | hey Claude, can you check my calendar | 16 | 0.001 | 0.010 | 0.942 | **2** |
| positive | hey Claude what time is it | 16 | 0.001 | 0.003 | 0.225 | **0** |
| negative | hey cloud | 16 | 0.001 | 0.002 | 0.952 | 2 |
| negative | say cloud out loud | 16 | 0.001 | 0.001 | 0.371 | 0 |
| negative | hey clod | 16 | 0.001 | 0.038 | 0.993 | 4 |
| negative | the weather today looks cloudy | 16 | 0.001 | 0.001 | 0.001 | 0 |
| negative | please open the terminal and run the tests | 16 | 0.001 | 0.001 | 0.001 | 0 |
| negative | hey there how are you | 16 | 0.001 | 0.001 | 0.001 | 0 |

- **Recall at 0.5:** 3 of 48 (6 %). The hits were Samantha at 150 wpm (2) and Rishi at 150 wpm (1). Ralph, Daniel, Flo and Aman never rose above 0.01.
- **Near-miss false accepts:** 6 of 32 ("hey cloud" or "hey clod"), from the Tara, Karen and Samantha voices.
- **Pipeline sanity check:**
  - The official `hey_jarvis_v0.1.onnx`, run through the same code, scored 0.995–0.999 on "hey jarvis" in 4 of 4 voices.
  - `okay_claude.onnx` scored 0.86 or higher on "okay claude" in 3 of 4 voices. It also scored 0.93 on "hey claude" from the Aman and Samantha voices, so it doesn't separate the two phrases.

### 2. False-positive estimate

- **Test audio:** 19.9 min in total.
  - 14.9 min of non-wake speech: one paragraph full of near-miss words ("cloud", "Claudia", "Clyde", "clawed", "Hey, did anyone…"), read three times by each of the 8 voices.
  - 5 min of low-level noise (σ = 30 LSB).
- **Result:** **0 detections at 0.5** (and 0 at 0.3). The peak score was 0.0009.
- **Per-hour rate:** the point estimate is 0 per hour. By the rule of three, the 95 % upper bound is **about 9 per hour**, because the sample is short.
- **Caveat:** this is synthetic TTS speech, not a room, music, TV or a real voice. Given the near-miss results above, this rate is **not** representative of real use (unverified).

### 3. Swift port vs Python

- **What was built:** `swift/Sources/F05Wake/main.swift`, about 300 lines. It is a direct port of `AudioFeatures._streaming_features` and `Model.predict` from openwakeword 0.6, for 80 ms frames:
  - the mel buffer is seeded with `ones(76,32)`, and the transform is `x/10 + 2`;
  - each frame takes 1,760 samples for the mel step (the frame plus 3×160 samples of context);
  - the embedding uses the last 76 mel rows;
  - the head uses the last 16 embeddings;
  - the first 5 predictions are zeroed.
- **Build:** `swift build -c release` succeeds on the Command Line Tools: the first build took 44 s, rebuilds about 3 s.
- **Match:** across all 144 clips plus the long speech file, the largest per-frame difference from Python was **8.86e-5** over 17,204 frames. Every clip's ≥ 0.5 decision is identical.
  - The init noise used to seed the feature buffer comes from a different random generator than Python's, and the match holds anyway.

### 4. CPU and memory (Swift, 80 ms frames at real-time pace, 60 s, one intra-op thread)

| Run | Provider | Avg CPU (% of one core) | CPU per frame | RSS (peak) | Footprint |
|---|---|---|---|---|---|
| speech file, run A | CPU | **3.22 %** | median 2.1 ms | 90.3 MB (`time -l`: 90.7 MB) | 78.8 MB |
| speech file, runs B and C | CPU | **6.05 %, 6.01 %** | — | 92.3 MB | 78.7 MB |
| 20 s spot checks | CPU | 3.8 % and 6.0 % (default QoS), 4.2 % (UI QoS), 5.1 % (utility QoS) | embedding 2.5–3.4 ms; mel 0.45 ms; head 0.08 ms | — | — |
| 20 s, batched 160 ms / 320 ms per call | CPU | 4.4 % / 3.7 % | — | — | — |
| 20 s | XNNPACK | 4.65 % | median 3.9 ms | 64.5 MB | 58.2 MB |
| 60 s | **Core ML** | **6.51 %** | median 5.5 ms | 285.8 MB at load | 156 MB |
| Python openwakeword (reference, 30 s) | ORT CPU | 7.18 % | — | 216.6 MB | — |

- **The budget is missed with the pipeline always on.** The ≤ 2 % budget in §2.1 is not met: the best measured run was 3.2 %, and runs typically landed at 4–6 % on this loaded machine.
- **Memory is borderline.** The process peaks at about 90 MB RSS, with a footprint of about 79 MB, for this pipeline alone. The app budget in §2.1 is ≤ 80 MB for everything.
- **Core ML is out:** it partitions the graphs into 5 and 20 pieces, uses more CPU, and adds about 200 MB at load. Note that `getrusage` doesn't count Neural Engine time.
- **An energy gate helps CPU but needs more work (experiment, not a pass).** The gate skips inference when the last 16 frames were all quieter than RMS 100.
  - On near-silence it cut CPU to **0.11–0.12 %**.
  - But it changed the ≥ 0.5 decision on 13 of 144 clips. The likely cause is that the quiet onset of "hey" (/h/) falls under the gate and is lost (unverified).
  - A usable gate would need to recompute the last ~1.3 s from the raw audio when it reopens; that was not built. Any VAD-driven gate has the same problem.

### 5. livekit-wakeword licence and fit

- **Licence:** Apache 2.0. The `LICENSE` file opens "Apache License / Version 2.0, January 2004", and the `NOTICE` file says:
  > "The source code and the model weights (*.onnx, *.tflite, encoders.tar.gz) are licensed under the Apache License, Version 2.0."

  This licence is permissive and compatible with the plan's reuse rules. It needs a NOTICE entry, which PLAN §6 assumes for MIT code.
- **Current version (main, v2.1.x, HEAD `0cfacde`, 2026-11-12): doesn't fit.**
  - The README says:
    > "The original LiveKit WakeWord implementation, based on openWakeWord, is deprecated. … Models from the deprecated implementation are not compatible with the new clients."
  - Its Swift `StreamingClassifier` requires a single end-to-end model with a `chunk` input and state tensors, and throws `notStreamingModel` otherwise. **`hey_claude.onnx` can't load.**
  - Its SwiftPM manifest depends on `onnxruntime-swift-package-manager` `from: "1.20.0"`. That version exists (tags `1.20.0`, `1.24.x`).
  - The build itself was **not tried** (unverified), because the model can't load anyway.
- **Legacy version (v0.2.3, deprecated): close, but no.**
  - It bundles the same openWakeWord `melspectrogram.onnx` and `embedding_model.onnx` (identical SHA-256).
  - Its `Classifier` hard-codes the input name `embeddings` and the output name `score`, while `hey_claude.onnx` uses `onnx::Flatten_0` and `39`. Loading would fail at run time unless the head's tensors were renamed (not tried).
  - Its streaming also differs from openWakeWord's: it re-runs mel on 1–3 s windows, so scores may not match the Python reference (unverified).
  - Building on it would mean depending on a deprecated tag.
- **Conclusion on REVIEW C3:** "use livekit-wakeword instead of porting by hand" doesn't hold for `hey_claude.onnx`. The hand port turned out small (about 150 lines of pipeline) and matches the Python reference exactly. The alternative is LiveKit's own encoder plus a retrained "hey claude" model, which LiveKit says is more accurate and cheaper on CPU (16.5 ms per second of audio, by their claim; unverified here). Note that its trainer uses LiveKit Inference TTS.

## Implications for PLAN.md

1. **§6 "What we reuse", livekit-wakeword row:**
   - Drop it as the runtime for `hey_claude.onnx`.
   - Replace it with "our own ~150-line port of the openWakeWord streaming front-end on `onnxruntime-swift-package-manager` (MIT), validated against Python to < 1e-4".
   - Or **decide** to switch to livekit-wakeword v2 with a retrained phrase. That changes the model, the training pipeline (LiveKit Inference TTS) and the licence (Apache-2.0, with a NOTICE entry).
2. **§2 Speech, wake word: `hey_claude.onnx` is not ready as the default.** Synthetic recall was 6 %, with false accepts on "hey cloud" and "hey clod". Before building, either:
   - **(a)** test it on real recordings of my voice (en-IN) in the room; or
   - **(b)** retrain: hey-claude's `training/` pipeline, or livekit-wakeword v2.

   My recommendation is (a) first, since it costs about 30 min. If recall is under 90 %, do (b).
3. **§2.1, CPU at idle ≤ 2 %:** it isn't met with the pipeline always on (3.2–6 % measured). Options:
   - **(a) Gate the wake word.** Use an energy or Silero gate that recomputes about 1.3 s of lookback when it reopens. On silence this measured about 0.1 %; the lookback still needs building and validating.
   - **(b) Relax the budget** to "≤ 2 % in silence, ≤ 6 % with speech or noise".
   - **(c) Use livekit-wakeword v2's cheaper encoder.**

   My recommendation is (a) + (b). Write the budget per acoustic condition, because idle at a quiet desk differs from idle with a TV on.
4. **§2.1, app memory ≤ 80 MB:** the wake pipeline alone has a footprint of about 79 MB (peak RSS about 90 MB) in a bare CLI. With Rive, Metal and SwiftUI on top, the 80 MB budget is not credible. Re-budget it, or measure inside the real app in phase 0.
5. **§2.1, "Core ML" or "Neural Engine" as a lever:** don't count on it. The Core ML execution provider was slower here and cost about 200 MB.
6. **REVIEW C3, technical-claims row "openWakeWord runs in Swift — Verified via ONNX Runtime (livekit-wakeword)":**
   - Change the source to "F05: hand port; livekit-wakeword v2 is not openWakeWord-compatible".
   - The claim itself now has a measurement behind it.
7. **Approach to note:** `okay_claude.onnx` fires on "hey claude". If both heads are loaded, treat them as one wake event, not two.

## How to re-run

```sh
cd feasibility/spikes/f05-wake

# Python env (openwakeword 0.6, ONNX)
uv venv -p 3.11 py/.venv && uv pip install -p py/.venv "openwakeword==0.6.*" onnxruntime numpy scipy

# Base models (official openWakeWord release) + heads
mkdir -p models && for f in melspectrogram embedding_model; do
  curl -sSL -o models/$f.onnx https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/$f.onnx; done
cp ../../assets/hey-claude/models/*.onnx models/

# Clips (~2 min). audio/long/*.wav were deleted after the run to save space; this recreates them.
rm -f audio/index.tsv && scripts/gen_clips.sh

# Python baseline -> results/py_scores.json, then the table
py/.venv/bin/python -I scripts/score_py.py
py/.venv/bin/python -I scripts/summarize.py py

# Swift (Command Line Tools only)
(cd swift && swift build -c release)
scripts/make_list.sh
swift/.build/release/F05Wake score models results/clips.tsv results/swift_scores.json
py/.venv/bin/python -I scripts/summarize.py swift py      # prints the max per-frame diff

# CPU and RSS at real-time pace (add --coreml, --xnnpack, --qos ui|utility, --batch N, --gate RMS)
/usr/bin/time -l swift/.build/release/F05Wake realtime models audio/long/l_0.wav 60
swift/.build/release/F05Wake realtime models silence 30 --gate 100
py/.venv/bin/python -I scripts/realtime_py.py audio/long/l_0.wav 30
```

- **Machine state:** take CPU figures with the machine otherwise idle. These runs had a load average of about 3–4, which is the likely reason for the 3.2–6 % spread.
- **Spike layout:**
  - `ext/` holds the two livekit-wakeword clones, the v2 HEAD and `v0.2.3`, for inspection only.
  - `swift/.build` (559 MB) and `py/.venv` (237 MB) can be deleted.

## Addendum (2026-11-17): own-voice test, verdict **FAIL** for `hey_claude.onnx`

**Method.**
- `spikes/f05-wake/scripts/record_wake.sh` records cued blocks on the MacBook Pro microphone: "Hey Claude" ×10 normal, ×8 followed by a command, ×6 from 1.5–2 m and quieter, ×6 fast; 12 near-misses; 51 s of free talk.
- Levels: mean −37 to −39 dB, peaks −14 to −17 dB.
- `scripts/score_own.py` (openwakeword 0.6.0 Python, which matches the Swift port to 9e-5) scores each block as one stream. It finds utterances by energy and counts one as detected if any frame up to 1 s after it scores ≥ the threshold.
- The energy finder split a few phrases in two (36 utterances for 30 cues), so recall is out of 36. Out of the 30 actual phrases it's the same: 3 detected.
- Report: `spikes/f05-wake/results/own_voice.md`. Audio: `spikes/f05-wake/audio/own/`.

| | ≥ 0.5 | ≥ 0.3 | ≥ 0.1 | ≥ 0.05 |
|---|---|---|---|---|
| "Hey Claude" detected | **3/36 (8 %)** | 3/36 | 3/36 | 4/36 |
| Near-misses fired | 0/13 | 0/13 | 0/13 | 0/13 |
| False fires, 2.5 min of ordinary speech | 0 | 0 | 0 | 0 |

- **Most "Hey Claude"s score 0.00–0.02**: not borderline, the model doesn't recognise my voice saying it. The three hits scored 0.72–0.89. No threshold helps.
- From 1.5–2 m: 0 of 8.
- **Not a level problem:** with +12 dB of gain the result is the same (3–5/36).
- It never fires on anything else, but that's no help at 8 % recall.

**Verdict.** The plan's gate (recall ≥ 90 %) fails badly. `hey_claude.onnx` can't be used as is. Phase 1 ships with **click and push-to-talk only**, with the wake word behind a setting, until a model passes this same test.

**Options to get a working wake word** (the scripts above re-run any new model on the same recordings):
1. **Few-shot head on my own recordings:** train a small classifier on openWakeWord's embedding features using these 30 phrases plus negatives, possibly with augmentation. This is quick (hours), but with one room and one mic there's a high risk of over-fitting, so it needs a fresh recording to test on.
2. **Full openWakeWord retrain:** thousands of synthetic clips (Piper TTS with many voices, including Indian English) plus my recordings, with augmentation. That's about a day, and slow on a Mac CPU. Generalises better.
3. **Different engine:** for example, a small always-on speech recogniser that listens for the phrase. Costlier in CPU; untested.
