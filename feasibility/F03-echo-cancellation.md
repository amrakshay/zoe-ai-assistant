# F03: echo cancellation of synthesised speech through AVAudioEngine voice processing

**Test ID:** F03 · **Date:** 2026-11-16 (run 13:20–14:05 UTC) · **Plan ref:** PLAN.md rev 5 §2, §2.1, §3; REVIEW.md B4

## Verdict: PARTIAL

**The planned path works.** The path is `AVSpeechSynthesizer.write(_:toBufferCallback:)` → `AVAudioPlayerNode` → an engine with `inputNode.setVoiceProcessingEnabled(true)`. With it, the assistant's voice on the built-in speakers is cancelled down to the mic's noise floor:
- **Steady-state reduction:** about 31–34 dB (two runs).
- **Residual:** one short burst at the start of playback, about 1 s in, at −29 dBFS.

The verdict is PARTIAL, not PASS, for these reasons:
1. **No Premium or Enhanced English voice is installed**, so every test used `Samantha (compact)`.
2. **The speaker level under voice processing (VP) was not measured independently.** A second, non-VP recorder process stops receiving mic audio as soon as the VP engine starts. So the ERLE assumes the speakers played at the same level with VP on as with it off.
3. **Barge-in (me talking over the assistant) was not tested.**
4. **VP is not cheap.** It costs 9–12 % of one core and about +57 MB RSS while idle. That breaks the §2.1 idle budget if VP stays on all the time.

**Gotcha found:** if VP is enabled before the player→mixer graph is connected, `engine.start()` fails with `-10875` (`kAUInitialize` on the output node, output format 0 Hz / 0 ch). Connect the graph first, then enable VP.

**The reviewer's failing case (`speak()` with VP on) is inconclusive.** The mic showed little or no synthesiser echo in 2 of 3 runs. That could be because it was cancelled, or because VP ducked or quieted the playback. I could not tell which (see Results).

## Environment

| Item | Value |
|---|---|
| macOS | 26.6.1 (25G76), Apple Silicon (arm64) |
| Toolchain | Swift 6.2 (swiftlang-6.2.0.19.9), Command Line Tools only, `swiftc -O -swift-version 5` |
| Output | MacBook Pro Speakers (default, built-in, 48 kHz), output volume 75 %, not muted |
| Input | MacBook Pro Microphone (default, built-in, 48 kHz), input volume 62 % |
| Other devices present | LG FULL HD (HDMI), ZoomAudioDevice (virtual), neither is default |
| Mic permission | `AVCaptureDevice.authorizationStatus(.audio)` = `authorized` for the binary launched from this Claude Code session. No prompt appeared and no input was all-zero. |
| Room | Uncontrolled. Run 1 picked up unrelated room sound (see below). |

## Results

### 1. Installed voices (en-US, en-GB, en-IN)

**No Enhanced or Premium voices are installed.** Every voice reports quality `default`:

| Locale | Voices |
|---|---|
| en-US | Samantha (`com.apple.voice.compact.en-US.Samantha`)<br>Eloquence voices: Eddy, Flo, Grandma, Grandpa, Reed, Rocko, Sandy, Shelley<br>Legacy/novelty voices: Albert, Bad News, Bahh, Bells, Boing, Bubbles, Cellos, Fred, Good News, Jester, Junior, Kathy, Organ, Ralph, Superstar, Trinoids, Whisper, Wobble, Zarvox |
| en-GB | Daniel (compact), plus the eight Eloquence voices |
| en-IN | Rishi (compact) |

All tests used **Samantha (compact)**, pinned with `VOICE_ID`.

**To get a Premium voice:** System Settings → Accessibility → Spoken Content → System voice → Manage Voices → download, for example "Zoe (Premium)" or "Ava (Premium)". This is a manual step for Akshay. Premium-voice latency and echo are **unverified**.

### 2. Synthesis latency (`write(_:toBufferCallback:)`, Samantha compact)

The phrase was 2 sentences and produced 9.73 s of audio.

| Run | Time to first buffer | Total synthesis | Real-time factor |
|---|---|---|---|
| 1 (cold, first use in process) | 399 ms | 445 ms | 0.046 |
| 2 (warm) | 31 ms | 79 ms | 0.008 |
| 3 (warm) | 35 ms | 90 ms | 0.009 |
| "On it." (warm) | 29 ms | 37 ms | — |

