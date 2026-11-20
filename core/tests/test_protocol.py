import asyncio
import json

import pytest

from zoe_core.main import serve
from zoe_core.protocol import MAX_LINE, ProtocolError, decode, encode


def test_encode_is_one_line():
    line = encode("say", text="two\nlines")
    assert line.endswith(b"\n") and line.count(b"\n") == 1
    assert json.loads(line) == {"type": "say", "text": "two\nlines"}


@pytest.mark.parametrize("bad", [b"", b"   ", b"not json", b"[1,2]", b'{"no_type":1}', b'{"type":5}', b"\xff\xfe"])
def test_decode_rejects(bad):
    with pytest.raises(ProtocolError):
        decode(bad)


def test_decode_too_long():
    with pytest.raises(ProtocolError):
        decode(b"x" * (MAX_LINE + 1))


def run_lines(data: bytes) -> list[dict]:
    async def go():
        reader = asyncio.StreamReader(limit=MAX_LINE)
        reader.feed_data(data)
        reader.feed_eof()
        out: list[bytes] = []

        async def write(b: bytes) -> None:
            out.append(b)

        await serve(reader, write)
        return [json.loads(x) for x in out]

    return asyncio.run(go())


def test_handshake_ping_and_echo():
    msgs = run_lines(
        b'{"type":"hello"}\n{"type":"ping","id":7}\n'
        b'{"type":"utterance","id":"u1","text":"hi","trigger":"ptt"}\n'
    )
    types = [m["type"] for m in msgs]
    assert types == ["hello", "state", "pong", "state", "say", "state"]
    assert msgs[2]["id"] == 7
    assert msgs[4] == {"type": "say", "utterance_id": "u1", "text": "You said: hi", "final": True}


def test_bad_lines_do_not_stop_the_loop():
    msgs = run_lines(b'garbage\n{"type":"nope"}\n\n{"type":"ping","id":1}\n')
    assert [m["type"] for m in msgs] == ["error", "error", "pong"]


def test_shutdown_stops_and_partial_line_at_eof_is_dropped():
    assert [m["type"] for m in run_lines(b'{"type":"shutdown"}\n{"type":"ping"}\n')] == []
    assert run_lines(b'{"type":"ping"') == []


def test_known_future_messages_are_ignored():
    assert run_lines(b'{"type":"mute","on":true}\n') == []
