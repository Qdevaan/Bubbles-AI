"""
Service singletons — initialized once and shared across all routes.
Import from here: `from app.services import graph_svc, vector_svc, brain_svc,
session_svc, entity_svc, audit_svc, gamification_svc, persona_svc`
"""

from app.services.graph_service import GraphService
from app.services.vector_service import VectorService
from app.services.brain_service import BrainService
from app.services.session_service import SessionService
from app.services.entity_service import EntityService
from app.services.audit_service import AuditService
from app.services.gamification_service import GamificationService
from app.services.task_dispatcher_service import TaskDispatcherService

# Initialize all services
graph_svc = GraphService()
vector_svc = VectorService()
brain_svc = BrainService()
session_svc = SessionService()
entity_svc = EntityService()
audit_svc = AuditService()
gamification_svc = GamificationService()
dispatcher_svc = TaskDispatcherService()

# Share the SentenceTransformer model so GraphService can do semantic search
# without loading the model twice
graph_svc.model = vector_svc.model

# Grammar / mistake tracker
from app.services.grammar_service import GrammarService
grammar_svc = GrammarService()
print("📝 Grammar Service: initialised")

from app.services.reminder_service import ReminderService
reminder_svc = ReminderService()
print("📨 Reminder Service: instance created (FCM init deferred to startup)")

# Persona service for user profile management and role classification
from app.services.persona_service import PersonaService
from app.database import db as _db
persona_svc = PersonaService(db=_db)
print("👤 Persona Service: initialised")
