"""The Claude router (PLAN.md §7, Router step 2; issue #27).

Used only when the local router flags a request to resume something ("continue the release notes from this
morning") or a repo name that fits several projects. One Haiku call (quick.py: no tools, no settings, ~2.5 s)
sees only the candidates' titles, summaries, folder names and ages, never conversation content, and returns
`{"pick": <number or null>, "reason": "..."}`. The pick is checked against the candidates: anything else means
"no match" (a new session).
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Awaitable, Callable

Ask = Callable[[str, str], Awaitable[tuple[dict | None, float]]]

SYSTEM = ("You route a voice assistant's request to one of the user's earlier sessions or projects. Reply with JSON "
          'only: {"pick": <the number of the best match, or null if none clearly fits>, "reason": "<at most 12 words>"}. '
          "Prefer null over a guess.")


@dataclass
class Pick:
    index: int | None       # into the candidates list
    reason: str
    seconds: float


def ago(t: float | None, now: float) -> str:
    if not t:
        return "unknown time"
    d = max(0, now - t)
    if d < 3600:
        return f"{int(d // 60)} min ago"
    if d < 86400:
        return f"{int(d // 3600)} h ago ({time.strftime('%H:%M', time.localtime(t))})"
    return f"{int(d // 86400)} days ago ({time.strftime('%a %H:%M', time.localtime(t))})"


def session_prompt(text: str, sessions: list[dict], now: float) -> str:
    lines = [f'Request: "{text}"', f"Now: {time.strftime('%a %H:%M', time.localtime(now))}", "Earlier sessions:"]
    for i, s in enumerate(sessions, 1):
        folder = os.path.basename((s.get("cwd") or "").rstrip("/")) or "home"
        lines.append(f"{i}. \"{s.get('title') or 'untitled'}\" — {s.get('summary') or 'no summary'} "
                     f"[folder: {folder}; {ago(s.get('last_used_at'), now)}]")
    return "\n".join(lines)


def project_prompt(text: str, projects: list) -> str:
    lines = [f'Request: "{text}"', "Projects with that name:"]
    for i, p in enumerate(projects, 1):
        lines.append(f"{i}. {p.name} [{p.path}]")
    return "\n".join(lines)


def checked(res: dict | None, n: int) -> tuple[int | None, str]:
    if not isinstance(res, dict):
        return None, "router failed"
    pick, reason = res.get("pick"), str(res.get("reason") or "")[:120]
    if isinstance(pick, bool) or not isinstance(pick, int) or not 1 <= pick <= n:
        return None, reason or "no clear match"
    return pick - 1, reason


async def pick_session(text: str, sessions: list[dict], ask: Ask, now: float | None = None) -> Pick:
    if not sessions:
        return Pick(None, "no earlier sessions", 0.0)
    res, dt = await ask(SYSTEM, session_prompt(text, sessions, now or time.time()))
    i, why = checked(res, len(sessions))
    return Pick(i, why, dt)


async def pick_project(text: str, projects: list, ask: Ask) -> Pick:
    res, dt = await ask(SYSTEM, project_prompt(text, projects))
    i, why = checked(res, len(projects))
    return Pick(i, why, dt)
