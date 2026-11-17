from zoe_core.speech import SentenceSplitter


def test_streams_sentences_as_they_end():
    s = SentenceSplitter()
    assert s.feed("You have three meetings this aft") == []
    assert s.feed("ernoon. The first is at two. ") == ["You have three meetings this afternoon.", "The first is at two."]
    assert s.feed("Then a sync at four") == []
    assert s.flush() == ["Then a sync at four"]


def test_short_fragments_and_abbreviations_wait():
    s = SentenceSplitter()
    assert s.feed("Yes. ") == []                     # too short to speak alone
    assert s.feed("Use a tool, e.g. ") == []          # abbreviation isn't an end
    assert s.feed("the calendar, to check. Done") == ["Yes. Use a tool, e.g. the calendar, to check."]


def test_newlines_end_sentences():
    s = SentenceSplitter()
    assert s.feed("Here is the summary line\n\nDetails follow") == ["Here is the summary line"]
