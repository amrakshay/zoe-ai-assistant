"""Projects and repo aliases (#25)."""
import json

from zoe_core.projects import Project, Projects, aliases_for, first_cwd, load


def write_session(root, folder, cwd, extra_lines=0):
    d = root / folder
    d.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps({"type": "summary"})] * extra_lines + [json.dumps({"type": "user", "cwd": cwd, "message": {"content": "SECRET"}})]
    (d / "s.jsonl").write_text("\n".join(lines) + "\n")


def test_aliases_from_folder_names():
    assert {"acme-api", "acme api", "acme", "api"} <= aliases_for("acme-api")
    assert "zoe" in aliases_for("zoe-ai-assistant") and "ai" not in aliases_for("zoe-ai-assistant")


def test_seed_keeps_git_repos_and_skips_the_rest(tmp_path, monkeypatch):
    import re
    import zoe_core.projects as m
    # pytest's tmp_path is itself under /private/var/folders, which Zoe skips as temporary: narrow it here.
    monkeypatch.setattr(m, "SKIP", re.compile(r"^/(private/)?tmp/|/scratch|/\.build/|/checkouts/"))
    claude = tmp_path / "claude"
    repo = tmp_path / "work" / "acme-api"
    (repo / ".git").mkdir(parents=True)
    (repo / "src").mkdir()
    plain = tmp_path / "work" / "notes"
    plain.mkdir()
    write_session(claude, "a", str(repo / "src"))          # inside the repo → the repo root
    write_session(claude, "b", str(plain))                 # not a git repo → skipped
    write_session(claude, "c", "/private/tmp/scratch-x")   # temporary → skipped
    write_session(claude, "d", str(tmp_path / "gone"))     # no longer exists → skipped
    ps = load(claude_projects=claude, aliases_file=tmp_path / "none.json")
    assert list(ps.items) == [str(repo)] and ps.seed_ms < 1000


def test_only_the_cwd_is_read(tmp_path):
    write_session(tmp_path, "a", "/x", extra_lines=3)
    assert first_cwd(tmp_path / "a" / "s.jsonl") == "/x"
    write_session(tmp_path, "b", "/y", extra_lines=100)    # beyond the first lines: not read
    assert first_cwd(tmp_path / "b" / "s.jsonl") is None


def proj(*names):
    return Projects([Project(f"/w/{n}", n, aliases_for(n)) for n in names])


def test_matching_needs_context():
    ps = proj("acme-api", "zoe-ai-assistant")
    assert [p.name for p in ps.match("In the api repo, what does the README say?")] == ["acme-api"]
    assert [p.name for p in ps.match("open the zoe project")] == ["zoe-ai-assistant"]
    assert [p.name for p in ps.match("in zoe, run the tests")] == ["zoe-ai-assistant"]
    assert ps.match("What's an API?") == [] and ps.match("tell me about zoe") == []


def test_longest_alias_wins_and_ties_are_ambiguous():
    ps = proj("acme-api", "beta-api")
    assert {p.name for p in ps.match("in the api repo")} == {"acme-api", "beta-api"}
    assert [p.name for p in ps.match("in the acme api repo")] == ["acme-api"]


def test_user_aliases(tmp_path):
    f = tmp_path / "aliases.json"
    f.write_text(json.dumps({"Gateway": "/w/acme-gw"}))
    ps = load(claude_projects=tmp_path / "empty", aliases_file=f)
    assert [p.path for p in ps.match("in the gateway repo")] == ["/w/acme-gw"]
