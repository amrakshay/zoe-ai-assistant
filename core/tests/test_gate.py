import asyncio

import pytest

from zoe_core.gate import BUILTIN_READ, CONNECTOR_READ, decide, pre_tool_use


@pytest.mark.parametrize("name", sorted(BUILTIN_READ | CONNECTOR_READ))
def test_read_tools_allowed(name):
    assert decide(name).allow


@pytest.mark.parametrize("name", [
    "Bash", "Write", "Edit", "NotebookEdit", "WebFetch", "WebSearch", "Task", "AskUserQuestion", "ExitPlanMode",
    "mcp__claude_ai_Google_Calendar__create_event", "mcp__claude_ai_Google_Calendar__delete_event",
    "mcp__claude_ai_Slack__slack_send_message", "mcp__claude_ai_Gmail__send_message",
    "mcp__claude_ai_Google_Calendar__list_events_and_delete",   # prefix tricks don't match exact names
    "read", "READ", "", None, "Bash(ls:*)",
])
def test_everything_else_denied(name):
    assert not decide(name).allow


def test_extra_allowed_via_env(monkeypatch):
    monkeypatch.setenv("ZOE_ALLOW_TOOLS", " mcp__claude_ai_Atlassian__getJiraIssue , ")
    assert decide("mcp__claude_ai_Atlassian__getJiraIssue").allow
    assert not decide("mcp__claude_ai_Atlassian__editJiraIssue").allow


def test_hook_output_shape():
    out = asyncio.run(pre_tool_use({"tool_name": "Bash", "tool_input": {"command": "touch x"}}, "t1", None))
    h = out["hookSpecificOutput"]
    assert h["hookEventName"] == "PreToolUse" and h["permissionDecision"] == "deny" and h["permissionDecisionReason"]
    out = asyncio.run(pre_tool_use({"tool_name": "Read", "tool_input": {}}, "t2", None))
    assert out["hookSpecificOutput"]["permissionDecision"] == "allow"


def test_hook_never_asks():
    for n in ["Bash", "Read", "anything"]:
        d = asyncio.run(pre_tool_use({"tool_name": n}, None, None))["hookSpecificOutput"]["permissionDecision"]
        assert d in {"allow", "deny"}
