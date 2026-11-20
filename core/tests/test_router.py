"""The local router and several sessions (#26)."""
import asyncio
import time

from zoe_core.brain import Brain, MAX_LIVE, home
from zoe_core.projects import Project, Projects, aliases_for
from zoe_core.router import RECENT_S, SessionInfo, route

HOME = "/Users/me"


def projects(*names):
    return Projects([Project(f"/w/{n}", n, aliases_for(n), last_used_at=i) for i, n in enumerate(names)])


PS = projects("acme-api", "zoe-ai-assistant")


def test_follow_up_within_30_minutes_continues():
    a = SessionInfo(1, HOME, last_used=1000)
    r = route("and tomorrow?", 1000 + RECENT_S - 1, a, [a], PS, HOME)
    assert r.action == "continue" and r.key == 1


def test_after_30_minutes_a_new_session_at_home():
    a = SessionInfo(1, "/w/acme-api", last_used=1000)
    r = route("what's on my calendar?", 1000 + RECENT_S + 1, a, [a], PS, HOME)
    assert r.action == "new" and r.cwd == HOME


def test_naming_a_repo_starts_a_session_there():
    a = SessionInfo(1, HOME, last_used=1000)
    r = route("In the api repo, what does the README say?", 1001, a, [a], PS, HOME)
    assert r.action == "new" and r.cwd == "/w/acme-api"


def test_naming_a_repo_with_a_recent_session_there_continues_it():
    a = SessionInfo(1, HOME, last_used=1000)
    b = SessionInfo(2, "/w/acme-api", last_used=990)
    r = route("in the api repo, run the tests", 1001, a, [a, b], PS, HOME)
    assert r.action == "continue" and r.key == 2


def test_ambiguous_names_are_flagged():
    ps = projects("acme-api", "beta-api")
    r = route("in the api repo", 5, None, [], ps, HOME)
    assert set(r.ambiguous) == {"/w/acme-api", "/w/beta-api"} and r.cwd == "/w/beta-api"   # most recent


def test_resume_requests_are_flagged_for_the_claude_router():
    assert route("continue the release thing from this morning", 5, None, [], PS, HOME).resume_request
    assert not route("what's the weather", 5, None, [], PS, HOME).resume_request


def test_routing_is_fast():
    many = projects(*[f"proj-{i}" for i in range(200)])
    sessions = [SessionInfo(i, f"/w/proj-{i}", i) for i in range(50)]
    t0 = time.perf_counter()
    for _ in range(100):
        route("in the proj-150 repo, list the tests", 1e9, sessions[0], sessions, many, HOME)
    assert (time.perf_counter() - t0) / 100 < 0.02


class Wire:
    def __init__(self):
        self.sent = []

    async def __call__(self, type_, **f):
        self.sent.append((type_, f))


class FakeClient:
    def __init__(self):
        self.closed = False

    async def disconnect(self):
        self.closed = True


def test_brain_switches_sessions_and_tells_the_app():
    w = Wire()
    b = Brain(w)
    b.projects = PS
    home_s = b.active
    asyncio.run(b.choose("in the api repo, what's in the README?"))
    assert b.active is not home_s and b.cwd == "/w/acme-api"
    st = dict(w.sent)["session_state"]
    assert st["cwd"] == "/w/acme-api" and st["name"] == "acme-api"
    assert b.gate is b.active.gate and b.gate is not home_s.gate          # taint is per session


def test_brain_keeps_at_most_max_live_processes():
    w = Wire()
    b = Brain(w)
    b.projects = projects("a-one", "b-two", "c-three")
    clients = []
    for n in ["one", "two", "three"]:
        asyncio.run(b.choose(f"in the {n} repo, hi"))
        b.active.client = FakeClient()
        b.active.last_used = time.time()
        clients.append(b.active.client)
    asyncio.run(b.close_extra())
    live = [s for s in b.sessions if s.client is not None]
    assert len(live) <= MAX_LIVE and b.active.client is not None and clients[0].closed


def test_a_new_route_reuses_the_unused_session_started_at_launch():
    b = Brain(Wire())
    warm = b.active                                  # pre-connected at hello, never used
    asyncio.run(b.choose("what's the capital of Portugal?"))
    assert b.active is warm and len(b.sessions) == 1


def test_idle_sessions_close_and_busy_ones_dont(monkeypatch):
    monkeypatch.setenv("ZOE_IDLE_CLOSE_S", "600")
    b = Brain(Wire())
    b.projects = projects("a-one")
    old = b.active
    old.client, old.last_used, old.session_id = FakeClient(), 1000, "s-old"
    asyncio.run(b.choose("in the one repo, hi"))
    new = b.active
    new.client, new.last_used = FakeClient(), 1500
    closed = asyncio.run(b.sweep_idle(now=1000 + 601))
    assert closed == 1 and old.client is None and new.client is not None and old.session_id == "s-old"
    assert b.options(old).resume == "s-old" and b.options(old).cwd == old.cwd   # resumes by id, in its folder
