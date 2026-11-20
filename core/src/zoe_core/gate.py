"""Interim approval gate for phase 1 (#2): read-only.

Every tool call goes through one catch-all PreToolUse hook (registered with on_failure="block", so a
hook error can never let a tool run). The decision is by **exact tool name**: an allowlist of read-only
tools runs; everything else is denied with a reason Claude can say out loud. The full gate with voice
and click approvals, taint and core-rendered cards is phase 2 (PLAN.md §7).
"""
from __future__ import annotations

import os
from dataclasses import dataclass

# Built-in tools that only read local files.
BUILTIN_READ = frozenset({"Read", "Grep", "Glob"})

# Connector tools that only read. Exact names, as reported by the session's init message.
CONNECTOR_READ = frozenset({
    "mcp__claude_ai_Google_Calendar__list_calendars",
    "mcp__claude_ai_Google_Calendar__list_events",
    "mcp__claude_ai_Google_Calendar__get_event",
    "mcp__claude_ai_Google_Calendar__search_events",
    "mcp__claude_ai_Google_Calendar__suggest_time",
})

DENY_REASON = (
    "Zoe can't use this tool yet: in this version only reading is allowed, and anything that changes, "
    "sends or runs something is blocked until approvals arrive. Tell the user briefly that you can't do "
    "that yet, and offer what you can do by reading instead."
)


@dataclass(frozen=True)
class Decision:
    allow: bool
    reason: str


def extra_allowed() -> frozenset[str]:
    """Extra exact tool names from ZOE_ALLOW_TOOLS (comma-separated), for trying other read-only tools."""
    raw = os.environ.get("ZOE_ALLOW_TOOLS", "")
    return frozenset(t.strip() for t in raw.split(",") if t.strip())


def decide(tool_name: str, allowed: frozenset[str] | None = None) -> Decision:
    allowed = (BUILTIN_READ | CONNECTOR_READ | extra_allowed()) if allowed is None else allowed
    if isinstance(tool_name, str) and tool_name in allowed:
        return Decision(True, "read-only tool on the allowlist")
    return Decision(False, DENY_REASON)


async def pre_tool_use(input_data: dict, tool_use_id: str | None, context) -> dict:
    """PreToolUse hook body: allow or deny by exact name. Never returns "ask" in phase 1."""
    d = decide(input_data.get("tool_name"))
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow" if d.allow else "deny",
            "permissionDecisionReason": d.reason,
        }
    }
