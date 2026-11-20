"""Waits that only a terminal can answer (PLAN.md §5.9; issue #19).

Claude's Bash has no terminal and its stdin is closed, so a command that wants a password or interactive input
fails fast instead of hanging. A hook on `PostToolUse` and `PostToolUseFailure` (a failing command fires only
the latter, with an `error` string instead of `tool_response`) spots those failures and:
- sends the app a `pending_input {kind: "terminal"}` card with the exact command and folder, and an
  **Open in Terminal** button (the app runs it there, where I can type the password myself);
- tells Claude it was handed over, so it doesn't retry or ask me for the password. **Passwords never go
  through Zoe.**

The same card covers a connector that needs signing in again (`claude` then `/mcp` in a terminal).
The card is informational: the core doesn't wait for it.
"""
from __future__ import annotations

import re
import uuid
from typing import Any, Awaitable, Callable

Send = Callable[..., Awaitable[None]]

NEEDS_TERMINAL = re.compile(
    r"a terminal is required|no tty present|askpass|password for |^password:|enter passphrase|"
    r"permission denied \(publickey|host key verification failed|stdin is not a terminal|"
    r"inappropriate ioctl for device|not a tty|must be run from a terminal|interactive login|"
    r"could not read (username|password)",
    re.IGNORECASE | re.MULTILINE)

NEEDS_SIGN_IN = re.compile(
    r"re-?authenticat|re-?authoriz|needs? (to )?(sign|log) ?in|token (has )?expired|invalid_grant|"
    r"unauthori[sz]ed|\b401\b|authentication required|reconnect",
    re.IGNORECASE)

HANDED_OVER = ("This needs a terminal (a password or interactive input). Zoe has offered the user an Open in "
               "Terminal button with this exact command. Don't retry it and never ask for a password; tell the user "
               "briefly that it's ready to run in Terminal.")
SIGN_IN = ("This connector needs signing in again. Zoe has offered the user a way to do it in Terminal (/mcp). "
           "Go on without it, and tell the user briefly.")


def response_text(resp: Any) -> str:
    if isinstance(resp, str):
        return resp
    if isinstance(resp, dict):
        parts = [str(resp.get(k, "")) for k in ("stdout", "stderr", "error", "output", "content", "text")]
        if not any(parts):
            parts = [str(resp)]
        return "\n".join(parts)
    if isinstance(resp, list):
        return "\n".join(response_text(x) for x in resp)
    return str(resp or "")


def is_error(resp: Any, text: str) -> bool:
    """A connector *error*, not content that happens to mention signing in (an email can say "unauthorized")."""
    if isinstance(resp, dict) and (resp.get("is_error") or resp.get("isError") or resp.get("error")):
        return True
    return bool(re.match(r"\s*(error|failed|mcp error)\b", text, re.IGNORECASE))


def service_of(tool: str) -> str:
    m = re.match(r"^mcp__(?:claude_ai_)?(.+?)__", tool)
    return m.group(1).replace("_", " ") if m else tool


class TerminalHandoff:
    def __init__(self, send: Send, session_id: Callable[[], str | None] | None = None):
        self.send = send
        self._session = session_id or (lambda: None)

    async def _card(self, title: str, command: str, cwd: str, note: str) -> None:
        await self.send("pending_input", id=f"term-{uuid.uuid4().hex[:12]}", session_id=self._session(), kind="terminal",
                        card={"title": title, "command": command, "cwd": cwd, "note": note}, voice_ok=False)

    async def post_tool_use(self, input_data: dict, tool_use_id: str | None, context) -> dict:
        event = input_data.get("hook_event_name") or "PostToolUse"
        tool = str(input_data.get("tool_name", ""))
        failed = event == "PostToolUseFailure"
        resp = {"is_error": True, "error": input_data.get("error", "")} if failed else input_data.get("tool_response")
        text = response_text(resp)
        cwd = str(input_data.get("cwd") or "")
        if tool == "Bash" and NEEDS_TERMINAL.search(text):
            cmd = str((input_data.get("tool_input") or {}).get("command", ""))
            await self._card("This command needs a terminal", cmd, cwd,
                             "It asks for a password or input that Zoe can't give. Run it in Terminal and type it there yourself.")
            return {"hookSpecificOutput": {"hookEventName": event, "additionalContext": HANDED_OVER}}
        if tool.startswith("mcp__") and is_error(resp, text) and NEEDS_SIGN_IN.search(text):
            svc = service_of(tool)
            await self._card(f"{svc} needs signing in again", "claude", cwd,
                             f"In Terminal, type /mcp and reconnect {svc}. Zoe carries on without it meanwhile.")
            return {"hookSpecificOutput": {"hookEventName": event, "additionalContext": SIGN_IN}}
        return {}
