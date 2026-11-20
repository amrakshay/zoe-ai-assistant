"""The local router (PLAN.md §7, Router; issue #26). Pure and fast (well under 20 ms): no model call.

Rules, in order:
1. A repo named in context ("in the api repo", projects.py) → a session in that repo: continue a session
   already there if it was used in the last 30 minutes, else start a new one there (its CLAUDE.md and rules
   load with it).
2. Several repos match the name equally → ambiguous. The Claude router decides (#27); until then, the most
   recently used of them.
3. Nothing named: continue the active session if it was used in the last 30 minutes, else start a new session
   in the home folder.
A request to resume something from earlier ("continue the X from this morning") is flagged for the Claude
router (#27); without it, rules 1–3 apply.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

RECENT_S = 30 * 60

RESUME = re.compile(
    r"\b(continue|resume|go back to|back to|pick up|carry on with|where (?:we|i) left)\b.*"
    r"\b(earlier|this morning|this afternoon|yesterday|last (?:week|time|night)|before|from (?:today|this)|thing|one)\b",
    re.IGNORECASE)


@dataclass
class SessionInfo:
    key: int                 # the brain's handle for the session
    cwd: str
    last_used: float         # wall time of its last turn; 0 = never used


@dataclass
class Route:
    action: str              # "continue" (an existing session) | "new" (a new session in `cwd`)
    cwd: str
    key: int | None = None   # for "continue"
    reason: str = ""
    ambiguous: list[str] = field(default_factory=list)
    resume_request: bool = False


def route(text: str, now: float, active: SessionInfo | None, sessions: list[SessionInfo], projects, home: str) -> Route:
    resume = bool(RESUME.search(text or ""))

    def recent(s: SessionInfo) -> bool:
        return s.last_used > 0 and now - s.last_used <= RECENT_S

    def in_repo(path: str, why: str) -> Route:
        here = [s for s in sessions if s.cwd == path and recent(s)]
        if here:
            best = max(here, key=lambda s: s.last_used)
            return Route("continue", path, best.key, f"{why}; continuing its recent session", resume_request=resume)
        return Route("new", path, None, f"{why}; new session there", resume_request=resume)

    matches = projects.match(text) if projects is not None else []
    if len(matches) == 1:
        return in_repo(matches[0].path, f"named {matches[0].name}")
    if len(matches) > 1:
        pick = max(matches, key=lambda p: p.last_used_at or 0)
        r = in_repo(pick.path, f"ambiguous ({', '.join(p.name for p in matches)}); most recently used")
        r.ambiguous = [p.path for p in matches]
        return r
    if active is not None and recent(active):
        return Route("continue", active.cwd, active.key, "used in the last 30 minutes", resume_request=resume)
    return Route("new", home, None, "nothing recent; new session at home", resume_request=resume)
