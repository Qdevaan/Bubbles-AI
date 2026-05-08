"""Persona models -- typed performa schema and per-meeting context."""

from datetime import datetime
from typing import List, Literal, Optional
from uuid import UUID

from pydantic import BaseModel, Field


RolePrimary = Literal[
    "student", "teacher", "professional", "manager",
    "freelancer", "homemaker", "other",
]
RoleFamily = Literal["educator", "learner", "professional", "casual", "default"]
AgeRange = Literal["<18", "18-24", "25-34", "35-44", "45+"]
Proficiency = Literal["beginner", "intermediate", "advanced", "fluent"]
Formality = Literal["casual", "neutral", "formal", "mixed"]
Scenario = Literal[
    "lecture", "1on1", "work_meeting", "casual", "interview", "presentation",
]
RoleMode = Literal["default", "mentor", "learner", "peer", "host"]


class UserPersona(BaseModel):
    user_id: UUID
    display_name: Optional[str] = None
    age_range: Optional[AgeRange] = None
    role_primary: RolePrimary
    profession_detail: Optional[str] = None
    expertise_tags: List[str] = Field(default_factory=list, max_length=5)
    native_language: str
    learning_language: str = "en"
    proficiency_self_rated: Optional[Proficiency] = None
    formality_preference: Formality = "neutral"
    communication_style: List[str] = Field(default_factory=list, max_length=3)
    primary_goals: List[str] = Field(default_factory=list, max_length=3)
    typical_scenarios: List[str] = Field(default_factory=list, max_length=4)
    cultural_context: Optional[str] = None
    avoid_list: Optional[str] = None
    role_family: RoleFamily
    completed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class UserPersonaUpdate(BaseModel):
    """Partial-update payload from Flutter wizard / settings.
    All fields optional; server fills role_family + completed_at."""
    display_name: Optional[str] = None
    age_range: Optional[AgeRange] = None
    role_primary: Optional[RolePrimary] = None
    profession_detail: Optional[str] = None
    expertise_tags: Optional[List[str]] = Field(default=None, max_length=5)
    native_language: Optional[str] = None
    learning_language: Optional[str] = None
    proficiency_self_rated: Optional[Proficiency] = None
    formality_preference: Optional[Formality] = None
    communication_style: Optional[List[str]] = Field(default=None, max_length=3)
    primary_goals: Optional[List[str]] = Field(default=None, max_length=3)
    typical_scenarios: Optional[List[str]] = Field(default=None, max_length=4)
    cultural_context: Optional[str] = None
    avoid_list: Optional[str] = None


class SessionContext(BaseModel):
    scenario: Scenario
    role_mode: RoleMode = "default"
    notes: Optional[str] = None
    set_at: datetime
