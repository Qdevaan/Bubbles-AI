"""
SessionService — session lifecycle, turn logging, consultant history.
Uses the unified db_final schema (sessions, session_logs, consultant_logs, sentiment_logs).
Every action records all available schema columns.
"""

import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from app.database import db


class SessionService:
    """Creates sessions, logs turns, fetches history."""

    def __init__(self):
        print("✅ Session Service: Initialized")

    # ── Session Creation ──────────────────────────────────────────────────────

    def start_session(
        self,
        user_id: str,
        mode: str = "live_wingman",
        is_ephemeral: bool = False,
        is_multiplayer: bool = False,
        persona: str = "casual",
        device_id: str = None,
        session_type: str = None,
        idempotency_key: str = None,
    ) -> str:
        """Create a new session row and return its UUID."""
        if not db:
            return str(uuid.uuid4())

        # Ephemeral (incognito) sessions bypass DB entirely
        if is_ephemeral:
            session_id = str(uuid.uuid4())
            print(
                f"🕵️ Session Service: Started INCOGNITO session {session_id} "
                f"for user {user_id} (mode={mode}, persona={persona})"
            )
            return session_id

        try:
            row = {
                "user_id": user_id,
                "title": "Live Wingman Session",
                "session_type": session_type or mode,
                "mode": mode,
                "status": "active",
                "is_ephemeral": is_ephemeral,
                "is_multiplayer": is_multiplayer,
                "persona": persona,
            }
            if device_id:
                row["device_id"] = device_id
            if idempotency_key:
                row["idempotency_key"] = idempotency_key
            result = (
                db.table("sessions")
                .insert(row)
                .execute()
            )
            session_id = result.data[0]["id"]
            print(
                f"📝 Session Service: Started session {session_id} "
                f"for user {user_id} (mode={mode})"
            )
            return session_id
        except Exception as e:
            print(f"❌ Session Service Error starting session: {e}")
            return str(uuid.uuid4())

    def create_session_record(
        self,
        user_id: str,
        title: str = "New Conversation",
        summary: str = None,
        mode: str = "live_wingman",
        idempotency_key: str = None,
    ) -> str:
        """Create a session record and return its ID."""
        if not db:
            return str(uuid.uuid4())
        try:
            data = {
                "user_id": user_id,
                "title": title,
                "session_type": mode,
                "mode": mode,
                "status": "active",
            }
            if summary:
                data["summary"] = summary
            if idempotency_key:
                data["idempotency_key"] = idempotency_key
            result = db.table("sessions").insert(data).execute()
            if result.data:
                return result.data[0]["id"]
            return str(uuid.uuid4())
        except Exception as e:
            print(f"❌ Session Service Error creating session: {e}")
            return str(uuid.uuid4())

    # ── Turn Logging ──────────────────────────────────────────────────────────

    def log_message(
        self,
        session_id: str,
        role: str,
        content: str,
        speaker_label: str = None,
        confidence: float = None,
        is_ephemeral: bool = False,
        model_used: str = None,
        latency_ms: int = None,
        tokens_used: int = None,
        finish_reason: str = None,
        turn_index: int = None,
    ) -> Optional[Dict[str, Any]]:
        """Log a single message to session_logs with inline sentiment and LLM metadata."""
        if not db or not session_id or not content.strip():
            return None
        if is_ephemeral:
            return None

        try:
            # ── Inline sentiment analysis ─────────────────────────────────
            sentiment_score = 0.0
            sentiment_label = "neutral"

            lower_content = content.lower()
            positive_words = [
                "great", "awesome", "good", "happy", "love",
                "excited", "amazing", "perfect", "thanks", "glad",
            ]
            negative_words = [
                "bad", "angry", "hate", "terrible", "sad",
                "frustrated", "annoyed", "worst", "failed", "mad",
            ]

            pos_count = sum(lower_content.count(w) for w in positive_words)
            neg_count = sum(lower_content.count(w) for w in negative_words)

            if pos_count > neg_count:
                sentiment_score = min(0.4 * pos_count, 1.0)
                sentiment_label = "positive"
            elif neg_count > pos_count:
                sentiment_score = max(-0.4 * neg_count, -1.0)
                sentiment_label = "negative"

            # Stress & arousal inference
            fillers = [" um", " uh", " like", " literally", " you know"]
            filler_count = sum(lower_content.count(f) for f in fillers)
            arousal = content.count("!") + content.count("?")
            hesitation = content.count("-") + content.count("...")
            stress_level = min(
                (filler_count * 0.2) + (arousal * 0.1) + (hesitation * 0.2), 1.0
            )
            if stress_level > 0.5:
                sentiment_label += "_stressed"
            elif stress_level > 0.2:
                sentiment_label += "_tense"

            # ── Compute turn_index if not provided ────────────────────────
            if turn_index is None:
                try:
                    count_res = (
                        db.table("session_logs")
                        .select("id", count="exact")
                        .eq("session_id", session_id)
                        .execute()
                    )
                    turn_index = (count_res.count or 0) + 1
                except Exception:
                    turn_index = 0

            # ── Insert session_log row ────────────────────────────────────
            row = {
                "session_id": session_id,
                "role": role,
                "content": content.strip(),
                "turn_index": turn_index,
                "sentiment_score": sentiment_score,
                "sentiment_label": sentiment_label,
            }
            if speaker_label:
                row["speaker_label"] = speaker_label
            if confidence is not None:
                row["confidence"] = confidence
            if model_used:
                row["model_used"] = model_used
            if latency_ms is not None:
                row["latency_ms"] = latency_ms
            if tokens_used is not None:
                row["tokens_used"] = tokens_used
            if finish_reason:
                row["finish_reason"] = finish_reason

            res = db.table("session_logs").insert(row).execute()
            logged_row = res.data[0] if res.data else row

            # ── Write to sentiment_logs ───────────────────────────────────
            try:
                sess_res = (
                    db.table("sessions")
                    .select("user_id")
                    .eq("id", session_id)
                    .maybe_single()
                    .execute()
                )
                user_id = sess_res.data["user_id"] if sess_res.data else None
            except Exception:
                user_id = None

            if user_id and role in ["user", "others", "llm"]:
                sent_row = {
                    "session_id": session_id,
                    "user_id": user_id,
                    "turn_index": turn_index,
                    "speaker_role": role,
                    "sentiment_score": sentiment_score,
                    "score": sentiment_score,
                    "label": sentiment_label,
                }
                db.table("sentiment_logs").insert(sent_row).execute()

            return logged_row
        except Exception as e:
            print(f"❌ Session Service Error logging message: {e}")
            return None

    def log_batch_messages(
        self, session_id: str, logs: List[Dict[str, Any]], is_ephemeral: bool = False
    ):
        """Log a batch of messages to session_logs with sequential turn indices."""
        if not db or not logs or is_ephemeral:
            return
        try:
            db_logs = []
            for idx, log in enumerate(logs, start=1):
                role = log.get("speaker", "unknown").lower()
                content = log.get("text", "")
                if content:
                    db_logs.append(
                        {
                            "session_id": session_id,
                            "role": role,
                            "content": content,
                            "turn_index": idx,
                        }
                    )
            if db_logs:
                db.table("session_logs").insert(db_logs).execute()
                print(
                    f"📝 Session Service: Logged {len(db_logs)} messages "
                    f"for session {session_id}"
                )
        except Exception as e:
            print(f"❌ Session Service Error logging batch: {e}")

    # ── Session Completion ────────────────────────────────────────────────────

    def end_session(self, session_id: str, summary: str = None, is_ephemeral: bool = False):
        """Mark session as completed and update aggregate sentiment on session."""
        if not db or not session_id:
            return
        if is_ephemeral:
            print(f"🕵️ Session Service: Ephemeral session {session_id} ended")
            return
        try:
            update = {
                "status": "completed",
                "ended_at": datetime.now().isoformat(),
                "end_time": datetime.now().isoformat(),
            }
            if summary:
                update["summary"] = summary

            # Compute aggregate sentiment for the session
            try:
                sent_res = (
                    db.table("session_logs")
                    .select("sentiment_score")
                    .eq("session_id", session_id)
                    .not_.is_("sentiment_score", "null")
                    .execute()
                )
                scores = [
                    r["sentiment_score"]
                    for r in (sent_res.data or [])
                    if r.get("sentiment_score") is not None
                ]
                if scores:
                    update["sentiment_score"] = round(sum(scores) / len(scores), 4)
            except Exception as e:
                print(f"⚠️ Session Service: Could not compute aggregate sentiment: {e}")

            db.table("sessions").update(update).eq("id", session_id).execute()
            print(f"✅ Session Service: Session {session_id} marked completed")
        except Exception as e:
            print(f"❌ Session Service Error ending session: {e}")

    # ── Token Usage Tracking ──────────────────────────────────────────────────

    def update_session_token_usage(
        self,
        session_id: str,
        tokens_prompt: int = 0,
        tokens_completion: int = 0,
    ):
        """Increment token usage counters on a session."""
        if not db or not session_id or (tokens_prompt == 0 and tokens_completion == 0):
            return
        try:
            # Fetch current values
            res = (
                db.table("sessions")
                .select("token_usage_prompt, token_usage_completion, total_cost_usd")
                .eq("id", session_id)
                .maybe_single()
                .execute()
            )
            current = res.data or {}
            new_prompt = (current.get("token_usage_prompt") or 0) + tokens_prompt
            new_completion = (current.get("token_usage_completion") or 0) + tokens_completion
            # Rough cost estimate: $0.05 per 1M tokens for fast models
            cost_delta = ((tokens_prompt + tokens_completion) / 1_000_000) * 0.05
            new_cost = (current.get("total_cost_usd") or 0) + cost_delta

            db.table("sessions").update({
                "token_usage_prompt": new_prompt,
                "token_usage_completion": new_completion,
                "total_cost_usd": round(new_cost, 6),
            }).eq("id", session_id).execute()
        except Exception as e:
            print(f"⚠️ Session Service: Token usage update failed: {e}")

    # ── Consultant History ────────────────────────────────────────────────────

    def log_consultant_qa(
        self, user_id: str, question: str, answer: str, session_id: str = None,
        is_ephemeral: bool = False,
        model_used: str = None, latency_ms: int = None, tokens_used: int = None,
        source_screen: str = None,
    ):
        """Log Q&A to consultant_logs and session_logs with full metadata."""
        if not db or is_ephemeral:
            return
        try:
            row = {
                "user_id": user_id,
                "question": question,
                "answer": answer,
                "query": question,
                "response": answer,
                "session_id": session_id,
            }
            if source_screen:
                row["source_screen"] = source_screen
            db.table("consultant_logs").insert(row).execute()
            if session_id:
                self.log_message(session_id, "user", question)
                self.log_message(
                    session_id, "llm", answer,
                    model_used=model_used,
                    latency_ms=latency_ms,
                    tokens_used=tokens_used,
                )
            print(f"📝 Session Service: Logged consultant Q&A for {user_id}")
        except Exception as e:
            print(f"❌ Session Service Error logging consultant Q&A: {e}")

    def fetch_consultant_history(self, user_id: str, limit: int = 5, session_id: str = None) -> str:
        """Fetch recent Q&A pairs from consultant_logs for the current session only.
        Passing session_id restricts history to that session so memories don't bleed
        across unrelated conversations."""
        if not db:
            return "No past consultant history."
        try:
            query = (
                db.table("consultant_logs")
                .select("question, answer")
                .eq("user_id", user_id)
            )
            if session_id:
                query = query.eq("session_id", session_id)
            res = (
                query
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )
            history_lines = []
            for item in reversed(res.data):
                history_lines.append(f"Q: {item['question']}")
                history_lines.append(f"A: {item['answer']}")
            history_str = "\n".join(history_lines)
            return history_str if history_str else "No past consultant history."
        except Exception as e:
            print(f"❌ Session Service Error fetching consultant history: {e}")
            return "Error fetching past consultant history."

    def fetch_session_summaries(self, user_id: str, limit: int = 3) -> str:
        """Fetch recent completed session summaries."""
        if not db:
            return "No previous session summaries."
        try:
            res = (
                db.table("sessions")
                .select("title, summary, mode, created_at")
                .eq("user_id", user_id)
                .eq("status", "completed")
                .not_.is_("summary", "null")
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )
            if not res.data:
                return "No previous session summaries."
            lines = []
            for s in reversed(res.data):
                mode_tag = s.get("mode", "session").upper()
                title = s.get("title", "Session")
                summary = s.get("summary", "")
                if summary:
                    lines.append(f"[{mode_tag}] {title}: {summary}")
            return "\n".join(lines) if lines else "No previous session summaries."
        except Exception as e:
            print(f"❌ Session Service Error fetching summaries: {e}")
            return "No previous session summaries."

    def count_session_turns(self, session_id: str) -> int:
        """Return the number of turns logged for a session."""
        if not db or not session_id:
            return 0
        try:
            res = (
                db.table("session_logs")
                .select("id", count="exact")
                .eq("session_id", session_id)
                .execute()
            )
            return res.count or 0
        except Exception as e:
            print(f"❌ Session Service Error counting turns: {e}")
            return 0
