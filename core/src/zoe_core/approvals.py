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
        self.question_timeout = max(self.timeout, 300.0)   # questions take longer to answer than yes/no

    @property
    def waiting(self) -> int:
        return len(self._pending)

    async def _wait(self, prefix: str, timeout: float, **fields: Any) -> tuple[Any, str]:
        """Send a pending_input and wait for its answer: (value, via). Timeout/interrupt → (None, reason)."""
        pid = f"{prefix}-{uuid.uuid4().hex[:12]}"
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending[pid] = fut
        await self.send("pending_input", id=pid, session_id=self._session(), timeout_s=timeout, **fields)
        try:
            value, via = await asyncio.wait_for(fut, timeout)
        except asyncio.TimeoutError:
            value, via = None, "timeout"
        except asyncio.CancelledError:
            value, via = None, "interrupt"
        finally:
            self._pending.pop(pid, None)
        if via in ("timeout", "interrupt"):
            await self.send("dismiss_panel", id=pid, reason=via)
        return value, via

    async def ask(self, req: ApprovalRequest) -> Answer:
        value, via = await self._wait("ap", self.timeout, kind="approval", card=self.render(req),
                                      voice_ok=req.policy is Policy.ASK, tool=req.tool_name)
        return Answer(value == "approve", via)

    async def question(self, tool_input: dict) -> dict | None:
        """Claude's AskUserQuestion (#19): show the questions, wait, and return `updated_input` for
        PermissionResultAllow ({questions, answers: {question text: label or typed text}}), or None."""
        questions = [q for q in (tool_input or {}).get("questions", []) if isinstance(q, dict) and q.get("question")]
        if not questions:
            return None
        value, via = await self._wait("q", self.question_timeout, kind="question", questions=questions, voice_ok=True)
        if not isinstance(value, dict):
            return None
        answers = {}
        for q in questions:
            a = value.get(q["question"])
            if isinstance(a, list):
                a = ", ".join(str(x) for x in a if str(x).strip())
            if isinstance(a, str) and a.strip():
                answers[q["question"]] = a.strip()
        if not answers:
            return None
        return {**tool_input, "questions": tool_input.get("questions", []), "answers": answers}

    def answer(self, msg: dict[str, Any]) -> bool:
        """Apply an `answer {pending_id, value, via}` from the app. For approvals `value` is approve|deny (anything
        else denies); for questions it's {question text: label(s) or typed text}. False if it matched nothing."""
        pid = msg.get("pending_id")
        fut = self._pending.get(pid)
        if fut is None or fut.done():
            return False
        value = msg.get("value")
        via = msg.get("via") if msg.get("via") in VALID_VIA else "click"
        if str(pid).startswith("ap-"):
            value = "approve" if value == "approve" else "deny"
        fut.set_result((value, via))
        return True

    def cancel_all(self, via: str = "interrupt") -> int:
        n = 0
        for fut in list(self._pending.values()):
            if not fut.done():
                fut.set_result((None, via))
                n += 1
        return n
