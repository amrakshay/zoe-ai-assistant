"""Approvals through pending_input (#15)."""
import asyncio

import pytest

from zoe_core.approvals import Approvals
from zoe_core.gate import ApprovalRequest, Gate
from zoe_core.policy import Policy


@pytest.fixture(autouse=True)
def data_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("ZOE_DATA_DIR", str(tmp_path))


class Wire:
    def __init__(self):
        self.sent = []

    async def __call__(self, type_, **f):
        self.sent.append((type_, f))

    def last(self, type_):
        return next(f for t, f in reversed(self.sent) if t == type_)


def req(tool="Edit", policy=Policy.ASK):
    return ApprovalRequest(tool, {"file_path": "/tmp/a"}, policy, "changes a file", "tu1")


async def ask_and_answer(answer: dict | None, timeout=1.0, policy=Policy.ASK):
    w = Wire()
    ap = Approvals(w, timeout=timeout)
    task = asyncio.create_task(ap.ask(req(policy=policy)))
    await asyncio.sleep(0)
    card = w.last("pending_input")
    if answer is not None:
        assert ap.answer({"pending_id": card["id"], **answer})
    return await task, w, card


def test_pending_input_shape_and_approve():
    ans, w, card = asyncio.run(ask_and_answer({"value": "approve", "via": "click"}))
    assert ans.approved and ans.via == "click"
    assert card["kind"] == "approval" and card["voice_ok"] is True and card["tool"] == "Edit" and card["card"]["title"]


def test_click_only_cards_say_no_voice():
    _, _, card = asyncio.run(ask_and_answer({"value": "deny", "via": "click"}, policy=Policy.CLICK))
    assert card["voice_ok"] is False


def test_deny_and_unknown_values_deny():
    for value in ["deny", "yes", None, "APPROVE"]:
        ans, _, _ = asyncio.run(ask_and_answer({"value": value, "via": "click"}))
        assert not ans.approved


def test_timeout_denies_and_dismisses():
    ans, w, card = asyncio.run(ask_and_answer(None, timeout=0.05))
    assert not ans.approved and ans.via == "timeout"
    assert w.last("dismiss_panel")["id"] == card["id"]


def test_unknown_via_counts_as_click_not_voice():
    ans, _, _ = asyncio.run(ask_and_answer({"value": "approve", "via": "telepathy"}))
    assert ans.via == "click"


def test_answer_for_unknown_or_finished_request():
    async def go():
        w = Wire()
        ap = Approvals(w, timeout=1)
        assert not ap.answer({"pending_id": "nope", "value": "approve"})
        t = asyncio.create_task(ap.ask(req()))
        await asyncio.sleep(0)
        pid = w.last("pending_input")["id"]
        assert ap.answer({"pending_id": pid, "value": "approve"})
        await t
        assert not ap.answer({"pending_id": pid, "value": "approve"})   # second answer is ignored
        assert ap.waiting == 0
    asyncio.run(go())


def test_interrupt_denies_everything_waiting():
    async def go():
        w = Wire()
        ap = Approvals(w, timeout=5)
        tasks = [asyncio.create_task(ap.ask(req())) for _ in range(3)]
        await asyncio.sleep(0)
        assert ap.waiting == 3 and ap.cancel_all("interrupt") == 3
        return await asyncio.gather(*tasks)
    for ans in asyncio.run(go()):
        assert not ans.approved and ans.via == "interrupt"


def test_hook_end_to_end_click_only_refuses_voice():
    async def go(tool, tool_input, value, via):
        w = Wire()
        ap = Approvals(w, timeout=1)
        g = Gate(approver=ap.ask)
        hook = asyncio.create_task(g.pre_tool_use({"tool_name": tool, "tool_input": tool_input}, "tu", None))
        while not any(t == "pending_input" for t, _ in w.sent):
            await asyncio.sleep(0)
        ap.answer({"pending_id": w.last("pending_input")["id"], "value": value, "via": via})
        return (await hook)["hookSpecificOutput"]["permissionDecision"]
    assert asyncio.run(go("Edit", {"file_path": "/tmp/a"}, "approve", "voice")) == "allow"
    assert asyncio.run(go("Bash", {"command": "ls"}, "approve", "voice")) == "deny"
    assert asyncio.run(go("Bash", {"command": "ls"}, "approve", "click")) == "allow"
