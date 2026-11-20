"""The session index (#24)."""
import sqlite3

import pytest

from zoe_core.index import MIGRATIONS, Index


@pytest.fixture
def ix(tmp_path):
    i = Index(tmp_path / "zoe.db")
    yield i
    i.close()


def test_fresh_file_is_migrated(ix):
    assert ix.version == len(MIGRATIONS)
    tables = {r[0] for r in ix.db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert {"sessions", "conversations", "projects", "pending_inputs", "actions"} <= tables


def test_reopening_doesnt_migrate_again(tmp_path):
    a = Index(tmp_path / "z.db")
    a.upsert_session("s1", "/repo")
    a.close()
    b = Index(tmp_path / "z.db")
    assert b.version == len(MIGRATIONS) and b.session("s1")["cwd"] == "/repo"


def test_a_failed_migration_rolls_back(tmp_path, monkeypatch):
    import zoe_core.index as m
    monkeypatch.setattr(m, "MIGRATIONS", ["CREATE TABLE a (x INT); THIS IS NOT SQL"])
    with pytest.raises(sqlite3.OperationalError):
        Index(tmp_path / "bad.db")
    db = sqlite3.connect(tmp_path / "bad.db")
    assert db.execute("PRAGMA user_version").fetchone()[0] == 0
    assert not db.execute("SELECT name FROM sqlite_master WHERE name='a'").fetchone()


def test_sessions_lifecycle(ix):
    ix.upsert_session("s1", "/home", now=100)
    ix.touch("s1", now=110)
    ix.touch("s1", now=120)
    ix.set_title("s1", "  Calendar today  ")
    ix.set_status("s1", "idle")
    s = ix.session("s1")
    assert s["turn_count"] == 2 and s["last_used_at"] == 120 and s["created_at"] == 100
    assert s["title"] == "Calendar today" and s["status"] == "idle"
    with pytest.raises(ValueError):
        ix.set_status("s1", "sleeping")


def test_forks_remember_their_parent(ix):
    ix.upsert_session("parent", "/home", now=1)
    ix.set_status("parent", "handed_off")
    ix.upsert_session("child", "/home", forked_from="parent", now=2)
    ix.upsert_session("child", "/home", now=3)                       # a later upsert keeps the parent
    assert ix.session("child")["forked_from"] == "parent" and ix.session("parent")["status"] == "handed_off"


def test_recent_orders_by_last_use(ix):
    for i, t in [("a", 10), ("b", 30), ("c", 20)]:
        ix.upsert_session(i, "/x", now=t)
    assert [s["session_id"] for s in ix.recent()] == ["b", "c", "a"]
    assert [s["session_id"] for s in ix.recent(since=15)] == ["b", "c"]


def test_conversations(ix):
    cid = ix.start_conversation(None, "x" * 500, "click", now=5)
    ix.set_conversation_session(cid, "s1")
    ix.end_conversation(cid, now=9)
    ix.end_conversation(cid, now=99)                                # the first end stands
    r = dict(ix.db.execute("SELECT * FROM conversations WHERE id=?", (cid,)).fetchone())
    assert r["session_id"] == "s1" and r["ended_at"] == 9 and len(r["first_utterance"]) == 300


def test_pending_inputs_drive_waiting_status(ix):
    ix.upsert_session("s1", "/x")
    ix.add_pending("ap-1", "s1", "approval", "Bash", "Run a command?", False)
    ix.add_pending("ap-2", "s1", "approval", "Edit", "Edit a file?", True)
    assert ix.session("s1")["status"] == "waiting_input" and ix.waiting("s1") == 2
    ix.answer_pending("ap-1", "deny", "click")
    assert ix.session("s1")["status"] == "waiting_input"
    ix.answer_pending("ap-2", "approve", "voice")
    assert ix.session("s1")["status"] == "running" and ix.waiting() == 0


def test_pending_inputs_store_no_card_fields(ix):
    cols = {r[1] for r in ix.db.execute("PRAGMA table_info(pending_inputs)")}
    assert "card" not in cols and "fields" not in cols


def test_actions_hold_hashes_only(ix):
    ix.log_action("s1", "Bash", "ab" * 32, "deny", "click", tainted=True, reason="needs a click")
    a = ix.actions()[0]
    assert a["tool"] == "Bash" and a["tainted"] == 1 and len(a["input_hash"]) == 64
    cols = {r[1] for r in ix.db.execute("PRAGMA table_info(actions)")}
    assert "input" not in cols and "tool_input" not in cols


def test_projects(ix):
    ix.upsert_project("/w/acme-api", "acme-api", ["api", "acme api", "api"], last_used_at=50)
    ix.upsert_project("/w/acme-api", "acme-api", ["api"], last_used_at=10)       # older info doesn't win
    p = ix.projects()[0]
    assert p["aliases"] == ["api"] and p["last_used_at"] == 50
