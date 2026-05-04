"""
EntityService — entity CRUD, fuzzy matching, event/conflict/task/highlight persistence.
Uses db_final schema: entities, entity_attributes, entity_relations, highlights, events, tasks.
"""

import unicodedata
from datetime import datetime
from difflib import SequenceMatcher
from typing import Dict, List, Optional

from app.database import db

_TITLE_PREFIXES = frozenset([
    "mr", "mrs", "ms", "miss", "dr", "prof", "rev", "sir",
    "lord", "lady", "mx", "eng", "capt", "maj", "col", "gen",
])

_RELATION_ALIASES: Dict[str, str] = {
    "employed by": "works at",
    "is employed by": "works at",
    "is an employee of": "works at",
    "is employed at": "works at",
    "works for": "works at",
    "is a member of": "member of",
    "belongs to": "member of",
    "is located in": "located in",
    "is based in": "located in",
    "based in": "located in",
    "is situated in": "located in",
    "is the founder of": "founded",
    "co-founded": "founded",
    "co founded": "founded",
    "is married to": "married to",
    "is wed to": "married to",
    "is the parent of": "is parent of",
    "is the child of": "is child of",
    "is a subsidiary of": "subsidiary of",
    "is owned by": "owned by",
    "is part of": "part of",
    "is affiliated with": "affiliated with",
}


