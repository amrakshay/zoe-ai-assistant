"""Claude Code brain (#2): one Agent SDK session on my own login, streamed sentence by sentence.

- Runs on the stored claude.ai login: ANTHROPIC_API_KEY and CLAUDE_* variables inherited from a host are
  removed before the CLI starts (F01).
- Loads my user, project and local settings, so plugins, connectors and CLAUDE.md context are there.
  The session connects at core start, so the slow first connect (my SessionStart hook, ~11 s in F01)
  happens at launch, not on the first question. Follow-up turns reuse the same session.
- Every tool goes through the approval gate (gate.py, policy.py); `can_use_tool` denies anything that reaches it.
"""
from __future__ import annotations

import asyncio
import os
import sys
import time
from typing import Any, Awaitable, Callable

from .approvals import Approvals
from .gate import Gate
from .policy import ENABLED_BUILTINS
from .speech import READ_ALL, SentenceSplitter, SpokenReply

PERSONA = """
You are Zoe, a voice assistant on the user's Mac. Your reply is spoken aloud, then shown in a small bubble.
- Start with a short spoken answer: one to three plain sentences (under 50 words), no markdown, no lists,
  no code, no URLs.
- If more detail would help, add it after a blank line; it is shown on screen, not read out. Don't say
  that the details are on screen; the app says so.
- Be direct and warm. Don't narrate your tool use. Never ask the user to type.
- Never use plan mode. Never run interactive commands.
- To change, send, create or run something, just call the tool: Zoe shows the user an approval card and
  waits for their answer, so don't ask for permission in words first. If it's declined or not answered,
  say so in one short sentence and don't retry.
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
        self.last_reply = ""
        self._connecting: asyncio.Task | None = None
        self._turn: asyncio.Task | None = None
        self.approvals = Approvals(send, session_id=lambda: self.session_id)
        self.gate = Gate(approver=self.approvals.ask, session_id=lambda: self.session_id)

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
            tools=sorted(ENABLED_BUILTINS),                  # every one of them goes through the gate
            system_prompt={"type": "preset", "preset": "claude_code", "append": PERSONA},
            hooks={"PreToolUse": [HookMatcher(matcher=None, hooks=[self.gate.pre_tool_use],
                                                          timeout=self.approvals.timeout + 30, on_failure="block")]},
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
        self.approvals.cancel_all("interrupt")   # hooks wait in the SDK's task, not the turn's
        if self._turn and not self._turn.done():
            self._turn.cancel()

    async def _read_all(self, uid: Any) -> None:
        """'Read it all': speak every speakable sentence of the last reply, without the cap."""
        spoken = SpokenReply(cap=False)
        splitter = SentenceSplitter()
        sentences = splitter.feed(self.last_reply + "\n") + splitter.flush()
        await self.send("state", value="talking")
        said = False
        for sentence in sentences:
            if spoken.offer(sentence):
                said = True
                await self.send("say", utterance_id=uid, text=sentence, final=False)
        if not said:
            await self.send("say", utterance_id=uid, text="There's nothing more to read out.", final=False)
        await self.send("say", utterance_id=uid, text="", final=True)
        await self.send("state", value="idle")

    async def _run(self, uid: Any, text: str) -> None:
        from claude_agent_sdk import AssistantMessage, ResultMessage, TextBlock
        from claude_agent_sdk.types import StreamEvent

        if READ_ALL.match(text.strip()) and self.last_reply:
            await self._read_all(uid)
            return
        t0 = time.monotonic()
        first = None
        splitter = SentenceSplitter()
        spoken = SpokenReply()
        full: list[str] = []
        streamed = False

        async def say(sentences: list[str], breaks: list[bool]) -> None:
            nonlocal first
            for sentence, new_para in zip(sentences, breaks):
                if (s := spoken.offer(sentence, new_para)) is None:
                    continue
                if first is None:
                    first = time.monotonic() - t0
                    await self.send("state", value="talking")
                await self.send("say", utterance_id=uid, text=s, final=False)

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
                        got = splitter.feed(delta)
                        await say(got, splitter.breaks)
                    elif ev.get("type") == "message_stop":
                        # End of one assistant message: close its last sentence and break paragraphs.
                        got = splitter.flush()
                        await say(got, splitter.breaks)
                        full.append("\n\n")
                elif isinstance(m, AssistantMessage) and not streamed:
                    for b in m.content:  # fallback if partial messages are unavailable
                        if isinstance(b, TextBlock):
                            full.append(b.text)
                            got = splitter.feed(b.text + "\n")
                            await say(got, splitter.breaks)
                            got = splitter.flush()
                            await say(got, splitter.breaks)
                elif isinstance(m, ResultMessage):
                    self.session_id = m.session_id
            got = splitter.flush()
            await say(got, splitter.breaks)
            for line in spoken.finish():
                await self.send("say", utterance_id=uid, text=line, final=False)
            reply = "".join(full).strip()
            self.last_reply = reply
            await self.send("say", utterance_id=uid, text="", final=True)
            await self.send("bubble", utterance_id=uid, text=reply, summarised=spoken.held_back)
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
