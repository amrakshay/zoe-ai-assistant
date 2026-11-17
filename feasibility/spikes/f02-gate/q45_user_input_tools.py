"""Q4 (AskUserQuestion) and Q5 (ExitPlanMode).

usage:
  uv run q45_user_input_tools.py ask            # AskUserQuestion, answer via updated_input.answers
  uv run q45_user_input_tools.py plan allow     # plan mode, approve ExitPlanMode
  uv run q45_user_input_tools.py plan deny      # plan mode, reject ExitPlanMode with feedback
A PreToolUse hook (returns {} = no opinion) logs whether hooks also see these tools.
can_use_tool prints the full input and decides; any other tool is denied.
"""
import asyncio
import json
import sys

from claude_agent_sdk import HookMatcher, PermissionResultAllow, PermissionResultDeny

from common import log, options, run, short

mode = sys.argv[1]
plan_decision = sys.argv[2] if len(sys.argv) > 2 else None
seen = []


async def pre_hook(inp, tool_use_id, ctx):
    log("PRE_TOOL_USE hook saw:", inp.get("tool_name"), "permission_mode=", inp.get("permission_mode"))
    return {}


async def can_use_tool(name, inp, ctx):
    seen.append(name)
    log("CAN_USE_TOOL:", name)
    print(json.dumps(inp, indent=2), flush=True)
    if name == "AskUserQuestion":
        answers = {}
        for q in inp.get("questions", []):
            opts = q.get("options", [])
            pick = opts[1]["label"] if len(opts) > 1 else opts[0]["label"]
            answers[q["question"]] = pick
        log("answering with", answers)
        return PermissionResultAllow(updated_input={**inp, "answers": answers})
    if name == "ExitPlanMode":
        if plan_decision == "allow":
            return PermissionResultAllow()
        return PermissionResultDeny(message="Request changes: name the file greeting.txt instead.")
    return PermissionResultDeny(message=f"{name} denied by test harness")


async def main():
    hooks = {"PreToolUse": [HookMatcher(matcher=None, hooks=[pre_hook])]}
    if mode == "ask":
        opts = options(can_use_tool=can_use_tool, hooks=hooks, max_turns=4)
        prompt = ("Use the AskUserQuestion tool to ask me ONE multiple-choice question: "
                  "'Which colour should the button be?' with options Red, Green, Blue. "
                  "After I answer, reply with exactly: 'You chose <answer>.' Do nothing else.")
    else:
        opts = options(can_use_tool=can_use_tool, hooks=hooks, max_turns=4, permission_mode="plan")
        prompt = ("Plan how to create a file notes.txt containing the word hi in the current directory. "
                  "It is a one-step plan; present it for approval right away with ExitPlanMode. "
                  "If approved, do not execute it, just reply 'Plan approved.'. "
                  "If rejected, reply with the feedback you got and stop.")
    await run(prompt, opts)
    log("can_use_tool saw:", seen)


asyncio.run(main())
