"""The `ui` tool server: panels Claude can draw (PLAN.md §4; issue #34).

An in-process SDK MCP server (measured: no extra memory, the SDK already loads the MCP library). Its tools only
display things, so the gate allows them by exact name. They never taint the session (they read nothing).

- `show_card`    {title, body (markdown)}
- `show_table`   {title, columns: [str], rows: [[str]]}
- `show_choices` {prompt, options: [str]}: a click sends my choice as my next turn
- `dismiss`      {id?}: close a panel (the latest one if no id)

Inputs are checked and size-limited here; the app shows them verbatim (no HTML, links aren't followed).
"""
from __future__ import annotations

import uuid
from typing import Any, Awaitable, Callable

Send = Callable[..., Awaitable[None]]

SERVER = "ui"
TOOLS = ("show_card", "show_table", "show_choices", "show_draft", "dismiss")
EXACT_NAMES = frozenset(f"mcp__{SERVER}__{t}" for t in TOOLS)

MAX_TITLE, MAX_BODY, MAX_CELL = 120, 8000, 300
MAX_COLS, MAX_ROWS, MAX_OPTIONS = 12, 500, 8


class InputError(ValueError):
    pass


def _text(v: Any, limit: int, what: str, required: bool = True) -> str:
    if v is None and not required:
        return ""
    if not isinstance(v, (str, int, float)) or (required and str(v).strip() == ""):
        raise InputError(f"{what} must be text")
    s = str(v)
    return s if len(s) <= limit else s[:limit] + f"… ({len(s) - limit} more characters)"


def card(args: dict) -> dict:
    return {"title": _text(args.get("title"), MAX_TITLE, "title"), "body": _text(args.get("body"), MAX_BODY, "body")}


def table(args: dict) -> dict:
    cols = args.get("columns")
    rows = args.get("rows")
    if not isinstance(cols, list) or not 1 <= len(cols) <= MAX_COLS:
        raise InputError(f"columns must be a list of 1–{MAX_COLS} names")
    if not isinstance(rows, list):
        raise InputError("rows must be a list of lists")
    cols = [_text(c, MAX_CELL, "column name") for c in cols]
    out, cut = [], max(0, len(rows) - MAX_ROWS)
    for r in rows[:MAX_ROWS]:
        if not isinstance(r, list):
            raise InputError("each row must be a list")
        cells = [_text(c, MAX_CELL, "cell", required=False) if c is not None else "" for c in r[:len(cols)]]
        out.append(cells + [""] * (len(cols) - len(cells)))
    return {"title": _text(args.get("title") or "Table", MAX_TITLE, "title"), "columns": cols, "rows": out,
            "truncated_rows": cut}


def choices(args: dict) -> dict:
    opts = args.get("options")
    if not isinstance(opts, list) or not 2 <= len(opts) <= MAX_OPTIONS:
        raise InputError(f"options must be a list of 2–{MAX_OPTIONS} items")
    return {"prompt": _text(args.get("prompt"), MAX_TITLE * 2, "prompt"),
            "options": [_text(o, MAX_TITLE, "option") for o in opts]}


def draft(args: dict) -> dict:
    return {"title": _text(args.get("title") or "Draft", MAX_TITLE, "title"), "text": _text(args.get("text"), MAX_BODY, "text")}


def _ok(text: str) -> dict:
    return {"content": [{"type": "text", "text": text}]}


def _err(text: str) -> dict:
    return {"content": [{"type": "text", "text": text}], "is_error": True}


class UI:
    def __init__(self, send: Send, session_id: Callable[[], str | None] | None = None):
        self.send = send
        self._session = session_id or (lambda: None)
        self.open: list[str] = []

    async def show(self, kind: str, payload: dict) -> dict:
        pid = f"panel-{uuid.uuid4().hex[:10]}"
        self.open.append(pid)
        await self.send("show_panel", id=pid, kind=kind, payload=payload, session_id=self._session())
        return _ok(f"Shown on screen (panel {pid}). Don't read its contents aloud; one short spoken sentence is enough.")

    async def handle(self, tool: str, args: dict) -> dict:
        try:
            if tool == "show_card":
                return await self.show("card", card(args))
            if tool == "show_table":
                return await self.show("table", table(args))
            if tool == "show_choices":
                return await self.show("choices", choices(args))
            if tool == "show_draft":
                return await self.show("draft", draft(args))
            if tool == "dismiss":
                pid = args.get("id") or (self.open[-1] if self.open else None)
                if pid:
                    if pid in self.open:
                        self.open.remove(pid)
                    await self.send("dismiss_panel", id=pid, reason="claude")
                return _ok("Closed." if pid else "Nothing to close.")
        except InputError as e:
            return _err(f"Not shown: {e}.")
        return _err("Unknown ui tool.")

    def server(self):
        """The SDK MCP server config for ClaudeAgentOptions.mcp_servers."""
        from claude_agent_sdk import create_sdk_mcp_server, tool

        str_ = {"type": "string"}
        schemas = {
            "show_card": ("Show a card on screen: a title and a markdown body. Use for details, code, links.",
                          {"type": "object", "properties": {"title": str_, "body": str_}, "required": ["title", "body"]}),
            "show_table": ("Show a table on screen. Use for more than about three items with several fields.",
                           {"type": "object", "properties": {"title": str_, "columns": {"type": "array", "items": str_},
                                                             "rows": {"type": "array", "items": {"type": "array", "items": str_}}},
                            "required": ["columns", "rows"]}),
            "show_choices": ("Show clickable choices; the user's click comes back as their next message.",
                             {"type": "object", "properties": {"prompt": str_, "options": {"type": "array", "items": str_}},
                              "required": ["prompt", "options"]}),
            "show_draft": ("Show a draft the user can edit and paste into the app they're in (never sent). Use for "
                           "'draft a reply', 'write a message', 'dictate'.",
                           {"type": "object", "properties": {"title": str_, "text": str_}, "required": ["text"]}),
            "dismiss": ("Close a panel (the latest one if no id is given).",
                        {"type": "object", "properties": {"id": str_}}),
        }
        tools = []
        for name in TOOLS:
            desc, schema = schemas[name]

            def make(n):
                async def run(args):
                    return await self.handle(n, args or {})
                return run
            tools.append(tool(name, desc, schema)(make(name)))
        return create_sdk_mcp_server(SERVER, "1.0.0", tools)
