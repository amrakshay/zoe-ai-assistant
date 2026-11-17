"""Q4 follow-up: why does a fresh connect() take ~11 s but a resume connect() ~0.4 s?
No queries are sent (zero model usage): only connect() then disconnect().

usage: ./cleanenv.sh uv run python p4b_connect.py <resume_session_id>
"""
import asyncio
import sys

from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient

from common import HERE, MODEL, assert_no_api_key, dump, now, summary

VARIANTS = {
    "fresh_default": dict(setting_sources=None),
    "fresh_isolated": dict(setting_sources=[]),
    "fresh_default_no_mcp_strict": dict(setting_sources=None, extra_args={"strict-mcp-config": None}),
    "resume_default": dict(setting_sources=None, resume="SID"),
}


async def connect_once(kw):
    c = ClaudeSDKClient(ClaudeAgentOptions(model=MODEL, cwd=str(HERE), **kw))
    t0 = now()
    await c.connect()
    dt = now() - t0
    await c.disconnect()
    return dt


async def main(sid):
    assert_no_api_key()
    out = {}
    for name, kw in VARIANTS.items():
        kw = {k: (sid if v == "SID" else v) for k, v in kw.items()}
        xs = [await connect_once(kw) for _ in range(3)]
        out[name] = summary(xs)
        print(name, out[name])
    print(dump("connect_only.json", out))


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1]))
