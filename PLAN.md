# Zoe: a voice assistant for Claude Code (high-level plan)

_Draft rev 7.2, 2026-11-17. Status: phase 0 feasibility tests run (`feasibility/README.md`); no product code yet. Interactive flow mock: published as an artifact (see chat). Independent review: `REVIEW.md`._

**Revision history:**
- **Rev 7.2:** the project is named **Zoe** (after its Premium voice) and lives in the public repo `amrakshay/zoe-ai-assistant`, with maclens-style CI and releases; the app build, packaging and Homebrew pieces are added in phase 1 (§8).
- **Rev 7.1:** long answers are spoken as a short summary, with the full text shown on screen (§5.12).
- **Rev 7:** **push-to-talk and click start a conversation; the "Hey Claude" wake word moves to a later phase** (the model caught 8 % of my own "Hey Claude"s, F05). With no wake word the mic and audio engine are off when idle. Whisper is the speech-to-text default (F04).
- **Rev 6:** measured results from the seven feasibility tests. **§12 overrides earlier sections wherever they disagree.**
- **Rev 5:** folds in the adversarial review (`REVIEW.md`, Fable 5.2).
  - Approvals are enforced by a `PreToolUse` hook rather than `can_use_tool` alone.
  - The allowlist uses exact tool names, and untrusted content gates network calls.
  - App and core talk over stdio instead of a websocket.
  - Text-to-speech goes through the echo-cancelling engine.
  - The router decides locally first.
  - Jobs run in git worktrees.
  - Budgets are corrected, phases rebuilt, and the scope trimmed.
  - The resolution of every finding is in §11.
- **Rev 4:** speed and footprint come first. All audio moves into the Swift app on Apple on-device speech, and the Python core becomes text-only.
- **Rev 3:** adds background jobs, screen context, repo-aware routing, briefings and nudges, quiet mode, drop onto the character, capture, and dictation into apps.
- **Rev 2:** the assistant becomes a native macOS app with a floating character, panels Claude can draw, and actions on the Mac.

## 1. Goal

A hands-free assistant on my Mac:

- **Start it two ways:** hold or tap a **push-to-talk hotkey**, or click a small animated character that floats on screen and can be dragged anywhere. A hands-free "Hey Claude" wake word comes in a later phase (§8).
- **Talk naturally,** like ChatGPT voice mode. The character animates while it listens, thinks and talks, and shows replies in a speech bubble.
- **Claude Code does the work,** so it has my plugins, connectors and context.
- **The right session every time:** it continues the current session, resumes an older one, or starts a new one, in the right repo.
- **Every session the assistant touches is recorded** in a local index.
- **Claude can draw windows** (cards, tables, choices) and **do things on the Mac. Nothing that changes anything runs without my approval.**
- **Hands off long jobs** to background sessions and keeps talking while they run.
- **Knows what I'm looking at,** so "this" works.
- **Speaks up when it matters,** and stays quiet when I'm busy.
- **Works without talking too:** typing, dropping things onto the character, dictating into other apps.
- **Runs locally on my existing Claude Code subscription,** for my personal use only.

**Priorities, in order:**
1. As fast and light as possible. Claude Code's own time and usage are outside our baseline, but stated (§2.1).
2. Never act on a write without approval.
3. Never get stuck when a session needs input that voice can't give.

## 2. Decisions made

| Topic | Decision |
|---|---|
| App stack | **Swift app + text-only Python core.** The SwiftUI/AppKit app owns the character, panels and the whole audio pipeline. A small Python process owns the Claude Agent SDK, routing, the session index, approvals, MCP servers, jobs and watchers. **The app starts the core as a child process, and they exchange JSON lines over stdin/stdout.** No network port, so nothing else can talk to the core. |
| Brain | Claude Code through the Claude Agent SDK (Python), in streaming-input mode. **Fallback** if the SDK can't use my subscription login: a long-lived `claude -p --input-format stream-json` process per session, a pattern taken from halo. |
| Speech | **Whisper** (WhisperKit, `large-v3-turbo`, no prompt) does the final transcript; Apple **SpeechAnalyzer** (macOS 26) gives live captions while I speak (rev 6, §12.1). **AVSpeechSynthesizer** with a Premium voice speaks, **rendered into buffers and played through the echo-cancelling engine** (§3). VAD: Silero. Wake word: **later phase** (§8). Kokoro is deferred. |
| Trigger | **v1: push-to-talk hotkey and a click on the character.** Hold the hotkey to talk (release ends the turn), or tap it to start a hands-free conversation (§3). No always-listening mic. A "Hey Claude" wake word is added later, once a retrained model passes the own-voice test (≥ 90 % recall). |
| Approvals | **A `PreToolUse` hook is the gate:** it runs before any settings allow rules. The allowlist uses exact tool names. Anything else asks, by voice or click, and some actions require a click (§7). |
| Platform | **macOS 26+** (needed for SpeechAnalyzer), Apple Silicon |
| Character | A free Rive community character whose licence allows reuse, with fixed inputs, so it can be swapped later |
| Home folder | the repo root, with its own `CLAUDE.md` (voice persona). Global plugins and connectors still load. |
| Use of Claude | **Initiated by me by default.** Watchers poll APIs directly and call Claude only when I opt in per watcher. The app is never distributed with subscription login. |

## 2.1 Speed and footprint budget

**What's measured:** our app and core only. Claude Code's run time and usage are excluded. Its footprint is still real, so it's stated here:
- **Each live SDK session is its own Claude Code process,** likely 100–300 MB each (unverified; to be measured in phase 0).
- **Limits on live sessions:** at most 1 conversation session plus 2 jobs.
- **Idle sessions are closed after 10 min** and resumed by id when needed.
- **Pre-warm is off by default.**

**Clocks** (where each measurement starts):
- **End of speech** is the moment VAD declares the turn over. It already includes VAD's ~0.7 s silence window; that window is tunable and not counted below.
- **Trigger** is the moment the hotkey goes down or the click lands.
- With hold-to-talk, **end of speech is the key release**, so there is no VAD silence window.

