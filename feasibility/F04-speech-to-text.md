# F04: On-device speech-to-text (SpeechAnalyzer vs SFSpeechRecognizer)

**Test id:** F04 · **Date:** 2026-11-16 · **Plan:** PLAN.md rev 5, §2 (Speech) and §2.1 (budget: end of speech → final transcript ≤ 250 ms)
**Spike folder:** `feasibility/spikes/f04-stt/`

## Verdict: PARTIAL

- **Speed: PASS.** SpeechAnalyzer returns the final transcript 28–50 ms (p50) and 52–117 ms (p90) after the last 100 ms audio chunk, when audio is streamed in real time. That is well inside the 250 ms budget. Across all 210 transcriptions the worst single case was 281 ms. With 0.7 s of trailing silence, as the VAD will add, the worst case was 121 ms.
- **Accuracy: promising, but measured on synthetic speech only.** The best setup was **DictationTranscriber, en-US, with contextual strings**. It scored 4.9–7.3 % WER without the low-quality Fred voice, and 1.6–3.2 % on the en-IN voices. It got 13 of 17 technical terms right.
  - **SpeechTranscriber ignores contextual strings:** its output was byte-identical with and without them.
  - **Only DictationTranscriber used them:** with them it got 13 of 17 terms right, without them 8 of 17.
- **Comparison with SFSpeechRecognizer: BLOCKED.** On-device SFSpeechRecognizer fails with `kLSRErrorDomain 201 "Siri and Dictation are disabled"`. Turning Dictation on is a System Settings change, which I may not make, so the side-by-side comparison was not run.
  - **SpeechAnalyzer needs neither:** no Dictation setting and no speech-recognition permission. It ran with `SFSpeechRecognizer.authorizationStatus = notDetermined`.
- **Own voice: not tested.** It is still the deciding test. Run `record_and_test.sh` (see "How to re-run").

## Environment

| Item | Value |
|---|---|
| OS | macOS 26.6.1 (25G76) |
| Hardware | Apple M4 Pro, 24 GB |
| Toolchain | Swift 6.2 (Command Line Tools only, no Xcode), built with `swiftc -swift-version 5`, ad-hoc signed, Info.plist embedded with `-sectcreate` |
| Engines | `SpeechAnalyzer` + `SpeechTranscriber` (reporting: volatileResults, fastResults); `SpeechAnalyzer` + `DictationTranscriber` (contentHints: shortForm; reporting: volatileResults, frequentFinalization; punctuation); `SFSpeechRecognizer` with `requiresOnDeviceRecognition` |
| Streaming | 16 kHz mono files, cut into 100 ms chunks and fed on a wall-clock schedule (chunk *i* is fed at (i+1)×100 ms) to simulate the mic. A new `SpeechAnalyzer` is made per utterance, with `modelRetention: .processLifetime`. |
| Analyzer audio format | `bestAvailableAudioFormat` = 1 ch, 16 kHz, Int16, for en-US and en-IN |

## Step 1: API availability

