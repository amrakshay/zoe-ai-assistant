"""Projects and repo aliases (PLAN.md §5.3; issue #25).

**Seeding.** The folders Claude Code sessions ran in: the `cwd` recorded in `~/.claude/projects/*/*.jsonl`
(the encoded folder names can't be decoded reliably, since a `-` may have been a `/`). Only the first few
lines of each file are read, just to find `cwd`, never the conversation. A folder counts if it's inside a git
repo; the repo root becomes the project. Temporary, scratch and package-checkout folders are skipped.

**Aliases.** From the folder name ("acme-api" → "acme api", "api", "acme"), plus my own in
`~/Library/Application Support/Zoe/aliases.json` ({"alias": "/path/to/repo"}).

**Matching** only counts an alias in context ("in the api repo", "the zoe project", "in zoe"), so "what's an
API?" doesn't switch repos. Several projects for one name → ambiguous (the Claude router decides, #27).
"""
from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass, field
from pathlib import Path

SKIP = re.compile(r"^/(private/)?(tmp|var/folders)/|/scratch|/\.build/|/node_modules/|/\.venv/|/checkouts/|/Library/")
GENERIC = {"ai", "app", "the", "and", "for", "my", "dev", "src", "lib", "main", "core", "test", "tests", "repo", "code", "new"}
CONTEXT_AFTER = r"(?:repo|repository|project|codebase|folder|code base)"


@dataclass
class Project:
    path: str
    name: str
    aliases: set[str] = field(default_factory=set)
    last_used_at: float = 0.0


def git_root(path: str) -> str | None:
    p = Path(path)
    for d in [p, *p.parents]:
        if (d / ".git").exists():
            return str(d)
        if d == Path.home() or d == d.parent:
            return None
    return None


def aliases_for(name: str) -> set[str]:
    words = [w for w in re.split(r"[-_.\s]+", name.lower()) if w]
    out = {name.lower(), " ".join(words)}
    useful = [w for w in words if w not in GENERIC and len(w) >= 3]
    if useful:
        out.add(useful[0])
        out.add(useful[-1])
    if len(words) >= 2:
        out.add(" ".join(words[-2:]))
    return {a for a in out if a and a not in GENERIC}


def first_cwd(path: Path, max_lines: int = 40, max_bytes: int = 256 * 1024) -> str | None:
    """The `cwd` from the first lines of a Claude Code session file (nothing else is read)."""
    try:
        with open(path, "rb") as f:
            for i, line in enumerate(f):
                if i >= max_lines or f.tell() > max_bytes:
                    break
                if b'"cwd"' not in line:
                    continue
                try:
                    cwd = json.loads(line).get("cwd")
                except ValueError:
                    continue
                if isinstance(cwd, str) and cwd:
                    return cwd
    except OSError:
        return None
    return None


def seed(claude_projects: str | os.PathLike | None = None) -> list[Project]:
    root = Path(claude_projects or os.path.expanduser("~/.claude/projects"))
    by_path: dict[str, Project] = {}
    for f in root.glob("*/*.jsonl"):
        cwd = first_cwd(f)
        if not cwd or SKIP.search(cwd) or not os.path.isdir(cwd):
            continue
        repo = git_root(cwd)
        if not repo or SKIP.search(repo):
            continue
        p = by_path.setdefault(repo, Project(repo, os.path.basename(repo), aliases_for(os.path.basename(repo))))
        p.last_used_at = max(p.last_used_at, f.stat().st_mtime)
    return sorted(by_path.values(), key=lambda p: -p.last_used_at)


def user_aliases(path: str | os.PathLike | None = None) -> dict[str, str]:
    p = Path(path or os.path.join(os.environ.get("ZOE_DATA_DIR") or os.path.expanduser("~/Library/Application Support/Zoe"),
                                  "aliases.json"))
    try:
        data = json.loads(p.read_text())
    except (OSError, ValueError):
        return {}
    return {str(k).lower().strip(): os.path.expanduser(str(v)) for k, v in data.items() if str(k).strip()}


class Projects:
    def __init__(self, projects: list[Project], extra: dict[str, str] | None = None):
        self.items = {p.path: p for p in projects}
        for alias, path in (extra or {}).items():
            p = self.items.setdefault(path, Project(path, os.path.basename(path.rstrip("/"))))
            p.aliases.add(alias)

    def match(self, utterance: str) -> list[Project]:
        """Projects named in context in `utterance`; longest alias wins; several → ambiguous."""
        text = " " + re.sub(r"[^a-z0-9 ]+", " ", utterance.lower().replace("-", " ").replace("_", " ")) + " "
        best: dict[str, int] = {}
        for p in self.items.values():
            for a in p.aliases:
                spaced = re.sub(r"[-_.]+", " ", a)
                pat = rf"(?:\bin (?:the |my )?{re.escape(spaced)}\b|\b{re.escape(spaced)} {CONTEXT_AFTER}\b)"
                if re.search(pat, text):
                    best[p.path] = max(best.get(p.path, 0), len(spaced))
        if not best:
            return []
        top = max(best.values())
        return [self.items[path] for path, n in best.items() if n == top]

    def save(self, index) -> None:
        for p in self.items.values():
            index.upsert_project(p.path, p.name, p.aliases, p.last_used_at or None)


def load(index=None, claude_projects=None, aliases_file=None) -> Projects:
    t0 = time.monotonic()
    ps = Projects(seed(claude_projects), user_aliases(aliases_file))
    if index is not None:
        ps.save(index)
    ps.seed_ms = (time.monotonic() - t0) * 1000  # type: ignore[attr-defined]
    return ps
