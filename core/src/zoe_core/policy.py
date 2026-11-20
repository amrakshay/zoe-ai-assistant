"""The approval gate's policy table (PLAN.md §4, §7; issue #14).

Every tool call gets one of four policies:
- ALLOW: runs without asking.
- ASK:   needs my answer, by voice or click.
- CLICK: needs a click; a spoken "yes" isn't accepted.
- DENY:  never runs.

Rules that must not regress (CLAUDE.md):
- **Exact tool names only grant ALLOW.** Name patterns may only make a decision *stricter* (e.g. anything
  named like a delete needs a click); they never loosen one, so a tool called `get_and_send` isn't a read.
- Unknown tools ASK.
- Protected paths (keys, credentials, keychains) are DENY for every file tool, whatever the table says.
"""
from __future__ import annotations

import enum
import os
import re
from dataclasses import dataclass


class Policy(enum.Enum):
    ALLOW = "allow"
    ASK = "ask"
    CLICK = "click"
    DENY = "deny"


@dataclass(frozen=True)
class Decision:
    policy: Policy
    reason: str

    @property
    def allow(self) -> bool:
        return self.policy is Policy.ALLOW


# --- built-in Claude Code tools -------------------------------------------------------------------------

BUILTIN_READ = frozenset({"Read", "Grep", "Glob"})
BUILTIN_WEB = frozenset({"WebFetch", "WebSearch"})        # allow; ask when the turn is tainted (#18)
BUILTIN_EDIT = frozenset({"Edit", "Write", "NotebookEdit"})
# Harmless session plumbing: planning notes, loading deferred tool schemas, and Claude asking me a question
# (answered through can_use_tool, #19).
BUILTIN_PLUMBING = frozenset({"TodoWrite", "ToolSearch"})

#: The built-ins the session may use at all (ClaudeAgentOptions.tools). Anything else isn't loaded.
#: AskUserQuestion's answers are filled in by can_use_tool; the gate gives it no decision (#19).
ENABLED_BUILTINS = BUILTIN_READ | BUILTIN_WEB | BUILTIN_EDIT | BUILTIN_PLUMBING | {"Bash", "AskUserQuestion"}

# --- connector tools (claude.ai connectors, exact names) --------------------------------------------------

CONNECTOR_READ = frozenset({
    "mcp__claude_ai_Google_Calendar__list_calendars",
    "mcp__claude_ai_Google_Calendar__list_events",
    "mcp__claude_ai_Google_Calendar__get_event",
    "mcp__claude_ai_Google_Calendar__search_events",
    "mcp__claude_ai_Google_Calendar__suggest_time",
    # Slack reads (names seen in a live session, 2026-11-20). Sends, posts and schedules stay ask.
    "mcp__claude_ai_Slack__slack_read_user_profile",
    "mcp__claude_ai_Slack__slack_search_users",
    "mcp__claude_ai_Slack__slack_search_channels",
    "mcp__claude_ai_Slack__slack_read_channel",
    "mcp__claude_ai_Slack__slack_read_thread",
    "mcp__claude_ai_Slack__slack_search_public",
    "mcp__claude_ai_Slack__slack_search_public_and_private",
    "mcp__claude_ai_Slack__slack_list_channel_members",
    "mcp__claude_ai_Slack__slack_list_user_channels",
    "mcp__claude_ai_Slack__slack_get_reactions",
    "mcp__claude_ai_Slack__slack_read_canvas",
})

# Explicit CLICK entries beyond the delete-like names (PLAN.md §7.7: Bash, deletes, jobs, screenshots).
CLICK_ONLY = frozenset({"Bash"})

# Names that look destructive need a click even if a table would say ASK. Stricter only, never looser.
_DESTRUCTIVE = re.compile(r"(^|[_\-.])(delete|remove|trash|purge|destroy|drop|wipe|erase)", re.IGNORECASE)

# --- protected paths -------------------------------------------------------------------------------------

_HOME = os.path.expanduser("~")
PROTECTED_DIRS = tuple(os.path.join(_HOME, p) for p in (
    ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".docker", ".config/gh", ".config/gcloud",
    "Library/Keychains", "Library/Cookies",
))
PROTECTED_FILES = tuple(os.path.join(_HOME, p) for p in (".netrc", ".git-credentials", ".npmrc", ".pypirc"))
_PROTECTED_NAME = re.compile(
    r"(^|/)(\.env(\.[^/]+)?|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?|[^/]+\.(pem|p12|pfx|key)|credentials(\.json)?|\.credentials\.json)$")

# Tool input fields that name a file or folder.
PATH_FIELDS = ("file_path", "path", "notebook_path")

#: Extra exact names to ALLOW, from ZOE_ALLOW_TOOLS (comma-separated), for trying other read-only tools.
def extra_allowed() -> frozenset[str]:
    raw = os.environ.get("ZOE_ALLOW_TOOLS", "")
    return frozenset(t.strip() for t in raw.split(",") if t.strip())


def _real(p: str) -> str:
    return os.path.realpath(os.path.expanduser(p))


def protected_path(p: str) -> bool:
    """True if `p` is, or is inside, a place that holds keys or credentials."""
    if not isinstance(p, str) or not p:
        return False
    rp = _real(p)
    if any(rp == d or rp.startswith(d + os.sep) for d in map(_real, PROTECTED_DIRS)):
        return True
    if rp in map(_real, PROTECTED_FILES):
        return True
    return bool(_PROTECTED_NAME.search(rp))


def paths_in(tool_input: dict) -> list[str]:
    return [v for k in PATH_FIELDS if isinstance(v := (tool_input or {}).get(k), str)]


# Zoe's own in-process tools (they only display things): allowed by exact name.
from .ui import EXACT_NAMES as UI_TOOLS  # noqa: E402


def decide(tool_name: object, tool_input: dict | None = None) -> Decision:
    """The policy for one call. Pure: no taint (#18) and no I/O here."""
    if not isinstance(tool_name, str) or not tool_name:
        return Decision(Policy.DENY, "no tool name")
    tool_input = tool_input if isinstance(tool_input, dict) else {}

    for p in paths_in(tool_input):
        if protected_path(p):
            return Decision(Policy.DENY, f"{p} holds keys or credentials; Zoe never touches it")

    if tool_name in BUILTIN_READ or tool_name in CONNECTOR_READ or tool_name in extra_allowed():
        return Decision(Policy.ALLOW, "read-only tool")
    if tool_name in BUILTIN_WEB:
        return Decision(Policy.ALLOW, "web read")
    if tool_name in BUILTIN_PLUMBING:
        return Decision(Policy.ALLOW, "session plumbing")
    if tool_name in UI_TOOLS:
        return Decision(Policy.ALLOW, "draws a panel")
    if tool_name in CLICK_ONLY or _DESTRUCTIVE.search(tool_name.split("__")[-1]):
        return Decision(Policy.CLICK, "runs a command or deletes something: needs a click")
    if tool_name in BUILTIN_EDIT:
        return Decision(Policy.ASK, "changes a file")
    if tool_name == "ExitPlanMode":
        return Decision(Policy.DENY, "Zoe doesn't use plan mode")
    return Decision(Policy.ASK, "not on the allowlist: needs approval")
