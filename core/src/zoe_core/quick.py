"""One-shot Haiku calls for small jobs: titles and summaries (#28) and the router (#27).

No tools, **no settings** (so none of my settings hooks run: a SessionStart hook made full sessions take ~11 s to
start; this takes ~2.5 s, measured), one turn, a JSON answer. Runs on my own login like everything else.
"""
from __future__ import annotations

import json
import os
import re
import time
from typing import Any

MODEL = os.environ.get("ZOE_QUICK_MODEL", "claude-haiku-5-5")


async def ask_json(system: str, prompt: str, timeout_s: float = 20.0) -> tuple[dict | None, float]:
    """Returns (parsed JSON object or None, seconds taken)."""
    import asyncio

    from claude_agent_sdk import AssistantMessage, ClaudeAgentOptions, TextBlock, query

    t0 = time.monotonic()
    opts = ClaudeAgentOptions(model=MODEL, tools=[], setting_sources=[], max_turns=1, system_prompt=system,
                              cwd=os.path.expanduser("~"))
    out = ""

    async def run() -> None:
        nonlocal out
        async for m in query(prompt=prompt, options=opts):
            if isinstance(m, AssistantMessage):
                out += "".join(b.text for b in m.content if isinstance(b, TextBlock))

    try:
        await asyncio.wait_for(run(), timeout_s)
    except Exception:  # noqa: BLE001 — a failed helper call must never break a turn
        return None, time.monotonic() - t0
    return parse_json(out), time.monotonic() - t0


def parse_json(text: str) -> dict | None:
    """The first JSON object in `text` (models sometimes wrap it in a code fence)."""
    m = re.search(r"\{.*\}", text or "", re.DOTALL)
    if not m:
        return None
    try:
        v: Any = json.loads(m.group(0))
    except ValueError:
        return None
    return v if isinstance(v, dict) else None
