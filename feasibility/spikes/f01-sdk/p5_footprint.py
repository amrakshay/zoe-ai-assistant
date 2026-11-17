"""Q5: resident memory and idle CPU.

usage: ./cleanenv.sh uv run python p5_footprint.py [idle_seconds=30] [default|isolated]
 (default = all setting sources, hooks off; isolated = setting_sources=[])
 1. RSS of this Python process before and after importing claude_agent_sdk (idle).
 2. Connect (all setting sources, hooks disabled), run ONE Haiku turn, then sample the whole
    process tree every second for idle_seconds: RSS and cumulative CPU time per process.
Writes out/footprint.json.
"""
import asyncio
import json
import os
import subprocess
import sys
import time


def ps_all():
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,rss=,time=,command="], capture_output=True, text=True).stdout
    rows = {}
    for line in out.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5:
            continue
        pid, ppid, rss, cpu, cmd = parts
        rows[int(pid)] = {"ppid": int(ppid), "rss_kb": int(rss), "cpu": cpu, "cmd": cmd}
    return rows


def cpu_s(t):  # ps TIME like "0:01.23" or "1:02:03.45"
    parts = [float(x) for x in t.split(":")]
    s = 0.0
    for p in parts:
        s = s * 60 + p
    return s


def tree(root):
    rows = ps_all()
    keep, frontier = {root: 0}, [root]
    while frontier:
        p = frontier.pop()
        for pid, r in rows.items():
            if r["ppid"] == p and pid not in keep:
                keep[pid] = keep[p] + 1
                frontier.append(pid)
    return {pid: dict(rows[pid], depth=d) for pid, d in keep.items() if pid in rows}


def short(cmd):
    cmd = cmd.replace(os.path.expanduser("~"), "~")
    return cmd if len(cmd) < 110 else cmd[:107] + "..."


me = os.getpid()
rss_bare = ps_all()[me]["rss_kb"]
t0 = time.perf_counter()
import claude_agent_sdk  # noqa: E402
from claude_agent_sdk import AssistantMessage, ClaudeAgentOptions, ClaudeSDKClient, ResultMessage  # noqa: E402
import_s = time.perf_counter() - t0
time.sleep(3)
rss_sdk = ps_all()[me]["rss_kb"]

sys.path.insert(0, os.path.dirname(__file__))
from common import HERE, MODEL, assert_no_api_key, dump  # noqa: E402


async def main(idle, mode):
    assert_no_api_key()
    opts = ClaudeAgentOptions(model=MODEL, cwd=str(HERE), max_turns=1,
                              setting_sources=[] if mode == "isolated" else None,
                              settings=json.dumps({"disableAllHooks": True}))
    async with ClaudeSDKClient(opts) as c:
        await c.query("Reply with exactly: ok")
        async for m in c.receive_response():
            if isinstance(m, ResultMessage):
                res = {"is_error": m.is_error, "cost": m.total_cost_usd}
        await asyncio.sleep(2)
        first = tree(me)
        samples = []
        for _ in range(idle):
            await asyncio.sleep(1)
            samples.append(tree(me))
        last = samples[-1]
    procs = []
    for pid, r in first.items():
        if r["cmd"].startswith("ps "):
            continue  # our own sampler
        rss_series = [s[pid]["rss_kb"] for s in samples if pid in s]
        cpu_delta = cpu_s(last[pid]["cpu"]) - cpu_s(r["cpu"]) if pid in last else None
        procs.append({
            "pid": pid, "depth": r["depth"], "cmd": short(r["cmd"]),
            "rss_mb_start": round(r["rss_kb"] / 1024, 1),
            "rss_mb_end": round(rss_series[-1] / 1024, 1) if rss_series else None,
            "cpu_s_over_window": round(cpu_delta, 3) if cpu_delta is not None else None,
            "cpu_pct_avg": round(100 * cpu_delta / idle, 2) if cpu_delta is not None else None,
        })
    procs.sort(key=lambda p: (p["depth"], p["pid"]))
    total_children = sum(p["rss_mb_end"] or 0 for p in procs if p["depth"] > 0)
    report = {
        "python_rss_mb_bare": round(rss_bare / 1024, 1),
        "python_rss_mb_sdk_imported_idle": round(rss_sdk / 1024, 1),
        "sdk_import_s": round(import_s, 3),
        "mode": mode, "turn": res, "idle_window_s": idle,
        "process_tree": procs,
        "children_rss_mb_total": round(total_children, 1),
    }
    print(dump(f"footprint_{mode}.json", report))
    print({k: v for k, v in report.items() if k != "process_tree"})
    for p in procs:
        print(f"{'  ' * p['depth']}{p['pid']:>6} rss {p['rss_mb_end']!s:>7} MB  cpu {p['cpu_pct_avg']!s:>5}%  {p['cmd']}")


asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 30, sys.argv[2] if len(sys.argv) > 2 else "default"))