**Buffer format:** `AVAudioPCMBuffer`, Float32, 22,050 Hz, mono, non-interleaved. There were 839 buffers of about 256 frames each.
- **No conversion was needed.** The player node is connected to the main mixer with this format, and the mixer resamples to 48 kHz stereo.
- **Implication:** the cold first call (about 0.4 s) misses the 300 ms acknowledgement budget, so warm up the synthesiser at app start. Warm calls are about 30 ms.

### 3. Echo measurement

**Method**
- **Recording.** Each case records the mic for 8.5 s: 1.5 s of silence, then 5.5 s of speech, then 1.5 s of tail.
  - The mic tap records channel 0. Under VP the input node reports **9 channels at 48 kHz**, and all 9 carried identical energy.
  - The reference is the same synthesised audio (`*_ref.wav`), resampled to 48 kHz for analysis.
- **Metrics** (`analyze.py`):
  - **Silence vs playback:** RMS of the silence (0.3–1.5 s) and of the playback window.
  - **Echo excess:** playback power minus silence power.
  - **Cross-correlation:** a normalised cross-correlation peak against the reference, and a Welch cross-spectrum "linearly predictable from the reference" echo power.
  - **Per-bin view:** for every 250 ms bin, the level and the best local correlation with the reference. Chance level for that local correlation is about 0.15–0.25; a clear echo scores about 0.4–0.7.
- **How ERLE is computed.** ERLE is measured against the VP-off run, at the same volume, position and audio:
  - **excess-power ERLE:** the drop in mean echo power;
  - **linear ERLE:** the drop in coherent echo power;
  - **median-bin:** the median 250 ms level during playback, VP off versus VP on.

**Run 2 (primary)**

Cases ran back to back with no other recorder running.

| Case | Silence dBFS | Playback dBFS (mean) | Playback median bin dBFS | Post-playback floor dBFS | Xcorr peak (norm.) | Linear-echo share of mic power | Linear echo dBFS |
|---|---|---|---|---|---|---|---|
| **VP off**, player node | −37.7 | −20.7 | −20.6 | −36.3 | **0.493** | **56.5 %** | −23.1 |
| **VP on**, player node (the plan) | −48.8 | −42.1 | **−54.4** | −55.8 | **0.090** | 6.8 % | −53.7 |
| VP on, `speak()` | −48.3 | −52.2 | −54.3 | −54.2 | 0.057 | 1.7 % | −70.5 |
| VP on, `speak()`, ducking set to `.min` | −48.7 | −50.7 | −53.1 | −45.1 | 0.045 | 1.5 % | −65.3 |

ERLE for the player-node path (run 2):

| Measure | ERLE | Notes |
|---|---|---|
| Linear (coherent) echo | **30.6 dB** | |
| Median playback bin | **33.8 dB** | −20.6 → −54.4 dBFS. This is a lower bound: VP output sits at its own noise floor, about −55 dBFS. |
| Mean excess power | **22.3 dB** | Conservative. The mean is dominated by one 250 ms bin at 2.50 s (−29 dBFS, local xcorr 0.33): residual echo about 1 s after playback started, before the canceller converged. Every later bin is at −51 to −58 dBFS. |

**Run 1 (repeat, with caveats)**

A separate non-VP recorder process ran alongside. It **stopped receiving audio when the VP engine started** (0.7 s and 1.4 s captured), so independent raw capture under VP is not possible.

| Case | Playback median bin dBFS | Floor dBFS | Linear ERLE vs VP off | Median-bin ERLE | Notes |
|---|---|---|---|---|---|
| VP off | −20.2 | −39.2 | — | — | xcorr 0.498 |
| VP on, player node | −52.7 | −54.8 | 26.5 dB | **32.5 dB** | Loud bins at 0.25–1.25 s (before playback) and at 4.0–5.0 s, with local xcorr 0.00–0.14. That is room sound, not echo. The mean-based numbers for this run are invalid. |
| VP on, `speak()` | −52.5 | −54.7 | 23.3 dB | — | Bins at 2.5–3.75 s reached −19 to −30 dBFS (xcorr 0.18–0.39), then dropped to the floor. |

**Other findings from the echo runs**
- **Noise suppression.** VP also lowers the background noise floor by about 19 dB (from −36 to −55 dBFS). That is good for VAD, but its effect on speech-to-text accuracy is **unverified**.
- **`speak()` + VP is inconclusive.**
  - The mic shows little correlated echo in run 2 and with ducking set to `.min`, but it shows clear energy for about 1.25 s in run 1.
  - The ducking change was applied and confirmed (`duckingLevel` read back as 10), and it did not bring the echo back.
  - I could not measure whether `speak()` audio actually came out of the speakers at normal level while VP was on. The independent recorder is starved under VP, and nobody listened.
  - So REVIEW.md B4's claim ("`speak()` is not cancelled") is **neither confirmed nor refuted** here. The plan's player-node path is the one with positive evidence.
