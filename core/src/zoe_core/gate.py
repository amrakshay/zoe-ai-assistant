"""The approval gate (PLAN.md §7; issues #14, #15).

Every tool call goes through one catch-all `PreToolUse` hook, registered with `on_failure="block"` so a hook
error can never let a tool run. The hook runs before any allow rule in my settings, so those can't approve a
tool behind Zoe's back (F02).

The decision comes from the policy table (`policy.py`):
- ALLOW → allow. DENY → deny with a reason Claude can say out loud.
- ASK / CLICK → the hook asks me itself through the `approver` (the app's approval card, #15) and waits.
  With no approver, or if asking fails, the answer is deny.

Every decision is logged without the raw input (`actions.py`).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Awaitable, Callable

from . import actions
from .policy import BUILTIN_READ, CONNECTOR_READ, Decision, Policy, decide  # noqa: F401 (re-exported)
from .taint import Taint


@dataclass(frozen=True)
class ApprovalRequest:
    tool_name: str
    tool_input: dict
    policy: Policy          # ASK or CLICK
    reason: str
    tool_use_id: str | None
    cwd: str = ""           # the session's folder (where a command would run)


@dataclass(frozen=True)
class Answer:
    approved: bool
    via: str                # click | voice | terminal | timeout | restart | interrupt | error


Approver = Callable[[ApprovalRequest], Awaitable[Answer]]

NO_APPROVALS = (
    "This needs the user's approval, and approvals aren't available right now, so it was not done. Tell the "
    "user briefly that you couldn't do it, and offer what you can do by reading instead."
)
DECLINED = "The user declined this. Don't retry it; say briefly that you didn't do it."
NOT_ANSWERED = "The user didn't approve this in time, so it was not done. Don't retry it unless they ask again."
IN_TERMINAL = ("The user chose to run this command in Terminal themselves, so it was not run here. Don't run or retry "
               "it; say in one short sentence that it's open in Terminal.")


def _out(decision: str, reason: str) -> dict:
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                   "permissionDecisionReason": reason}}


class Gate:
    def __init__(self, approver: Approver | None = None, session_id: Callable[[], str | None] | None = None,
                 taint: Taint | None = None):
        self.approver = approver
        self._session = session_id or (lambda: None)
        self.taint = taint or Taint()

    async def pre_tool_use(self, input_data: dict, tool_use_id: str | None, context) -> dict:
        name = input_data.get("tool_name")
        tool_input = input_data.get("tool_input") or {}
        if name == "AskUserQuestion":
            # No decision: it falls through to can_use_tool, where the answers are filled in (#19).
            actions.log_decision(str(name), tool_input, "question", "policy", "Claude asks the user", self._session())
            return {}
        d: Decision = self.taint.adjust(str(name), tool_input, decide(name, tool_input))
        sid = self._session()
        if d.policy is Policy.ALLOW:
            actions.log_decision(str(name), tool_input, "allow", "policy", d.reason, sid, self.taint.tainted)
            self.taint.observe(str(name))           # its result enters Claude's context
            return _out("allow", d.reason)
        if d.policy is Policy.DENY:
            actions.log_decision(str(name), tool_input, "deny", "policy", d.reason, sid, self.taint.tainted)
            return _out("deny", f"Blocked: {d.reason}.")
        if self.approver is None:
            actions.log_decision(str(name), tool_input, "deny", "no-approver", d.reason, sid)
            return _out("deny", NO_APPROVALS)
        try:
            ans = await self.approver(ApprovalRequest(name, tool_input, d.policy, d.reason, tool_use_id,
                                                      str(input_data.get("cwd") or "")))
        except Exception:  # noqa: BLE001 — any failure while asking is a deny
            ans = Answer(False, "error")
        if d.policy is Policy.CLICK and ans.approved and ans.via != "click":
            ans = Answer(False, ans.via)          # a click-only tool approved any other way is still a deny
        actions.log_decision(str(name), tool_input, "allow" if ans.approved else "deny", ans.via, d.reason, sid,
                             self.taint.tainted)
        if ans.approved:
            self.taint.observe(str(name))
            return _out("allow", f"approved by the user ({ans.via})")
        if ans.via == "terminal":
            return _out("deny", IN_TERMINAL)
        return _out("deny", DECLINED if ans.via in ("click", "voice") else NOT_ANSWERED)


# Phase 1 entry point, kept for tests and callers that don't need approvals: no approver, so ASK/CLICK deny.
_default = Gate()


async def pre_tool_use(input_data: dict, tool_use_id: str | None, context) -> dict:
    return await _default.pre_tool_use(input_data, tool_use_id, context)
