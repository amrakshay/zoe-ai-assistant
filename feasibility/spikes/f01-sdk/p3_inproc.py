"""Q3: an in-process SDK MCP server alongside the user's other MCP servers.

usage: ./cleanenv.sh uv run python p3_inproc.py
One Haiku query that must call mcp__va__echo once. Writes out/inproc.json.
"""
import asyncio

from claude_agent_sdk import (
    AssistantMessage, ClaudeAgentOptions, ClaudeSDKClient, ResultMessage, SystemMessage,
    TextBlock, ToolResultBlock, ToolUseBlock, UserMessage, create_sdk_mcp_server, tool,
)

from common import HERE, MODEL, assert_no_api_key, dump

CALLS = []


@tool("echo", "Echo the given text back unchanged.", {"text": str})
async def echo(args):
    CALLS.append(args)  # proves the handler ran inside this Python process
    return {"content": [{"type": "text", "text": f"echo: {args['text']}"}]}


async def main():
    assert_no_api_key()
    server = create_sdk_mcp_server(name="va", version="0.0.1", tools=[echo])
    opts = ClaudeAgentOptions(
        model=MODEL, cwd=str(HERE), max_turns=3,
        mcp_servers={"va": server},
        allowed_tools=["mcp__va__echo"],  # only our tool is pre-approved
    )
    events, init = [], None
    async with ClaudeSDKClient(opts) as client:
        await client.query("Call the mcp__va__echo tool once with text 'ping-123', then reply with its output only.")
        async for m in client.receive_response():
            if isinstance(m, SystemMessage) and m.subtype == "init":
                init = m.data
            elif isinstance(m, AssistantMessage):
                for b in m.content:
                    if isinstance(b, ToolUseBlock):
                        events.append({"tool_use": b.name, "input": b.input})
                    elif isinstance(b, TextBlock):
                        events.append({"text": b.text})
            elif isinstance(m, UserMessage) and isinstance(m.content, list):
                for b in m.content:
                    if isinstance(b, ToolResultBlock):
                        events.append({"tool_result": b.content, "is_error": b.is_error})
            elif isinstance(m, ResultMessage):
                events.append({"result": m.subtype, "is_error": m.is_error, "cost": m.total_cost_usd})
    servers = [(s["name"], s.get("status")) for s in init["mcp_servers"]]
    report = {
        "va_status": [s for s in servers if s[0] == "va"],
        "mcp_server_count": len(servers),
        "connected_others": [n for n, st in servers if st == "connected" and n != "va"],
        "va_tools_in_init": [t for t in init["tools"] if "va" in t.split("__")[1:2]],
        "handler_calls": CALLS,
        "events": events,
    }
    print(dump("inproc.json", report))
    for k, v in report.items():
        print(k, "=", v)


if __name__ == "__main__":
    asyncio.run(main())
