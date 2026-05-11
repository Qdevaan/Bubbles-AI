"""
AuditService — lightweight fire-and-forget audit logging to the audit_log table.
Records every significant server action for compliance and debugging.
"""

from datetime import datetime
from typing import Any, Dict, Optional

from app.database import db


class AuditService:
    """Writes structured audit entries to the audit_log table."""

    def __init__(self):
        print("✅ Audit Service: Initialized")

    def log(
        self,
        user_id: Optional[str],
        action: str,
        entity_type: Optional[str] = None,
        entity_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
    ):
        """Insert a row into audit_log. Never raises — failures are printed only."""
        if not db:
            return
        try:
            row: Dict[str, Any] = {
                "action": action,
                "created_at": datetime.now().isoformat(),
            }
            if user_id:
                row["user_id"] = user_id
            if entity_type:
                row["entity_type"] = entity_type
            if entity_id:
                row["entity_id"] = entity_id
            if details:
                row["details"] = details
            if ip_address:
                row["ip_address"] = ip_address
            if user_agent:
                row["user_agent"] = user_agent

            db.table("audit_log").insert(row).execute()
        except Exception as e:
            print(f"⚠️ Audit Service: Failed to log '{action}': {e}")
