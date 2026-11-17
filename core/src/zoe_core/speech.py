"""Turn a stream of text deltas into speakable sentences.

Each complete sentence is emitted as soon as it ends, so the app can start speaking the first one while
Claude is still writing the rest.
"""
from __future__ import annotations

import re

# A sentence ends at . ! ? or : followed by whitespace, or at a line break. Short fragments wait for more.
_END = re.compile(r"(?<=[.!?:])\s+|\n+")
_ABBREV = re.compile(r"\b(e\.g|i\.e|etc|vs|Mr|Mrs|Ms|Dr|St|No)\.$", re.IGNORECASE)
MIN_CHARS = 12


class SentenceSplitter:
    def __init__(self) -> None:
        self.buf = ""

    def feed(self, delta: str) -> list[str]:
        self.buf += delta
        out: list[str] = []
        start = 0
        for m in _END.finditer(self.buf):
            candidate = self.buf[start:m.start()].strip()
            if len(candidate) < MIN_CHARS or _ABBREV.search(candidate):
                continue
            out.append(candidate)
            start = m.end()
        self.buf = self.buf[start:]
        return out

    def flush(self) -> list[str]:
        rest, self.buf = self.buf.strip(), ""
        return [rest] if rest else []
