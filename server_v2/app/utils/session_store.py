"""
Session Store — Redis-backed abstraction with in-memory fallback.

Usage:
    from app.utils.session_store import session_store

    await session_store.set_live_session(user_id, session_id)
    sid = await session_store.get_live_session(user_id)
    await session_store.set_metadata(session_id, {...})
    meta = await session_store.get_metadata(session_id)
    await session_store.delete_session(session_id, user_id)

Configuration:
    Set REDIS_URL in your .env for production multi-worker deployments.
    Example: REDIS_URL=redis://localhost:6379/0

    If REDIS_URL is empty, the store uses in-process Python dicts.
    This is fine for local development / single-worker setups.
"""

import asyncio
import json
import logging
from datetime import datetime
from typing import Any, Dict, Optional

from app.config import settings

logger = logging.getLogger(__name__)

# ── TTL constants ─────────────────────────────────────────────────────────────
_SESSION_TTL_SECONDS = 6 * 60 * 60  # 6 hours
_REDIS_KEY_PREFIX = "bubbles:session:"


# ══════════════════════════════════════════════════════════════════════════════
# In-Memory Fallback Store
# ══════════════════════════════════════════════════════════════════════════════

class _InMemoryStore:
    """Thread-safe in-memory fallback. Single-worker only."""

    def __init__(self):
        self._live: Dict[str, str] = {}           # user_id → session_id
        self._meta: Dict[str, dict] = {}          # session_id → metadata dict
        self._timestamps: Dict[str, datetime] = {}
        self._turn_counters: Dict[str, int] = {}

    async def get_live_session(self, user_id: str) -> Optional[str]:
        return self._live.get(user_id)

    async def set_live_session(self, user_id: str, session_id: str) -> None:
        self._live[user_id] = session_id
        self._timestamps[session_id] = datetime.now()

    async def remove_live_session_by_session_id(self, session_id: str) -> None:
        for uid, sid in list(self._live.items()):
            if sid == session_id:
                del self._live[uid]
                break

    async def get_metadata(self, session_id: str) -> Dict:
        return self._meta.get(session_id, {})

    async def set_metadata(self, session_id: str, metadata: Dict) -> None:
        self._meta[session_id] = metadata

    async def delete_session(self, session_id: str, user_id: Optional[str] = None) -> None:
        self._meta.pop(session_id, None)
        self._timestamps.pop(session_id, None)
        self._turn_counters.pop(session_id, None)
        if user_id:
            self._live.pop(user_id, None)
        else:
            await self.remove_live_session_by_session_id(session_id)

    async def get_turn_count(self, session_id: str) -> int:
        return self._turn_counters.get(session_id, 0)

    async def increment_turn_count(self, session_id: str) -> int:
        self._turn_counters[session_id] = self._turn_counters.get(session_id, 0) + 1
        return self._turn_counters[session_id]

    async def get_all_session_ids(self) -> Dict[str, datetime]:
        return dict(self._timestamps)

    async def evict_stale(self, cutoff: datetime) -> int:
        stale = [sid for sid, ts in self._timestamps.items() if ts < cutoff]
        for sid in stale:
            await self.delete_session(sid)
        return len(stale)

    async def evict_oldest_if_over(self, max_count: int) -> int:
        if len(self._timestamps) <= max_count:
            return 0
        sorted_sessions = sorted(self._timestamps.items(), key=lambda x: x[1])
        to_remove = len(self._timestamps) - max_count
        for sid, _ in sorted_sessions[:to_remove]:
            await self.delete_session(sid)
        return to_remove


# ══════════════════════════════════════════════════════════════════════════════
# Redis Store
# ══════════════════════════════════════════════════════════════════════════════

