"""The Claude router (#27), with a fake model."""
import asyncio
import time

from zoe_core.claude_router import checked, pick_project, pick_session, session_prompt
from zoe_core.projects import Project

NOW = time.time()
SESSIONS = [
    {"session_id": "a", "title": "Release notes draft", "summary": "Drafted 0.1 release notes.", "cwd": "/w/zoe", "last_used_at": NOW - 5 * 3600},
    {"session_id": "b", "title": "Calendar today", "summary": "Checked today's meetings.", "cwd": "/Users/me", "last_used_at": NOW - 600},
]


def fake(answer):
    seen = []

    async def ask(system, prompt):
        seen.append(prompt)
        return answer, 0.01
    return ask, seen


def test_prompt_has_titles_summaries_folders_and_ages_only():
    p = session_prompt("continue the release notes", SESSIONS, NOW)
    assert '1. "Release notes draft"' in p and "folder: zoe" in p and "5 h ago" in p and "10 min ago" in p


def test_pick_is_checked():
    assert checked({"pick": 1, "reason": "r"}, 2) == (0, "r")
    for bad in [{"pick": 3}, {"pick": 0}, {"pick": "1"}, {"pick": True}, {"pick": None}, None, {"nope": 1}]:
        assert checked(bad, 2)[0] is None


def test_pick_session():
    ask, seen = fake({"pick": 1, "reason": "release notes from this morning"})
    pk = asyncio.run(pick_session("continue the release notes thing from this morning", SESSIONS, ask, NOW))
    assert pk.index == 0 and "release" in pk.reason and len(seen) == 1


def test_no_sessions_no_call():
    ask, seen = fake({"pick": 1})
    assert asyncio.run(pick_session("continue it", [], ask)).index is None and seen == []


def test_pick_project():
    ask, _ = fake({"pick": 2, "reason": "beta"})
    ps = [Project("/w/acme-api", "acme-api"), Project("/w/beta-api", "beta-api")]
    assert asyncio.run(pick_project("in the beta api repo", ps, ask)).index == 1


def test_brain_resumes_the_picked_session_in_its_stored_folder(tmp_path, monkeypatch):
    from zoe_core.brain import Brain
    from zoe_core.index import Index

    async def ask(system, prompt):
        return {"pick": 1, "reason": "it"}, 0.01
    monkeypatch.setattr("zoe_core.quick.ask_json", ask)

    async def send(*a, **k):
        pass
    ix = Index(tmp_path / "z.db")
    ix.upsert_session("old-1", "/w/zoe")
    ix.set_title("old-1", "Release notes draft")
    ix.set_status("old-1", "handed_off")
    b = Brain(send, index=ix)
    asyncio.run(b.choose("continue the release notes thing from this morning"))
    assert b.active.session_id == "old-1" and b.active.cwd == "/w/zoe"
    assert b.active.fork_next and b.options().fork_session      # it was handed off: fork, don't write to it