| Question | Finding (verified) |
|---|---|
| Usable from a CLI with no Xcode and no app bundle? | **Yes.** SpeechTranscriber and DictationTranscriber both ran from a bare `swiftc` binary. Running under the Claude host process, no TCC prompt appeared and no Info.plist key was needed. `SpeechTranscriber.isAvailable = true`. |
| Is en-IN supported? | **Yes, by both.** SpeechTranscriber supports 30 locales, including en-IN. DictationTranscriber supports 54, including en-IN and hi-IN. SpeechTranscriber does not support hi-IN. |
| Are the assets installed? | Before the test: `SpeechTranscriber.installedLocales` listed 9 English locales, including en-US and en-IN, but `AssetInventory.status` returned `supported`, not `installed`. `DictationTranscriber.installedLocales` listed en-US and en-IN. |
| Can AssetInventory download them? | **Yes.** `assetInstallationRequest(...).downloadAndInstall()` took 4–735 ms per module/locale, and every status then read `installed`. The speed suggests the files were already on disk and the request mostly reserved them (`maximumReservedLocales = 5`); not verified. |
| DictationTranscriber vs SpeechTranscriber | DictationTranscriber is the older dictation model in the new API. It has presets (`phrase`, `shortDictation`, …), `contentHints` (`shortForm`, `farField`, `atypicalSpeech`, `customizedLanguage(modelConfiguration:)`) and **it uses contextual strings**. SpeechTranscriber is the newer long-form model. It has no content hints, and in this test it ignored contextual strings. |
| Custom vocabulary | `AnalysisContext.contextualStrings[.general] = [String]`, set with `analyzer.setContext(_:)`. That is the only vocabulary hook on SpeechTranscriber, and it had no effect there. DictationTranscriber also takes `ContentHint.customizedLanguage(modelConfiguration: SFSpeechLanguageModel.Configuration)`, a trained custom language model built from `SFCustomLanguageModelData` (phrase counts, templates, custom pronunciations) through `SFSpeechLanguageModel.prepareCustomLanguageModel`. **I did not test that** (unverified). |
| SFSpeechRecognizer (legacy) | It reports `supportsOnDeviceRecognition = true` for en-US and en-IN, and false for en-GB and hi-IN. It has two blockers. **(1)** Run from the CLI, it crashes under TCC, because the "responsible process" (the host app) has no `NSSpeechRecognitionUsageDescription`. Packaging it as `F04STT.app` and launching it with `open` fixed that; authorization then came back as 3 (authorized). I did not observe whether a dialog was shown. **(2)** Every request then failed with `kLSRErrorDomain Code=201 "Siri and Dictation are disabled"`. That needs System Settings → Keyboard → Dictation turned on. I did not change it and stopped retrying. |

## Step 3: Accuracy (word error rate)

**Test set.** 15 command phrases made with `say` at 16 kHz:
- **en-IN voices:** 9 (Rishi, Aman and Tara, 3 each)
- **en-US voices:** 6 (Samantha 3, Fred 3)

**Normalisation:** lowercase, punctuation dropped, `21,499` → `21499`, `argo cd` → `argocd`, summarise and summarize treated as the same.

**Tech terms** counts exact hits on Jira, MR, merge request, Databricks, PRJ-21499, GitLab, Grafana, Kubernetes, ArgoCD, collector and CCB (17 occurrences).

**Contextual strings** (`context.txt`): Jira, MR, merge request, Databricks, PRJ-21499, GitLab, Grafana, Kubernetes, ArgoCD, collector, CCB, hash collector dev, bulk push batching, Slack, pods.

| Engine | Locale | Context | WER all | WER en-IN voices | WER en-US voices | WER excl. Fred | Tech terms right |
|---|---|---|---|---|---|---|---|
| SpeechTranscriber | en-US | no | 18.9 % | 11.3 % | 29.5 % | 9.8 % | 10/17 |
| SpeechTranscriber | en-US | yes | 18.9 % | 11.3 % | 29.5 % | 9.8 % | 10/17 |
| SpeechTranscriber | en-IN | no | 18.9 % | 11.3 % | 29.5 % | 9.8 % | 10/17 |
| SpeechTranscriber | en-IN | yes | 18.9 % | 11.3 % | 29.5 % | 9.8 % | 10/17 |
| DictationTranscriber | en-US | no | 18.9 % | 12.9 % | 27.3 % | 14.6 % | 8/17 |
| **DictationTranscriber** | **en-US** | **yes** | **15.1 %** | **3.2 %** | 31.8 % | **7.3 %** | **13/17** |
| DictationTranscriber | en-IN | no | 24.5 % | 17.7 % | 34.1 % | 19.5 % | 8/17 |
| DictationTranscriber | en-IN | yes | 22.6 % | 14.5 % | 34.1 % | 17.1 % | 9/17 |
| SFSpeechRecognizer (on-device) | en-US / en-IN | both | n/a | n/a | n/a | n/a | **BLOCKED** (Dictation disabled) |

**Extra runs:**
- **Repeat for determinism:** DictationTranscriber en-US, with and without context, run again. The transcripts were identical to the first run.
- **0.7 s trailing silence:** with this padding, DictationTranscriber en-US with context scored **11.3 % all, 1.6 % en-IN voices, 4.9 % without Fred**, 13/17 terms. SpeechTranscriber was unchanged at 18.9 %.

**What the errors show:**
- **Fred dominates the en-US WER.** Fred is a 1990s formant voice: "open the MR for bulk push batching in GitLab" came out as "Oh, the MR or, oh, push matching, even good lap". Treat the "excl. Fred" column as the meaningful one.
- **Contextual strings fixed these on DictationTranscriber en-US:**
  - Kubernetes (was "Cuban")
  - Grafana (was "Rana")
  - GitLab (was "get lab")
  - "hash collector dev" (was "Hash Kale Dev")
  - "merge request" (was "emerge request")
