# Zoe

[![CI](https://github.com/amrakshay/zoe-ai-assistant/actions/workflows/ci.yml/badge.svg)](https://github.com/amrakshay/zoe-ai-assistant/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A voice assistant for my Mac that does its work through **Claude Code**, so it has my plugins, connectors and context.

- **Hold a key and talk** (or click the small character floating on screen). It answers out loud, like ChatGPT voice mode, and keeps listening for follow-ups.
- **Claude Code does the work.** Zoe picks the right session: it continues the current one, resumes an older one, or starts a new one in the right repo, and keeps an index of every session it touches.
- **Nothing that changes anything runs without my approval.** Writes, sends and commands wait for a voice "yes" or a click.
- **Long answers are summarised out loud,** with the full text on screen.
- **Fast and light.** A native Swift app; audio stays on the Mac (Whisper and Apple speech run on-device). The mic is off unless I start a conversation.

> **Status: design and feasibility done; phase 1 (the voice loop) is next.** There's no app to install yet.

## How it works

```
Swift menu-bar app                                   Python core (child process, JSON lines over stdio)
  push-to-talk / click ─► mic ─► VAD ─► Whisper ──►    router ─► Claude Agent SDK ─► Claude Code sessions
  speaker ◄─ echo-cancelling engine ◄─ Zoe voice ◄──   approval gate (PreToolUse hook) · session index · jobs
  character · bubble · panels · approvals
```

- **App (Swift, macOS 26+):** the floating Rive character, panels and the whole audio pipeline (echo cancellation, Silero VAD, Whisper large-v3-turbo via WhisperKit, Apple speech synthesis).
- **Core (Python):** a small process the app starts and talks to over stdin/stdout, so nothing else can reach it. It owns the Claude Agent SDK, routing, approvals and the session index.

## Documents

| | |
|---|---|
| [PLAN.md](PLAN.md) | The plan: goals, decisions, architecture, features, phases and budgets |
| [REVIEW.md](REVIEW.md) | Independent adversarial review of the design |
| [feasibility/](feasibility/README.md) | Phase 0 feasibility tests with measured results, and the code to re-run them |
| [mock/assistant-flows.html](mock/assistant-flows.html) | Interactive mock of the main flows (open in a browser) |
| [docs/RELEASING.md](docs/RELEASING.md) | How releases work |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, branches, commits and checks |

## Requirements (planned)

- macOS 26 or later on Apple Silicon.
- Claude Code, signed in. Zoe uses your existing Claude login through the Agent SDK; it never asks for an API key.
- Permissions: Microphone and Accessibility (push-to-talk key, reading the selection, paste).

## Privacy

- Audio never leaves the Mac, and nothing is recorded or stored.
- The mic is on only during a conversation you started.
- Screen text, the clipboard, dropped files and connector results are treated as untrusted: in those turns Zoe asks before any network call.

## License

[MIT](LICENSE). Reused code keeps its own MIT notices (see PLAN.md §6).
