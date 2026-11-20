from zoe_core.speech import ALL_ON_SCREEN, ON_SCREEN, READ_ALL, SentenceSplitter, SpokenReply, speakable


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


def test_paragraph_breaks_are_reported():
    s = SentenceSplitter()
    assert s.feed("You have three meetings today.\n\nThe first one is at two. ") == [
        "You have three meetings today.", "The first one is at two."]
    assert s.breaks == [False, True]


def speak_all(text, **kw):
    s, r = SentenceSplitter(), SpokenReply(**kw)
    out = [x for sent, br in zip(s.feed(text), s.breaks) if (x := r.offer(sent, br))]
    out += [x for sent, br in zip(s.flush(), s.breaks) if (x := r.offer(sent, br))]
    return out + r.finish()


def test_short_answer_is_spoken_whole():
    assert speak_all("You have three meetings this afternoon. The first is at two.") == [
        "You have three meetings this afternoon.", "The first is at two."]


def test_details_after_a_blank_line_stay_on_screen():
    out = speak_all("You have three meetings this afternoon.\n\nAt two, a design review with the team. At four, a sync.")
    assert out == ["You have three meetings this afternoon.", ON_SCREEN]


def test_cap_at_three_sentences():
    text = " ".join(f"This is sentence number {n} of the reply." for n in range(1, 7))
    out = speak_all(text)
    assert len(out) == 4 and out[-1] == ON_SCREEN


def test_cap_at_about_fifty_words():
    long = "word " * 30
    out = speak_all(f"First sentence has {long.strip()}. Second one also has {long.strip()}. Third.")
    assert out[0].startswith("First") and out[1] == ON_SCREEN


def test_lists_code_and_links_are_not_read():
    out = speak_all("Here are the failing pods in the cluster.\n- pod-a is crashing\n- pod-b is pending\n")
    assert out == ["Here are the failing pods in the cluster.", ON_SCREEN]
    assert not speakable("See https://example.com/docs for more information.")
    assert not speakable("| name | status |")
    assert not speakable("Run `kubectl get pods` to check.")


def test_only_unspeakable_content_says_it_is_on_screen():
    assert speak_all("```\nprint('hi')\n```\n") == [ALL_ON_SCREEN]


def test_read_it_all_has_no_cap():
    text = " ".join(f"This is sentence number {n} of the reply." for n in range(1, 7))
    assert len(speak_all(text, cap=False)) == 6


def test_read_all_phrases():
    for p in ["Read it all", "read it all.", "Read me the whole thing", "read everything"]:
        assert READ_ALL.match(p), p
    assert not READ_ALL.match("read my email")