- **They did not fix:**
  - Jira → "Gerard" (Samantha)
  - CCB → "CC" (Fred)
  - sync → "sink" (sync was not in the list)
- **PRJ-21499** comes back as `PRJ 21,499`. It needs a small normaliser (`PRJ 21,499` → `PRJ-21499`) in the router either way.
- **SpeechTranscriber returned the same text for en-US and en-IN** on all 15 files; only the spelling differed (summarise/summarize). This suggests en-IN maps to the same acoustic model (inference, unverified). DictationTranscriber en-IN came out *worse* than en-US on these voices: it dropped "Jira" and "Grafana".

## Step 4: Latency (real-time streaming, 100 ms chunks)

- **First partial** is measured from the first chunk being sent, so it includes the speech needed before a hypothesis exists.
- **Final** is measured from the last chunk being sent to the last `isFinal` result. That is the "end of speech → final transcript" clock, and `finalizeAndFinishThroughEndOfInput()` is called right after the last chunk.

Each run has n = 15.

| Engine | Locale | Context | First partial p50 / p90 (ms) | **Final after last chunk p50 / p90 (ms)** | Max final (ms) |
|---|---|---|---|---|---|
| SpeechTranscriber | en-US | no | 1114 / 1114 | **39 / 52** | 104 |
| SpeechTranscriber | en-US | yes | 1112 / 1117 | 36 / 49 | 59 |
| SpeechTranscriber | en-IN | no | 1115 / 1122 | 50 / 68 | 78 |
| SpeechTranscriber | en-IN | yes | 1115 / 1125 | 49 / 61 | 67 |
| DictationTranscriber | en-US | no | 817 / 830 | **43 / 111** | 281 |
| DictationTranscriber | en-US | yes | 814 / 823 | **28 / 91** | 229 |
| DictationTranscriber | en-IN | no | 813 / 819 | 54 / 117 | 132 |
| DictationTranscriber | en-IN | yes | 815 / 826 | 55 / 105 | 134 |
| DictationTranscriber + 0.7 s pad | en-US | yes | 820 / 830 | 37 / 94 | 121 |
| SpeechTranscriber + 0.7 s pad | en-US | no | 1119 / 1126 | 60 / 77 | 98 |
| SFSpeechRecognizer | — | — | BLOCKED | BLOCKED | — |

**Notes on latency:**
- **No cold-start penalty was visible.** The first file in each fresh process was no slower (e.g. DictationTranscriber en-US with context: 809 ms first partial, 15 ms final).
- **Analyzer setup time was not measured** (unverified). That covers `SpeechAnalyzer` init, `prepareToAnalyze` and `setContext`, which happen before the clock starts. The app should create and prepare the analyzer when listening starts, or keep one warm, so the "click → listening ≤ 50 ms" budget is not spent on it.
- **First partials are slow:** about 0.8 s for DictationTranscriber and about 1.1 s for SpeechTranscriber. That is fine for the budget, which has no partial-result target, but live captions will lag about a second behind speech.

## Step 5: Footprint

Measured with `/usr/bin/time -l` for the test process, plus a `ps` sample every 2 s during the 8-run matrix.

| Process | Peak RSS | Peak CPU (2 s sample) | Notes |
|---|---|---|---|
| `stt` (our test process) | **19.1–19.5 MB** | 3.6 % | Every run |
| **`localspeechrecognition`** (`/System/Library/Frameworks/Speech.framework/Versions/A/XPCServices/localspeechrecognition.xpc`) | **177 MB** | 40 % | **The model runs here**, out of process, as an XPC service of our app. It was gone shortly after the test process exited. |
| `corespeechd` | 8.7 MB | 0.5 % | Already running before the test; system daemon |

**What this means for the §2.1 memory budget:**
- **App process:** speech-to-text adds about 20 MB at most to the app's RSS (the ≤ 80 MB idle budget).
- **XPC service:** while listening, about 177 MB lives in `localspeechrecognition`. It is outside our process but caused by us.
- **Not measured:** whether the service stays resident between turns while the app keeps running with `.processLifetime` retention (unverified). Compare with `.whileInUse` or `.lingering` in phase 0.

