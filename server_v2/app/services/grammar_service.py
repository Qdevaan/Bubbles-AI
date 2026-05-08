"""Grammar/style detector using LanguageTool.

Env-toggle:
  - settings.LANGUAGETOOL_URL set  → POST to that URL (public API or self-host)
  - unset                          → embedded language_tool_python subprocess
                                     (requires Java JRE 8+)
"""
from __future__ import annotations

import asyncio
from typing import Any, Dict, List, Optional

import httpx

from app.config import settings
from app.services.prompt_loader import render_persona_block, render_scenario_header

# Lazy-resolved persona_svc -- the service singleton is created in
# app.services.__init__ AFTER this module is imported, so we cannot bind
# `persona_svc` at module load. Tests patch `app.services.grammar_service.persona_svc`
# to inject a mock; the proxy honours that by reading via getattr at call time.
import app.services as _services_pkg


class _PersonaSvcProxy:
    def get(self, user_id):
        svc = getattr(_services_pkg, "persona_svc", None)
        if svc is None:
            return None
        return svc.get(user_id)


persona_svc = _PersonaSvcProxy()


_DEFAULT_PERSONA_DICT: Dict[str, Any] = {
    "role_family": "default",
    "native_language": "en",
    "learning_language": "en",
    "formality_preference": "neutral",
}


_GRAMMAR_INSTRUCTIONS = (
    "You are a strict spoken-English reviewer. Identify filler words, awkward "
    "phrasing, repetition, and grammar/style issues. Output STRICT JSON with "
    "this shape: "
    '{"issues": [{"category": "...", "snippet": "exact phrase", '
    '"suggestion": "rewrite or empty"}]}. Empty list if nothing flagged.'
)


_CATEGORY_MAP = {
    "grammar": "grammar",
    "typos": "grammar",
    "typography": "grammar",
    "punctuation": "grammar",
    "redundancy": "word_choice",
    "collocations": "word_choice",
    "style": "style",
}


def _map_lt_category(raw: str) -> str:
    """LanguageTool category → internal category. Best-effort mapping."""
    if not raw:
        return "grammar"
    lower = raw.lower()
    if "agreement" in lower:
        return "agreement"
    if "tense" in lower or "verb" in lower:
        return "tense"
    if "article" in lower:
        return "article"
    if "prep" in lower:
        return "preposition"
    return _CATEGORY_MAP.get(lower, "grammar")


class GrammarService:
    def __init__(self):
        self._embedded: Optional[Any] = None  # lazy
        self._embedded_lock = asyncio.Lock()

    def build_check_prompt(
        self,
        user_id: Optional[str],
        text: str,
        session_context: Optional[dict] = None,
    ) -> str:
        """Compose a persona-aware grammar-check prompt.

        Even though grammar detection itself runs through LanguageTool today,
        downstream consumers (e.g. mistake-explanation LLM calls) need the
        same persona+scenario framing brain_service uses, so the helper lives
        here as the canonical builder for any LLM-mediated grammar prompt.
        """
        if user_id:
            try:
                persona = persona_svc.get(user_id)
            except Exception:  # pragma: no cover -- defensive
                persona = None
        else:
            persona = None

        if persona is None:
            persona_dict: Dict[str, Any] = dict(_DEFAULT_PERSONA_DICT)
        else:
            persona_dict = persona.model_dump(mode="json")

        persona_block = render_persona_block(persona_dict)
        scenario_block = render_scenario_header(session_context)
        header = persona_block
        if scenario_block.strip():
            header = f"{persona_block}\n{scenario_block}"
        return f"{header.rstrip()}\n\n{_GRAMMAR_INSTRUCTIONS}\n\nText: {text}"

    async def _ensure_embedded(self) -> Any:
        if self._embedded is None:
            async with self._embedded_lock:
                if self._embedded is None:
                    import language_tool_python  # type: ignore
                    self._embedded = await asyncio.to_thread(
                        language_tool_python.LanguageTool, "en-US"
                    )
        return self._embedded

    async def check(self, text: str) -> List[Dict[str, Any]]:
        if not text or not text.strip():
            return []
        url = settings.LANGUAGETOOL_URL
        if url:
            return await self._check_http(text, url)
        try:
            lt = await self._ensure_embedded()
            matches = await asyncio.to_thread(lt.check, text)
            return [self._normalize_embedded(m) for m in matches]
        except Exception as e:
            print(f"⚠️ GrammarService embedded failure: {e}")
            return []

    async def _check_http(self, text: str, url: str) -> List[Dict[str, Any]]:
        timeout = 2.0 if url.startswith("https://api.") else 0.5
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                resp = await client.post(
                    url,
                    data={"text": text, "language": "en-US", "level": "picky"},
                )
            if resp.status_code != 200:
                return []
            data = resp.json()
            return [self._normalize_http(m) for m in data.get("matches", [])]
        except Exception as e:
            print(f"⚠️ GrammarService HTTP failure: {e}")
            return []

    @staticmethod
    def _normalize_embedded(m: Any) -> Dict[str, Any]:
        replacements = list(getattr(m, "replacements", None) or [])
        return {
            "rule_id": getattr(m, "ruleId", "unknown"),
            "category": _map_lt_category(getattr(m, "category", "")),
            "snippet": getattr(m, "matchedText", "") or "",
            "suggestion": replacements[0] if replacements else None,
            "source": "lt",
        }

    @staticmethod
    def _normalize_http(match: Dict[str, Any]) -> Dict[str, Any]:
        rule = match.get("rule") or {}
        category = (rule.get("category") or {}).get("id", "GRAMMAR")
        ctx = match.get("context") or {}
        snippet_full = ctx.get("text", "") or ""
        offset = ctx.get("offset", 0)
        length = ctx.get("length", 0)
        snippet = snippet_full[offset: offset + length] if length else snippet_full
        replacements = match.get("replacements") or []
        return {
            "rule_id": rule.get("id", "unknown"),
            "category": _map_lt_category(category),
            "snippet": snippet,
            "suggestion": replacements[0]["value"] if replacements else None,
            "source": "lt",
        }
