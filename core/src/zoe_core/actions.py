"""Decision log (PLAN.md §7.8; issue #14): one JSON line per gate decision in
`~/Library/Application Support/Zoe/actions.jsonl` (`ZOE_DATA_DIR` overrides the folder).

Never the raw tool input: only its SHA-256, so the log can show *that* something ran without holding
message text, file contents or commands.
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path


_index = None


def use_index(index) -> None:
    """Log into the session index (#24) from now on, instead of actions.jsonl."""
    global _index
    _index = index


def data_dir() -> Path:
    d = os.environ.get("ZOE_DATA_DIR") or os.path.expanduser("~/Library/Application Support/Zoe")
    return Path(d)


def input_hash(tool_input: object) -> str:
    raw = json.dumps(tool_input, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(raw.encode()).hexdigest()


def log_decision(tool: str, tool_input: object, decision: str, via: str, reason: str = "",
                 session_id: str | None = None, tainted: bool = False) -> None:
    """`decision`: allow | deny | question. `via`: policy | click | voice | terminal | timeout | interrupt | …"""
    if _index is not None:
        try:
            _index.log_action(session_id, tool, input_hash(tool_input), decision, via, tainted, reason)
            return
        except Exception:  # noqa: BLE001 — fall back to the file rather than lose the record
            pass
    rec = {"ts": round(time.time(), 3), "session": session_id, "tool": tool, "input_sha256": input_hash(tool_input),
           "decision": decision, "via": via, "reason": reason}
    try:
        d = data_dir()
        d.mkdir(parents=True, exist_ok=True)
        with open(d / "actions.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass   # the log must never decide anything; a full disk shouldn't block a deny
