"""Titles and summaries (#28): the parts that don't need a live model."""
import asyncio

from zoe_core.brain import Brain
from zoe_core.index import Index
from zoe_core.quick import parse_json


def test_parse_json_handles_fences_and_noise():
    assert parse_json('```json\n{"title": "Calendar", "summary": "x"}\n```') == {"title": "Calendar", "summary": "x"}
    assert parse_json("no json here") is None and parse_json("[1, 2]") is None


async def _send(*a, **k):
    pass


def test_summary_runs_once_per_new_turns(tmp_path, monkeypatch):
    calls = []

    async def fake(system, prompt, timeout_s=20.0):
        calls.append(prompt)
        return {"title": "Release notes draft", "summary": "Drafted the 0.1 release notes."}, 0.1

    monkeypatch.setattr("zoe_core.quick.ask_json", fake)
    ix = Index(tmp_path / "z.db")
    b = Brain(_send, index=ix)
    s = b.active
    s.session_id = "s1"
    ix.upsert_session("s1", s.cwd)
    s.turns = [("draft release notes", "Here's a draft.")]

    async def go():
        b.summarise_soon(s)
        b.summarise_soon(s)                       # nothing new → no second call
        await asyncio.sleep(0.05)
    asyncio.run(go())
    assert len(calls) == 1 and "draft release notes" in calls[0]
    assert ix.session("s1")["title"] == "Release notes draft" and ix.session("s1")["summary"].startswith("Drafted")
