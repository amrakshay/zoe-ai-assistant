"""Approval cards, rendered by the core from the tool's raw input (PLAN.md §7.6; issue #16).

A card shows exactly what will happen: who a message goes to and its exact text, which file changes and
how, the exact command. It never shows Claude's own account of the action, so text injected into Claude's
context can't misdescribe it:
- built-in tools show only the fields that decide what happens (e.g. `Bash` shows the command, never its
  `description`, which is Claude's own narration);
- connector tools show **every** input field, because all of it is sent or saved (a calendar event's
  `description` is real content there);
- unknown tools fall back to the raw JSON input, labelled as such;
- every value is shown verbatim (never interpreted as markup) and truncated visibly, never silently.

Card: {title, fields: [{label, value, mono}], summary (spoken, #17), why}.
"""
from __future__ import annotations

import json
import re
from typing import Any
from urllib.parse import urlparse

from .gate import ApprovalRequest
from .names import Names

MAX_CHARS = 600
MAX_LINES = 12
SPOKEN_WORDS = 14

TO_KEYS = ("channel", "channel_id", "channel_name", "to", "recipient", "recipients", "user", "user_id", "email",
           "attendees", "cc", "bcc")
TEXT_KEYS = ("text", "message", "body", "content", "markdown", "comment")
SUBJECT_KEYS = ("subject", "title", "summary", "name")
TIME_KEYS = ("start", "start_time", "end", "end_time", "when", "time", "post_at")


def clip(value: Any, max_chars: int = MAX_CHARS, max_lines: int = MAX_LINES) -> str:
    """Verbatim text, cut visibly: '… (N more lines)' / '… (N more characters)'."""
    s = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, default=str)
    lines = s.splitlines() or [""]
    note = ""
    if len(lines) > max_lines:
        note = f"… ({len(lines) - max_lines} more lines)"
        s = "\n".join(lines[:max_lines])
    if len(s) > max_chars:
        note = f"… ({len(s) - max_chars} more characters)" if not note else note
        s = s[:max_chars]
    return s + ("\n" + note if note else "")


def words(s: str, n: int = SPOKEN_WORDS) -> str:
    w = str(s).split()
    return " ".join(w[:n]) + (" …" if len(w) > n else "")


def service_of(tool: str) -> tuple[str, str]:
    """`mcp__claude_ai_Google_Calendar__create_event` → ("Google Calendar", "create_event")."""
    m = re.match(r"^mcp__(?:claude_ai_)?(.+?)__(.+)$", tool)
    if not m:
        return "", tool
    return m.group(1).replace("_", " "), m.group(2)


def first(d: dict, keys: tuple[str, ...]) -> tuple[str, Any] | None:
    for k in keys:
        if k in d and d[k] not in (None, "", [], {}):
            return k, d[k]
    return None


def field(label: str, value: Any, mono: bool = False) -> dict:
    return {"label": label, "value": clip(value), "mono": mono}


def raw_card(req: ApprovalRequest, title: str | None = None) -> dict:
    raw = json.dumps(req.tool_input, indent=2, ensure_ascii=False, default=str)
    service, action = service_of(req.tool_name)
    return {"title": title or f"Allow {action.replace('_', ' ')}{' in ' + service if service else ''}?",
            "fields": [{"label": f"Tool: {req.tool_name}", "value": "", "mono": True},
                       field("Raw input", raw, mono=True)],
            "summary": f"Zoe wants to use {action.replace('_', ' ')}{' in ' + service if service else ''}.",
            "why": req.reason}


def _bash(req: ApprovalRequest) -> dict:
    cmd = req.tool_input.get("command", "")
    fields = [field("Command", cmd, mono=True)]
    if req.tool_input.get("run_in_background"):
        fields.append(field("Runs", "in the background"))
    return {"title": "Run a command?", "fields": fields,
            "summary": "Zoe wants to run a command. It's on screen.", "why": req.reason}


def _edit(req: ApprovalRequest) -> dict:
    i = req.tool_input
    path = i.get("file_path") or i.get("notebook_path", "")
    old, new = str(i.get("old_string", "")), str(i.get("new_string", i.get("new_source", "")))
    diff = "\n".join(["- " + l for l in old.splitlines()] + ["+ " + l for l in new.splitlines()])
    fields = [field("File", path, mono=True), field("Change", diff, mono=True)]
    if i.get("replace_all"):
        fields.append(field("Applies to", "every occurrence in the file"))
    return {"title": "Edit a file?", "fields": fields, "summary": f"Zoe wants to edit {path.rsplit('/', 1)[-1]}.",
            "why": req.reason}


