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
from .names import Names
from .renderers import render
from .terminal import TerminalHandoff
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
- The user's words come from speech-to-text, which can mishear short technical words ("ls" as "is"). If a
  request to run, change or send something is unclear or doesn't quite make sense, say what you understood in
  one sentence and ask before doing anything; don't go exploring to guess.
- Before sending to a Slack user or channel by ID, look it up first (slack_read_user_profile with its user_id,
  or slack_search_channels), so the approval card can show its name.
""".strip()

Send = Callable[..., Awaitable[None]]


def log(*a: Any) -> None:
    print("[brain]", *a, file=sys.stderr, flush=True)


def scrub_env() -> None:
    """Use the stored claude.ai login, never a key or session variables inherited from a host process."""
    for k in list(os.environ):
        if k == "ANTHROPIC_API_KEY" or k.startswith(("CLAUDE", "ANTHROPIC_")):
            os.environ.pop(k, None)


def resume_command(session_id: str) -> str:
    """`claude --resume <id>`: my own claude if it's on the PATH, else the copy the Agent SDK ships (same login and
    settings either way)."""
    import shlex
    try:
        import claude_agent_sdk
        bundled = os.path.join(os.path.dirname(claude_agent_sdk.__file__), "_bundled", "claude")
    except Exception:  # noqa: BLE001
        bundled = "claude"
    sid = shlex.quote(session_id)
    return f"if command -v claude >/dev/null; then claude --resume {sid}; else {shlex.quote(bundled)} --resume {sid}; fi"


class Brain:
    def __init__(self, send: Send, index=None) -> None:
        self.index = index        # the session index (#24); None in tests
        self.send = send
        self.client = None
        self.session_id: str | None = None
        self.last_reply = ""
        self._connecting: asyncio.Task | None = None
        self._turn: asyncio.Task | None = None
        self.names = Names()
        self.approvals = Approvals(send, render=lambda req: render(req, self.names), session_id=lambda: self.session_id,
                                   index=index)
        self.gate = Gate(approver=self.approvals.ask, session_id=lambda: self.session_id)
        self.handoff = TerminalHandoff(send, session_id=lambda: self.session_id, names=self.names)
        # Handoff (#20): once the session is opened in Terminal, Zoe never writes to it again; the next turn
        # forks it (the terminal keeps the original). PLAN.md §5.10.
        self.handed_off: str | None = None
        self.fork_next = False

    @property
    def cwd(self) -> str:
        return os.environ.get("ZOE_HOME", os.path.expanduser("~"))

    async def hand_off(self) -> dict | None:
        """Open this session in Terminal (#20): stop the turn (pending approvals are denied), close Zoe's own
        connection so there's never a second writer, and return what the app should run. None: no session yet."""
        if not self.session_id:
            return None
        sid = self.session_id
        await self.interrupt()
        if self._turn:
            try:
                await asyncio.wait_for(asyncio.shield(self._turn), 5)
            except Exception:  # noqa: BLE001 - cancelled or timed out; we disconnect regardless
                pass
        if self.client:
            try:
                await self.client.disconnect()
            except Exception:  # noqa: BLE001
                pass
        self.client, self._connecting = None, None
        self.handed_off, self.fork_next = sid, True
        if self.index is not None:
            self.index.set_status(sid, "handed_off")
        log(f"handed off session {sid[:8]} to Terminal; the next turn forks it")
        return {"session_id": sid, "cwd": self.cwd, "command": resume_command(sid)}

    def take_back(self) -> None:
        """Talk to Zoe again about a handed-off session: connect a fork now (the terminal keeps the original)."""
        if self.handed_off:
            self.fork_next = True
            self.warm_up()

    def options(self):
        from claude_agent_sdk import ClaudeAgentOptions, HookMatcher, PermissionResultAllow, PermissionResultDeny

        async def can_use_tool(tool_name, tool_input, ctx):
            # Only AskUserQuestion is meant to get here (the hook decides everything else); the rest is denied.
            if tool_name == "AskUserQuestion":
                updated = await self.approvals.question(tool_input)
                if updated is not None:
                    return PermissionResultAllow(updated_input=updated)
                return PermissionResultDeny(message="The user didn't answer. Don't ask again; go on without it or stop.")
            return PermissionResultDeny(message="Blocked: this didn't go through Zoe's approval gate.")

        # Sonnet by default: warm calendar turn 3.7 s to the first sentence (Haiku 2.7 s, my default Opus ~8 s).
        model = os.environ.get("ZOE_MODEL", "claude-sonnet-5-5")
        sources = os.environ.get("ZOE_SETTING_SOURCES", "user,project,local")
        return ClaudeAgentOptions(
            model=model,
            cwd=self.cwd,
            setting_sources=[s for s in sources.split(",") if s],
            tools=sorted(ENABLED_BUILTINS),                  # every one of them goes through the gate
            system_prompt={"type": "preset", "preset": "claude_code", "append": PERSONA},
            hooks={"PreToolUse": [HookMatcher(matcher=None, hooks=[self.gate.pre_tool_use],
                                                          timeout=self.approvals.timeout + 30, on_failure="block")],
                   "PostToolUse": [HookMatcher(matcher=None, hooks=[self.handoff.post_tool_use], timeout=10)],
                   "PostToolUseFailure": [HookMatcher(matcher=None, hooks=[self.handoff.post_tool_use], timeout=10)]},
            can_use_tool=can_use_tool,
            include_partial_messages=True,
            resume=self.session_id,
            fork_session=bool(self.fork_next and self.session_id),
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

        self.gate.taint.user_said(text)          # domains I name myself don't need approval (#18)
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
        if self.index is not None and self.session_id:
            self.index.set_status(self.session_id, "running")
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
                    forked_from = self.handed_off if (self.fork_next and m.session_id != self.handed_off) else None
                    if self.index is not None:
                        self.index.upsert_session(m.session_id, self.cwd, status="idle", forked_from=forked_from)
                        self.index.touch(m.session_id)
                    if self.fork_next and m.session_id != self.handed_off:
                        log(f"forked {str(self.handed_off)[:8]} → {m.session_id[:8]}")
                        self.fork_next, self.handed_off = False, None
                        await self.send("session_state", session_id=m.session_id, handed_off=False, forked=True)
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
