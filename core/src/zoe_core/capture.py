"""Capture: notes, todos and reminders (PLAN.md §5.7; issue #47).

- `add_note` / `add_todo` append a timestamped line to a Markdown inbox file I choose:
  `~/Library/Application Support/Zoe/settings.json` → `{"notes_inbox": "~/path/to/Inbox.md"}`
  (default: `inbox.md` in Zoe's folder). Nothing personal is hard-coded.
- `remind_me` creates a Reminder through the app (EventKit), which asks macOS for Reminders access once.
Allowed without asking (they only append to my own lists), by exact name; they read nothing, so they don't taint.
"""
from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Awaitable, Callable

Send = Callable[..., Awaitable[None]]

SERVER = "capture"
TOOLS = ("add_note", "add_todo", "remind_me")
EXACT_NAMES = frozenset(f"mcp__{SERVER}__{t}" for t in TOOLS)
MAX_TEXT = 2000


def data_dir() -> Path:
    return Path(os.environ.get("ZOE_DATA_DIR") or os.path.expanduser("~/Library/Application Support/Zoe"))


def inbox_path() -> Path:
    try:
        s = json.loads((data_dir() / "settings.json").read_text())
        p = s.get("notes_inbox")
        if isinstance(p, str) and p.strip():
            return Path(os.path.expanduser(p.strip()))
    except (OSError, ValueError):
        pass
    return data_dir() / "inbox.md"


def line(kind: str, text: str, now: float | None = None) -> str:
    stamp = datetime.fromtimestamp(time.time() if now is None else now).strftime("%Y-%m-%d %H:%M")
    clean = " ".join(str(text).split())[:MAX_TEXT]
    return f"- [ ] {clean} ({stamp})\n" if kind == "todo" else f"- {stamp} {clean}\n"


def append(kind: str, text: str) -> Path:
    if not str(text).strip():
        raise ValueError("nothing to write")
    p = inbox_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "a", encoding="utf-8") as f:
        f.write(line(kind, text))
    return p


class Capture:
    def __init__(self, send: Send, timeout: float = 15.0):
        self.send = send
        self.timeout = timeout
        self._pending: dict[str, asyncio.Future] = {}

    async def remind(self, text: str, due: str | None) -> tuple[bool, str]:
        rid = f"rem-{uuid.uuid4().hex[:10]}"
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending[rid] = fut
        await self.send("add_reminder", id=rid, title=str(text)[:300], due=due or "")
        try:
            return await asyncio.wait_for(fut, self.timeout)
        except asyncio.TimeoutError:
            return False, "the app didn't answer"
        finally:
            self._pending.pop(rid, None)

    def reminder_done(self, msg: dict[str, Any]) -> bool:
        fut = self._pending.get(msg.get("id"))
        if fut is None or fut.done():
            return False
        fut.set_result((bool(msg.get("ok")), str(msg.get("detail") or "")))
        return True

    async def handle(self, tool: str, args: dict) -> dict:
        def ok(t: str) -> dict:
            return {"content": [{"type": "text", "text": t}]}

        def err(t: str) -> dict:
            return {"content": [{"type": "text", "text": t}], "is_error": True}

        text = str(args.get("text", "")).strip()
        if not text:
            return err("Nothing to capture.")
        if tool in ("add_note", "add_todo"):
            try:
                p = await asyncio.to_thread(append, "todo" if tool == "add_todo" else "note", text)
            except OSError as e:
                return err(f"Couldn't write the inbox: {e}")
            return ok(f"Added to {p.name}.")
        if tool == "remind_me":
            done, detail = await self.remind(text, args.get("due"))
            return ok(f"Reminder set{': ' + detail if detail else ''}.") if done else err(f"Couldn't set the reminder: {detail}")
        return err("Unknown capture tool.")

    def server(self):
        from claude_agent_sdk import create_sdk_mcp_server, tool

        s = {"type": "string"}
        specs = {
            "add_note": ("Append a note to the user's notes inbox.", {"type": "object", "properties": {"text": s}, "required": ["text"]}),
            "add_todo": ("Append a todo to the user's notes inbox.", {"type": "object", "properties": {"text": s}, "required": ["text"]}),
            "remind_me": ("Create a reminder in Apple Reminders. `due`: local date-time like 2026-11-23T16:00 (optional).",
                          {"type": "object", "properties": {"text": s, "due": s}, "required": ["text"]}),
        }
        tools = []
        for name in TOOLS:
            desc, schema = specs[name]

            def make(n):
                async def call(args):
                    return await self.handle(n, args or {})
                return call
            tools.append(tool(name, desc, schema)(make(name)))
        return create_sdk_mcp_server(SERVER, "1.0.0", tools)
