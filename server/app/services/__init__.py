"""
Service singletons — initialized once and shared across all routes.
Import from here: `from app.services import graph_svc, vector_svc, brain_svc, session_svc, entity_svc, audit_svc`
"""

from app.services.graph_service import GraphService
from app.services.vector_service import VectorService
from app.services.brain_service import BrainService
from app.services.session_service import SessionService
from app.services.entity_service import EntityService
from app.services.audit_service import AuditService

# Initialize all services
graph_svc = GraphService()
vector_svc = VectorService()
brain_svc = BrainService()
session_svc = SessionService()
entity_svc = EntityService()
audit_svc = AuditService()

# Share the SentenceTransformer model so GraphService can do semantic search
# without loading the model twice
graph_svc.model = vector_svc.model
