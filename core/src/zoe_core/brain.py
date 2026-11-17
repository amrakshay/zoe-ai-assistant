"""Claude Code brain (#2): one Agent SDK session on my own login, streamed sentence by sentence.

- Runs on the stored claude.ai login: ANTHROPIC_API_KEY and CLAUDE_* variables inherited from a host are
  removed before the CLI starts (F01).
- Loads my user, project and local settings, so plugins, connectors and CLAUDE.md context are there.
  The session connects at core start, so the slow first connect (my SessionStart hook, ~11 s in F01)
  happens at launch, not on the first question. Follow-up turns reuse the same session.
- Every tool goes through the read-only gate (gate.py); `can_use_tool` denies anything that reaches it.
"""
from __future__ import annotations

import asyncio
import os
import sys
import time
from typing import Any, Awaitable, Callable

from .gate import BUILTIN_READ, pre_tool_use
from .speech import SentenceSplitter

PERSONA = """
You are Zoe, a voice assistant on the user's Mac. Your reply is spoken aloud, then shown in a small bubble.
- Start with a short spoken answer: one to three plain sentences, no markdown, no lists, no code, no URLs.
- If more detail would help, add it after a blank line; it is shown on screen, not read out.
- Be direct and warm. Don't narrate your tool use. Never ask the user to type.
- Never use plan mode. Never run interactive commands.
- You can only read in this version. If asked to change, send, create or run something, say you can't do
  that yet in one sentence.
""".strip()

Send = Callable[..., Awaitable[None]]


def log(*a: Any) -> None:
    print("[brain]", *a, file=sys.stderr, flush=True)


def scrub_env() -> None:
    """Use the stored claude.ai login, never a key or session variables inherited from a host process."""
    for k in list(os.environ):
        if k == "ANTHROPIC_API_KEY" or k.startswith(("CLAUDE", "ANTHROPIC_")):
            os.environ.pop(k, None)


class Brain:
    def __init__(self, send: Send) -> None:
        self.send = send
        self.client = None
        self.session_id: str | None = None
        self._connecting: asyncio.Task | None = None
        self._turn: asyncio.Task | None = None

    def options(self):
        from claude_agent_sdk import ClaudeAgentOptions, HookMatcher, PermissionResultDeny

        async def deny_all(tool_name, tool_input, ctx):  # final catch-all: the hook already decided
            return PermissionResultDeny(message="Blocked: not on Zoe's read-only allowlist.")

        # Sonnet by default: warm calendar turn 3.7 s to the first sentence (Haiku 2.7 s, my default Opus ~8 s).
        model = os.environ.get("ZOE_MODEL", "claude-sonnet-5-5")
        sources = os.environ.get("ZOE_SETTING_SOURCES", "user,project,local")
        return ClaudeAgentOptions(
            model=model,
            cwd=os.environ.get("ZOE_HOME", os.path.expanduser("~")),
            setting_sources=[s for s in sources.split(",") if s],
            tools=sorted(BUILTIN_READ),                      # no Bash / Edit / Write / Web* at all
            system_prompt={"type": "preset", "preset": "claude_code", "append": PERSONA},
            hooks={"PreToolUse": [HookMatcher(matcher=None, hooks=[pre_tool_use], timeout=10, on_failure="block")]},
            can_use_tool=deny_all,
            include_partial_messages=True,
            resume=self.session_id,
        )

    def warm_up(self) -> None:
        if self._connecting is None:
            self._connecting = asyncio.create_task(self._connect())

    async def _connect(self) -> None:
        from claude_agent_sdk import ClaudeSDKClient

        scrub_env()
        t0 = time.monotonic()
        client = ClaudeSDKClient(options=self.options())
        await client.connect()
        self.client = client
        log(f"connected in {time.monotonic() - t0:.2f} s")

    async def ready(self) -> None:
        self.warm_up()
        try:
            await self._connecting
        except Exception:
            self._connecting = None  # let the next turn retry
            raise

    def handle(self, utterance_id: Any, text: str) -> None:
        """Start a turn; a new utterance interrupts the one still running."""
        if self._turn and not self._turn.done():
            self._turn.cancel()
        self._turn = asyncio.create_task(self._run(utterance_id, text))

    async def interrupt(self) -> None:
        if self._turn and not self._turn.done():
            self._turn.cancel()

    async def _run(self, uid: Any, text: str) -> None:
        from claude_agent_sdk import AssistantMessage, ResultMessage, TextBlock
        from claude_agent_sdk.types import StreamEvent

        t0 = time.monotonic()
        first = None
        splitter = SentenceSplitter()
        full: list[str] = []
        streamed = False
        await self.send("state", value="thinking")
        try:
            await self.ready()
            await self.client.query(text)
            async for m in self.client.receive_response():
                if isinstance(m, StreamEvent):
                    ev = m.event
                    if ev.get("type") == "content_block_delta" and ev.get("delta", {}).get("type") == "text_delta":
                        delta = ev["delta"]["text"]
                        streamed = True
                        full.append(delta)
                        for sentence in splitter.feed(delta):
                            if first is None:
                                first = time.monotonic() - t0
                                await self.send("state", value="talking")
                            await self.send("say", utterance_id=uid, text=sentence, final=False)
                    elif ev.get("type") == "message_stop":
                        # End of one assistant message: close its last sentence and break paragraphs.
                        for sentence in splitter.flush():
                            await self.send("say", utterance_id=uid, text=sentence, final=False)
                        full.append("\n\n")
                elif isinstance(m, AssistantMessage) and not streamed:
                    for b in m.content:  # fallback if partial messages are unavailable
                        if isinstance(b, TextBlock):
                            full.append(b.text)
                            await self.send("say", utterance_id=uid, text=b.text, final=False)
                elif isinstance(m, ResultMessage):
                    self.session_id = m.session_id
            for sentence in splitter.flush():
                await self.send("say", utterance_id=uid, text=sentence, final=False)
            reply = "".join(full).strip()
            await self.send("say", utterance_id=uid, text="", final=True)
            await self.send("bubble", utterance_id=uid, text=reply)
            log(f"turn: first sentence {first if first is None else round(first, 2)} s, total {time.monotonic() - t0:.2f} s")
        except asyncio.CancelledError:
            if self.client:
                try:
                    await self.client.interrupt()
                except Exception as e:  # noqa: BLE001
                    log("interrupt failed:", e)
            await self.send("say", utterance_id=uid, text="", final=True, interrupted=True)
            raise
        except Exception as e:  # noqa: BLE001
            log("turn failed:", repr(e))
            await self.send("say", utterance_id=uid, text="Sorry, I couldn't reach Claude just now.", final=True)
            await self.send("error", message=f"brain: {e}")
        finally:
            await self.send("state", value="idle")

    async def close(self) -> None:
        await self.interrupt()
        if self.client:
            try:
                await self.client.disconnect()
            except Exception:  # noqa: BLE001
                pass