- **Startup ordering bug.**
  - **Symptom:** calling `setVoiceProcessingEnabled(true)` before `engine.connect(player, to: mainMixerNode, …)` leaves `outputNode` at 0 Hz / 0 ch, and `engine.start()` throws `-10875`.
  - **Reproduced:** 3 times (echo vp, echo speak, and idle).
  - **Fix:** build the output graph first, then enable VP. It worked every time after that.

**Plays used:** 8 of the 8 allowed, each 5.5 s or shorter. The two VP attempts that failed to start played nothing.

### 4. Mouth level

**It works.** A tap on the player node output, with a 20 ms buffer size requested, gives a level every 20 ms:
- It produced 425 windows of 20 ms per run, 254 of them with speech above −60 dBFS, at a peak RMS of 0.27. The result was identical with VP on and off.
- **Caveat:** the tap ignores the requested size. Callbacks arrive every **96 ms** (median, 85 calls) carrying about 4,800 frames, which I split into 20 ms windows. A tap-driven mouth therefore lags by up to about 100 ms and updates in bursts.
- **Better for the app:** compute the 20 ms envelope from the synthesiser buffers before scheduling them; the samples are already in hand. Then drive the mouth from `player.playerTime(forNodeTime: player.lastRenderTime)`. This is **unverified**, but standard.

### 5. Footprint while idle

The engine ran with VP on, the mic tap installed, a player attached, and no playback, for about 20 s.

| Config | CPU (getrusage, % of one core) | Cross-check | RSS |
|---|---|---|---|
| VP **on** (3 runs) | 12.1 %, 11.8 %, 8.9 % | `ps time` 1.83 s CPU over 15 s = 12.2 %; `top` 9.9 % | 69–88 MB; peak `ru_maxrss` 86–88 MB; `top` MEM 56 MB |
| VP **off** (same graph) | **0.47 %** | — | `ru_maxrss` 29 MB |
| Bare process, no engine (`f03 voices`) | — | — | 25.7 MB peak RSS, 6.6 MB footprint |

`coreaudiod` was about 0.9 % CPU and 33 MB in a sample taken while the idle test was failing on the ordering bug, **not** during the VP-on idle run. Its share during VP was not measured.

**Code and recordings** (all in `feasibility/spikes/f03-echo/`):

| File | What it is |
|---|---|
| `f03.swift` | The spike, single file |
| `f03` | Built binary |
| `analyze.py` | Analysis script |
| `novp_mic.wav`, `vp_mic.wav`, `speak_mic.wav`, `speakduckmin_mic.wav` | Run 2 mic recordings (16-bit, 48 kHz mono) |
| `*_ref.wav`, `*_meta.json` | Matching reference audio and play-window indices for each case |
| `run1/` | Run 1, including `*_raw.wav`: the starved independent recorder captures |
| `ref_full.wav` | Full 9.73 s synthesised phrase |

## Implications for PLAN.md

1. **Full duplex is viable for the planned path.** Keep §3 as written: `write(toBufferCallback:)` → `AVAudioPlayerNode` on the VP engine.
   - About 31–34 dB steady-state echo reduction, with the residual at the noise floor, is enough that VAD and the wake word should not trigger on the assistant's own voice. This is **inferred, not tested**: I did not run VAD or the wake word on these recordings. A cheap follow-up is to feed `vp_mic.wav` into Silero and openWakeWord offline.
   - **Keep the half-duplex fallback** until the remaining tests pass:
     - **Barge-in:** a human talking over playback. Not tested, and it is what full duplex is for.
     - **Onset residual:** the burst about 1 s into playback (−29 dBFS for 250 ms) could trip VAD. Mitigation: gate VAD for about the first 1 s of each utterance, or raise its threshold while speaking.
     - **A Premium voice.**
     - **An ear check** that VP does not quiet the assistant's own playback.
