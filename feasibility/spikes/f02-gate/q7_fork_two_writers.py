"""Q7: fork_session, and two writers (SDK client + `claude -p --resume`) on one session.

usage: uv run q7_fork_two_writers.py
Transcripts under ~/.claude/projects/ are only READ (hashed, line-counted, parsed).
"""
import asyncio
import hashlib
import json
import os
import time
from pathlib import Path

from common import MODEL, REPO, log, options, run

PROJECTS = Path.home() / ".claude" / "projects"


def transcript(sid):
    hits = list(PROJECTS.glob(f"*/{sid}.jsonl"))
    return hits[0] if hits else None


def snap(sid):
    p = transcript(sid)
    if not p:
        return None
    b = p.read_bytes()
    return {"path": str(p), "lines": b.count(b"\n"), "sha": hashlib.sha256(b).hexdigest()[:16]}


def analyse(sid):
    """Parse every line; check JSON validity, sessionIds, and parentUuid branching."""
    p = transcript(sid)
    bad, entries = 0, []
    for ln in p.read_text().splitlines():
        try:
            entries.append(json.loads(ln))
        except json.JSONDecodeError:
            bad += 1
    sids = {e.get("sessionId") for e in entries if e.get("sessionId")}
    children = {}
    for e in entries:
        if e.get("uuid") and e.get("type") in ("user", "assistant"):
            children.setdefault(e.get("parentUuid"), []).append(e)
    branches = {k: v for k, v in children.items() if len(v) > 1}
    texts = []
    for e in entries:
        if e.get("type") in ("user", "assistant"):
            c = e.get("message", {}).get("content")
            t = c if isinstance(c, str) else " ".join(
                x.get("text", "") for x in (c or []) if isinstance(x, dict) and x.get("type") == "text")
            if t.strip():
                texts.append(f"{e['type']}: {t.strip()[:70]!r} (parent={str(e.get('parentUuid'))[:8]}, ts={e.get('timestamp')})")
    return {"lines": len(entries) + bad, "invalid_json_lines": bad, "sessionIds": sids,
            "parents_with_multiple_children": {str(k)[:8]: len(v) for k, v in branches.items()},
            "texts": texts}


async def cli_writer(sid):
    t = time.monotonic()
    proc = await asyncio.create_subprocess_exec(
        "claude", "-p", "--resume", sid, "--model", MODEL, "--setting-sources", "project",
        "--strict-mcp-config", "--tools", "", "--output-format", "json", "say hi",
        cwd=str(REPO), stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        env={**os.environ, "ENABLE_CLAUDEAI_MCP_SERVERS": "false"})
    out, err = await proc.communicate()
    try:
        j = json.loads(out)
        log(f"CLI writer done in {time.monotonic() - t:.1f}s rc={proc.returncode} session_id={j.get('session_id')} result={j.get('result')!r}")
        return j.get("session_id")
    except json.JSONDecodeError:
        log("CLI writer rc", proc.returncode, "stdout", out[:300], "stderr", err[:300])


async def main():
    # 1. original session
    a, _, _ = await run("Remember the word PINEAPPLE. Reply only: OK.", options(tools=[], max_turns=1))
    before = snap(a)
    log("ORIGINAL", a, before)

    # 2. fork
    b, res, _ = await run("What word did I ask you to remember? Also remember MANGO. Reply in one line.",
                          options(tools=[], max_turns=1, resume=a, fork_session=True))
    after = snap(a)
    log("FORK", b, "differs from original:", b != a, "fork transcript:", snap(b))
    log("original unchanged after fork:", before == after, after)

    # 3. two writers on the ORIGINAL session at nearly the same time
    pre = snap(a)
    sdk_task = run("say hello", options(tools=[], max_turns=1, resume=a))
    cli_task = cli_writer(a)
    (sdk_sid, sdk_res, _), cli_sid = await asyncio.gather(sdk_task, cli_task)
    log("TWO WRITERS: sdk session", sdk_sid, "cli session", cli_sid, "original", a)
    log("original before:", pre)
    log("original after :", snap(a))
    for sid in {a, sdk_sid, cli_sid} - {None}:
        r = analyse(sid)
        log(f"ANALYSIS {sid}: lines={r['lines']} invalid={r['invalid_json_lines']} sessionIds={r['sessionIds']} "
            f"branches={r['parents_with_multiple_children']}")
        for t in r["texts"]:
            print("    ", t)


asyncio.run(main())
