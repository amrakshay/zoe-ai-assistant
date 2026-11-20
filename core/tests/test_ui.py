"""The ui tool server (#34)."""
import asyncio

from zoe_core.policy import Policy, decide
from zoe_core.taint import Taint
from zoe_core.ui import EXACT_NAMES, MAX_ROWS, UI


class Wire:
    def __init__(self):
        self.sent = []

    async def __call__(self, type_, **f):
        self.sent.append((type_, f))


def run(ui, tool, args):
    return asyncio.run(ui.handle(tool, args))


def test_ui_tools_are_allowed_by_exact_name_only():
    for n in EXACT_NAMES:
        assert decide(n, {}).policy is Policy.ALLOW
    assert decide("mcp__ui__show_card_and_send", {}).policy is not Policy.ALLOW
    assert decide("mcp__uix__show_card", {}).policy is not Policy.ALLOW


def test_ui_tools_dont_taint():
    t = Taint()
    t.observe("mcp__ui__show_table")
    assert not t.tainted


def test_card_and_table_send_show_panel():
    w = Wire()
    ui = UI(w)
    out = run(ui, "show_card", {"title": "Notes", "body": "**hi** [link](https://x)"})
    assert "is_error" not in out and w.sent[-1][0] == "show_panel" and w.sent[-1][1]["kind"] == "card"
    assert w.sent[-1][1]["payload"]["body"] == "**hi** [link](https://x)"          # verbatim
    run(ui, "show_table", {"title": "Meetings", "columns": ["When", "What"], "rows": [["10:00", "Standup"], ["11:00"]]})
    p = w.sent[-1][1]["payload"]
    assert p["rows"] == [["10:00", "Standup"], ["11:00", ""]] and p["truncated_rows"] == 0


def test_limits_are_visible_not_silent():
    w = Wire()
    ui = UI(w)
    run(ui, "show_table", {"columns": ["n"], "rows": [[str(i)] for i in range(MAX_ROWS + 20)]})
    p = w.sent[-1][1]["payload"]
    assert len(p["rows"]) == MAX_ROWS and p["truncated_rows"] == 20
    run(ui, "show_card", {"title": "t", "body": "x" * 9000})
    assert w.sent[-1][1]["payload"]["body"].endswith("(1000 more characters)")


def test_bad_input_is_an_error_not_a_panel():
    w = Wire()
    ui = UI(w)
    for tool, args in [("show_table", {"columns": [], "rows": []}), ("show_table", {"columns": ["a"], "rows": "x"}),
                       ("show_choices", {"prompt": "p", "options": ["only one"]}), ("show_card", {"title": "", "body": "b"})]:
        assert run(ui, tool, args).get("is_error")
    assert w.sent == []


def test_dismiss_latest_or_by_id():
    w = Wire()
    ui = UI(w)
    run(ui, "show_card", {"title": "a", "body": "b"})
    first = w.sent[-1][1]["id"]
    run(ui, "show_choices", {"prompt": "Which?", "options": ["One", "Two"]})
    second = w.sent[-1][1]["id"]
    run(ui, "dismiss", {})
    assert w.sent[-1] == ("dismiss_panel", {"id": second, "reason": "claude"})
    run(ui, "dismiss", {"id": first})
    assert w.sent[-1][1]["id"] == first


def test_server_builds():
    assert UI(Wire()).server() is not None