| Metric | Budget | Notes |
|---|---|---|
| App memory, idle | ≤ 80 MB | Rive/Metal + ONNX Runtime + SwiftUI; measure in phase 0 |
| Core memory, idle | ≤ 80 MB | the SDK pulls in `mcp`, pydantic and anyio; measure in phase 0 |
| CPU, idle | ≈ 0 % (rev 7: mic and audio engine off; Rive paused) | the core is idle on stdin |
| App cold start → ready | ≤ 1 s | the core starts in parallel and is ready ≤ 1.5 s |
| Hotkey or click → listening | ≤ 50 ms | the chime plays at once; the engine starts on trigger (start-up time to measure in phase 1) |
| Wake → chime | (later phase) | applies once the wake word is added |
| End of speech → final transcript | ≤ 250 ms | streaming speech-to-text |
| End of speech → spoken acknowledgement | ≤ 300 ms | **generic cached acknowledgements only** ("On it", "One sec"); topic-specific progress lines come later from Claude |
| Our overhead per turn | ≤ 150 ms | transcript → request sent, plus first streamed sentence → first audio |
| Routing | ≤ 20 ms locally | a Claude router call happens only for ambiguous or "resume" requests (§7) |
| Panel open | ≤ 50 ms | |
| Chat window, 1,000 messages | ≤ 150 ms | virtualised list; only visible rows are rendered |

**How we get there:**
- **Native UI only.** No web views. The character is rendered by Rive on Metal at 30 fps while active and about 10 fps idle, and stops when hidden, covered, muted, or on another Space.
- **Audio never leaves the app.** One `AVAudioEngine` with voice processing, started only for a conversation; mic, VAD, speech-to-text and the synthesised voice all run through it.
- **Small, lazily loaded models.**
  - Nothing audio-related needs to stay loaded while idle (rev 7: no wake word). VAD (about 2 MB) loads with the engine; Whisper loads for a conversation (§12).
  - Speech-to-text and text-to-speech are OS services.
- **A tiny core.**
  - Dependencies: `claude-agent-sdk`, `httpx` and the standard library (`sqlite3`, `asyncio`).
  - No numpy, torch or onnx.
  - It sleeps between events; watchers use coalesced timers with backoff, and FSEvents instead of polling.
- **Measured in phase 0 and at every phase.** `os_signpost` markers in the app and timing logs in the core. A simple Performance view and an 8-hour soak test come in polish.

## 3. Architecture

```
┌──────────────────────── Swift app (menu-bar app, no Dock icon) ────────────────────────┐            ┌──────── Python core (child process) ─────┐
│                                                                                          │            │                                           │
│  AVAudioEngine + voice processing (echo cancellation)                                    │            │  conversation manager                     │
│     mic (on hotkey/click) ─► Silero VAD ─► Whisper (+ live captions) ────────────────────┼── stdin ──►│     ├─► router (local rules, then Claude) │
│     speaker ◄── AVAudioPlayerNode ◄── AVSpeechSynthesizer.write(toBufferCallback:) ◄─────┼◄─ stdout ──┤     └─► Agent SDK client ─────────────────┼──► Claude Code process(es)
│                       ▲ (synth audio goes through the same engine, so it is cancelled)  │ JSON lines │           ├ PreToolUse hook = approval gate│     (excluded from the
│  Character (Rive) + badge/ring + bubble                                                  │            │           ├ can_use_tool = questions       │      baseline, stated in §2.1)
│  Panels: approval, choices, card, table, sessions, draft, (later) chat window            │            │           └ in-process MCP: ui, mac,       │
│  Context (frontmost app, URL, selection), push-to-talk, drop target, paste               │            │             context, jobs, capture        │
│                                                                                          │            │  jobs (git worktrees) · watchers · presence│
└──────────────────────────────────────────────────────────────────────────────────────────┘            │  SQLite index                              │
        launchd starts the app at login; the app spawns and supervises the core                         └───────────────────────────────────────────┘
```

**Why all audio lives in the app:**
- Echo cancellation only subtracts audio played **through the same engine**. So the synthesiser renders into buffers that an `AVAudioPlayerNode` on that engine plays. Playing through the synthesiser's own `speak()` would not be cancelled.
- The player node's output level also drives the character's mouth.
- **Fallback if this doesn't work well enough:** half-duplex. While it speaks the mic is muted; the hotkey or a click interrupts it.

**Why stdio and not a websocket:**
- Any local process or web page can reach a localhost websocket, which would let it fake an approval.
- A child process's stdin/stdout can only be reached by the app that spawned it.

### App ↔ core messages (JSON lines over stdio)

| Direction | Messages |
|---|---|
| App → core | `utterance {text, trigger: voice\|click\|ptt\|text, started_at}`, `user_interrupted`, `dropped {kind, payload}`, `context_snapshot {app, window, url, selection}`, `answer {pending_id, value, via: voice\|click\|text, at}`, `open_session {id, where: chat\|terminal}`, `take_back {id}`, `cancel {id}`, `chat_message {session_id, text}`, `presence {in_call, idle_secs}`, `mute {on}` |
| Core → app | `state {idle\|listening\|thinking\|talking\|offline}`, `mode {voice\|quiet}`, `say {text, utterance_id}`, `ack {kind}`, `bubble {text}`, `show_panel {id, kind, payload}`, `dismiss_panel {id}`, `pending_input {id, session_id, kind, card, voice_ok}`, `sessions_activity {list}`, `nudge {id, text, priority}`, `context_request {}`, `paste {text, target_app, target_field}`, `transcript_event {session_id, event}` |

### Conversation lifecycle

1. **Idle.**
   - **The mic and audio engine are off.** The app only watches the hotkey and the character.
   - The core waits on stdin.
2. **Start.** The push-to-talk hotkey or a click on the character.
   - The chime and the listening state come at once.
   - **Hold to talk:** speak while holding the key; releasing it ends the turn. Good for noisy rooms and one-off questions.
   - **Tap (or click):** starts a hands-free conversation. VAD ends each turn and the mic stays open for follow-ups until the conversation ends (step 6). Tapping again ends it at once.
   - Hotkey: **hold right ⌥ by default** (a `CGEventTap`, needs Accessibility, which the app requires anyway); **⌃⌥Space** (`RegisterEventHotKey`) as a setting. Both report press and release (F07 addendum, 2026-11-17).
