"""Q6: do interactive commands fail fast under the SDK's Bash tool? Is stdin closed / TTY absent?

usage: uv run q6_interactive.py [probe]   (probe = run only the TTY probe command)
The hook allows only the exact commands listed below (everything else denied), and timestamps
PreToolUse and PostToolUse/PostToolUseFailure per tool_use_id.
example.invalid is a reserved TLD (RFC 6761): it never resolves, so no real host is contacted.
"""
import asyncio
import sys
import time

from claude_agent_sdk import HookMatcher

from common import log, options, run, short

CMDS = [
    "test -t 0; echo stdin_tty=$?; test -t 1; echo stdout_tty=$?; tty; ls -l /dev/fd/0; "
    "python3 -c \"import sys; print('stdin read ->', repr(sys.stdin.read()))\"; "
    "(exec 3</dev/tty) 2>&1 && echo dev_tty=openable || echo dev_tty=unavailable",
    "python3 -c \"input('pw: ')\"",
    "python3 -c \"import getpass; getpass.getpass('pw: ')\"",
    "ssh -o BatchMode=no git@example.invalid",
]
if len(sys.argv) > 1 and sys.argv[1] == "probe":
    CMDS = CMDS[:1]
starts = {}


async def pre(inp, tid, ctx):
    cmd = inp.get("tool_input", {}).get("command", "")
    ok = cmd in CMDS
    starts[tid] = time.monotonic()
    log("PRE", "allow" if ok else "deny", short(cmd, 120))
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "allow" if ok else "deny",
                                   "permissionDecisionReason": "not in F02 list" if not ok else "F02 list"}}


async def post(inp, tid, ctx):
    dt = time.monotonic() - starts.get(tid, time.monotonic())
    out = inp.get("tool_response") or inp.get("error")
    log(f"{inp.get('hook_event_name')} after {dt:.2f}s:", short(out, 600))
    return {}


async def main():
    hooks = {
        "PreToolUse": [HookMatcher(matcher="Bash", hooks=[pre])],
        "PostToolUse": [HookMatcher(matcher="Bash", hooks=[post])],
        "PostToolUseFailure": [HookMatcher(matcher="Bash", hooks=[post])],
    }
    opts = options(hooks=hooks, max_turns=8, tools=["Bash"])
    listing = "\n".join(f"{i + 1}. {c}" for i, c in enumerate(CMDS))
    prompt = ("Run each of these shell commands with the Bash tool, one Bash call per command, "
              "in order, exactly as written (no changes, no timeout parameter, no background). "
              "Do not retry. After all of them, give a one-line result per command.\n" + listing)
    await run(prompt, opts)


asyncio.run(main())