def _write(req: ApprovalRequest) -> dict:
    path, content = req.tool_input.get("file_path", ""), str(req.tool_input.get("content", ""))
    size = f"{len(content.encode())} bytes, {len(content.splitlines())} lines"
    return {"title": "Write a file?", "fields": [field("File", path, mono=True), field("Size", size),
                                                 field("Content", content, mono=True)],
            "summary": f"Zoe wants to write {path.rsplit('/', 1)[-1]}.", "why": req.reason}


def _fetch(req: ApprovalRequest) -> dict:
    i = req.tool_input
    if req.tool_name == "WebSearch":
        return {"title": "Search the web?", "fields": [field("Query", i.get("query", ""))],
                "summary": f"Zoe wants to search the web for {words(i.get('query', ''), 8)}.", "why": req.reason}
    url = str(i.get("url", ""))
    domain = urlparse(url).hostname or "?"
    return {"title": "Open a web page?", "fields": [field("Site", domain), field("Address", url, mono=True)],
            "summary": f"Zoe wants to open a page on {domain}.", "why": req.reason}


def _message(req: ApprovalRequest, names: Names | None = None) -> dict | None:
    """Sends, posts, replies, emails, drafts: the recipient and the exact text."""
    service, action = service_of(req.tool_name)
    i = req.tool_input
    to, text = first(i, TO_KEYS), first(i, TEXT_KEYS)
    if not (to or text):
        return None
    subject = first(i, ("subject",))
    noun = "an email" if re.search(r"mail", service, re.I) else "a message"
    verb = "Draft" if "draft" in action.lower() else "Send"
    fields = []
    if to:
        named = names.label(to[1]) if names else None
        fields.append(field("To", named or to[1]))
    if subject:
        fields.append(field("Subject", subject[1]))
    if text:
        fields.append(field("Message", text[1]))
    rest = {k: v for k, v in i.items() if k not in {to and to[0], text and text[0], subject and subject[0]}}
    if rest:
        fields.append(field("Other details", json.dumps(rest, ensure_ascii=False, default=str), mono=True))
    known = names.by_id.get(to[1]) if (names and to and isinstance(to[1], str)) else None
    who = f" to {words(known or to[1], 4)}" if to else ""
    say = f": {words(text[1])}" if text else ""
    why = f"{'Drafts' if verb == 'Draft' else 'Sends'} {noun} as you." + ("" if req.reason.startswith("not on the allowlist") else f" ({req.reason})")
    return {"title": f"{verb} {noun}{' in ' + service if service else ''}?", "fields": fields,
            "summary": f"{verb} {noun}{who}{say}?", "why": why}


def _event(req: ApprovalRequest) -> dict | None:
    service, action = service_of(req.tool_name)
    i = req.tool_input
    if "calendar" not in service.lower():
        return None
    verb = {"create": "Create", "update": "Change", "respond": "Respond to", "delete": "Delete"}.get(
        action.split("_")[0].lower(), action.replace("_", " ").capitalize())
    fields = [field(k.replace("_", " ").capitalize(), v) for k, v in i.items()]
    what = first(i, SUBJECT_KEYS)
    return {"title": f"{verb} a calendar event?", "fields": fields,
            "summary": f"{verb} the calendar event{' ' + words(what[1], 8) if what else ''}?", "why": req.reason}


def render(req: ApprovalRequest, names: Names | None = None) -> dict:
    """The card for one approval request. Never raises: on any problem, the raw card."""
    try:
        if req.tool_name == "Bash":
            card = _bash(req)
        elif req.tool_name in ("Edit", "NotebookEdit"):
            card = _edit(req)
        elif req.tool_name == "Write":
            card = _write(req)
        elif req.tool_name in ("WebFetch", "WebSearch"):
            card = _fetch(req)
        elif req.tool_name.startswith("mcp__"):
            card = _event(req) or _message(req, names) or raw_card(req)
        else:
            card = raw_card(req)
    except Exception:  # noqa: BLE001 — a renderer bug must not hide the input
        card = raw_card(req)
    return card
