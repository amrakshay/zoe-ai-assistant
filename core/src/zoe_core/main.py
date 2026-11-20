"""Core stdio loop: handshake, ping, and utterances answered by the Claude Code brain (#2).

`ZOE_BRAIN=echo` swaps the brain for an echo (tests, CI). stdout carries protocol messages only; logs go
to stderr.
"""
from __future__ import annotations

import asyncio
import os
import sys
import time
from typing import Any, Awaitable, Callable

from . import PROTOCOL_VERSION
from .protocol import APP_TO_CORE, MAX_LINE, ProtocolError, decode, encode

Send = Callable[..., Awaitable[None]]


def log(*a: Any) -> None:
    print("[core]", *a, file=sys.stderr, flush=True)


class Core:
    def __init__(self, send: Send, brain: Any = None) -> None:
        self.send = send
        self.started = time.monotonic()
        self.brain = brain

    async def handle(self, msg: dict[str, Any]) -> bool:
        """Handle one message. Returns False when the core should exit."""
        t = msg["type"]
        if t == "hello":
            await self.send("hello", protocol=PROTOCOL_VERSION, pid=os.getpid())
            await self.send("state", value="idle")
            if self.brain:
                self.brain.warm_up()
                if hasattr(self.brain, "load_projects"):
                    asyncio.create_task(self.brain.load_projects())
        elif t == "ping":
            await self.send("pong", id=msg.get("id"), uptime_s=round(time.monotonic() - self.started, 3))
        elif t == "utterance":
            await self.handle_utterance(msg)
        elif t == "open_session":
            await self.open_session(msg)
        elif t == "take_back":
            if self.brain:
                self.brain.take_back()
        elif t == "answer":
            if not (self.brain and self.brain.approvals.answer(msg)):
                await self.send("error", message=f"answer for unknown or finished request: {msg.get('pending_id')}")
        elif t == "user_interrupted":
            if self.brain:
                await self.brain.interrupt()
        elif t == "shutdown":
            if self.brain:
                await self.brain.close()
            return False
        elif t in APP_TO_CORE:
            pass  # known but not implemented yet (later phases)
        else:
            await self.send("error", message=f"unknown message type: {t}")
        return True

    async def open_session(self, msg: dict[str, Any]) -> None:
        """`open_session {where: terminal}` (#20): hand the conversation to Terminal."""
        if msg.get("where", "terminal") != "terminal":
            await self.send("error", message="only Terminal is supported for now")
            return
        info = await self.brain.hand_off() if self.brain else None
        if info is None:
            await self.send("error", message="no conversation to open yet")
            return
        await self.send("open_terminal", command=info["command"], cwd=info["cwd"], session_id=info["session_id"])
        await self.send("session_state", session_id=info["session_id"], handed_off=True)

    async def handle_utterance(self, msg: dict[str, Any]) -> None:
        text = str(msg.get("text", ""))
        uid = msg.get("id")
        if self.brain:
            self.brain.handle(uid, text)
            return
        await self.send("state", value="thinking")
        await self.send("say", utterance_id=uid, text=f"You said: {text}", final=True)
        await self.send("state", value="idle")


async def serve(reader: asyncio.StreamReader, write: Callable[[bytes], Awaitable[None]], brain: bool = False) -> None:
    async def send(type_: str, **fields: Any) -> None:
        await write(encode(type_, **fields))

    b = None
    if brain:
        from . import actions
        from .brain import Brain
        from .index import Index
        try:
            index = Index()
            actions.use_index(index)
        except Exception as e:  # noqa: BLE001 — Zoe still works without its index
            log("session index unavailable:", repr(e))
            index = None
        b = Brain(send, index=index)
    core = Core(send, b)
    while True:
        try:
            line = await reader.readuntil(b"\n")
        except asyncio.IncompleteReadError as e:  # EOF: the app went away
            if e.partial.strip():
                log("dropping partial line at EOF")
            if b:
                await b.close()
            return
        except asyncio.LimitOverrunError:
            await send("error", message="line too long")
            await reader.read(reader._limit)  # noqa: SLF001 - discard the oversized chunk
            continue
        if not line.strip():
            continue
        try:
            msg = decode(line)
        except ProtocolError as e:
            await send("error", message=str(e))
            continue
        if not await core.handle(msg):
            return


async def amain() -> None:
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=MAX_LINE)
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    out = sys.stdout.buffer

    async def write(data: bytes) -> None:
        out.write(data)
        out.flush()

    log(f"started pid={os.getpid()} protocol={PROTOCOL_VERSION}")
    await serve(reader, write, brain=os.environ.get("ZOE_BRAIN", "claude") != "echo")
    log("exiting")


def run() -> None:
    try:
        asyncio.run(amain())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    run()