3. **Route** (§7 Router), local rules first.
4. **Converse loop.**
   - VAD ends the turn and the transcript goes to the session.
   - The reply streams back and is spoken sentence by sentence through the engine.
   - **Long answers: speak a short summary, show the full answer on screen** (§5.12).
5. **Approval** (§7 Approval gate).
6. **End.**
   - About 20 s of silence, "bye", a click, or a tap of the hotkey ends the conversation. **The engine then stops and the mic is released.**
   - The core writes a one-line summary to the index.
   - The SDK session closes after 10 min idle and is resumed by id when needed.

**If the core restarts:**
- Every pending approval counts as **deny**.
- Every session stays resumable by id.
- The character shows "offline" until the core is back.

## 4. Claude-facing tools (in-process SDK MCP servers)

**Exact names, with the policy for each.**
- *allow* runs without asking.
- *ask* needs voice or a click.
- *click* needs a click; voice isn't accepted.

| Server | Tool | Policy |
|---|---|---|
| `ui` | `show_card`, `show_table`, `show_choices`, `dismiss` | allow |
| `ui` | `show_image(path_or_url)` | allow for local paths; ask for URLs when the turn is tainted (§7) |
| `context` | `get_frontmost` (app, window title, URL, selection) | allow, and **marks the turn tainted** |
| `context` | `take_screenshot` | click; the file is deleted after the turn |
| `mac` | `open_app`, `reveal_in_finder`, `set_volume`, `notify` | ask |
| `mac` | `open_url` | ask; click when the turn is tainted |
| `mac` | `get_clipboard` | **ask**; marks the turn tainted |
| `mac` | `set_clipboard` | ask |
| `jobs` | `list_jobs`, `job_status` | allow |
| `jobs` | `start_job`, `cancel_job` | **click** |
| `capture` | `add_note`, `add_todo`, `remind_me` | allow (they only append to my own notes and reminders) |

The voice `CLAUDE.md` tells Claude:
- Draw instead of talking for anything over about 3 items, tables, code or links.
- Start every reply with a spoken summary of at most 2–3 sentences; put the details after it, for the screen (§5.12).
- Never use plan mode.
- Never run interactive commands.

## 5. Productivity features

### 5.1 Background jobs
- **Starting one:** "Run the local review on my collector branch" makes Claude call `start_job`. Starting a job **needs a click**.
- **Where it runs:** each job runs in its **own git worktree** of the target repo, so it never touches my working copy.
- **Job policy** (enforced by the hook):
  - **Read tools:** allowed.
  - **Edits:** Edit and Write are allowed only inside the worktree. Writes to `.claude/`, `.git/`, `CLAUDE.md` and anything outside the worktree are **denied**.
  - **Bash:** asks, except an exact-command allowlist: `git status`, `git diff`, `git log`, `git add <paths in worktree>`, `git commit -m …`, plus the repo's own test command if I add it to `config.toml`.
  - **Anything outward-facing** (push, MR, Slack, Jira, any MCP write) needs a click.
- **Limits:** at most 2 jobs at once.
- **Waiting for me:** job approvals queue as nudges and never interrupt mid-sentence. A pending job approval auto-denies after 4 h.
- **When it finishes:** a nudge with the result, plus **Open in Terminal**, which runs `claude --resume` inside the worktree.

### 5.2 Understand "this"
- **What the app reads:** the frontmost app, window title, browser URL and selected text. It sends them with the utterance when I say "this" / "here" / "that" / "on screen", or when Claude calls `get_frontmost`.
- **Screenshots:** click only, never stored.
- **Untrusted content:** screen text is **untrusted**. It marks the turn tainted, and tainted turns gate network calls (§7).

### 5.3 Repo-aware routing
- **How the repo is chosen:** a `projects` table with aliases ("collector" → `acme-collector`), seeded from the recent project folders.
- **Matching:** the local router matches aliases. A new session in a repo loads that repo's `CLAUDE.md` and rules.
- **Resuming** always uses the session's **stored `cwd`**, never a new guess.

### 5.4 Briefings and nudges
- **Morning briefing,** on the first conversation after 07:00, or when I say "brief me".
  - It uses the `morning` skill: meetings, Jira changes, MRs waiting for me, my pipelines, Slack mentions, important email.
  - It speaks a 30–60 s summary and shows a card. It's user-initiated, since I start the conversation.
- **Meeting prep,** 2 min before an event. It shows a card only, and is **opt-in**, since it calls Claude.
- **Watchers** (direct API polls, no Claude by default). I start with three, each switchable:
  - my MR pipeline failed
  - review requested from me
  - a Slack DM or mention

  Claude summaries for a watcher are opt-in per watcher.
- **Quiet rules:**
  - No speech during calendar events, calls, outside working hours, or in Do Not Disturb.
  - At most one spoken nudge every 10 min.
  - Only `high` priority speaks.
- **Deferred to later:** meeting follow-up, Grafana and pod watchers.

### 5.5 Quiet mode and calls
- **Type** in the bubble, or **hold the push-to-talk hotkey** to talk (one turn, no hands-free follow-ups).
- **During a call** (another process is capturing input, detected per process; to verify in phase 0):
  - The app **stops its audio engine entirely** and the hotkey only shows "in a call": no listening and no speech.
  - Typing still works. The character shows headphones.
  - The engine restarts when the call ends.

### 5.6 Drop onto the character
- **What it accepts:** a file, image, URL or text. The assistant asks what to do with it.
- **What gets sent:** a path, never an upload.
- **Untrusted content:** the dropped item is untrusted and taints the turn.

### 5.7 Capture
- "Note this", "todo: …" and "remind me at 4 to …" go into the vault inbox or Reminders.
- **Deferred:** the end-of-day wrap with draft Jira worklogs.

### 5.8 Dictate into any app
1. "Draft a reply to this" opens a draft card with Paste, Edit and Discard.
2. **Paste does three things:**
   - It **re-checks** that the same app and field are still frontmost (it asks again if not).
   - It **strips trailing newlines**, because a newline in a terminal would run the command.
   - It sends ⌘V, then **restores my previous clipboard**.
3. It never presses Send or Enter.

### 5.9 Input voice or the bubble can't give
Every wait is a **pending-input** record that the character shows. Every card has an **Open in Terminal** way out.

