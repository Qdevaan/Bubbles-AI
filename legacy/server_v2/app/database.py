"""
Supabase client singleton — used by all services.
Uses the service-role key to bypass RLS (server enforces ownership checks).
"""

from supabase import create_client, Client
from app.config import settings


def _create_supabase_client() -> Client:
    """Create a Supabase client using the service-role key."""
    return create_client(
        settings.SUPABASE_URL,
        settings.SUPABASE_SERVICE_KEY,
    )


# Module-level singleton — import `db` anywhere
try:
    db: Client = _create_supabase_client()
    print("Database: Supabase client connected")
except Exception as e:
    print(f"Database: Failed to connect - {e}")
    db = None  # type: ignore
