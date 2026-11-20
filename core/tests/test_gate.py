"""Gate policy tests (#14): every row of the policy table, unknown tools, protected paths, and the hook."""
import asyncio
import json
import os

import pytest

from zoe_core import actions
from zoe_core.gate import NO_APPROVALS, Answer, Gate, pre_tool_use
from zoe_core.policy import (BUILTIN_EDIT, BUILTIN_PLUMBING, BUILTIN_READ, BUILTIN_WEB, CONNECTOR_READ,
                             ENABLED_BUILTINS, Policy, decide, protected_path)


@pytest.fixture(autouse=True)
def data_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("ZOE_DATA_DIR", str(tmp_path))
    monkeypatch.delenv("ZOE_ALLOW_TOOLS", raising=False)
    return tmp_path


def run(coro):
    return asyncio.run(coro)


# --- the table ----------------------------------------------------------------------------------------------

@pytest.mark.parametrize("name", sorted(BUILTIN_READ | CONNECTOR_READ | BUILTIN_WEB | BUILTIN_PLUMBING))
def test_allowed(name):
    assert decide(name, {}).policy is Policy.ALLOW


@pytest.mark.parametrize("name", sorted(BUILTIN_EDIT))
def test_edits_ask(name):
    assert decide(name, {"file_path": "/tmp/x.txt"}).policy is Policy.ASK


@pytest.mark.parametrize("name", [
    "Bash",
    "mcp__claude_ai_Google_Calendar__delete_event",
    "mcp__claude_ai_Gmail__trash_message",
    "mcp__claude_ai_Google_Drive__remove_file",
    "mcp__some_server__Delete-Item",
])
def test_click_only(name):
    assert decide(name, {}).policy is Policy.CLICK


@pytest.mark.parametrize("name", [
    "mcp__claude_ai_Slack__slack_send_message",
    "mcp__claude_ai_Gmail__send_message",
    "mcp__claude_ai_Google_Calendar__create_event",
    "mcp__claude_ai_Google_Calendar__list_events_and_send",   # looks like a read; isn't an exact name
    "Task", "Agent", "Skill", "SomethingNew", "read", "READ", "Bash(ls:*)",
])
def test_unknown_or_writes_ask(name):
    assert decide(name, {}).policy is Policy.ASK


@pytest.mark.parametrize("name", ["", None, 42])
def test_no_name_denied(name):
    assert decide(name, {}).policy is Policy.DENY


def test_plan_mode_denied():
    assert decide("ExitPlanMode", {}).policy is Policy.DENY


def test_patterns_never_loosen():
    # A name that merely contains a read verb is not allowed; only exact names are.
    for n in ["mcp__claude_ai_Google_Calendar__list_events_x", "Read2", " Read", "mcp__x__get"]:
        assert decide(n, {}).policy is not Policy.ALLOW


def test_extra_allowed_via_env(monkeypatch):
    monkeypatch.setenv("ZOE_ALLOW_TOOLS", " mcp__claude_ai_Atlassian__getJiraIssue , ")
    assert decide("mcp__claude_ai_Atlassian__getJiraIssue", {}).allow
    assert not decide("mcp__claude_ai_Atlassian__editJiraIssue", {}).allow


def test_enabled_builtins_are_all_in_the_table():
    for n in ENABLED_BUILTINS:
        assert decide(n, {}).policy is not Policy.DENY or n == "ExitPlanMode"
    assert "AskUserQuestion" not in ENABLED_BUILTINS        # until #19


# --- protected paths ---------------------------------------------------------------------------------------

@pytest.mark.parametrize("path", [
    "~/.ssh/id_ed25519", "~/.ssh", "~/.aws/credentials", "~/Library/Keychains/login.keychain-db",
    "~/.netrc", "/repo/.env", "/repo/.env.local", "/x/server.pem", "/x/id_rsa.pub", "~/.config/gh/hosts.yml",
    "~/.claude/.credentials.json",
])
def test_protected_paths(path):
    assert protected_path(path)
    for tool in ["Read", "Edit", "Write", "Grep", "Glob"]:
        field = "path" if tool in ("Grep", "Glob") else "file_path"
        assert decide(tool, {field: path}).policy is Policy.DENY