| Situation | What we do |
|---|---|
| Tool approval | Card rendered by the core from the **tool name and raw input** (§7), plus a spoken summary when voice is allowed |
| `AskUserQuestion` (arrives through `can_use_tool`; answered via `updated_input.answers`; verified in the docs) | Choices panel with an "Other" box; answer by voice, click or typing. **It isn't available inside subagents,** so the persona avoids asking questions from subagents. |
| `ExitPlanMode` (not documented for `can_use_tool`) | The persona never uses plan mode. If a plan request appears anyway: a plan card with Approve, Request changes and Open in Terminal. |
| MCP elicitation (not documented in the SDK) | **Deferred.** A generic "waiting for you" card with Open in Terminal. |
| Connector needs signing in again | A card with "Open connector settings" or "Open in Terminal" (to run `/mcp`); the turn continues without that connector |
| A command wants a password or an interactive login | Bash has no terminal and stdin is closed, so it fails fast. A card offers Open in Terminal with the command ready. **Passwords never go through the assistant.** |
| Secrets or tokens needed | I set them myself (Keychain, terminal, settings), never by voice or bubble |
| Long input | Paste into the bubble (it grows into a text box), or drop a file |
| Large diff to review | Summary card + Open in Terminal / Open in editor |
| Usage limit reached | A card with the reset time; jobs pause |
| Browser sign-in or captcha | I do it myself; a card has a Continue button |
| Anything else | A generic "Session is waiting for you" card + Open in Terminal |

