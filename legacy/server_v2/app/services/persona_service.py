# Purpose: Fetches and caches user Performa persona profiles from Supabase for prompt construction.
"""Persona service -- typed performa CRUD + role-family classification."""

import time
from datetime import datetime, timezone
from typing import Final, Optional

from app.models.persona import UserPersona, UserPersonaUpdate


_ROLE_FAMILY_MAP: Final[dict[str, str]] = {
    "teacher": "educator",
    "student": "learner",
    "professional": "professional",
    "manager": "professional",
    "freelancer": "professional",
    "homemaker": "casual",
}


def classify_role_family(role_primary: str) -> str:
    """Pure mapping: role_primary -> role_family.

    Unknown values (including 'other') fall back to 'default'."""
    return _ROLE_FAMILY_MAP.get(role_primary, "default")


_TABLE = "user_personas"
_CACHE_TTL_SECONDS = 300  # 5 minutes


class PersonaService:
    def __init__(self, db):
        self._db = db
        # cache: user_id (str) -> (expires_at_epoch, UserPersona)
        self._cache: dict[str, tuple[float, UserPersona]] = {}

    def _is_complete(self, payload: dict) -> bool:
        return all(payload.get(k) for k in ("role_primary", "native_language", "learning_language"))

    def _from_row(self, row: dict) -> UserPersona:
        return UserPersona.model_validate(row)

    def get(self, user_id: str) -> Optional[UserPersona]:
        now = time.time()
        cached = self._cache.get(user_id)
        if cached and cached[0] > now:
            return cached[1]

        resp = (
            self._db.table(_TABLE)
            .select("*")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        if not resp or not resp.data:
            return None
        persona = self._from_row(resp.data)
        self._cache[user_id] = (now + _CACHE_TTL_SECONDS, persona)
        return persona

    def upsert(self, user_id: str, update: UserPersonaUpdate) -> UserPersona:
        existing = self.get(user_id)
        existing_dict = existing.model_dump(mode="json") if existing else {}

        merged = {**existing_dict, **update.model_dump(exclude_unset=True)}
        merged["user_id"] = user_id

        if merged.get("role_primary"):
            merged["role_family"] = classify_role_family(merged["role_primary"])
        else:
            merged.setdefault("role_family", "default")

        if (existing is None or existing.completed_at is None) and self._is_complete(merged):
            merged["completed_at"] = datetime.now(timezone.utc).isoformat()

        resp = self._db.table(_TABLE).upsert(merged).execute()
        row = resp.data[0] if resp.data else merged
        # Defensive: ensure returned row's role_family stays consistent with role_primary.
        if row.get("role_primary"):
            row = {**row, "role_family": classify_role_family(row["role_primary"])}
        persona = self._from_row(row)
        self._cache[user_id] = (time.time() + _CACHE_TTL_SECONDS, persona)
        return persona

    def invalidate(self, user_id: str) -> None:
        self._cache.pop(user_id, None)