2. **The §2.1 idle budget cannot be met with VP always on.** VP-on idle is 9–12 % of one core and about 86 MB RSS, against a budget of 2 % CPU and 80 MB for the whole app. Proposed change:
   - **Idle (wake word only):** a plain engine with no VP, measured at 0.5 % CPU and 29 MB.
   - **After wake or click,** for the duration of the conversation: switch to the VP engine.
   - **Follow-ups to measure:** the switch cost (engine stop, enable VP, start) against the 150 ms wake→chime budget. Also the fact that the wake chime will play before AEC is active. Both **unverified**.
3. **Add the ordering rule to §3 and §7 components:** build the player→mixer graph before `setVoiceProcessingEnabled(true)`.
4. **The VP input node is 9 channels at 48 kHz.** Take channel 0, or downmix, before wake word, VAD and speech-to-text, which want 16 kHz mono.
5. **Warm up the synthesiser at launch.** The cold first buffer took 0.4 s; warm calls take about 30 ms. Pre-render the cached acknowledgements ("On it", "One sec") as buffers at startup so the 300 ms acknowledgement budget holds.
6. **Mouth sync:** compute the levels from the buffers ahead of time instead of from a player tap, because the tap has about 96 ms granularity.
7. **REVIEW.md B4:** the fix it asks for is validated. Its premise, that `speak()` is not cancelled, is still **unverified** on macOS 26.6. It does not matter for the plan, which no longer uses `speak()`.

## How to re-run

```sh
cd feasibility/spikes/f03-echo
swiftc -O -swift-version 5 f03.swift -o f03
./f03 perm                      # mic authorization status (prompts if notDetermined)
./f03 voices                    # en-US/en-GB/en-IN voices with quality, plus the auto-picked best
export VOICE_ID=com.apple.voice.compact.en-US.Samantha   # or a Premium id once one is downloaded
export GRAPH_FIRST=1            # REQUIRED for VP cases (graph before VP; see the ordering bug)
./f03 synth                     # latency: 3x the phrase plus "On it."
./f03 echo novp novp            # plays 5.5 s out loud; writes novp_mic.wav, novp_ref.wav, novp_meta.json
./f03 echo vp vp                # same, VP on, player node
./f03 echo speak speak          # VP on, AVSpeechSynthesizer.speak()
DUCK_MIN=1 ./f03 echo speak speakduckmin   # speak() with VP ducking set to .min
./f03 idle 20; NOVP=1 ./f03 idle 20        # idle CPU/RSS with and without VP
uv run --with numpy --with soundfile python analyze.py novp vp speak speakduckmin
```

**Before re-running:**
- Use the built-in speakers at a fixed volume (75 % here), in a quiet room, with nobody talking.
- To check the open `speak()` question, listen during `echo speak`: does the voice sound as loud as in `echo novp`?
- Don't run `./f03 rec` alongside a VP case. It is starved as soon as VP starts.

## Addendum (2026-11-17): re-run with the Premium voice (Zoe)

**Setup.** `VOICE_ID=com.apple.voice.premium.en-US.Zoe GRAPH_FIRST=1`, built-in speakers and mic, same phrase. Runs: `./f03 synth`, `./f03 echo novp zoe_novp`, `./f03 echo vp zoe_vp`, then `analyze.py novp vp zoe_novp zoe_vp`.

| | Basic voice (Samantha, compact) | **Zoe (Premium)** |
|---|---|---|
| First buffer, cold | 399 ms | **1,072 ms** |
| First buffer, warm | 31–35 ms | 51–54 ms |
| "On it." first buffer | — | 38 ms |
| Format | Float32 22,050 Hz mono | same |
| Mic during playback, no VP | −20.6 dBFS | −13.9 dBFS (Zoe plays louder) |
| Mic during playback, VP on | −54.4 dBFS (floor −55.8) | **−57.8 dBFS (floor −52.9)** |
| Echo removed by VP (excess power / linear echo) | 22 / 31 dB | **28 / 47 dB** (zoe_vp vs zoe_novp) |
| Mouth tap | every 96 ms | every 96 ms |

- **Zoe is cancelled to the noise floor:** the median playback bin is below the post-playback floor. One 250 ms bin reached −29 dBFS, the same single spike seen with the basic voice. It's probably an onset transient, but that's **unverified**.
- **Warm-up matters more with Zoe:** the first sentence after launch costs about 1.1 s. Synthesise a short phrase at launch and cache "On it." as audio.
- **New for barge-in:** for about 1.2 s mid-playback, VP output dropped to digital silence (−96 to −100 dBFS), i.e. VP fully suppressed the mic. If I start talking over the assistant then, the start of my speech may be lost. Barge-in testing in phase 1 must check this.
