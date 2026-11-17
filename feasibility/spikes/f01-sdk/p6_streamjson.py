"""Q6: fallback - long-lived `claude -p --input-format stream-json` process.

usage: ./cleanenv.sh uv run python p6_streamjson.py
 1. spawn claude -p (stream-json in/out, Haiku, hooks disabled by flag), two turns over stdin
 2. take session_id from the output, close stdin, wait for exit
 3. spawn claude -p --resume <id> and send one turn; check it remembers turn 1
Three Haiku queries. Writes out/streamjson.json (incl. the CLI's own init lists, for Q2).
"""
import json
import os
import select
import subprocess
import time

from common import HERE, MODEL, assert_no_api_key, dump, now

BASE = ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--model", MODEL, "--settings", json.dumps({"disableAllHooks": True})]


def send(p, text):
    p.stdin.write((json.dumps({"type": "user", "message": {"role": "user", "content": text}}) + "\n").encode())
    p.stdin.flush()


def read_until(p, pred, timeout=60):
    """Read JSON lines until pred(msg) is true; return (msg, seconds, all msgs)."""
    t0, seen = now(), []
    buf = b""
    fd = p.stdout.fileno()
    while now() - t0 < timeout:
        r, _, _ = select.select([fd], [], [], 0.05)
        if not r:
            if p.poll() is not None:
                break
            continue
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if not line.strip():
                continue
            m = json.loads(line)
            seen.append(m)
            if pred(m):
                return m, now() - t0, seen
    return None, now() - t0, seen


def is_init(m):
    return m.get("type") == "system" and m.get("subtype") == "init"


def is_text(m):
    return m.get("type") == "assistant" and any(b.get("type") == "text" for b in m["message"]["content"])


def text_of(msgs):
    return "".join(b["text"] for m in msgs if m.get("type") == "assistant"
                   for b in m["message"]["content"] if b.get("type") == "text")


def spawn(extra=()):
    return subprocess.Popen(BASE + list(extra), cwd=HERE, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=False, bufsize=0)


def main():
    assert_no_api_key()
    rep = {}
    t0 = now()
    p = spawn()
    # does init arrive before the first input?
    m, dt, _ = read_until(p, is_init, timeout=6)
    rep["init_before_first_input"] = m is not None
    send(p, "Remember the code word PELICAN. Reply with exactly: noted")
    t_send = now()
    init = m
    if init is None:
        init, _, _ = read_until(p, is_init, timeout=30)
    rep["spawn_to_init_s"] = round(now() - t0, 3) if not rep["init_before_first_input"] else round(dt, 3)
    first1, _, pre1 = read_until(p, is_text)
    rep["turn1_send_to_first_text_s"] = round(now() - t_send, 3)
    _, _, msgs1 = read_until(p, lambda x: x.get("type") == "result")
    msgs1 = pre1 + msgs1
    rep["turn1_send_to_result_s"] = round(now() - t_send, 3)
    rep["turn1_reply"] = text_of(msgs1)
    sid = next((x.get("session_id") for x in msgs1 if x.get("session_id")), init.get("session_id") if init else None)
    rep["session_id"] = sid
    rep["spawn_to_turn1_result_s"] = round(now() - t0, 3)

    t2 = now()
    send(p, "Reply with exactly: two")
    first, tf, _ = read_until(p, is_text)
    res2, _, msgs2 = read_until(p, lambda x: x.get("type") == "result")
    rep["turn2_send_to_first_text_s"] = round(tf, 3)
    rep["turn2_send_to_result_s"] = round(now() - t2, 3)
    rep["turn2_reply"] = text_of([first] if first else []) + text_of(msgs2)
    rep["same_process_session_id_stable"] = (res2 or {}).get("session_id") == sid
    p.stdin.close()
    rep["exit_code"] = p.wait(timeout=30)

    # resume later in a fresh process
    t3 = now()
    q = spawn(["--resume", sid])
    send(q, "What was the code word? Reply with the word only.")
    first3, tf3, _ = read_until(q, is_text)
    res3, _, msgs3 = read_until(q, lambda x: x.get("type") == "result")
    rep["resume_spawn_to_first_text_s"] = round(tf3, 3)
    rep["resume_reply"] = text_of([first3] if first3 else []) + text_of(msgs3)
    rep["resume_session_id"] = (res3 or {}).get("session_id")
    q.stdin.close()
    rep["resume_exit_code"] = q.wait(timeout=30)
    rep["stderr_tail"] = (q.stderr.read() or b"")[-500:].decode(errors="replace")

    rep["cli_init"] = {k: init.get(k) for k in ("apiKeySource", "model", "claude_code_version")} if init else None
    if init:
        rep["cli_init_lists"] = {
            "mcp_servers": [(s["name"], s.get("status")) for s in init.get("mcp_servers", [])],
            "plugins": [x["name"] for x in init.get("plugins", [])],
            "skills": init.get("skills"), "agents": init.get("agents"),
            "slash_commands_n": len(init.get("slash_commands", [])), "tools_n": len(init.get("tools", [])),
            "tools": init.get("tools"),
        }
    print(dump("streamjson.json", rep))
    for k, v in rep.items():
        if k not in ("cli_init_lists",):
            print(f"{k}: {v}")


if __name__ == "__main__":
    main()
