"""The session index (PLAN.md §7; issue #24): every session Zoe touches, in SQLite.

`~/Library/Application Support/Zoe/zoe.db` (`ZOE_DATA_DIR` overrides the folder). Stdlib `sqlite3`, WAL, one
connection used from the core's single event loop. Versioned migrations (`PRAGMA user_version`).

What it holds, and what it deliberately doesn't:
- sessions: id, folder, title, summary, times, turn count, status, fork parent.
- conversations: when they started and ended, the trigger, and the first thing I said (so I can recognise a
  conversation later; it stays on this Mac).
- projects: folders and their aliases (#25).
- pending_inputs: kind, tool and card **title** only, never the card's fields (message text, commands).
- actions: tool, input **hash**, decision, how it was given, whether the session was tainted. Never the input.
"""
from __future__ import annotations

import json
import os
import sqlite3
import time
from pathlib import Path
from typing import Any, Iterable

STATUSES = {"running", "waiting_input", "idle", "handed_off", "done", "failed"}

MIGRATIONS = [
    # 1: the PLAN.md §7 schema (nudges come in phase 7)
    """
    CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL DEFAULT 'conversation',
        title TEXT, summary TEXT,
        cwd TEXT NOT NULL, worktree TEXT,
        created_at REAL NOT NULL, last_used_at REAL NOT NULL,
        turn_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'running',
        forked_from TEXT
    );
    CREATE INDEX sessions_last_used ON sessions(last_used_at DESC);
    CREATE TABLE conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT, started_at REAL NOT NULL, ended_at REAL,
        first_utterance TEXT, trigger TEXT
    );
    CREATE TABLE projects (
        path TEXT PRIMARY KEY, name TEXT NOT NULL, aliases TEXT NOT NULL DEFAULT '[]',
        description TEXT, last_used_at REAL
    );
    CREATE TABLE pending_inputs (
        id TEXT PRIMARY KEY, session_id TEXT, kind TEXT NOT NULL, tool TEXT, title TEXT,
        voice_ok INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL,
        answered_at REAL, answer TEXT, via TEXT
    );
    CREATE TABLE actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, tool TEXT NOT NULL, input_hash TEXT NOT NULL,
        decision TEXT NOT NULL, via TEXT NOT NULL, tainted INTEGER NOT NULL DEFAULT 0, reason TEXT, at REAL NOT NULL
    );
    CREATE INDEX actions_at ON actions(at DESC);
    """,
]


def default_path() -> Path:
    d = os.environ.get("ZOE_DATA_DIR") or os.path.expanduser("~/Library/Application Support/Zoe")
    return Path(d) / "zoe.db"


