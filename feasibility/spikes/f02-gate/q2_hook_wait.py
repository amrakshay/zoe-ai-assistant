"""Q2: can a PreToolUse hook await a long time (simulated user click) and then decide?

usage: uv run q2_hook_wait.py <sleep_s> <allow|deny|raise> [matcher_timeout_s|none] [continue|block] [allowed_tools]
can_use_tool logs and DENIES, so a created file means the hook's allow was honoured
without can_use_tool.
"""
import asyncio
import sys
import time

from claude_agent_sdk import HookMatcher, PermissionResultDeny

from common import REPO, log, options, run, short

sleep_s = float(sys.argv[1])
decision = sys.argv[2]
mt = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] != 'none' else None
on_failure = sys.argv[4] if len(sys.argv) > 4 else None
allow_rule = len(sys.argv) > 5 and sys.argv[5] == 'allowed_tools'
calls = {"hook": 0, "hook_returned": 0, "can_use_tool": 0}


async def can_use_tool(name, inp, ctx):
    calls["can_use_tool"] += 1
    log("CAN_USE_TOOL called:", name, short(inp))
    return PermissionResultDeny(message="denied by can_use_tool (test)")


async def pre_hook(inp, tool_use_id, ctx):
    calls["hook"] += 1
    t = time.monotonic()
    log(f"PRE_TOOL_USE hook start ({inp.get('tool_name')}), awaiting {sleep_s}s 'user click'")
    try:
        await asyncio.sleep(sleep_s)
    except BaseException as e:  # noqa: BLE001 - want to see cancellation
        log("hook sleep interrupted:", type(e).__name__, f"after {time.monotonic() - t:.1f}s")
        raise
    if decision == 'raise':
        log('PRE_TOOL_USE hook raising RuntimeError')
        raise RuntimeError('gate bug (simulated)')
    calls["hook_returned"] += 1
    log(f"PRE_TOOL_USE hook returning {decision} after {time.monotonic() - t:.1f}s")
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": f"user said {decision} (simulated)",
        }
    }


async def main():
    target = REPO / "hello.txt"
    target.unlink(missing_ok=True)
    hooks = {"PreToolUse": [HookMatcher(matcher="Bash", hooks=[pre_hook], timeout=mt, on_failure=on_failure)]}
    extra = {'allowed_tools': ['Bash(touch:*)']} if allow_rule else {}
    opts = options(can_use_tool=can_use_tool, hooks=hooks, max_turns=3, **extra)
    await run("Run exactly this shell command with the Bash tool: `touch hello.txt`. "
              "Do not retry or try alternatives. Then report whether it succeeded.", opts)
    log("sleep", sleep_s, "decision", decision, "matcher timeout", mt, "on_failure", on_failure, "allow rule", allow_rule, "calls", calls,
        "hello.txt exists:", target.exists())
    target.unlink(missing_ok=True)


asyncio.run(main())
