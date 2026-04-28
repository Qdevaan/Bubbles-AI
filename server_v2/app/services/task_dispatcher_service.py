"""
TaskDispatcherService — personalizes conversation mission briefs after each session.

After a session ends, fetches the user's today-assigned conversation quests and
rewrites their brief using the user's real entities and recent highlights.
Updates user_quests.brief_state.personalized_brief with the LLM-generated content.

Never raises. Fire-and-forget safe.
"""
import asyncio
import json
import logging
from datetime import date
from typing import Any

from groq import AsyncGroq

from app.config import settings
from app.database import db

logger = logging.getLogger(__name__)

_BRIEF_MODEL = "llama-3.1-8b-instant"

_SYSTEM_PROMPT = """\
You are a language coaching AI. Personalize a conversation mission brief for a specific user.

Given the generic mission brief, the user's known contacts and entities, and their recent \
session highlights, rewrite the scenario and context so it feels relevant to this user's \
actual conversations and relationships. Keep the mission goal and success criteria intact \
but ground the scenario in their real world.

Respond with valid JSON only:
{
  "scenario": "2-3 sentence personalized scenario using the user's actual entities",
  "context": "1-2 sentences of specific context for this user",
  "criteria": ["criterion 1", "criterion 2", "criterion 3"],
  "success_hint": "1 sentence practical tip targeting their weak area"
}"""


class TaskDispatcherService:
    def __init__(self):
        self.aclient = AsyncGroq(api_key=settings.GROQ_API_KEY)

    async def personalize_quest_briefs(self, user_id: str) -> None:
        """
        Personalize conversation mission briefs for today's assigned quests.
        Skips quests already personalized or without a brief template.
        """
        try:
            today = date.today().isoformat()

            quests_res = await asyncio.to_thread(
                lambda: db.from_("user_quests")
                .select("id, quest_id, brief_state")
                .eq("user_id", user_id)
                .eq("assigned_date", today)
                .execute()
            )
            if not quests_res.data:
                return

            quest_ids = [q["quest_id"] for q in quests_res.data]
            defs_res = await asyncio.to_thread(
                lambda: db.from_("quest_definitions")
                .select("id, brief, focus_area")
                .in_("id", quest_ids)
                .eq("mission_type", "conversation")
                .execute()
            )
            if not defs_res.data:
                return

            conv_def_map = {d["id"]: d for d in defs_res.data}
            # Only process quests that have a template brief and aren't yet personalized
            pending = [
                q for q in quests_res.data
                if q["quest_id"] in conv_def_map
                and conv_def_map[q["quest_id"]].get("brief")
                and not (q.get("brief_state") or {}).get("personalized_brief")
            ]
            if not pending:
                return

            # Fetch user context in parallel
            entities_res, highlights_res = await asyncio.gather(
                asyncio.to_thread(
                    lambda: db.from_("entities")
                    .select("name, entity_type, description")
                    .eq("user_id", user_id)
                    .limit(8)
                    .execute()
                ),
                asyncio.to_thread(
                    lambda: db.from_("highlights")
                    .select("title, body")
                    .eq("user_id", user_id)
                    .order("created_at", desc=True)
                    .limit(4)
                    .execute()
                ),
            )

            entity_lines = [
                f"{e['name']} ({e['entity_type']})"
                + (f": {e['description'][:80]}" if e.get("description") else "")
                for e in (entities_res.data or [])
            ]
            highlight_lines = [
                h.get("body") or h.get("title") or ""
                for h in (highlights_res.data or [])
            ]

            for quest in pending:
                defn = conv_def_map[quest["quest_id"]]
                personalized = await self._rewrite_brief(
                    brief=defn["brief"],
                    focus_area=defn.get("focus_area") or "engagement",
                    entities=entity_lines,
                    highlights=highlight_lines,
                )
                if not personalized:
                    continue

                new_state = {**(quest.get("brief_state") or {}), "personalized_brief": personalized}
                qid = quest["id"]
                await asyncio.to_thread(
                    lambda _qid=qid, _state=new_state: db.from_("user_quests")
                    .update({"brief_state": _state})
                    .eq("id", _qid)
                    .execute()
                )

        except Exception as exc:
            logger.warning("TaskDispatcher.personalize_quest_briefs(%s): %s", user_id, exc)

    async def _rewrite_brief(
        self,
        brief: dict,
        focus_area: str,
        entities: list[str],
        highlights: list[str],
    ) -> dict[str, Any] | None:
        try:
            user_msg = (
                f"Mission brief:\n{json.dumps(brief, indent=2)}\n\n"
                f"User entities: {', '.join(entities) if entities else 'none yet'}\n"
                f"Recent highlights: {'; '.join(h for h in highlights if h) or 'none'}\n"
                f"Target weak area: {focus_area}"
            )
            completion = await self.aclient.chat.completions.create(
                model=_BRIEF_MODEL,
                messages=[
                    {"role": "system", "content": _SYSTEM_PROMPT},
                    {"role": "user", "content": user_msg},
                ],
                response_format={"type": "json_object"},
                temperature=0.7,
                max_tokens=350,
            )
            return json.loads(completion.choices[0].message.content.strip())
        except Exception as exc:
            logger.warning("TaskDispatcher._rewrite_brief failed: %s", exc)
            return None
