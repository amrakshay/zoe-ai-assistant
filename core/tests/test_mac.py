"""The mac tool server (#45)."""
import asyncio

import pytest

from zoe_core.gate import ApprovalRequest
from zoe_core.mac import EXACT_NAMES, InputError, check, handle
from zoe_core.policy import Policy, decide
from zoe_core.renderers import render
from zoe_core.taint import Taint


def test_every_mac_tool_asks_by_exact_name():
    for n in EXACT_NAMES:
        assert decide(n, {}).policy is Policy.ASK
    assert decide("mcp__mac__open_app_and_delete", {}).policy is not Policy.ALLOW


def test_open_url_needs_a_click_once_tainted():
    t = Taint()
    d = decide("mcp__mac__open_url", {"url": "https://x.example"})
    assert t.adjust("mcp__mac__open_url", {}, d).policy is Policy.ASK
    t.mark("your screen")
    assert t.adjust("mcp__mac__open_url", {}, d).policy is Policy.CLICK


def test_clipboard_read_taints_other_mac_tools_dont():
    t = Taint()
    t.observe("mcp__mac__open_app")
    assert not t.tainted
    t.observe("mcp__mac__get_clipboard")
    assert "your clipboard" in t.sources


@pytest.mark.parametrize("tool,args", [
    ("open_app", {"name": "Calc; rm -rf ~"}), ("open_app", {"name": "-a"}), ("set_volume", {"percent": 101}),
    ("set_volume", {"percent": "loud"}), ("open_url", {"url": "file:///etc/passwd"}), ("open_url", {"url": "javascript:alert(1)"}),
    ("reveal_in_finder", {"path": "/no/such/path"}), ("set_clipboard", {"text": ""}),
])
def test_bad_input_is_refused(tool, args):
    with pytest.raises(InputError):
        check(tool, args)


def test_commands_are_argument_lists():
    assert check("open_app", {"name": "Calculator"}) == ["open", "-a", "Calculator"]
    assert check("open_url", {"url": "https://example.com/x?a=1"}) == ["open", "https://example.com/x?a=1"]
    assert check("notify", {"title": 'say "hi"', "body": "a\\\\b"})[0] == "osascript"


def test_cards_say_exactly_what_happens():
    c = render(ApprovalRequest("mcp__mac__open_url", {"url": "https://evil.example.net/a"}, Policy.CLICK, "why", "t"))
    assert c["title"] == "Open a web page?" and c["fields"][0]["value"] == "evil.example.net"
    c = render(ApprovalRequest("mcp__mac__set_clipboard", {"text": "secret plan"}, Policy.ASK, "why", "t"))
    assert c["fields"][0]["value"] == "secret plan"


def test_clipboard_round_trip_is_marked_untrusted():
    async def go():
        await handle("set_clipboard", {"text": "zoe clipboard test"})
        return await handle("get_clipboard", {})
    out = asyncio.run(go())["content"][0]["text"]
    assert "zoe clipboard test" in out and "untrusted" in out