## Caveats about synthetic speech

- **All audio is TTS from `say`.** Pronunciation is clean and consistent, with no room noise, no mic colouring, no hesitations and no code-switching. Real en-IN speech, especially Akshay's own, can be easier or harder. **These WER figures are a proxy only and do not prove real-world accuracy.**
- **The voices are an uneven test.** Fred is a very old formant voice and inflates the en-US WER. Rishi, Aman and Tara are the only en-IN voices installed, and they are a narrow sample of Indian English.
- **TTS reads terms in its own way.** `say` pronounces "PRJ-21499", "MR" and "CCB" however its text front-end decides, which may not match how Akshay says them (e.g. "D G two one four nine nine").
- **The set is small.** With 15 utterances (about 100 words), one word is about 1 % WER. The differences between configurations are directional, not statistically solid.
- **The latency is genuine.** It is real wall-clock streaming at real-time pace, but on clean files with no AEC and no concurrent load (wake word, Rive, TTS).

## Implications for PLAN.md

1. **Default engine: SpeechAnalyzer with `DictationTranscriber`, not `SpeechTranscriber`.**
   - **Settings:** en-US locale, `contentHints: [.shortForm]`, contextual strings on, reporting `[.volatileResults, .frequentFinalization]`.
   - **Why:** it is the only module that used contextual strings (13/17 terms vs 10/17). It gives first partials about 300 ms sooner. Its final latency is the same or better (p50 28 ms).
   - **Change to make:** §2 "Speech" currently names SpeechTranscriber.
   - **Option:** keep SpeechTranscriber as a configurable alternative for long-form dictation.
2. **Locale: en-US, not en-IN, by default.** On this proxy, en-IN gave no gain on SpeechTranscriber and did worse on DictationTranscriber. Re-check with own voice. Make it a setting.
3. **Contextual strings: yes, with DictationTranscriber.**
   - **Where they come from:** feed a vocabulary list from a config file, plus dynamic terms such as current Jira keys, repo names and colleague names.
   - **Add more terms:** "sync", "Jira tickets", and maybe phonetic aliases.
   - **Keep a normaliser in the router:** `PRJ 21,499` → `PRJ-21499`, "data bricks" → Databricks, sink/sync in a Kubernetes or ArgoCD context.
4. **SFSpeechRecognizer: drop it as a fallback.**
   - It needs Siri/Dictation turned on in System Settings, plus the speech-recognition permission prompt.
   - SpeechAnalyzer needs neither, which is a real setup advantage.
   - This also removes a TCC prompt from onboarding. Microphone permission is still needed.
5. **WhisperKit: not needed on this evidence. Keep it deferred, with a measurable trigger.**
   - Speed is far inside budget. Accuracy without Fred is 5–7 % WER on synthetic voices.
   - **Decide after the own-voice run.** Re-open WhisperKit if the own-voice DictationTranscriber en-US run with context shows **WER > 15 %** or **fewer than 80 % of tech terms right**.
6. **§2.1 budget numbers to update:**
   - "End of speech → final transcript ≤ 250 ms" is met: measured p90 ≤ 117 ms.
   - Add a line for the `localspeechrecognition` XPC service: about 177 MB RSS while transcribing. It is outside the app budget but counts toward the machine's footprint.
7. **Phase 0 follow-ups (open):**
   - Measure analyzer prepare time, and whether to keep one analyzer warm.
   - Test with the real mic through the AEC engine. The analyzer format is 16 kHz Int16, so the app converts from the voice-processing format.
   - Measure `localspeechrecognition` residency at idle.
   - Optionally try `customizedLanguage` (a custom LM built from `SFCustomLanguageModelData` with custom pronunciations for Jira, CCB and ArgoCD), if contextual strings are not enough with own voice.

## How to re-run

Everything is in `feasibility/spikes/f04-stt/`:

```sh
cd feasibility/spikes/f04-stt
./build.sh                                  # swiftc build of stt.swift (CLT only)
./stt info --download en-US,en-IN           # locales, asset status, reserve/download assets
./make_audio.sh                             # regenerate synthetic WAVs from phrases.tsv
./run_matrix.sh                             # ST/DT x en-US/en-IN x context on/off -> results/*.jsonl (+ *.time peak RSS)
python3 wer.py results audio/manifest.tsv -v   # WER, term hits, latency table, per-utterance errors
./stt run --engine dt --locale en-US --context context.txt --pad 0.7 audio/manifest.tsv audio   # single run, VAD-like padding
```

