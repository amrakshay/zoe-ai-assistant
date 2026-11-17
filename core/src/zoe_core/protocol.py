"""JSON-lines framing and message helpers for the app <-> core link.

One message per line: a JSON object with a string "type". Anything else is reported back as an
`error` message and otherwise ignored, so a bad line can never stop the loop.
"""
from __future__ import annotations

import json
from typing import Any

# Messages the app may send (PLAN.md §3). Phase 1 handles the first three; the rest are accepted and
# ignored until their features land, so the app can be ahead of the core without breaking the link.
APP_TO_CORE = {
    "hello", "ping", "utterance", "user_interrupted", "dropped", "context_snapshot", "answer",
    "open_session", "take_back", "cancel", "chat_message", "presence", "mute", "shutdown",
}

MAX_LINE = 1 << 20  # 1 MiB: anything longer is rejected rather than buffered without bound


class ProtocolError(ValueError):
    pass


def decode(line: str | bytes) -> dict[str, Any]:
    """Parse one line into a message dict. Raises ProtocolError on anything that isn't one."""
    if isinstance(line, bytes):
        if len(line) > MAX_LINE:
            raise ProtocolError("line too long")
        try:
            line = line.decode("utf-8")
        except UnicodeDecodeError as e:
            raise ProtocolError(f"not UTF-8: {e}") from None
    line = line.strip()
    if not line:
        raise ProtocolError("empty line")
    try:
        msg = json.loads(line)
    except json.JSONDecodeError as e:
        raise ProtocolError(f"invalid JSON: {e.msg}") from None
    if not isinstance(msg, dict) or not isinstance(msg.get("type"), str):
        raise ProtocolError("message must be an object with a string 'type'")
    return msg


def encode(type_: str, **fields: Any) -> bytes:
    """One message as a single UTF-8 line ending in \\n. Newlines inside strings are escaped by JSON."""
    return (json.dumps({"type": type_, **fields}, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
