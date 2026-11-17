"""Q4 follow-up: is the ~11 s fresh connect the user's SessionStart(startup) hook?
Connect-only (no queries) with hooks disabled through a flag-level --settings override.
Nothing in ~/.claude is changed. usage: ./cleanenv.sh uv run python p4c_nohooks.py"""
import asyncio, json
from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient
from common import HERE, MODEL, assert_no_api_key, dump, now, summary

async def once(**kw):
    c = ClaudeSDKClient(ClaudeAgentOptions(model=MODEL, cwd=str(HERE), **kw))
    t0 = now(); await c.connect(); dt = now() - t0; await c.disconnect(); return dt

async def main():
    assert_no_api_key()
    xs = [await once(settings=json.dumps({"disableAllHooks": True})) for _ in range(3)]
    s = summary(xs); print("fresh_default_hooks_disabled", s)
    dump("connect_nohooks.json", {"fresh_default_hooks_disabled": s})

asyncio.run(main())
