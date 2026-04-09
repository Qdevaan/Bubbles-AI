"""
GraphService — manages per-user knowledge graphs backed by NetworkX.
Persists graph data to the `knowledge_graphs` table in Supabase.
"""

import numpy as np
import networkx as nx
from typing import Dict, List, Optional

from app.database import db


class GraphService:
    """In-memory NetworkX graphs keyed by user_id, synced to Supabase."""

    def __init__(self):
        self.active_graphs: Dict[str, nx.Graph] = {}
        self.model = None  # Shared SentenceTransformer (set after VectorService init)
        print("✅ Graph Service: Initialized")

    # ── Load / Save ───────────────────────────────────────────────────────────

    def load_graph(self, user_id: str):
        """Load a user's knowledge graph from DB into memory."""
        if not db:
            return
        try:
            response = (
                db.table("knowledge_graphs")
                .select("graph_data")
                .eq("user_id", user_id)
                .execute()
            )
            if response.data and response.data[0]["graph_data"]:
                data = response.data[0]["graph_data"]
                self.active_graphs[user_id] = nx.node_link_graph(data)
                print(
                    f"✅ Graph Service: Loaded {len(self.active_graphs[user_id].nodes)} "
                    f"nodes for {user_id}"
                )
            else:
                self.active_graphs[user_id] = nx.Graph()
                print(f"🆕 Graph Service: New empty graph for {user_id}")
        except Exception as e:
            print(f"❌ Graph Service Error loading graph for {user_id}: {e}")
            self.active_graphs[user_id] = nx.Graph()

    def save_graph(self, user_id: str):
        """Persist the in-memory graph back to Supabase and free memory."""
        if user_id not in self.active_graphs or not db:
            return
        try:
            from datetime import datetime

            graph_json = nx.node_link_data(self.active_graphs[user_id])
            data = {
                "user_id": user_id,
                "graph_data": graph_json,
                "updated_at": datetime.now().isoformat(),
            }
            db.table("knowledge_graphs").upsert(data).execute()
            print(f"✅ Graph Service: Saved graph for {user_id}")
            del self.active_graphs[user_id]
        except Exception as e:
            print(f"❌ Graph Service Error saving graph for {user_id}: {e}")

    # ── Context Search ────────────────────────────────────────────────────────

    def _keyword_nodes(self, G: nx.Graph, text: str) -> set:
        """Fallback: simple substring matching for graph nodes."""
        text_lower = text.lower()
        nodes_found = set()
        for node in G.nodes():
            if str(node).lower() in text_lower or text_lower in str(node).lower():
                nodes_found.add(node)
        return nodes_found

    def find_context(self, user_id: str, text: str, top_k: int = 5) -> str:
        """Find relevant facts from the in-memory graph using semantic similarity."""
        if user_id not in self.active_graphs:
            return "No known graph facts."
        G = self.active_graphs[user_id]
        if len(G.nodes()) == 0:
            return "No known graph facts."

        nodes_found: set = set()

        if self.model is not None:
            try:
                node_names = [str(n) for n in G.nodes()]
                query_vec = self.model.encode(text, convert_to_numpy=True)
                node_vecs = self.model.encode(node_names, convert_to_numpy=True)

                q_norm_val = np.linalg.norm(query_vec)
                q_unit = query_vec / (q_norm_val + 1e-10)
                norms = np.linalg.norm(node_vecs, axis=1, keepdims=True)
                node_units = node_vecs / (norms + 1e-10)

                scores = node_units @ q_unit
                threshold = 0.3
                nodes_found = {
                    node
                    for score, node in zip(scores, G.nodes())
                    if score >= threshold
                }
                if not nodes_found:
                    ranked = sorted(zip(scores, G.nodes()), reverse=True)
                    nodes_found = {node for _, node in ranked[:3]}
            except Exception as e:
                print(f"⚠️ GraphService: Semantic search failed, falling back: {e}")
                nodes_found = self._keyword_nodes(G, text)
        else:
            nodes_found = self._keyword_nodes(G, text)

        # Collect edge facts for matched nodes
        facts = []
        for u, v, data in G.edges(data=True):
            if u in nodes_found or v in nodes_found:
                rel = data.get("relation", "related to")
                facts.append(f"Fact: {u} {rel} {v}")

        context_str = "\n".join(list(set(facts))[:top_k])
        return context_str if context_str else "No known graph facts."

    # ── Graph Mutation ────────────────────────────────────────────────────────

    def update_local_graph(self, user_id: str, updates: List[dict]):
        """Add new relationships to the in-memory graph."""
        if user_id not in self.active_graphs:
            print(f"⚠️ Graph Service: No active graph for {user_id}")
            return
        if updates:
            print(
                f"➕ Graph Service: Updating graph for {user_id} "
                f"with {len(updates)} new relationships"
            )
        for u in updates:
            source = u.get("source")
            target = u.get("target")
            relation = u.get("relation", "related")
            if source and target:
                self.active_graphs[user_id].add_edge(
                    source, target, relation=relation
                )
