"""Approvals through pending_input (PLAN.md §5.9, §7; issue #15).

The gate's hook calls `Approvals.ask`, which sends the app a `pending_input` card and waits for the app's
`answer`. Anything other than an explicit approval is a deny:
- a timeout (default 120 s, `ZOE_APPROVAL_TIMEOUT`),
- an interrupt (I talked over Zoe or ended the conversation),
- the core going away (the app denies everything pending when the core restarts, CoreLink).

The SDK calls hooks from its own task, not the turn's, so cancelling a turn doesn't release a waiting hook;
`cancel_all` does.
"""
from __future__ import annotations

import asyncio
import os
import uuid
from typing import Any, Awaitable, Callable

from .gate import Answer, ApprovalRequest
from .policy import Policy

Send = Callable[..., Awaitable[None]]
Render = Callable[[ApprovalRequest], dict]

VALID_VIA = {"click", "voice", "text"}


def default_timeout() -> float:
    try:
        return float(os.environ.get("ZOE_APPROVAL_TIMEOUT", "120"))
    except ValueError:
        return 120.0


def basic_card(req: ApprovalRequest) -> dict:
    """Fallback card: the tool name and its raw input. Replaced by the per-tool renderers (#16)."""
    import json
    raw = json.dumps(req.tool_input, indent=2, ensure_ascii=False, default=str)
    if len(raw) > 2000:
        raw = raw[:2000] + f"\n… ({len(raw) - 2000} more characters)"
    return {"title": f"Allow {req.tool_name}?", "fields": [{"label": "Input", "value": raw, "mono": True}],
            "summary": f"Zoe wants to use {req.tool_name}.", "why": req.reason}


class Approvals:
    def __init__(self, send: Send, render: Render = basic_card, timeout: float | None = None,
                 session_id: Callable[[], str | None] | None = None):
        self.send = send
        self.render = render
        self.timeout = default_timeout() if timeout is None else timeout
        self._session = session_id or (lambda: None)
        self._pending: dict[str, asyncio.Future] = {}

    @property
    def waiting(self) -> int:
        return len(self._pending)

    async def ask(self, req: ApprovalRequest) -> Answer:
        pid = f"ap-{uuid.uuid4().hex[:12]}"
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending[pid] = fut
        card = self.render(req)
        await self.send("pending_input", id=pid, session_id=self._session(), kind="approval", card=card,
                        voice_ok=req.policy is Policy.ASK, tool=req.tool_name, timeout_s=self.timeout)
        try:
            value, via = await asyncio.wait_for(fut, self.timeout)
        except asyncio.TimeoutError:
            value, via = "deny", "timeout"
        except asyncio.CancelledError:
            value, via = "deny", "interrupt"
        finally:
            self._pending.pop(pid, None)
        if via in ("timeout", "interrupt"):
            await self.send("dismiss_panel", id=pid, reason=via)
        return Answer(value == "approve", via)

    def answer(self, msg: dict[str, Any]) -> bool:
        """Apply an `answer {pending_id, value: approve|deny, via}` from the app. False if it matched nothing."""
        fut = self._pending.get(msg.get("pending_id"))
        if fut is None or fut.done():
            return False
        value = msg.get("value")
        via = msg.get("via") if msg.get("via") in VALID_VIA else "click"
        fut.set_result(("approve" if value == "approve" else "deny", via))
        return True

    def cancel_all(self, via: str = "interrupt") -> int:
        n = 0
        for fut in list(self._pending.values()):
            if not fut.done():
                fut.set_result(("deny", via))
                n += 1
        return n
