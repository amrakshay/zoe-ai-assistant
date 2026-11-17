#!/usr/bin/env python3
"""Samples Zoe's resource use every N seconds (default 2) until stopped.

Per sample: CPU % (from CPU-time deltas, one core = 100 %), physical footprint (what Activity Monitor calls
Memory) and RSS for the app; CPU and RSS for the core; and the total for the core's descendants (Claude Code).
Usage: scripts/measure.py [interval]      (while Zoe is running; Ctrl-C to stop)
"""
import re
import subprocess
import sys
import time

INTERVAL = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0


def sh(*cmd: str) -> str:
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def cpu_seconds(pid: int) -> float:
    t = sh("ps", "-o", "time=", "-p", str(pid)).strip()       # [hh:]mm:ss.cc
    if not t:
        return 0.0
    parts = [float(x) for x in t.split(":")]
    return sum(p * 60 ** i for i, p in enumerate(reversed(parts)))


def rss_mb(pid: int) -> int:
    t = sh("ps", "-o", "rss=", "-p", str(pid)).strip()
    return int(t) // 1024 if t else 0


def footprint_mb(pid: int) -> float:
    m = re.search(r"Footprint:\s*([\d.]+)\s*(KB|MB|GB)", sh("footprint", "-p", str(pid)))
    if not m:
        return 0.0
    v, unit = float(m.group(1)), m.group(2)
    return v / 1024 if unit == "KB" else v * 1024 if unit == "GB" else v


def children(pid: int) -> list[int]:
    return [int(x) for x in sh("pgrep", "-P", str(pid)).split()]


def descendants(pid: int) -> list[int]:
    out = []
    for c in children(pid):
        out += [c] + descendants(c)
    return out


last: dict[int, float] = {}


def pct(pid: int) -> float:
    now = cpu_seconds(pid)
    prev = last.get(pid, now)
    last[pid] = now
    return (now - prev) / INTERVAL * 100


print("time      app%   appFP  appRSS | core%  coreRSS | claude%  claudeRSS (n)", flush=True)
while True:
    apps = [int(x) for x in sh("pgrep", "-x", "Zoe").split()]
    if not apps:
        print("Zoe not running", flush=True)
        time.sleep(INTERVAL)
        continue
    app = apps[0]
    kids = children(app)
    core = kids[0] if kids else None
    claude = descendants(core) if core else []
    line = f"{time.strftime('%H:%M:%S')}  {pct(app):5.1f}  {footprint_mb(app):6.0f}  {rss_mb(app):6d}"
    line += f" | {pct(core):5.1f}  {rss_mb(core):7d}" if core else " |     -        -"
    line += f" | {sum(pct(c) for c in claude):6.1f}  {sum(rss_mb(c) for c in claude):9d} ({len(claude)})"
    print(line, flush=True)
    time.sleep(INTERVAL)
