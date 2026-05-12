"""
VectorService — long-term memory via SentenceTransformer embeddings + pgvector.
"""

import asyncio
from sentence_transformers import SentenceTransformer

from app.config import settings
from app.database import db


class VectorService:
    """Embedding model + Supabase vector store for memory search/save."""

    def __init__(self):
        print("🧠 Vector Service: Loading Embedding Model (MiniLM)...")
        self.model = SentenceTransformer(settings.EMBEDDING_MODEL)
        print("✅ Vector Service: Embedding Model Loaded & DB Connected")

    def search_memory(self, user_id: str, query: str) -> str:
        """Search long-term memory via cosine similarity (pgvector HNSW)."""
        if not db:
            return "No relevant past memories."
        try:
            vec = self.model.encode(query).tolist()
            res = db.rpc(
                "match_memory",
                {
                    "query_embedding": vec,
                    "match_threshold": 0.5,
                    "match_count": 3,
                    "p_user_id": user_id,
                },
            ).execute()
            memories = [
                f"Memory: {item['content']}"
                for item in res.data
                if item["content"]
            ]
            return "\n".join(memories) if memories else "No relevant past memories."
        except Exception as e:
            print(f"❌ Vector Service Error searching memory: {e}")
            return "Error searching past memories."

    async def save_memory(
        self, user_id: str, content: str, session_id: str = None,
        memory_type: str = "general",
    ):
        """Save content to the user's long-term memory with embedding."""
        if not db or not content.strip():
            return

        def encode_sync(text):
            return self.model.encode(text.strip()).tolist()

        try:
            vec = await asyncio.to_thread(encode_sync, content)
            data = {
                "user_id": user_id,
                "content": content.strip(),
                "memory_type": memory_type,
                "embedding": vec,
            }
            if session_id:
                data["session_id"] = session_id
            db.table("memory").insert(data).execute()
            print(f"💾 Vector Service: Saved new memory for {user_id}")
        except Exception as e:
            print(f"❌ Vector Service Error saving memory: {e}")