**Your own voice:**

```sh
./record_and_test.sh          # records the 15 phrases (Enter to start/stop each), trims silence,
                              # runs the same matrix, writes own_voice/report.md
./record_and_test.sh --test-only   # re-score existing own_voice/ recordings
```

- **Run it from Terminal or iTerm,** not from inside Claude. It needs `ffmpeg` (installed at `/opt/homebrew/bin/ffmpeg`) and microphone permission for that terminal app. Your speaker id is `me` and counts in the "en-IN voices" column.

**To complete the SFSpeechRecognizer comparison:**
1. Turn on System Settings → Keyboard → Dictation (your decision; it is a system setting).
2. Run `open -W -n --stdout $PWD/sf.out --stderr $PWD/sf.err F04STT.app --args run --engine sf --locale en-US $PWD/audio/manifest.tsv $PWD/audio`. It must be launched as the `.app` so TCC attributes the speech permission to it.

**Files:**
- `stt.swift`: the harness (`info`, and `run` with `--engine st|dt|sf`)
- `wer.py`: scoring
- `info.txt`: raw output of step 1
- `results/`, `results_repeat/`, `results_pad/`: raw JSON lines
- `results/proc_samples.txt`: the `ps` samples

---

## Addendum (2026-11-16): own-voice run, verdict changed to **FAIL** for Apple on-device as the default

**Method.** I recorded my own voice saying all 15 phrases, using `spikes/f04-stt/record_and_test.sh` on the MacBook Pro microphone with leading and trailing silence trimmed.
- Recordings: 1.6–4.3 s each, mean level −29 to −32 dB, peaks −14 to −15 dB.
- Same matrix as before: 2 engines × 2 locales × with or without contextual strings, streamed in real time.
- Raw results: `spikes/f04-stt/own_voice/results/`. Report: `spikes/f04-stt/own_voice/report.md`.
- Note: the script's first version read the Enter key from the phrase file. That was fixed (fd 3 for phrases, `/dev/tty` for keys, `ffmpeg -nostdin`) before this run.

| Run | Word error rate | Tech terms right | Final after last chunk p50 / p90 |
|---|---|---|---|
| **SpeechTranscriber en-US** (best) | **32.1 %** | 5/17 | 53 / 68 ms |
| SpeechTranscriber en-IN | 33.0 % | 6/17 | 58–62 / 69–70 ms |
| DictationTranscriber en-US + context | 48.1 % | 6/17 | 60 / 164 ms |
| DictationTranscriber en-IN | 48–52 % | 3/17 | 52–54 / 113–138 ms |

**What went wrong:**
- **Technical terms are the main failure.** Even the best engine, SpeechTranscriber, got them wrong: Jira, ArgoCD → "Alco cities" / "anniversary", Grafana → "Rapana", Databricks → "database", Kubernetes → "Cubanitis" / "community", CCB → "SUV", PRJ- → "BG", collector → "collective", Slack → "select", GitLab → "get…".
- **Everyday phrases were fine** ("What's on my calendar this afternoon?", "Remind me to review and merge request at five").
- **DictationTranscriber**, the synthetic-test winner, **drops whole spans of real speech** when streaming. For example, p12 came back as just "Beta", p07 as "Kerala" or empty, and its first partial arrived only at the very end. So it is unusable as is.
- **Contextual strings** had no effect on SpeechTranscriber and only a small one on DictationTranscriber.
- **en-IN was no better than en-US.**

**Speed still passes:** finals arrive 52–72 ms (p50) after the last audio.

**Verdict.** The plan's own gate, under 15 % word errors and at least 80 % of terms right, **fails clearly** (32 % and 35 %). Apple on-device speech-to-text should not be the default for my voice.
- **Next:** evaluate Whisper (WhisperKit in the app; for a quick check, the same `large-v3-turbo` weights through mlx-whisper or whisper.cpp) on these exact recordings, with an initial prompt or vocabulary of my terms.
- **Also possible:** keep SpeechTranscriber for fast partial results and the end-of-turn signal, and get the final text from Whisper.

## Addendum 2 (2026-11-16): Whisper on the same recordings

