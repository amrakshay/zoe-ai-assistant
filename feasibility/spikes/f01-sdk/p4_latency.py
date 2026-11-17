"""Q4: latency, 3 runs (default) of 3 Haiku queries each.

usage: ./cleanenv.sh uv run python p4_latency.py [runs] [default|nohooks|isolated]
Per run:
  A. new client: connect() -> returns; query 1 -> init message; query 1 -> first streamed text
  B. same client, query 2 -> first streamed text
  C. disconnect; new client with resume=<session_id>: connect + query 3 -> first streamed text
Writes out/latency_<mode>.json.
"""
import asyncio
import json
import sys

from claude_agent_sdk import (
    AssistantMessage, ClaudeAgentOptions, ClaudeSDKClient, ResultMessage, StreamEvent, SystemMessage, TextBlock,
)

from common import HERE, MODEL, assert_no_api_key, dump, now, summary


def opts(mode, resume=None):
    # default  = all setting sources (user SessionStart hook runs on fresh sessions)
    # nohooks  = all setting sources, hooks disabled by a flag-level --settings override
    # isolated = setting_sources=[]
    extra = {"settings": json.dumps({"disableAllHooks": True})} if mode == "nohooks" else {}
    return ClaudeAgentOptions(model=MODEL, cwd=str(HERE), max_turns=1, include_partial_messages=True,
                              resume=resume, setting_sources=[] if mode == "isolated" else None, **extra)


async def turn(client, prompt):
    """Send prompt; return (t_init, t_first_text, t_result, session_id) relative to send."""
    t0 = now()
    await client.query(prompt)
    t_init = t_text = t_res = sid = None
    async for m in client.receive_response():
        t = now() - t0
        if isinstance(m, SystemMessage) and m.subtype == "init" and t_init is None:
            t_init = t
        elif isinstance(m, StreamEvent) and t_text is None:
            ev = m.event
            if ev.get("type") == "content_block_delta" and ev.get("delta", {}).get("type") == "text_delta":
                t_text = t
        elif isinstance(m, AssistantMessage) and t_text is None and any(isinstance(b, TextBlock) for b in m.content):
            t_text = t
        elif isinstance(m, ResultMessage):
            t_res, sid = t, m.session_id
    return t_init, t_text, t_res, sid


async def one_run(mode):
    r = {}
    c = ClaudeSDKClient(opts(mode))
    t0 = now()
    await c.connect()
    r["connect_call"] = now() - t0
    t_init, t_text, t_res, sid = await turn(c, "Reply with exactly: one")
    r["connect_to_init"] = r["connect_call"] + t_init
    r["q1_send_to_init"] = t_init
    r["q1_send_to_first_text"] = t_text
    r["q1_send_to_result"] = t_res
    _, t_text2, t_res2, _ = await turn(c, "Reply with exactly: two")
    r["q2_warm_send_to_first_text"] = t_text2
    r["q2_warm_send_to_result"] = t_res2
    await c.disconnect()

    c2 = ClaudeSDKClient(opts(mode, resume=sid))
    t0 = now()
    await c2.connect()
    t_conn = now() - t0
    _, t_text3, _, sid3 = await turn(c2, "Reply with exactly: three")
    r["resume_connect_call"] = t_conn
    r["resume_connect_to_first_text"] = t_conn + t_text3
    r["resume_same_session_id"] = sid3 == sid
    await c2.disconnect()
    return r


async def main(runs, mode):
    assert_no_api_key()
    rows = []
    for i in range(runs):
        r = await one_run(mode)
        rows.append(r)
        print(i, {k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})
    keys = [k for k in rows[0] if isinstance(rows[0][k], float)]
    agg = {k: summary([r[k] for r in rows]) for k in keys}
    print(dump(f"latency_{mode}.json", {"mode": mode, "runs": rows, "summary": agg}))
    for k, v in agg.items():
        print(f"{k:32s} median {v['median_s']:.3f}  range {v['min_s']:.3f}-{v['max_s']:.3f}")


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 3, sys.argv[2] if len(sys.argv) > 2 else "default"))