### 5.10 Opening a session elsewhere
1. **Open in Terminal** (phase 3a). Runs `claude --resume <id>` in the session's stored `cwd`. It's always available and gives the full Claude Code UI.
2. **Built-in chat window** (later phase). Shows the transcript (virtualised) with a text box, on the same live session.
3. ~~Open in the Claude desktop app~~: **dropped.** Today its sidebar lists only its own sessions (anthropics/claude-code#58670, #43786). Revisit if that changes.

**Handoff rule** (never two writers on one session):
- Opening a session in Terminal marks it `handed_off`, and the assistant stops sending turns to it.
- **There's no automatic take-back.** An idle terminal still owns the session.
- **Take back** in the menu, or talking about that session, **forks** it (`fork_session`). The terminal keeps the original.

### 5.11 Activity on the character
- **Phase 3a: one count badge.** It shows the number of running sessions and turns amber with the number waiting for me. The character raises its hand when anything waits.
- **Later: the full activity ring.**
  - One orbiting dot per active session, coloured by state: running, waiting, handed off, finished, failed.
  - Hovering lists the sessions.
  - Clicking opens the Sessions panel.

### 5.12 Long answers: speak the summary, show the rest
- **The rule:** if a reply would take more than about 20 s to say (roughly 50 words), the assistant speaks **only a 1–3 sentence summary** and then says "The details are on screen."
- **Where the full answer goes:**
  - v1: the bubble expands into a scrollable card next to the character.
  - Once the chat window exists (phase 8): it opens there, scrolled to that reply.
- **How it's enforced:**
  - The voice `CLAUDE.md` asks Claude to put a short spoken summary first, then the details (§4).
  - The core also enforces a hard cap, in case Claude doesn't follow that. If the spoken part is over the limit, it speaks the first sentences up to the cap, then the "on screen" line, and sends the whole reply to the card.
  - Code, tables, links and long lists are never read aloud.
- **When I want more:**
  - **"Read it all"** speaks the full answer.
  - **"Shorter"** or **"Just the gist"** re-summarises it.
- **Settings:** the limit (default about 20 s); always-full; always-summary.
- **Quiet mode** speaks nothing and shows everything.

## 6. What we reuse

All reused code is MIT-licensed, keeps its headers, and is listed in `NOTICE.md`. Claude_Chat (no licence) contributes ideas only. The Rive asset's licence is checked before use.

| From | What | Where |
|---|---|---|
| [hey-claude](https://github.com/tachyurgy/hey-claude) | **Later phase:** the `reset()` and refractory logic, the `training/` pipeline for retraining (`hey_claude.onnx` itself failed on my voice) | App: wake word (later) |
| ~~livekit-wakeword~~ | Dropped: v2 can't load openWakeWord models; our own Swift port works (F05) and is kept for the later wake-word phase | — |
| hey-claude | The LaunchAgent pattern (`service.py`) | App: launch at login |
| [halo](https://github.com/VW3st/halo) | Sentence buffer policy, spoken acknowledgements and cues, barge-in decision, `GapCapture`, transcript filters (ported to Swift) | App: turn-taking |
| halo | `claude -p --input-format stream-json` long-lived process pattern | Core: **fallback** brain |
| [spych](https://github.com/connor-makowski/spych) | Session chaining (`session_id` from the init message, then `resume=`) | Core: brain |
| [VoiceMode](https://github.com/mbailey/voicemode) | The Silero end-of-turn approach (reference) | App: VAD |
| Claude_Chat (ideas) | Mic calibration and self-test | App: settings |

**We build ourselves:**
- the approval gate (the hook, per-tool card renderers, tainting)
- the router and session index
- the MCP servers
- the character and panels
- the stdio protocol
- job worktrees
- everything in §5

## 7. Core design details

### Approval gate
1. **The `PreToolUse` hook runs first,** before settings allow rules. That matters because my user and repo settings may contain allow rules, and those would otherwise approve tools before `can_use_tool` is ever called.
2. **The hook decides from a policy table:** exact tool names (§4), the built-in tools below, and job rules (§5.1). It returns:
   - **allow:** on the allowlist and not blocked by taint.
   - **deny:** a denied path or tool.
   - **ask:** anything else. **The hook itself asks me:** it sends `pending_input` to the app, waits for the answer, and returns allow or deny. So nothing depends on whether a hook's "ask" reaches `can_use_tool` (to verify, §9).
3. **`can_use_tool` is used only** for `AskUserQuestion` (to return `updated_input.answers`) and as a final catch-all that asks. The Python SDK needs streaming input for `can_use_tool`, which we already use.
4. **Built-in tools:**
   - **allow:** `Read`, `Grep`, `Glob`.
   - **allow, unless the turn is tainted** (then ask): `WebSearch` and `WebFetch`.
   - **ask:** `Edit` and `Write` (allowed only inside a job's worktree, §5.1).
   - **click:** `Bash` (except the job's exact-command allowlist).
5. **Tainting.** A turn becomes tainted once it has taken in untrusted content. Sources:
   - screen context or a selection
   - a dropped item
   - the clipboard
   - connector results (email, Slack, Jira, web pages)

   In a tainted turn, every network-egress tool (`WebFetch`, `WebSearch`, `open_url`, `show_image` with a URL) asks, unless the domain appears in my own utterance.
6. **Approval cards come from the core, not from Claude.**
   - Each tool has a renderer (for example "Send to #channel: <exact text>"), falling back to raw JSON input.
   - Claude's own description of the action isn't shown, so injected text can't misdescribe it.
7. **Voice answers are bound:**
   - "Yes" or "no" counts only if I start speaking **after the prompt finished**, while that request's card is the active one.
   - **A click is required** for Bash, deletes, `start_job`, `cancel_job`, screenshots, `open_url` in tainted turns, and every job approval.
   - A timeout, an unclear answer, or a core restart counts as deny.
8. **Every decision is logged** in `actions`: the tool, the raw input hash, the decision and how it was given.

### Router
1. **Local rules first** (≤ 20 ms):
   - An active session used in the last 30 min → continue.
   - An alias in the utterance ("in the collector repo") → a new session in that repo.
   - Otherwise → a new session in the home folder.
2. **A Claude router call** (Haiku, low effort, no tools) only when the utterance asks to resume ("continue the Jira thing from this morning") or the local rules are ambiguous. It returns `{action, session_id, reason}`.
3. **Resume always uses the stored `cwd`.**

### Session index (SQLite)
- `sessions(session_id PK, kind: conversation|job, title, summary, cwd, worktree, created_at, last_used_at, turn_count, status: running|waiting_input|idle|handed_off|done|failed, forked_from)`
- `pending_inputs(id, session_id, kind, card, voice_ok, created_at, answered_at, answer, via)`
- `conversations(id, session_id, started_at, ended_at, first_utterance, trigger)`
- `projects(path PK, name, aliases, description, last_used_at)`
- `nudges(id, source, text, priority, created_at, delivered_at, spoken)`
- `actions(id, session_id, tool, input_hash, decision, via, tainted, at)`

### Character spec
**Rive inputs:**
- `state` (0–3)
- `audioLevel` (0–1)
- `hover`
- `muted`
- `needsInput`
- `quiet`

The badge and ring are drawn by the app.

### Components

```
voice-assistant/
  CLAUDE.md  NOTICE.md  config.toml
  app/                       # SwiftUI + AppKit, macOS 26+
    AssistantApp.swift       # menu-bar app; spawns + supervises core (stdio)
    CoreLink.swift           # JSON-lines protocol over the child's stdin/stdout
    CharacterWindow.swift  CharacterView.swift  Bubble.swift  Badge.swift  (ActivityRing.swift later)
    Panels/                  # Approval, Choices, Card, Table, Sessions, Draft, Waiting  (ChatWindow later)
    Audio/AudioEngine.swift  # voice-processing engine; mic + AVAudioPlayerNode for synth
    Audio/VAD.swift  Audio/STT.swift (Whisper + live captions)  Audio/TTS.swift  Audio/TurnTaking.swift  (Audio/Wake.swift later)
    Context.swift  CallDetect.swift  Hotkey.swift (push-to-talk: hold / tap)  DropTarget.swift  Paste.swift  OpenInTerminal.swift  Perf.swift
  core/                      # Python 3.11+, uv
    main.py                  # stdio loop
    conversation.py  router.py  brain.py
    gate.py                  # PreToolUse hook: policy table, taint, cards, voice/click rules
    renderers.py             # per-tool approval card renderers
    pending.py  handoff.py  jobs.py  worktrees.py
    mcp_ui.py  mcp_mac.py  mcp_context.py  mcp_jobs.py  mcp_capture.py
    watchers.py  briefings.py  presence.py  index.py
  tests/                     # gate policy tests run on every change
```

## 8. Phases

| Phase | Scope | Done when |
|---|---|---|
| **0. Spike** (about 3–4 days; the order matters) | 1. **SDK on my subscription:** login with no API key; connectors and plugins load; in-process MCP works next to them. 2. **Gate test:** put `Bash(touch:*)` in a repo's settings and confirm the hook still asks. 3. **Echo test:** Premium voice → `write(toBufferCallback:)` → player node on the voice-processing engine, on built-in speakers, while the mic listens. 4. **SpeechAnalyzer** accuracy and latency on my speech and terms (Jira, MR, Databricks, PRJ-…). 5. **Wake word in Swift** (livekit-wakeword or ONNX Runtime) with `hey_claude.onnx`: idle CPU and scores. 6. **Footprint** of the bare app, the core, and one Claude Code process. 7. Rive in a transparent panel. 8. Per-process call detection. | Each item passes or fails with numbers. A fail changes the plan before phase 1: no subscription login means the `claude -p` fallback; weak echo cancellation means half-duplex; weak speech-to-text means WhisperKit. |
| **1. Voice loop** | **Push-to-talk hotkey (hold and tap) and click to start**; long answers spoken as a summary with the full text in the bubble (§5.12); the Swift audio pipeline (engine on demand, VAD, Whisper speech-to-text, speech through the engine) + the text core over stdio + one SDK session; a minimal floating character | A 5-turn spoken conversation started by the hotkey, using one connector, without headphones, within the §2.1 budgets; the mic is off when idle. **Also in phase 1, release and CI as in maclens** (`docs/RELEASING.md` → "Coming in phase 1"): `build-app.sh` → `Zoe.app`, `package-release.sh` → zip + sha256, `zoe-selftest` and the core's gate policy tests in CI, the full `check-version.sh`, a build + attest + upload job in `release.yml`, the Homebrew cask (`make-cask.sh`, `publish-cask.sh`, `homebrew.yml`, tap token) with cask lint in CI, CodeQL for Swift, Dependabot for Swift and Python |
| **2. Safety** (phase 3a) | The gate (hook, policy table, taint, core-rendered cards, voice/click rules), pending input (§5.9), Open in Terminal + handoff + fork, count badge, gate policy tests | A Slack send waits for approval; an allow rule in settings can't skip the gate; injected screen text can't fetch a URL without asking; a password prompt opens Terminal |
| **3. Sessions** (phase 3b) | Local router + Claude fallback, SQLite index, summaries, repo aliases, stored-`cwd` resume, idle close and resume | "In the collector repo…" opens there; "continue the Jira thing from this morning" resumes it in its own folder |
| **4. Panels + quiet** (phase 3c) | `ui` panels, quiet mode, typing, call handling (engine off) | "Show my tickets" opens a table; silent during calls; typing works |
| **5. Context + hands** | Screen context, drop, `mac` tools, dictation with safe paste, capture | "What's this error?" works; a draft pastes into Slack after a click, never sent |
| **6. Jobs** | Worktree jobs, job policy, nudges | A review runs in a worktree while I talk; outward actions need a click |
| **7. Proactive** | Morning briefing, three watchers, quiet rules; meeting prep (opt-in) | A briefing on the first conversation of the day; a failed pipeline is reported within about 5 min |
| **8. Polish** | Chat window, full activity ring, barge-in, start at login, Performance view, 8-hour soak | Runs from login; I can interrupt mid-sentence; no memory growth over 8 h |
| **9. Wake word** (later) | "Hey Claude" hands-free: retrain the openWakeWord model (synthetic voices incl. Indian English + my recordings), run it on our Swift port with an energy gate, plain engine while waiting, chime on detection | Passes `spikes/f05-wake/scripts/record_wake.sh` on fresh recordings: ≥ 90 % recall, 0 near-miss fires, ≤ 1 false fire per hour of talk; idle CPU within the §12.2 wake rows |
| **Later** | Elicitation forms, Kokoro, end-of-day wrap + worklogs, meeting follow-up, Grafana/pod watchers, custom character | As needed |

## 9. Open items (phase 0 unless noted)

- [ ] **The SDK uses my subscription login.** The docs don't say. Test it. If not, fall back to `claude -p` stream-json.
- [ ] **claude.ai connectors and plugins load in SDK sessions.** Implied by the docs, not stated.
- [ ] **A hook's "ask" decision with `can_use_tool`.** Not needed, because the hook asks me itself, but good to know.
- [ ] **`ExitPlanMode` through `can_use_tool`.** Not documented; the persona avoids plan mode.
- [ ] **The echo-cancellation test** with the synthesiser routed through the engine.
- [ ] **SpeechAnalyzer** support for Indian English, and custom vocabulary.
- [x] **livekit-wakeword:** dropped (F05). Wake word moved to phase 9.
- [x] **Push-to-talk:** right ⌥ via event tap and ⌃⌥Space via `RegisterEventHotKey` both report press and release (F07 addendum). Not known: whether the shortcut works without Accessibility (moot, since the app requires it).
- [ ] **Selected text in Chromium/Electron apps** (browsers, Slack, VS Code): AX gave nothing in a quick probe; test with real selections in phase 5, with ⌘C plus clipboard restore as the fallback.
- [ ] **Per-process input detection** for calls (CoreAudio process objects), and whether two voice-processing apps at once cause trouble.
- [ ] **Footprint of one Claude Code process.**
- [ ] **Rive** in a transparent, borderless panel.
- [ ] **Two writers / fork** behaviour with `claude --resume` (phase 2).
- [ ] **Paste reliability** in Slack, Chrome and IDEs (phase 5).
- [ ] **Concurrency limits** for parallel sessions on my subscription (phase 6).
- [ ] **Watcher APIs** that can be polled directly with Keychain tokens (phase 7).

## 10. Risks

- **Latency of Claude itself.** Mitigated by a cached acknowledgement, the "thinking" state, panels instead of long speech, local routing and resumable warm sessions.
- **Approval bypass.** Mitigated by the hook gate before allow rules, exact names, taint, core-rendered cards, click-only for high-risk actions, and policy tests in CI.
- **Prompt injection** from screen, clipboard, files or connectors. Mitigated by taint gating egress and by cards showing the raw input.
- **Echo or self-triggering.** Mitigated by synthesis through the engine, with half-duplex as the fallback.
- **Mic use.** Rev 7: the mic is on only during a conversation I started. On-device only and nothing stored. The engine stops during calls and when muted. (An always-on mic returns with the wake word in phase 9.)
- **Subscription terms.** Personal, user-initiated use only; Claude calls from watchers are opt-in; never distributed.
- **Claude Code's footprint.** Capped live sessions and idle close (§2.1).
- **Swift learning curve.** A thin app; reuse packages (RiveRuntime, WhisperKit, ONNX Runtime) instead of hand ports.

## 11. Review resolution (`REVIEW.md`)

| Finding | Resolution |
|---|---|
| B1 allow rules bypass `can_use_tool` | `PreToolUse` hook is the gate and asks itself (§7); phase 0 test 2 |
| B2 read-verb allowlist + free WebFetch | Exact-name policy table (§4), `get_clipboard` asks, taint gates egress (§7) |
| B3 unauthenticated websocket | stdio JSON lines with a child process (§3) |
| B4 synthesiser not echo-cancelled | `write(toBufferCallback:)` → player node on the engine; half-duplex fallback; phase 0 test 3 |
| S1 model-written summaries, weak voice yes | Core-rendered cards, voice bound to the prompt, click for high risk (§7) |
| S2 job policy undefined | Worktrees, denied paths, exact git allowlist, click for outward actions (§5.1) |
| S3 budgets | Chime on detection, clocks defined, generic acks, memory ≤ 80 MB each to be measured, virtualised chat, assets downloaded at setup (§2.1) |
| S4 router latency | Local rules first, Claude only for resume or ambiguity, stored `cwd` (§7) |
| S5 rev 4 not carried through | Phases rebuilt; macOS 26+; VoiceMode servers removed (§8) |
| S6 call detection | Per-process detection; the engine stops during calls (§5.5) |
| S7 auto take-back | Removed; take back = fork (§5.10) |
| S8 paste safety | Re-check the target, strip newlines, restore the clipboard (§5.8) |
| S9 subscription terms | Personal, user-initiated by default; watcher Claude calls opt-in (§2) |
| C1 cut scope | Deferred: elicitation, Whisper/Kokoro, worklogs, meeting follow-up, Grafana/pod watchers. **Kept but moved later at my request:** chat window and full activity ring. **Dropped:** Open in desktop app. |
| C2 split phase 3 | Phases 2–4 (safety → sessions → panels) |
| C3 don't hand-port the wake word | livekit-wakeword as the candidate (§6). Rev 6: it can't load openWakeWord models, so our own port is used. Rev 7: the wake word moves to phase 9 |
| C4 phase 0 too small | 3–4 days, ordered by risk |
| C5 real footprint | Stated, with session caps (§2.1) |
| C6 core restart | Pending → deny, sessions resumable (§3) |

## 12. Feasibility results (rev 6)

Source: `feasibility/README.md` and the reports F01–F07. **Where this section disagrees with an earlier one, this section wins.**

### 12.1 Decisions changed by measurement

| Area | Before | Now | Evidence |
|---|---|---|---|
| Approval gate | `PreToolUse` hook asks me itself | **One catch-all `PreToolUse` hook with an explicit `timeout` and `on_failure="block"`** (the default fails *open* when the hook throws). The hook decides allow or deny; "ask" goes to `can_use_tool`, which renders the card and waits. `AskUserQuestion` (answer via `updated_input.answers` keyed by question text) and `ExitPlanMode` (`{plan, planFilePath}`) are **listed explicitly in `tools`**, since they're absent by default. Plan mode stays banned, because it auto-writes to `~/.claude/plans/`. | F02, F01 |
| Settings | Allow rules from my settings may load | Same. Note: in an **untrusted** workspace the CLI ignores project allow rules, but `--settings` and `allowed_tools` rules still apply, so the hook stays mandatory. | F02 |
| Audio engine | One voice-processing engine always on | **Rev 7: engine off when idle** (no wake word); it starts on the hotkey or a click. **Phase 1 measurement (#3): a voice-processing engine takes ~1 s to start (first words lost) and suppressed speech from other apps in a test, so phase 1 listens with a plain engine (starts in ~160 ms, ~3 % CPU, 75 MB while listening) and is half-duplex: the mic is paused while Zoe speaks. Voice processing returns with barge-in (phase 8); `ZOE_VP=1` turns it on for testing.** (For phase 9, waiting for the wake word: a plain engine, about 0.5 % CPU, 29 MB.) **Voice processing turns on only for a conversation** (9–12 % CPU, about 86 MB while on). Connect the player→mixer graph **before** enabling voice processing (otherwise error −10875). The voice-processing input is 48 kHz with 9 identical channels; take channel 0. | F03 |
| Speaking | Synthesiser buffers → player node | Confirmed: echo drops about 22–31 dB with the basic voice and **28 dB with Zoe (Premium)**, to the mic's noise floor. **Warm the synthesiser up at launch** (first buffer 399 ms basic, **1,072 ms Zoe**; later ones 31–54 ms). Buffers are Float32, 22,050 Hz, mono, so no conversion is needed. **Compute mouth levels from buffers before scheduling** (the player tap fires only every ~96 ms). | F03 |
| Speech-to-text | SpeechAnalyzer (SpeechTranscriber) | **Whisper `large-v3-turbo` via WhisperKit for the final transcript, no prompt to start; SpeechTranscriber only for live partial captions. Ids, names, environments and numbers in a request are read back before any write.** Held-out test (30 phrases, Claude reading each transcript with my work context): Whisper gets the intent fully right 23/30 and wrong 3/30, against Apple's 13/30 and 10/30. A term prompt helps only the terms in it, doesn't improve intent, adds about 0.4 s, and can leak into the output. Earlier first-set notes: On my voice Apple's engines fail (SpeechTranscriber 32 % word errors, 5/17 terms; DictationTranscriber drops speech). Whisper with the prompt: 17 % word errors (about 15 % with contractions treated as equal), 16/17 terms, final 0.9 s after end of speech (0.48 s without the prompt), about 185 MB in-process. If a prompt is added later, it needs a **prompt-echo guard** (a list-style prompt was hallucinated back once). Drop the SFSpeechRecognizer fallback. **In the app (phase 1, measured):** a warm load takes about 1.1 s (started on the trigger, while I speak), a transcript 0.42–0.52 s, and the app peaks at about 230 MB in a conversation; Whisper unloads 2 min after it ends. The **first load compiles the model for the Neural Engine: 113–157 s, 17 s of CPU, 1.4 GB peak.** It recurs for each new app binary (so likely once per app update) and per macOS build, so Zoe does it in the background at launch, and a turn spoken meanwhile waits for it. Each compile adds to `~/Library/Caches/Zoe` (1.3 GB after a day of dev rebuilds; stale entries aren't cleaned up yet). | F04 |
| Wake word | livekit-wakeword package | **Our own Swift port** (mel → embedding → head, about 150 lines) on Microsoft's `onnxruntime-swift-package-manager` 1.24.2 (MIT). It matches Python to within 9e-5 and builds without Xcode. livekit-wakeword v2 can't load openWakeWord models. Core ML is worse here (6.5 % CPU, 286 MB). | F05 |
| Wake model | `hey_claude.onnx` as is | **Fails on my voice: 3/36 (8 %) at any threshold, 0 false fires** (2026-11-17). **Rev 7: push-to-talk and click for v1; wake word in phase 9.** Earlier, on synthetic voices: 3 of 48 positives detected, near misses fire 6 of 32. **Gate:** an own-voice test; if recall is under 90 %, retrain (openWakeWord training with real and synthetic data). **Phase-1 fallback:** click and push-to-talk only, with the wake word behind a setting. | F05 |
| Wake CPU (phase 9) | ≤ 2 % | 3.2–6 % measured (under a background load average of 3–4). **Add an energy gate with about 1.3 s of look-back,** so silence costs about 0.1 % and the model re-runs the buffered audio when the gate opens. | F05 |
| Character | Rive at 30 fps active and 10 fps idle | **Set fps explicitly** (the default is 120 fps on ProMotion, 10–13 % CPU): 30 fps while active (about 4 %), **paused when idle** (0 %, 25 MB footprint). The asset must have **no artboard background**. Use Rive's data-binding API (the state-machine input API is deprecated in 6.30). Dragging needs an explicit drag overlay; verify by hand. Ships a 15 MB framework. | F06 |
| Call detection | "To verify" | **Works with no permission:** CoreAudio process objects, with listeners on `prs#` (process list) and `pdv#` (per-process devices), plus a 2–5 s safety poll (~1 ms CPU each). The `IsRunningInput` listener never fires on 26.6.1. | F07 |
| Permissions onboarding | Listed loosely | **Required:** Microphone, and **Accessibility** (selected text, window title, the push-to-talk event tap, the paste keystroke; the keystroke is silently dropped without it). **Optional:** Automation per browser (URL), Screen Recording (screenshots), Input Monitoring (only for a listen-only tap). No permission needed: call detection, frontmost app, clipboard. Paste must check `AXIsProcessTrusted()` before it's offered. | F07 |
| SDK sessions | Default options | Pass a **trimmed `mcp_servers`** (connectors I need plus in-process servers), so each session doesn't start its own copies of my local stdio servers (tradingview, web-search, voicemode; about 240 MB per session). **Skip my user `SessionStart` hook** for assistant sessions (it adds about 11 s to a fresh connect), or keep one warm session. | F01 |
| Fallback brain | `claude -p` stream-json | Works: two turns over stdin, stable id, `--resume`. Resume spawn → first text 2.06 s, versus 1.60 s with the SDK. | F01 |
| Interactive commands | Expected to fail fast | Confirmed: stdin is `/dev/null` and there's no TTY. `input()` fails in 0.07 s, `getpass` in 0.11 s, `ssh` in 0.28 s. GUI password prompts (askpass, Keychain) are unverified. | F02 |
| Two writers | Forbidden, take-back forks | Confirmed necessary: two writers at once split the conversation onto a side branch. `fork_session` leaves the original byte-identical. | F02 |

### 12.2 Budget, rewritten from measurements

The baseline still excludes Claude Code's own processes. They're stated separately because they're large.

| Metric | Rev 5 | Rev 6 target | Measured basis |
|---|---|---|---|
| App CPU, idle (rev 7, no wake word) | ≤ 2 % | **≈ 0 %** | engine off; Rive paused 0 %; hotkey handling is event-driven |
| App CPU, waiting for wake word (phase 9) | — | silence ≤ 1 % (energy gate); speech or noise around ≤ 6 % | plain engine 0.5 %; gated wake 0.1 %; wake model 3.2–6 % |
| App CPU, in conversation | — | **≤ 20 %** | voice processing 9–12 % + Rive at 30 fps about 4 % |
| App memory (footprint), idle | ≤ 80 MB | **≤ 80 MB** (rev 7; estimate, to measure in phase 1) | Rive paused 25 MB + app baseline about 9 MB; no engine, no ONNX Runtime. Phase 9 adds the wake pipeline (about 79–90 MB) and the plain engine (29 MB) |
| App memory (footprint), in conversation | — | **≤ 300 MB** | + voice processing about 57 MB + Rive animating about 100 MB. **Whisper adds about 185 MB:** run it in a helper process loaded only during conversations, or raise this to about 500 MB |
| Core memory (RSS) | ≤ 80 MB | **≤ 80 MB** ✔ | 68 MB with the SDK imported, about 40 MB idle |
| System speech service | — | not budgeted | `localspeechrecognition` peak about 177 MB, only while transcribing (partial captions) |
| **Claude Code per live session** | not stated | **about 250–325 MB** (+ about 240 MB if local MCP servers aren't trimmed) | F01 |
| End of speech → final transcript | ≤ 250 ms | **≤ 600 ms** (Whisper, no prompt) ✖ vs rev 5 | Whisper 0.49 s p50, 0.51 s p90 without a prompt; 0.9 s with one; Apple 28–117 ms but inaccurate. Caching the prompt state may cut it (unverified). The ≤ 300 ms acknowledgement still runs from end of speech |
| SDK connect / first text | — | connect 0.4 s; first text 0.9–1.3 s (Haiku); resume 1.6 s | F01 |

### 12.3 Phase 0 status

| # | Item | Status |
|---|---|---|
| 1 | SDK on my login, connectors, in-process MCP | ✔ works. ✔ **Team plan use confirmed with IT (2026-11-17, as reported by me)** |
| 2 | Gate test (allow rule vs hook) | ✔ |
| 3 | Echo test | ✔ with **Zoe (Premium)**: echo removed 28 dB, to the noise floor; first sentence after launch 1.1 s, so warm up at launch. ⚠ VP briefly mutes the mic during playback, so barge-in may lose my first words (phase 1) |
| 4 | Speech-to-text | ✔ synthetic. ✖ **own voice: Apple on-device fails** (32 % word errors, 5–6/17 terms). ✔ **Whisper turbo, no prompt: intent right or nearly right 27/30, wrong 3/30, 0.49 s** (two sets, 30 phrases; word errors 19–24 %). Gate changed to intent on 2026-11-17: **passes** (on the line). Keep checking with real use in phase 1. |
| 5 | Wake word in Swift | ✔ engine. ✖ **own voice: `hey_claude.onnx` detects 3/36 (8 %)**, 0 false fires (F05 addendum). Rev 7: push-to-talk and click for v1; the wake word moves to **phase 9** (retrain, then pass the same test). |
| 6 | Footprint | ✔ measured (§12.2) |
| 7 | Rive transparent panel | ✔ (drag and full-screen to check by hand) |
| 8 | Call detection | ✔ |
| — | Accessibility-dependent checks (context, push-to-talk, paste) | ✔ granted 2026-11-17: window title, selection in native apps, paste, right-⌥ and ⌃⌥Space push-to-talk all work. ⚠ selection in Chromium apps unverified |
| — | Barge-in, two voice-processing apps at once, hook waits over 70 s, token refresh | ⏳ phase 1 / 2 |

**Ready for phase 1 when:**
- ✔ IT confirms use of the Team plan (2026-11-17),
- speech-to-text gets my intent right or nearly right in at least 90 % of phrases and wrong in at most 10 % (Whisper with no prompt: 90 % / 10 % over 30 phrases ✔; this gate replaced the word-error one on 2026-11-17), and
- ✔ phase 1 uses push-to-talk and click (rev 7); the wake word failed the own-voice test on 2026-11-17 (8 % recall) and is now phase 9.
