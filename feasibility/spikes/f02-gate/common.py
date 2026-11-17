"""Shared helpers for F02 spikes. Every run logs timestamped events to stdout."""
import json
import os
import time
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ClaudeSDKClient,
    ResultMessage,
    SystemMessage,
    TextBlock,
    ToolResultBlock,
    ToolUseBlock,
    UserMessage,
)

HERE = Path(__file__).parent
REPO = HERE / "repo"
MODEL = "claude-haiku-5-5"
T0 = time.monotonic()


def log(*a):
    print(f"[{time.monotonic() - T0:7.2f}s]", *a, flush=True)


def short(x, n=400):
    s = x if isinstance(x, str) else json.dumps(x, default=str)
    return s if len(s) <= n else s[:n] + "…"


def options(**kw):
    """Locked-down options: project settings only, no MCP servers, no plugins."""
    base = dict(
        model=MODEL,
        cwd=str(REPO),
        setting_sources=["project"],
        mcp_servers={},
        strict_mcp_config=True,
        plugins=[],
        tools=["Bash", "Read", "AskUserQuestion", "ExitPlanMode", "Write"],
        max_turns=6,
        env={"ENABLE_CLAUDEAI_MCP_SERVERS": "false"},
    )
    base.update(kw)
    return ClaudeAgentOptions(**base)


async def run(prompt, opts, client=None):
    """Run one prompt; return (session_id, result_text, tool_results)."""
    sid = None
    result = None
    tool_results = []
    own = client is None
    if own:
        client = ClaudeSDKClient(options=opts)
        await client.connect()
    try:
        log("PROMPT:", short(prompt))
        await client.query(prompt)
        async for m in client.receive_response():
            if isinstance(m, SystemMessage) and m.subtype == "init":
                d = m.data
                log("INIT session", d.get("session_id"), "mcp_servers=", d.get("mcp_servers"),
                    "plugins=", d.get("plugins"), "tools=", d.get("tools"),
                    "permissionMode=", d.get("permissionMode"))
            elif isinstance(m, AssistantMessage):
                for b in m.content:
                    if isinstance(b, TextBlock):
                        log("ASSISTANT:", short(b.text))
                    elif isinstance(b, ToolUseBlock):
                        log("TOOL_USE:", b.name, short(b.input))
            elif isinstance(m, UserMessage) and isinstance(m.content, list):
                for b in m.content:
                    if isinstance(b, ToolResultBlock):
                        tool_results.append(b)
                        log("TOOL_RESULT is_error=", b.is_error, short(b.content))
            elif isinstance(m, ResultMessage):
                sid = m.session_id
                result = m.result
                log("RESULT", m.subtype, "session", sid, "turns", m.num_turns,
                    "cost", m.total_cost_usd, "dur_ms", m.duration_ms)
    finally:
        if own:
            await client.disconnect()
    return sid, result, tool_results
