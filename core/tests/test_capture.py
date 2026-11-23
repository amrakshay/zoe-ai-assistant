"""Capture: notes, todos and reminders (#47)."""
import asyncio
import json

from zoe_core.capture import Capture, EXACT_NAMES, inbox_path, line
from zoe_core.policy import Policy, decide
from zoe_core.taint import Taint


class Wire:
    def __init__(self):
        self.sent = []

    async def __call__(self, type_, **f):
        self.sent.append((type_, f))


def test_allowed_by_exact_name_and_never_taint():
    t = Taint()
    for n in EXACT_NAMES:
        assert decide(n, {}).policy is Policy.ALLOW
        t.observe(n)
    assert not t.tainted


def test_inbox_path_default_and_setting(tmp_path, monkeypatch):
    monkeypatch.setenv("ZOE_DATA_DIR", str(tmp_path))
    assert inbox_path() == tmp_path / "inbox.md"
    (tmp_path / "settings.json").write_text(json.dumps({"notes_inbox": str(tmp_path / "vault" / "Inbox.md")}))
    assert inbox_path() == tmp_path / "vault" / "Inbox.md"


def test_notes_and_todos_append(tmp_path, monkeypatch):
    monkeypatch.setenv("ZOE_DATA_DIR", str(tmp_path))
    c = Capture(Wire())
    asyncio.run(c.handle("add_note", {"text": "call the bank\nabout the card"}))
    asyncio.run(c.handle("add_todo", {"text": "renew passport"}))
    lines = (tmp_path / "inbox.md").read_text().splitlines()
    assert lines[0].endswith("call the bank about the card") and lines[1].startswith("- [ ] renew passport (")
    assert asyncio.run(c.handle("add_note", {"text": "  "})).get("is_error")


def test_line_formats():
    assert line("note", "x", now=0).startswith("- 1970-01-01") and line("todo", "y", now=0).startswith("- [ ] y (")


def test_reminder_round_trip_and_timeout():
    async def go():
        w = Wire()
        c = Capture(w, timeout=1)
        t = asyncio.create_task(c.handle("remind_me", {"text": "review the MR", "due": "2026-11-23T16:00"}))
        while not w.sent:
            await asyncio.sleep(0)
        m = w.sent[0][1]
        assert w.sent[0][0] == "add_reminder" and m["due"] == "2026-11-23T16:00"
        c.reminder_done({"id": m["id"], "ok": True, "detail": "today 16:00"})
        return await t
    assert "Reminder set" in asyncio.run(go())["content"][0]["text"]
    slow = asyncio.run(Capture(Wire(), timeout=0.05).handle("remind_me", {"text": "x"}))
    assert slow.get("is_error")
