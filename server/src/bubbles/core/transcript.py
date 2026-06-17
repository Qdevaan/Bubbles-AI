# Purpose: Transcript normalisation: strips filler words, merges diarised speaker turns, and caps chunk length.
"""Pure transcript parsing — turn/word counts from a plain-text transcript.

v5 does not persist per-turn ``session_logs``; the post-session worker only
receives the accumulated transcript string. Speaker roles are inferred from
``Speaker: text`` line prefixes (the same shape v5's wingman prompts render).
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_SPEAKER_RE = re.compile(r"^\s*([^:]{1,40}?)\s*:\s*(.*)$")
# Lines that *look* like ``prefix: rest`` but are URLs / scheme strings, e.g.
# ``https://example.com`` — without this guard the speaker would be parsed as
# "https". A real speaker prefix is plain text with no slashes; the URL form is
# ``scheme://…`` with no space after the colon.
_URL_LIKE_RE = re.compile(r"^\s*[A-Za-z][A-Za-z0-9+.\-]*://")
_USER_NAMES = frozenset({"user", "me", "you"})
_LLM_NAMES = frozenset({"ai", "assistant", "bubbles"})


@dataclass(frozen=True, slots=True)
class TranscriptStats:
    total_turns: int
    user_turns: int
    others_turns: int
    llm_turns: int
    user_words: int
    assistant_words: int
    others_words: int


def _word_count(text: str) -> int:
    return len(text.split())


def parse_transcript(transcript: str) -> TranscriptStats:
    # role -> list of content fragments for the current open turn
    turns: list[tuple[str, list[str]]] = []
    for raw_line in transcript.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        m = None if _URL_LIKE_RE.match(line) else _SPEAKER_RE.match(line)
        if m is not None:
            speaker = m.group(1).strip().lower()
            content = m.group(2)
            if speaker in _USER_NAMES:
                role = "user"
            elif speaker in _LLM_NAMES:
                role = "llm"
            else:
                role = "others"
            turns.append((role, [content] if content else []))
        elif turns:
            turns[-1][1].append(line.strip())
        # else: continuation before any speaker -> dropped

    total = user_t = others_t = llm_t = 0
    user_w = asst_w = others_w = 0
    for role, fragments in turns:
        total += 1
        wc = sum(_word_count(f) for f in fragments)
        if role == "user":
            user_t += 1
            user_w += wc
        elif role == "llm":
            llm_t += 1
            asst_w += wc
        else:
            others_t += 1
            others_w += wc
    return TranscriptStats(total, user_t, others_t, llm_t, user_w, asst_w, others_w)
