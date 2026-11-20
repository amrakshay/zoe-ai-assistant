"""Names for IDs on approval cards (#22 feedback): "Akshay R (URRN4FWQ2)" instead of a bare Slack ID.

Names are learned **only from connector results** (what Slack itself returned in this session), never from
Claude's own words, so a card can't be made to show a false name. Unknown IDs stay as IDs, labelled.
"""
from __future__ import annotations

import json
import re
from typing import Any

SLACK_ID = re.compile(r"^[UCDGW][A-Z0-9]{8,11}$")
_PAIR = re.compile(r"([A-Za-z][^\n()\[\]]{0,60}?)\s*\(([UCDGW][A-Z0-9]{8,11})\)")
_ID_FIRST = re.compile(r"\b([UCDGW][A-Z0-9]{8,11})\b\s*[:\-–]\s*([^\n,;]{1,60})")
KIND = {"U": "Slack user", "W": "Slack user", "C": "Slack channel", "G": "Slack private channel", "D": "Slack direct message"}


def _texts(resp: Any) -> list[str]:
    """Text blocks of an MCP result, with any JSON `{"result": "..."}` wrapper opened."""
    out: list[str] = []
    if isinstance(resp, str):
        out.append(resp)
    elif isinstance(resp, dict):
        if isinstance(resp.get("text"), str):
            out.append(resp["text"])
        else:
            out.append(json.dumps(resp))
    elif isinstance(resp, list):
        for x in resp:
            out += _texts(x)
    res = []
    for t in out:
        try:
            j = json.loads(t)
            if isinstance(j, dict) and isinstance(j.get("result"), str):
                res.append(j["result"])
                continue
        except (ValueError, TypeError):
            pass
        res.append(t)
    return res


class Names:
    def __init__(self) -> None:
        self.by_id: dict[str, str] = {}

    def learn(self, tool: str, tool_input: dict, resp: Any) -> None:
        if not tool.startswith("mcp__"):
            return
        texts = _texts(resp)
        joined = "\n".join(texts)
        # A profile read for a given user: its first line is "display name (real name)".
        uid = (tool_input or {}).get("user_id")
        if tool.endswith("read_user_profile") and isinstance(uid, str) and SLACK_ID.match(uid) and texts:
            first = texts[0].strip().splitlines()[0].strip() if texts[0].strip() else ""
            if first:
                self.by_id[uid] = first[:80]
        for name, i in _PAIR.findall(joined):
            self.by_id.setdefault(i, name.strip()[:80])
        for i, name in _ID_FIRST.findall(joined):
            self.by_id.setdefault(i, name.strip()[:80])

    def label(self, value: Any) -> str | None:
        """'Akshay R (URRN4FWQ2)', or 'URRN4FWQ2 (Slack user ID; name not looked up)', or None if not an ID."""
        if not isinstance(value, str) or not SLACK_ID.match(value):
            return None
        if value in self.by_id:
            return f"{self.by_id[value]} ({value})"
        return f"{value} ({KIND.get(value[0], 'Slack')} ID; name not looked up)"