class Index:
    def __init__(self, path: str | os.PathLike | None = None):
        p = Path(path) if path is not None else default_path()
        if str(p) != ":memory:":
            p.parent.mkdir(parents=True, exist_ok=True)
        self.path = p
        self.db = sqlite3.connect(str(p), isolation_level=None, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=NORMAL")
        self.migrate()

    # --- schema ------------------------------------------------------------------------------------------------

    @property
    def version(self) -> int:
        return self.db.execute("PRAGMA user_version").fetchone()[0]

    def migrate(self) -> None:
        v = self.version
        for i, sql in enumerate(MIGRATIONS[v:], start=v + 1):
            self.db.execute("BEGIN")
            try:
                for stmt in _statements(sql):
                    self.db.execute(stmt)
                self.db.execute(f"PRAGMA user_version={i}")
                self.db.execute("COMMIT")
            except Exception:
                self.db.execute("ROLLBACK")
                raise

    def close(self) -> None:
        self.db.close()

    # --- sessions ----------------------------------------------------------------------------------------------

    def upsert_session(self, session_id: str, cwd: str, *, kind: str = "conversation", status: str = "running",
                       forked_from: str | None = None, now: float | None = None) -> None:
        now = now or time.time()
        self.db.execute(
            """INSERT INTO sessions(session_id, kind, cwd, created_at, last_used_at, status, forked_from)
               VALUES (?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(session_id) DO UPDATE SET last_used_at=excluded.last_used_at, status=excluded.status,
                   forked_from=COALESCE(sessions.forked_from, excluded.forked_from)""",
            (session_id, kind, cwd, now, now, _status(status), forked_from))

    def touch(self, session_id: str, turns: int = 1, now: float | None = None) -> None:
        self.db.execute("UPDATE sessions SET last_used_at=?, turn_count=turn_count+? WHERE session_id=?",
                        (now or time.time(), turns, session_id))

    def set_status(self, session_id: str, status: str) -> None:
        self.db.execute("UPDATE sessions SET status=? WHERE session_id=?", (_status(status), session_id))

    def set_title(self, session_id: str, title: str) -> None:
        self.db.execute("UPDATE sessions SET title=? WHERE session_id=?", (title.strip()[:120], session_id))

    def set_summary(self, session_id: str, summary: str) -> None:
        self.db.execute("UPDATE sessions SET summary=? WHERE session_id=?", (summary.strip()[:400], session_id))

    def session(self, session_id: str) -> dict | None:
        r = self.db.execute("SELECT * FROM sessions WHERE session_id=?", (session_id,)).fetchone()
        return dict(r) if r else None

    def recent(self, limit: int = 20, since: float | None = None) -> list[dict]:
        q, args = "SELECT * FROM sessions", []
        if since is not None:
            q += " WHERE last_used_at >= ?"
            args.append(since)
        q += " ORDER BY last_used_at DESC LIMIT ?"
        args.append(limit)
        return [dict(r) for r in self.db.execute(q, args)]

    # --- conversations -----------------------------------------------------------------------------------------

    def start_conversation(self, session_id: str | None, first_utterance: str, trigger: str = "",
                           now: float | None = None) -> int:
        cur = self.db.execute(
            "INSERT INTO conversations(session_id, started_at, first_utterance, trigger) VALUES (?, ?, ?, ?)",
            (session_id, now or time.time(), first_utterance[:300], trigger))
        return int(cur.lastrowid)

    def set_conversation_session(self, conv_id: int, session_id: str) -> None:
        self.db.execute("UPDATE conversations SET session_id=? WHERE id=?", (session_id, conv_id))

    def end_conversation(self, conv_id: int, now: float | None = None) -> None:
        self.db.execute("UPDATE conversations SET ended_at=? WHERE id=? AND ended_at IS NULL",
                        (now or time.time(), conv_id))

    # --- projects (#25) ------------------------------------------------------------------------------------------

    def upsert_project(self, path: str, name: str, aliases: Iterable[str], last_used_at: float | None = None) -> None:
        self.db.execute(
            """INSERT INTO projects(path, name, aliases, last_used_at) VALUES (?, ?, ?, ?)
               ON CONFLICT(path) DO UPDATE SET name=excluded.name, aliases=excluded.aliases,
                   last_used_at=MAX(COALESCE(projects.last_used_at, 0), COALESCE(excluded.last_used_at, 0))""",
            (path, name, json.dumps(sorted(set(aliases))), last_used_at))

    def projects(self) -> list[dict]:
        out = []
        for r in self.db.execute("SELECT * FROM projects ORDER BY last_used_at DESC"):
            d = dict(r)
            d["aliases"] = json.loads(d["aliases"] or "[]")
            out.append(d)
        return out

    # --- pending inputs ------------------------------------------------------------------------------------------

    def add_pending(self, pid: str, session_id: str | None, kind: str, tool: str | None, title: str | None,
                    voice_ok: bool) -> None:
        self.db.execute(
            "INSERT OR IGNORE INTO pending_inputs(id, session_id, kind, tool, title, voice_ok, created_at) VALUES (?,?,?,?,?,?,?)",
            (pid, session_id, kind, tool, (title or "")[:200], int(bool(voice_ok)), time.time()))
        if session_id:
            self.set_status(session_id, "waiting_input")

    def answer_pending(self, pid: str, answer: str, via: str) -> None:
        self.db.execute("UPDATE pending_inputs SET answered_at=?, answer=?, via=? WHERE id=? AND answered_at IS NULL",
                        (time.time(), answer, via, pid))
        r = self.db.execute("SELECT session_id FROM pending_inputs WHERE id=?", (pid,)).fetchone()
        if r and r[0] and not self.waiting(r[0]):
            self.set_status(r[0], "running")

    def waiting(self, session_id: str | None = None) -> int:
        q, args = "SELECT COUNT(*) FROM pending_inputs WHERE answered_at IS NULL", []
        if session_id:
            q += " AND session_id=?"
            args.append(session_id)
        return self.db.execute(q, args).fetchone()[0]

    # --- actions -------------------------------------------------------------------------------------------------

    def log_action(self, session_id: str | None, tool: str, input_hash: str, decision: str, via: str,
                   tainted: bool = False, reason: str = "") -> None:
        self.db.execute(
            "INSERT INTO actions(session_id, tool, input_hash, decision, via, tainted, reason, at) VALUES (?,?,?,?,?,?,?,?)",
            (session_id, tool, input_hash, decision, via, int(bool(tainted)), reason[:200], time.time()))

    def actions(self, limit: int = 50) -> list[dict]:
        return [dict(r) for r in self.db.execute("SELECT * FROM actions ORDER BY id DESC LIMIT ?", (limit,))]


def _status(s: str) -> str:
    if s not in STATUSES:
        raise ValueError(f"unknown session status: {s}")
    return s


def _statements(sql: str) -> list[str]:
    return [s.strip() for s in sql.split(";") if s.strip()]
