"""Waits only a terminal can answer (#19)."""
import asyncio

import pytest

from zoe_core.terminal import TerminalHandoff


class Wire:
    def __init__(self):
        self.sent = []

    async def __call__(self, type_, **f):
        self.sent.append((type_, f))


def run(tool, tool_input, response, cwd="/repo"):
    w = Wire()
    out = asyncio.run(TerminalHandoff(w).post_tool_use(
        {"tool_name": tool, "tool_input": tool_input, "tool_response": response, "cwd": cwd}, "t", None))
    return out, w.sent


@pytest.mark.parametrize("stderr", [
    "sudo: a terminal is required to read the password; either use the -S option",
    "sudo: no tty present and no askpass program specified",
    "git@host: Permission denied (publickey,password).",
    "Host key verification failed.",
    "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
    "Password:",
])
def test_password_and_interactive_commands_get_a_terminal_card(stderr):
    out, sent = run("Bash", {"command": "sudo true", "description": "x"}, {"stdout": "", "stderr": stderr})
    assert sent and sent[0][0] == "pending_input"
    f = sent[0][1]
    assert f["kind"] == "terminal" and f["card"]["command"] == "sudo true" and f["card"]["cwd"] == "/repo" and f["voice_ok"] is False
    ctx = out["hookSpecificOutput"]["additionalContext"]
    assert "never ask for a password" in ctx


def test_ordinary_output_is_left_alone():
    out, sent = run("Bash", {"command": "ls"}, {"stdout": "README.md\npassword_reset.py\n", "stderr": ""})
    assert out == {} and sent == []


def test_connector_sign_in():
    out, sent = run("mcp__claude_ai_Gmail__search_threads", {"q": "x"}, "Error: token has expired, please re-authenticate")
    assert sent[0][1]["card"]["title"] == "Gmail needs signing in again" and sent[0][1]["card"]["command"] == "claude"
    assert "additionalContext" in out["hookSpecificOutput"]


def test_connector_content_mentioning_words_inside_results_is_not_a_sign_in():
    out, sent = run("mcp__claude_ai_Google_Calendar__list_events", {}, {"events": [{"summary": "Team lunch"}]})
    assert out == {} and sent == []


def test_an_email_that_mentions_signing_in_is_content_not_an_error():
    out, sent = run("mcp__claude_ai_Gmail__get_thread", {}, {"messages": [{"body": "Your token expired, please re-authenticate"}]})
    assert out == {} and sent == []
    out, sent = run("mcp__claude_ai_Gmail__get_thread", {}, {"is_error": True, "content": "401 Unauthorized: re-authenticate"})
    assert sent and sent[0][1]["kind"] == "terminal"


def test_failed_commands_arrive_as_post_tool_use_failure():
    w = Wire()
    out = asyncio.run(TerminalHandoff(w).post_tool_use(
        {"hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": {"command": "sudo true"},
         "error": "Exit code 1\nsudo: a terminal is required to read the password", "cwd": "/repo"}, "t", None))
    assert w.sent and w.sent[0][1]["kind"] == "terminal"
    assert out["hookSpecificOutput"]["hookEventName"] == "PostToolUseFailure"
