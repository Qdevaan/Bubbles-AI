"""Persona service -- typed performa CRUD + role-family classification."""

from typing import Final


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
