"""Unit tests for the pure transcript parser."""

from __future__ import annotations

from bubbles.core.transcript import TranscriptStats, parse_transcript


def test_empty_transcript_is_all_zeros() -> None:
    assert parse_transcript("") == TranscriptStats(0, 0, 0, 0, 0, 0, 0)
    assert parse_transcript("   \n  \n") == TranscriptStats(0, 0, 0, 0, 0, 0, 0)


def test_single_user_line() -> None:
    s = parse_transcript("User: hello there friend")
    assert s.total_turns == 1
    assert s.user_turns == 1
    assert s.others_turns == 0
    assert s.llm_turns == 0
    assert s.user_words == 3


def test_mixed_speakers() -> None:
    text = "\n".join(
        [
            "User: hi how are you",  # 4 user words
            "AI: I am well thanks",  # 4 assistant words
            "Alice: nice to meet you both",  # 5 others words
            "User: same here",  # 2 user words
        ]
    )
    s = parse_transcript(text)
    assert s.total_turns == 4
    assert s.user_turns == 2
    assert s.llm_turns == 1
    assert s.others_turns == 1
    assert s.user_words == 6
    assert s.assistant_words == 4
    assert s.others_words == 5


def test_continuation_lines_attach_to_previous_turn() -> None:
    text = "User: first part\nand second part\nAI: reply"
    s = parse_transcript(text)
    assert s.total_turns == 2
    assert s.user_turns == 1
    assert s.user_words == 5  # "first part and second part"
    assert s.llm_turns == 1
    assert s.assistant_words == 1


def test_leading_continuation_with_no_speaker_is_ignored() -> None:
    # Lines before any speaker prefix have nowhere to attach -> dropped.
    s = parse_transcript("just some preamble text\nUser: real turn")
    assert s.total_turns == 1
    assert s.user_turns == 1
    assert s.user_words == 2


def test_assistant_aliases_classified_as_llm() -> None:
    for name in ("Assistant", "ai", "Bubbles", "AI"):
        s = parse_transcript(f"{name}: one two three")
        assert s.llm_turns == 1, name
        assert s.assistant_words == 3, name


def test_user_aliases_classified_as_user() -> None:
    for name in ("User", "me", "You", "user"):
        s = parse_transcript(f"{name}: alpha beta")
        assert s.user_turns == 1, name
        assert s.user_words == 2, name


def test_long_speaker_label_is_treated_as_content_not_prefix() -> None:
    # A "prefix" longer than 40 chars before the colon is not a speaker.
    long_label = "x" * 50
    s = parse_transcript(f"{long_label}: hello")
    assert s.total_turns == 0


def test_extra_whitespace_around_speaker_and_content() -> None:
    s = parse_transcript("  User  :   spaced   out   words  ")
    assert s.user_turns == 1
    assert s.user_words == 3


def test_url_lines_are_not_parsed_as_speakers() -> None:
    # "https://..." must not be read as speaker "https" (H14 nit).
    s = parse_transcript("User: see this\nhttps://example.com/path?x=1\nMore notes here.")
    assert s.user_turns == 1
    # The URL line and the trailing note are continuations of the user turn.
    assert s.others_turns == 0
    assert s.total_turns == 1


def test_real_speaker_with_colon_in_content_still_works() -> None:
    s = parse_transcript("AI: note: bring the report tomorrow")
    assert s.llm_turns == 1
    assert s.assistant_words == 5  # "note: bring the report tomorrow"
