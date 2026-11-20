"""Open in Terminal, handoff and fork (#20) — the parts that don't need a live session."""
import asyncio

from zoe_core.brain import Brain, resume_command
from zoe_core.main import Core


class Wire:
    def __init__(self):
        self.sent = []

    async def __call__(self, type_, **f):
        self.sent.append((type_, f))


def test_no_session_yet_is_an_error():
    w = Wire()
    asyncio.run(Core(w, Brain(w)).handle({"type": "open_session", "where": "terminal"}))
    assert w.sent[-1][0] == "error"


def test_hand_off_closes_zoe_and_forks_next():
    w = Wire()
    b = Brain(w)
    b.session_id = "11111111-2222-3333-4444-555555555555"
    asyncio.run(Core(w, b).handle({"type": "open_session", "where": "terminal"}))
    kinds = [t for t, _ in w.sent]
    assert "open_terminal" in kinds and "session_state" in kinds
    ot = dict(w.sent)["open_terminal"]
    assert "--resume 11111111-2222-3333-4444-555555555555" in ot["command"] and ot["cwd"] == b.cwd
    assert b.client is None and b.handed_off == b.session_id and b.fork_next
    o = b.options()
    assert o.resume == b.session_id and o.fork_session is True


def test_resume_command_quotes_the_id():
    cmd = resume_command("abc; rm -rf ~")
    assert "'abc; rm -rf ~'" in cmd and "command -v claude" in cmd


def test_options_dont_fork_normally():
    b = Brain(Wire())
    b.session_id = "x"
    assert b.options().fork_session is False