class EntityService:
    """Persists structured entity data to SQL tables."""

    def __init__(self):
        print("✅ Entity Service: Initialized")

    # ── Name / Relation Normalisation ────────────────────────────────────────

    @staticmethod
    def _normalize_name(name: str) -> str:
        """Strip accents, honorifics, and lowercase for dedup comparison.

        'Dr. José Smith' → 'jose smith', 'Mr. Ahmad' → 'ahmad'
        Used only for comparison — does not change what is stored in the DB.
        """
        nfkd = unicodedata.normalize("NFKD", name)
        ascii_name = "".join(c for c in nfkd if not unicodedata.combining(c))
        words = ascii_name.strip().lower().split()
        while words and words[0].rstrip(".") in _TITLE_PREFIXES:
            words = words[1:]
        return " ".join(words) if words else ascii_name.strip().lower()

    @staticmethod
    def _normalize_relation(relation: str) -> str:
        """Lowercase and map synonym phrases to canonical verb forms.

        Prevents 'employed by' and 'works at' from creating duplicate relation rows.
        """
        normalized = relation.strip().lower()
        return _RELATION_ALIASES.get(normalized, normalized)

    # ── Fuzzy Matching ────────────────────────────────────────────────────────

    def _find_fuzzy_match(self, user_id: str, canonical: str) -> Optional[str]:
        """Return entity_id if a similar entity exists.

        Compares unicode-normalised, honorific-stripped forms of both sides so
        'Dr. Ahmad' matches 'Ahmad', 'José' matches 'Jose', and common name
        spelling variants ('Ahmad'/'Ahmed') are caught. Threshold is adaptive:
        shorter names use a slightly lower bar without sacrificing precision on
        longer strings.
        """
        if not db:
            return None
        try:
            res = (
                db.table("entities")
                .select("id, canonical_name")
                .eq("user_id", user_id)
                .execute()
            )
            norm_input = self._normalize_name(canonical)
            threshold = 0.78 if len(norm_input) < 6 else 0.82
            best_id, best_ratio = None, 0.0
            for ent in res.data or []:
                norm_existing = self._normalize_name(ent["canonical_name"])
                ratio = SequenceMatcher(None, norm_input, norm_existing).ratio()
                if ratio > best_ratio:
                    best_ratio = ratio
                    best_id = ent["id"]
            if best_ratio >= threshold:
                print(
                    f"🔁 Entity dedup: '{canonical}' matched existing "
                    f"(ratio={best_ratio:.2f})"
                )
                return best_id
        except Exception as e:
            print(f"❌ Entity Service Error in fuzzy match: {e}")
        return None

    # ── Entity Upsert ─────────────────────────────────────────────────────────

    def _upsert_entity(
        self,
        user_id: str,
        name: str,
        entity_type: str,
        description: str = None,
    ) -> Optional[str]:
        """Upsert an entity by canonical name. Returns entity UUID."""
        if not db or not name.strip():
            return None
        canonical = name.strip().lower()
        display = name.strip()
        try:
            existing = (
                db.table("entities")
                .select("id, mention_count")
                .eq("user_id", user_id)
                .eq("canonical_name", canonical)
                .execute()
            )
            if existing.data:
                entity_id = existing.data[0]["id"]
                db.table("entities").update(
                    {
                        "last_seen_at": datetime.now().isoformat(),
                        "mention_count": (existing.data[0].get("mention_count", 1) or 1)
                        + 1,
                    }
                ).eq("id", entity_id).execute()
                return entity_id
            else:
                # Check for near-duplicate before inserting
                fuzzy_id = self._find_fuzzy_match(user_id, canonical)
                if fuzzy_id:
                    db.table("entities").update(
                        {"last_seen_at": datetime.now().isoformat()}
                    ).eq("id", fuzzy_id).execute()
                    return fuzzy_id

                valid_types = (
                    "person",
                    "place",
                    "organization",
                    "event",
                    "object",
                    "concept",
                )
                row = {
                    "user_id": user_id,
                    "canonical_name": canonical,
                    "display_name": display,
                    "entity_type": entity_type if entity_type in valid_types else "person",
                }
                if description:
                    row["description"] = description
                result = db.table("entities").insert(row).execute()
                return result.data[0]["id"] if result.data else None
        except Exception as e:
            print(f"❌ Entity Service Error upserting entity '{name}': {e}")
            return None

    def _upsert_attributes(
        self, entity_id: str, attributes: dict, source_session: str = None
    ):
        """Upsert key-value attributes for an entity."""
        if not db or not attributes:
            return
        for key, value in attributes.items():
            if not key or value is None:
                continue
            try:
                row = {
                    "entity_id": entity_id,
                    "attribute_key": str(key),
                    "attribute_value": str(value),
                    "updated_at": datetime.now().isoformat(),
                }
                if source_session:
                    row["source_session"] = source_session
                    row["source_session_id"] = source_session
                db.table("entity_attributes").upsert(
                    row, on_conflict="entity_id,attribute_key"
                ).execute()
            except Exception as e:
                print(f"❌ Entity Service Error upserting attribute '{key}': {e}")

    def _upsert_relation(
        self,
        user_id: str,
        source_id: str,
        target_id: str,
        relation: str,
        source_session: str = None,
    ):
        """Upsert a directed edge between two entities."""
        if not db or not source_id or not target_id:
            return
        try:
            row = {
                "user_id": user_id,
                "source_id": source_id,
                "target_id": target_id,
                "relation": self._normalize_relation(relation),
                "updated_at": datetime.now().isoformat(),
            }
            if source_session:
                row["source_session"] = source_session
            db.table("entity_relations").upsert(
                row, on_conflict="source_id,target_id,relation"
            ).execute()
        except Exception as e:
            print(f"❌ Entity Service Error upserting relation '{relation}': {e}")

    # ── Entity Context ────────────────────────────────────────────────────────

    def get_entity_context(self, user_id: str, entity_id: str) -> str:
        """Compile a context string for a specific entity."""
        if not db:
            return ""
        try:
            ent_res = (
                db.table("entities")
                .select("*")
                .eq("id", entity_id)
                .eq("user_id", user_id)
                .execute()
            )
            if not ent_res.data:
                return ""
            entity = ent_res.data[0]

            attr_res = (
                db.table("entity_attributes")
                .select("attribute_key, attribute_value")
                .eq("entity_id", entity_id)
                .execute()
            )
            attrs_text = "\n".join(
                f"  - {a['attribute_key']}: {a['attribute_value']}"
                for a in (attr_res.data or [])
            )

            rel_res = (
                db.table("entity_relations")
                .select("relation, target_id")
                .eq("source_id", entity_id)
                .execute()
            )
            relations_text = ""
            if rel_res.data:
                target_ids = list({r["target_id"] for r in rel_res.data})
                tgt_res = (
                    db.table("entities")
                    .select("id, display_name")
                    .in_("id", target_ids)
                    .execute()
                )
                tgt_map = {
                    t["id"]: t["display_name"] for t in (tgt_res.data or [])
                }
                rel_lines = [
                    f"  - {r['relation']}: {tgt_map.get(r['target_id'], r['target_id'])}"
                    for r in rel_res.data
                ]
                relations_text = "\n".join(rel_lines)

            entity_context = (
                f"Entity: {entity.get('display_name', entity['canonical_name'])} "
                f"({entity['entity_type']})\n"
                f"Description: {entity.get('description', '')}\n"
            )
            if attrs_text:
                entity_context += f"Attributes:\n{attrs_text}\n"
            if relations_text:
                entity_context += f"Relations:\n{relations_text}\n"
            return entity_context
        except Exception as e:
            print(f"❌ Entity Service Error getting context: {e}")
            return ""

    # ── Batch Persistence ─────────────────────────────────────────────────────

    def persist_extraction(
        self, user_id: str, extraction: dict, source_session: str = None
    ):
        """Persist a full extraction payload with rollback on failure."""
        if not db:
            return
        entity_name_to_id: Dict[str, str] = {}
        created_entity_ids: List[str] = []

        try:
            # Upsert all entities
            for ent in extraction.get("entities", []):
                name = ent.get("name", "").strip()
                if not name:
                    continue
                entity_id = self._upsert_entity(
                    user_id, name, ent.get("type", "person"), ent.get("description")
                )
                if entity_id:
                    entity_name_to_id[name.lower()] = entity_id
                    created_entity_ids.append(entity_id)
                    self._upsert_attributes(
                        entity_id, ent.get("attributes", {}), source_session
                    )

            # Upsert all relations
            for rel in extraction.get("relations", []):
                src_name = rel.get("source", "").strip().lower()
                tgt_name = rel.get("target", "").strip().lower()
                relation = rel.get("relation", "").strip()
                if not src_name or not tgt_name or not relation:
                    continue

                if src_name not in entity_name_to_id:
                    eid = self._upsert_entity(user_id, rel["source"], "concept")
                    if eid:
                        entity_name_to_id[src_name] = eid
                        created_entity_ids.append(eid)
                if tgt_name not in entity_name_to_id:
                    eid = self._upsert_entity(user_id, rel["target"], "concept")
                    if eid:
                        entity_name_to_id[tgt_name] = eid
                        created_entity_ids.append(eid)

                src_id = entity_name_to_id.get(src_name)
                tgt_id = entity_name_to_id.get(tgt_name)
                if src_id and tgt_id:
                    self._upsert_relation(
                        user_id, src_id, tgt_id, relation, source_session
                    )

            if entity_name_to_id:
                print(
                    f"✅ Entity Service: Persisted {len(entity_name_to_id)} "
                    f"entities for user {user_id}"
                )
        except Exception as e:
            print(f"❌ Entity Service: persist_extraction FAILED: {e}")
            print(f"   Rolling back {len(created_entity_ids)} orphaned entities...")
            for eid in created_entity_ids:
                try:
                    db.table("entity_attributes").delete().eq("entity_id", eid).execute()
                    db.table("entity_relations").delete().eq("source_id", eid).execute()
                    db.table("entity_relations").delete().eq("target_id", eid).execute()
                    db.table("entities").delete().eq("id", eid).execute()
                except Exception as cleanup_err:
                    print(f"   ⚠️ Rollback error for entity {eid}: {cleanup_err}")

    # ── Conflicts & Events ────────────────────────────────────────────────────

    def save_conflicts(
        self, user_id: str, conflicts: List[dict], session_id: str = None
    ):
        """Write conflict highlights to the highlights table."""
        if not db or not conflicts:
            return
        try:
            rows = []
            for c in conflicts:
                row = {
                    "user_id": user_id,
                    "highlight_type": "conflict",
                    "title": c.get("title", "Conflicting information detected"),
                    "body": c.get("body", ""),
                    "content": c.get("body", c.get("title", "")),
                }
                if session_id:
                    row["session_id"] = session_id
                rows.append(row)
            if rows:
                db.table("highlights").insert(rows).execute()
                print(
                    f"⚠️ Entity Service: Saved {len(rows)} conflict(s) for {user_id}"
                )
        except Exception as e:
            print(f"❌ Entity Service Error saving conflicts: {e}")

    def save_events(
        self, user_id: str, events: List[dict], session_id: str = None
    ):
        """Write extracted calendar events to the events table."""
        if not db or not events:
            return
        try:
            rows = []
            for ev in events:
                row = {
                    "user_id": user_id,
                    "title": ev.get("title", ""),
                    "due_text": ev.get("due_text"),
                    "description": ev.get("description"),
                }
                if session_id:
                    row["session_id"] = session_id
                rows.append(row)
            if rows:
                db.table("events").insert(rows).execute()
                print(
                    f"📅 Entity Service: Saved {len(rows)} event(s) for {user_id}"
                )
        except Exception as e:
            print(f"❌ Entity Service Error saving events: {e}")

    # ── Tasks ─────────────────────────────────────────────────────────────────

    def save_tasks(
        self, user_id: str, tasks: List[dict], session_id: str = None
    ):
        """Write extracted action items/tasks to the tasks table."""
        if not db or not tasks:
            return
        try:
            rows = []
            for t in tasks:
                row = {
                    "user_id": user_id,
                    "title": t.get("title", ""),
                    "status": "pending",
                }
                if t.get("description"):
                    row["description"] = t["description"]
                priority = t.get("priority", "medium")
                if priority in ("low", "medium", "high", "urgent"):
                    row["priority"] = priority
                else:
                    row["priority"] = "medium"
                if session_id:
                    row["source_session_id"] = session_id
                rows.append(row)
            if rows:
                db.table("tasks").insert(rows).execute()
                print(
                    f"✅ Entity Service: Saved {len(rows)} task(s) for {user_id}"
                )
        except Exception as e:
            print(f"❌ Entity Service Error saving tasks: {e}")

    # ── Highlights ────────────────────────────────────────────────────────────

    def save_highlights(
        self, user_id: str, highlights: List[dict], session_id: str = None
    ):
        """Write extracted highlights (insights, action_items, key_facts) to highlights table."""
        if not db or not highlights:
            return
        try:
            rows = []
            for h in highlights:
                hl_type = h.get("type", "insight")
                valid_types = ("conflict", "action_item", "insight", "key_fact")
                if hl_type not in valid_types:
                    hl_type = "insight"
                row = {
                    "user_id": user_id,
                    "highlight_type": hl_type,
                    "title": h.get("title", ""),
                    "body": h.get("body", ""),
                    "content": h.get("body", h.get("title", "")),
                }
                if session_id:
                    row["session_id"] = session_id
                rows.append(row)
            if rows:
                db.table("highlights").insert(rows).execute()
                print(
                    f"💡 Entity Service: Saved {len(rows)} highlight(s) for {user_id}"
                )
        except Exception as e:
            print(f"❌ Entity Service Error saving highlights: {e}")
