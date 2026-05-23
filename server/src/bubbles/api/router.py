"""Mount all /v1 sub-routers under a single prefix."""

from __future__ import annotations

from fastapi import APIRouter

from bubbles.api.v1.analytics import router as analytics_router
from bubbles.api.v1.consultant import router as consultant_router
from bubbles.api.v1.dashboard import router as dashboard_router
from bubbles.api.v1.drills import router as drills_router
from bubbles.api.v1.entities import router as entities_router
from bubbles.api.v1.gamification import router as gamification_router
from bubbles.api.v1.grammar import router as grammar_router
from bubbles.api.v1.memories import router as memories_router
from bubbles.api.v1.persona import router as persona_router
from bubbles.api.v1.scenarios import router as scenarios_router
from bubbles.api.v1.sessions import router as sessions_router
from bubbles.api.v1.speaker import router as speaker_router
from bubbles.api.v1.stt import router as stt_router
from bubbles.api.v1.voice import router as voice_router
from bubbles.api.v1.wingman import router as wingman_router

v1_router = APIRouter(prefix="/v1")
v1_router.include_router(sessions_router)
v1_router.include_router(wingman_router)
v1_router.include_router(speaker_router)
v1_router.include_router(consultant_router)
v1_router.include_router(analytics_router)
v1_router.include_router(dashboard_router)
v1_router.include_router(entities_router)
v1_router.include_router(gamification_router)
v1_router.include_router(memories_router)
v1_router.include_router(persona_router)
v1_router.include_router(drills_router)
v1_router.include_router(scenarios_router)
v1_router.include_router(grammar_router)
v1_router.include_router(voice_router)
v1_router.include_router(stt_router)
