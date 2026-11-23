#!/usr/bin/env python3
"""Samples Zoe's resource use every N seconds (default 2) until stopped.

Per sample: CPU % (from CPU-time deltas, one core = 100 %) and physical footprint (what Activity Monitor calls
Memory) for the app and for zoe-stt, the Whisper helper (#41), and **app + helper**, which is what the memory
budget counts (PLAN.md §12.2: the helper is part of Zoe, not memory moved off the books). Then CPU and RSS for
the core, and the total for the core's descendants (Claude Code). The helper runs only during a conversation
and for 2 minutes after it.

On Ctrl-C (or after --for SECONDS) it prints a summary: footprint mean and max for the app alone and for
app + helper, split by whether the helper was running.

Usage: scripts/measure.py [interval] [--for SECONDS] [--pid APP_PID]      (while Zoe is running; --pid picks
one when several processes are called Zoe, e.g. the installed app and a development build)
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time

args = sys.argv[1:]
DURATION = None
if "--for" in args:
    i = args.index("--for")
    DURATION = float(args[i + 1])
    del args[i:i + 2]
APP_PID = None
if "--pid" in args:
    i = args.index("--pid")
    APP_PID = int(args[i + 1])
    del args[i:i + 2]
INTERVAL = float(args[0]) if args else 2.0
HELPER = "zoe-stt"


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


def name(pid: int) -> str:
    return os.path.basename(sh("ps", "-o", "comm=", "-p", str(pid)).strip())


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


# (app footprint, helper footprint or None) per sample
samples: list[tuple[float, float | None]] = []


def stats(xs: list[float]) -> str:
    return f"mean {sum(xs) / len(xs):4.0f} MB, max {max(xs):4.0f} MB" if xs else "no samples"


def summary() -> None:
    idle = [a for a, h in samples if h is None]
    busy = [(a, h) for a, h in samples if h is not None]
    print(f"\n{len(samples)} samples, every {INTERVAL:g} s")
    print(f"  helper not running ({len(idle)}):  app {stats(idle)}  (= app + helper)")
    print(f"  helper running ({len(busy)}):      app {stats([a for a, _ in busy])};"
          f"  helper {stats([h for _, h in busy])};  app + helper {stats([a + h for a, h in busy])}")
    if samples:
        print(f"  peak: app {max(a for a, _ in samples):.0f} MB; app + helper {max(a + (h or 0) for a, h in samples):.0f} MB")


print("time      app%   appFP |  stt%   sttFP | app+stt | core%  coreRSS | claude%  claudeRSS (n)", flush=True)
start = time.time()
try:
    while DURATION is None or time.time() - start < DURATION:
        apps = [int(x) for x in sh("pgrep", "-x", "Zoe").split()]
        if APP_PID is not None:
            apps = [APP_PID] if APP_PID in apps else []
        if not apps:
            print("Zoe not running", flush=True)
            time.sleep(INTERVAL)
            continue
        app = apps[0]
        kids = children(app)
        helper = next((k for k in kids if name(k) == HELPER), None)
        core = next((k for k in kids if k != helper), None)
        claude = descendants(core) if core else []
        app_fp = footprint_mb(app)
        stt_fp = footprint_mb(helper) if helper else None
        samples.append((app_fp, stt_fp))
        line = f"{time.strftime('%H:%M:%S')}  {pct(app):5.1f}  {app_fp:6.0f}"
        line += f" | {pct(helper):5.1f}  {stt_fp:6.0f}" if helper else " |     -       -"
        line += f" | {app_fp + (stt_fp or 0):7.0f}"
        line += f" | {pct(core):5.1f}  {rss_mb(core):7d}" if core else " |     -        -"
        line += f" | {sum(pct(c) for c in claude):6.1f}  {sum(rss_mb(c) for c in claude):9d} ({len(claude)})"
        print(line, flush=True)
        time.sleep(INTERVAL)
except KeyboardInterrupt:
    pass
summary()