class _RedisStore:
    """Redis-backed session store. Supports multiple Uvicorn workers."""

    def __init__(self, redis_url: str):
        self._url = redis_url
        self._client = None

    async def _get_client(self):
        if self._client is None:
            try:
                import redis.asyncio as aioredis  # type: ignore
                self._client = aioredis.from_url(
                    self._url,
                    encoding="utf-8",
                    decode_responses=True,
                )
                await self._client.ping()
                logger.info("✅ Session Store: Redis connected at %s", self._url)
            except Exception as e:
                logger.error("❌ Redis connection failed: %s — falling back to in-memory", e)
                self._client = None
                raise
        return self._client

    def _live_key(self, user_id: str) -> str:
        return f"{_REDIS_KEY_PREFIX}live:{user_id}"

    def _meta_key(self, session_id: str) -> str:
        return f"{_REDIS_KEY_PREFIX}meta:{session_id}"

    def _turn_key(self, session_id: str) -> str:
        return f"{_REDIS_KEY_PREFIX}turns:{session_id}"

    async def get_live_session(self, user_id: str) -> Optional[str]:
        r = await self._get_client()
        return await r.get(self._live_key(user_id))

    async def set_live_session(self, user_id: str, session_id: str) -> None:
        r = await self._get_client()
        await r.setex(self._live_key(user_id), _SESSION_TTL_SECONDS, session_id)

    async def remove_live_session_by_session_id(self, session_id: str) -> None:
        # Scan for live keys matching this session_id (costly but rare)
        r = await self._get_client()
        async for key in r.scan_iter(f"{_REDIS_KEY_PREFIX}live:*"):
            if await r.get(key) == session_id:
                await r.delete(key)
                break

    async def get_metadata(self, session_id: str) -> Dict:
        r = await self._get_client()
        raw = await r.get(self._meta_key(session_id))
        if raw:
            return json.loads(raw)
        return {}

    async def set_metadata(self, session_id: str, metadata: Dict) -> None:
        r = await self._get_client()
        await r.setex(
            self._meta_key(session_id),
            _SESSION_TTL_SECONDS,
            json.dumps(metadata),
        )

    async def delete_session(self, session_id: str, user_id: Optional[str] = None) -> None:
        r = await self._get_client()
        keys_to_delete = [self._meta_key(session_id), self._turn_key(session_id)]
        if user_id:
            keys_to_delete.append(self._live_key(user_id))
        else:
            await self.remove_live_session_by_session_id(session_id)
        await r.delete(*keys_to_delete)

    async def get_turn_count(self, session_id: str) -> int:
        r = await self._get_client()
        val = await r.get(self._turn_key(session_id))
        return int(val) if val else 0

    async def increment_turn_count(self, session_id: str) -> int:
        r = await self._get_client()
        count = await r.incr(self._turn_key(session_id))
        await r.expire(self._turn_key(session_id), _SESSION_TTL_SECONDS)
        return count

    async def get_all_session_ids(self) -> Dict[str, datetime]:
        # Redis TTL-based eviction handles cleanup; return empty dict for compat
        return {}

    async def evict_stale(self, cutoff: datetime) -> int:
        # Redis handles TTL-based eviction automatically
        return 0

    async def evict_oldest_if_over(self, max_count: int) -> int:
        # Redis handles memory limits via maxmemory policy
        return 0


# ══════════════════════════════════════════════════════════════════════════════
# Smart Session Store — auto-selects backend
# ══════════════════════════════════════════════════════════════════════════════

class SessionStore:
    """
    Smart session store that auto-selects Redis or in-memory based on config.
    Provides a unified async interface regardless of the backend.
    """

    def __init__(self):
        self._redis: Optional[_RedisStore] = None
        self._memory = _InMemoryStore()
        self._backend_initialized = False
        self._use_redis = False

    async def _init(self):
        if self._backend_initialized:
            return
        self._backend_initialized = True

        if settings.REDIS_URL:
            try:
                self._redis = _RedisStore(settings.REDIS_URL)
                # Test connection eagerly
                await self._redis._get_client()
                self._use_redis = True
                logger.info("📦 Session Store: Using Redis backend")
                return
            except Exception:
                logger.warning("⚠️ Redis unavailable — falling back to in-memory session store")

        logger.info("📦 Session Store: Using in-memory backend (single-worker mode)")

    @property
    def _backend(self) -> Any:
        return self._redis if self._use_redis else self._memory

    async def get_live_session(self, user_id: str) -> Optional[str]:
        await self._init()
        return await self._backend.get_live_session(user_id)

    async def set_live_session(self, user_id: str, session_id: str) -> None:
        await self._init()
        await self._backend.set_live_session(user_id, session_id)

    async def get_metadata(self, session_id: str) -> Dict:
        await self._init()
        return await self._backend.get_metadata(session_id)

    async def set_metadata(self, session_id: str, metadata: Dict) -> None:
        await self._init()
        await self._backend.set_metadata(session_id, metadata)

    async def delete_session(self, session_id: str, user_id: Optional[str] = None) -> None:
        await self._init()
        await self._backend.delete_session(session_id, user_id)

    async def get_turn_count(self, session_id: str) -> int:
        await self._init()
        return await self._backend.get_turn_count(session_id)

    async def increment_turn_count(self, session_id: str) -> int:
        await self._init()
        return await self._backend.increment_turn_count(session_id)

    async def get_all_session_ids(self) -> Dict[str, datetime]:
        await self._init()
        return await self._backend.get_all_session_ids()

    async def evict_stale(self, cutoff: datetime) -> int:
        await self._init()
        return await self._backend.evict_stale(cutoff)

    async def evict_oldest_if_over(self, max_count: int) -> int:
        await self._init()
        return await self._backend.evict_oldest_if_over(max_count)


# Module-level singleton — import `session_store` anywhere
session_store = SessionStore()
