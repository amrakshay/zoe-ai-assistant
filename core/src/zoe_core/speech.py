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
    """Sentences from streamed text. After each `feed`/`flush`, `breaks` says, per returned sentence,
    whether a blank line (a new paragraph) came before it."""

    def __init__(self) -> None:
        self.buf = ""
        self.breaks: list[bool] = []
        self._para = False

    def feed(self, delta: str) -> list[str]:
        self.buf += delta
        out: list[str] = []
        self.breaks = []
        start = 0
        for m in _END.finditer(self.buf):
            candidate = self.buf[start:m.start()].strip()
            if not candidate:                       # leading separator: remember a blank line
                self._para = self._para or m.group().count("\n") >= 2
                start = m.end()
                continue
            if len(candidate) < MIN_CHARS or _ABBREV.search(candidate):
                continue
            out.append(candidate)
            self.breaks.append(self._para or _BLANK.search(candidate) is not None)
            self._para = m.group().count("\n") >= 2
            start = m.end()
        self.buf = self.buf[start:]
        return out

    def flush(self) -> list[str]:
        rest, self.buf = self.buf.strip(), ""
        self.breaks = [self._para] if rest else []
        self._para = False
        return [rest] if rest else []


_BLANK = re.compile(r"\n\s*\n")

# Lines that are for the screen, never read aloud (§5.12): code, tables, list items, headings, links.
_UNSPEAKABLE = re.compile(
    r"^\s*(```|\||[-*+•]\s|\d+[.)]\s|#{1,6}\s|>\s)|https?://|`[^`]+`|\]\(")

ON_SCREEN = "The details are on screen."
QUIET_ON = re.compile(r"^\W*(?:zoe,? )?(?:quiet mode|go quiet|be quiet|silent mode|mute yourself|stop talking)\W*$", re.I)
QUIET_OFF = re.compile(r"^\W*(?:zoe,? )?(?:talk to me again|voice mode|unmute|you can talk again|speak again)\W*$", re.I)
ALL_ON_SCREEN = "The answer is on screen."
READ_ALL = re.compile(r"^\W*(read (it|that|this) (all|out)|read (it )?all|read (me )?(the whole thing|everything))\W*$", re.I)


def speakable(sentence: str) -> bool:
    return not _UNSPEAKABLE.search(sentence)


def words(s: str) -> int:
    return len(s.split())


class SpokenReply:
    """Decides which sentences of a streamed reply are spoken (PLAN.md §5.12).

    Speaks the opening paragraph, up to `max_sentences` and about `max_words`; stops at the first
    paragraph break, list, code block, table or link. If anything was held back, `finish()` adds
    "The details are on screen." The full text always goes to the bubble.
    """

    def __init__(self, max_sentences: int = 3, max_words: int = 50, cap: bool = True) -> None:
        self.max_sentences, self.max_words, self.cap = max_sentences, max_words, cap
        self.spoken: list[str] = []
        self.held_back = False
        self.done = False           # stopped speaking this reply
        self._in_code = False

    def offer(self, sentence: str, new_paragraph: bool = False) -> str | None:
        """Returns the sentence if it should be spoken now, else None."""
        if sentence.lstrip().startswith("```"):
            self._in_code = not self._in_code if sentence.count("```") % 2 else self._in_code
            self.held_back = True
            if self.cap and self.spoken:
                self.done = True
            return None
        if self._in_code or not speakable(sentence):
            self.held_back = True
            if self.cap and self.spoken:
                self.done = True
            return None
        if self.done:
            self.held_back = True
            return None
        if self.cap and self.spoken and (
            new_paragraph
            or len(self.spoken) >= self.max_sentences
            or sum(map(words, self.spoken)) + words(sentence) > self.max_words
        ):
            self.done = True
            self.held_back = True
            return None
        self.spoken.append(sentence)
        return sentence

    def finish(self) -> list[str]:
        if not self.held_back:
            return []
        return [ON_SCREEN] if self.spoken else [ALL_ON_SCREEN]
