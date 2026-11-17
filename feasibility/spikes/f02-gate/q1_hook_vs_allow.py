"""Q1 + Q3: does a PreToolUse hook run before settings allow rules?

usage: uv run q1_hook_vs_allow.py {nohook|deny|ask} [project|flag|allowed_tools]
project = rely on repo/.claude/settings.json only (ignored if the workspace is untrusted)
flag = also pass the same file via --settings (ClaudeAgentOptions.settings)
allowed_tools = also pass allowed_tools=["Bash(touch:*)"]
repo/.claude/settings.json allows Bash(touch:*).
can_use_tool logs every call and DENIES, so a created file means it was never consulted.
"""
import asyncio
import sys

from claude_agent_sdk import HookMatcher, PermissionResultDeny

from common import REPO, log, options, run, short

mode = sys.argv[1]
src = sys.argv[2] if len(sys.argv) > 2 else "project"
calls = {"hook": 0, "can_use_tool": 0}


async def can_use_tool(name, inp, ctx):
    calls["can_use_tool"] += 1
    log("CAN_USE_TOOL called:", name, short(inp))
    return PermissionResultDeny(message="denied by can_use_tool (test)")


async def pre_hook(inp, tool_use_id, ctx):
    calls["hook"] += 1
    log("PRE_TOOL_USE hook:", inp.get("tool_name"), short(inp.get("tool_input")))
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": mode,
            "permissionDecisionReason": f"F02 test hook says {mode}",
        }
    }


async def main():
    target = REPO / "hello.txt"
    target.unlink(missing_ok=True)
    hooks = None if mode == "nohook" else {"PreToolUse": [HookMatcher(matcher=None, hooks=[pre_hook])]}
    extra = {}
    if src == "flag":
        extra["settings"] = str(REPO / ".claude" / "settings.json")
    elif src == "allowed_tools":
        extra["allowed_tools"] = ["Bash(touch:*)"]
    opts = options(can_use_tool=can_use_tool, hooks=hooks, max_turns=3, **extra)
    await run("Run exactly this shell command with the Bash tool: `touch hello.txt`. "
              "Do not retry or try alternatives. Then report whether it succeeded.", opts)
    log("MODE", mode, "allow source", src, "calls", calls, "hello.txt exists:", target.exists())
    target.unlink(missing_ok=True)


asyncio.run(main())