**Method.**
- WhisperKit CLI 1.1.1 (`brew install whisperkit-cli`), Core ML on the Neural Engine (the library the app would embed), `--language en --without-timestamps`, temperature 0.
- Models: `large-v3-v20240930_turbo` (1.5 GB on disk) and its quantized `_632MB` variant (624 MB).
- Each recording transcribed as a whole utterance (no streaming), in three modes: no prompt; a comma list of my terms; the same terms inside one sentence.
- Script: `spikes/f04-stt/run_whisper.sh`. Raw output: `own_voice/whisper/<run>/`; JSONL in `own_voice/results/whisper_*`; scored with the same `wer.py` into `own_voice/report.md`.
- Latency is WhisperKit's `fullPipeline` (log-mel + encode + decode) for the utterance, i.e. end of speech → final text. Model load (about 0.85 s) is excluded; the app keeps it loaded.

| Run | Word error rate | Tech terms right | End of speech → final, p50 / p90 |
|---|---|---|---|
| Apple SpeechTranscriber en-US (best Apple) | 32.1 % | 5/17 | 53 / 68 ms |
| Whisper turbo, no prompt | 23.6 % | 12/17 | 482 / 506 ms |
| Whisper turbo, term list prompt | 20.8 % | 14/17 | 864 / 885 ms |
| **Whisper turbo, sentence prompt** | **17.0 %** | **16/17** | 903 / 924 ms |
| Whisper turbo 632 MB, no prompt | 26.4 % | 11/17 | 455 / 473 ms |
| Whisper turbo 632 MB, sentence prompt | 17.9 % | 15/17 | 917 / 936 ms |

Sentence prompt used: "I work on GitLab MRs and Jira tickets like PRJ-21499, check Grafana and ArgoCD on Kubernetes pods, the Databricks collector, the CCB meeting, and Slack, like hash collector dev and bulk push batching."

**What I saw:**
- **Terms are mostly fixed.** With the sentence prompt, Grafana, ArgoCD, Kubernetes, GitLab, Jira, CCB, PRJ-21499 and Slack all come through. The one miss is Databricks → "database".
- **The remaining errors are everyday words:** "show" → "so", "is" → "this is", "unread" → "Android", "list the failing" → "digital fending", "pods are crashing" → "parts are caching". Whether Claude still gets the intent from these is likely but **unverified**.
- **The scorer is a little harsh:** "what is" against "what's" counts as 2 errors. Without that, the best run is about 15.1 % (16 of 106 words).
- **The list-style prompt made Whisper hallucinate** on p07: it returned the prompt itself ("Jira, MR, merge, PRJ-21499, GitLab,"). The sentence prompt didn't, on these 15. The app needs a guard: if the output overlaps the prompt heavily, retry without the prompt or ask me to repeat.
- **Optimistic test:** the prompt contains exactly the terms the phrases test. That matches how the app would use it (my vocabulary), but a **held-out set** (new phrases, terms not all in the prompt) is needed before trusting 17 %.
- **Latency:** the encoder takes about 330 ms for any utterance (Whisper always pads to a 30 s window). The prompt adds about 400 ms, because the CLI decodes the prompt tokens each time. Caching the prompt's state in the app could cut that, but that's **unverified**.
- **Memory:** about 180–190 MB peak footprint per process, the same for both model sizes (the weights live in Core ML/ANE memory, mostly outside the footprint figure). Unlike Apple's engine, this is **inside our process** unless we put it in a helper.
- **The quantized model** is about 1 point worse and saves only disk.

**Verdict.**
- **Much better than Apple:** word errors fall from 32 % to 17 %, and terms from 5/17 to 16/17 (94 %).
- **The plan's gate still fails narrowly on word errors** (17.0 %, about 15.1 % with contractions treated as equal, against < 15 %). It **passes on terms** (≥ 80 %).
- **Latency fails the 250 ms target** (0.9 s with prompt). The acknowledgement chime on end of speech still hides part of it.
- **Recommended design:** SpeechTranscriber for live partial captions; Whisper large-v3-turbo with a sentence-style vocabulary prompt for the final transcript that goes to Claude, with the prompt-echo guard. Confirm with a held-out recording set before phase 1.

## Addendum 3 (2026-11-16): held-out phrases and an intent check

**Why:** the first Whisper result was optimistic, because the prompt contained exactly the terms being tested. Word error rate also overstates harm, since what matters is whether Claude does the right thing.

