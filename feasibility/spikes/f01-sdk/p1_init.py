"""Q1 + Q2: auth source and what loads in an SDK session.

usage: ./cleanenv.sh uv run python p1_init.py {default|explicit|isolated}
  default  = setting_sources left as None (SDK docstring: all sources, like the CLI)
  explicit = setting_sources=["user","project","local"]
  isolated = setting_sources=[]
One short Haiku query per run. Writes out/init_<mode>.json.
"""
import asyncio
import sys

from claude_agent_sdk import (
    AssistantMessage, ClaudeAgentOptions, ClaudeSDKClient, ResultMessage, SystemMessage, TextBlock,
)

from common import HERE, MODEL, assert_no_api_key, dump, now

MODES = {"default": None, "explicit": ["user", "project", "local"], "isolated": []}


async def main(mode: str):
    assert_no_api_key()
    opts = ClaudeAgentOptions(model=MODEL, cwd=str(HERE), setting_sources=MODES[mode],
                              max_turns=1, permission_mode="default")
    client = ClaudeSDKClient(opts)
    t0 = now()
    await client.connect()
    t_conn = now() - t0
    init, pre_query_init, texts, result = None, False, [], None

    # Does init arrive before any query is sent?
    async def wait_init():
        async for m in client.receive_messages():
            if isinstance(m, SystemMessage) and m.subtype == "init":
                return m
    try:
        init = await asyncio.wait_for(wait_init(), timeout=8)
        pre_query_init = True
    except asyncio.TimeoutError:
        pass

    await client.query("Reply with exactly the word: ok")
    async for m in client.receive_response():
        if isinstance(m, SystemMessage) and m.subtype == "init" and init is None:
            init = m
        elif isinstance(m, AssistantMessage):
            texts += [b.text for b in m.content if isinstance(b, TextBlock)]
        elif isinstance(m, ResultMessage):
            result = m
    await client.disconnect()

    d = init.data if init else {}
    report = {
        "mode": mode,
        "setting_sources": MODES[mode],
        "connect_s": round(t_conn, 3),
        "init_before_query": pre_query_init,
        "apiKeySource": d.get("apiKeySource"),
        "model": d.get("model"),
        "claude_code_version": d.get("claude_code_version"),
        "permissionMode": d.get("permissionMode"),
        "mcp_servers": d.get("mcp_servers"),
        "plugins": d.get("plugins"),
        "skills": d.get("skills"),
        "slash_commands": d.get("slash_commands"),
        "agents": d.get("agents"),
        "tools": d.get("tools"),
        "init_keys": sorted(d.keys()),
        "reply": "".join(texts),
        "result": None if not result else {
            "is_error": result.is_error, "subtype": result.subtype,
            "total_cost_usd": result.total_cost_usd, "session_id": result.session_id,
            "duration_ms": result.duration_ms,
        },
    }
    p = dump(f"init_{mode}.json", report)
    print(f"wrote {p}")
    print({k: report[k] for k in ("apiKeySource", "model", "claude_code_version", "init_before_query", "reply")})
    print("result:", report["result"])
    print("counts:", {k: len(report[k] or []) for k in ("mcp_servers", "plugins", "skills", "slash_commands", "agents", "tools")})


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "default"))