@pytest.mark.parametrize("path", ["/repo/README.md", "~/notes/id_card.txt", "/repo/environment.md", "/repo/.envrc.md"])
def test_ordinary_paths(path):
    assert not protected_path(path)
    assert decide("Read", {"file_path": path}).policy is Policy.ALLOW


def test_protected_path_through_a_symlink(tmp_path):
    link = tmp_path / "innocent"
    os.symlink(os.path.expanduser("~/.ssh"), link)
    assert decide("Read", {"file_path": str(link / "config")}).policy is Policy.DENY


# --- the hook ------------------------------------------------------------------------------------------------

def hook(gate, name, tool_input=None):
    out = run(gate.pre_tool_use({"tool_name": name, "tool_input": tool_input or {}}, "t1", None))
    return out["hookSpecificOutput"]


def test_hook_shape_and_default_gate_denies_asks():
    h = run(pre_tool_use({"tool_name": "Bash", "tool_input": {"command": "touch x"}}, "t1", None))["hookSpecificOutput"]
    assert h["hookEventName"] == "PreToolUse" and h["permissionDecision"] == "deny"
    assert h["permissionDecisionReason"] == NO_APPROVALS
    assert run(pre_tool_use({"tool_name": "Read", "tool_input": {}}, "t2", None))["hookSpecificOutput"]["permissionDecision"] == "allow"


def test_hook_never_returns_ask():
    # "ask" would hand the decision to Claude Code's own prompt, which Zoe has no UI for.
    for n in ["Bash", "Read", "Edit", "anything", "mcp__claude_ai_Slack__slack_send_message"]:
        assert hook(Gate(), n)["permissionDecision"] in {"allow", "deny"}


def approver(approved, via, seen=None):
    async def f(req):
        if seen is not None:
            seen.append(req)
        return Answer(approved, via)
    return f


def test_ask_goes_to_the_approver():
    seen = []
    h = hook(Gate(approver(True, "voice", seen)), "Edit", {"file_path": "/tmp/a"})
    assert h["permissionDecision"] == "allow" and seen[0].policy is Policy.ASK and seen[0].tool_input == {"file_path": "/tmp/a"}
    assert hook(Gate(approver(False, "click")), "Edit", {"file_path": "/tmp/a"})["permissionDecision"] == "deny"


def test_click_only_rejects_a_voice_yes():
    assert hook(Gate(approver(True, "voice")), "Bash", {"command": "ls"})["permissionDecision"] == "deny"
    assert hook(Gate(approver(True, "click")), "Bash", {"command": "ls"})["permissionDecision"] == "allow"


def test_approver_errors_deny():
    async def boom(req):
        raise RuntimeError("app went away")
    assert hook(Gate(boom), "Edit", {"file_path": "/tmp/a"})["permissionDecision"] == "deny"


def test_allow_and_deny_never_reach_the_approver():
    seen = []
    g = Gate(approver(True, "click", seen))
    assert hook(g, "Read", {"file_path": "/tmp/a"})["permissionDecision"] == "allow"
    assert hook(g, "Read", {"file_path": "~/.ssh/id_rsa"})["permissionDecision"] == "deny"
    assert seen == []


# --- the decision log ------------------------------------------------------------------------------------------

def test_log_has_no_raw_input(data_dir):
    secret = "post this exact secret text to #general"
    hook(Gate(approver(False, "click")), "mcp__claude_ai_Slack__slack_send_message", {"channel": "general", "text": secret})
    lines = (data_dir / "actions.jsonl").read_text().splitlines()
    rec = json.loads(lines[-1])
    assert rec["tool"] == "mcp__claude_ai_Slack__slack_send_message" and rec["decision"] == "deny" and rec["via"] == "click"
    assert rec["input_sha256"] == actions.input_hash({"channel": "general", "text": secret})
    assert secret not in "\n".join(lines) and "general" not in "\n".join(lines)