**Held-out set.**
- 15 new phrases (`spikes/f04-stt/phrases_holdout.tsv`), recorded the same way into `own_voice_holdout/`.
- Eight of their terms are **not in the Whisper prompt:** PRJ-21604, Helm, Confluence, PagerDuty, Postgres, ATLAS, alpha and runtime manager. The prompts were left unchanged.
- Scored with `TERMS=…` set to the held-out term list (17 term occurrences).
- The recording script was fixed along the way: it stops ffmpeg with SIGTERM, ignores stray Enter presses, retries empty takes, and resumes.

| Run | Word errors, held-out | Terms, held-out | Word errors, first set | Terms, first set | End of speech → final, p50 |
|---|---|---|---|---|---|
| Apple SpeechTranscriber (best locale) | 33.3 % (en-IN) | 5/17 | 32.1 % | 5/17 | 55–62 ms |
| Whisper turbo, no prompt | 18.9 % | 8/17 | 23.6 % | 12/17 | 0.49 s |
| Whisper turbo, term list prompt | **14.4 %** | 11/17 | 20.8 % | 14/17 | 0.87 s |
| Whisper turbo, sentence prompt | 17.1 % | 11/17 | 17.0 % | 16/17 | 0.90 s |

**Intent check.**
- Script: `spikes/f04-stt/intent_check.py`. Results in `own_voice*/intent*.md`.
- Step 1: Claude (Sonnet, no tools) reads each transcript **without the reference**, plus a two-line description of my work context (tools, environments, components), and writes the command it thinks I meant. The context stands in for what a real session knows from CLAUDE.md.
- Step 2: a separate Claude call grades each reading against what I actually said: **same** (would do the same thing), **partial** (right action, a detail wrong or missing), or **wrong**.

| Run | Same | Partial | Wrong | Same or partial |
|---|---|---|---|---|
| Apple SpeechTranscriber | 13/30 | 7/30 | 10/30 | 67 % |
| Whisper, no prompt | 23/30 | 4/30 | 3/30 | 90 % |
| Whisper, term list prompt | 22/30 | 5/30 | 3/30 | 90 % |
| Whisper, sentence prompt | 23/30 | 5/30 | 2/30 | 93 % |

**What I saw:**
- **The prompt helps only the terms in it.** Prompted terms improve (Grafana, ArgoCD, CCB, PRJ-21499). Unprompted terms still fail with or without a prompt: PagerDuty → "Pajabuki", Postgres → "postgrade", ATLAS → "page", alpha → "average". Confluence was right once.
- **On intent, the prompt makes no real difference:** 22–23 of 30 fully right either way. Claude's own context repairs most term errors ("database job" → Databricks job, "Grapana" → Grafana).
- **The prompt adds two costs:** about 400 ms more latency, and **prompt leakage**. The list prompt once returned the prompt itself (p07). The sentence prompt turned "join the CCB late" into "join the CCB meeting", a phrase taken from the prompt.
- **The dangerous misses are details:** ticket numbers (PRJ-21604 → "PRJ-216042"), environment names (alpha → "average"/"Gamma"), and "release" → "next release". These would do the wrong thing on the right tool. The approval card and a spoken read-back of ids and names before any write are what catch them.
- **Grading noise:** the grader isn't perfectly consistent. The same transcript was sometimes graded differently across runs, and "Tell #collector-dev" for "hash collector dev" was graded partial though it's probably right. Treat differences of 1–2 items as noise.
- **Limits:** one speaker, one built-in mic, a quiet room, 30 short phrases.

**Verdict.**
- **Whisper large-v3-turbo replaces Apple's engine for the final transcript.** Fully right intent goes from 43 % to about 77 %, and wrong from 33 % to 7–10 %.
- **Start without a prompt.** Intent is equal, it's 0.4 s faster (0.49 s), and there's no prompt leakage. A short prompt of only the terms that keep failing can be tried later, once the app can cache the prompt's state.
- **Word error rate as a gate:** only the list prompt on the held-out set gets under 15 %. I suggest gating on intent instead: at least 90 % same-or-partial and at most 10 % wrong. Whisper meets that (no prompt: 90 % / 10 %, right on the line).
- **Read-back is required:** ids, names, environments and numbers must be confirmed by voice or card before any write.
