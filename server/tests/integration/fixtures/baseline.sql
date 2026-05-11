-- Test-only baseline schema.
-- Mirrors the subset of `Documentation/db_schema.sql` repo tests touch.
-- Differences from production:
--   * `auth.users` is a stub plain table (no Supabase auth schema).
--   * No RLS, no pgvector index.
--   * `memory.embedding` uses pgvector if available; tests skip vector ops if not.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Stub auth.users so FKs targeting it resolve.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text
);

-- pgvector is optional in tests; tests requiring it should skip when missing.
DO $$ BEGIN
    CREATE EXTENSION IF NOT EXISTS vector;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

CREATE TABLE sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    title text,
    summary text,
    session_type text DEFAULT 'general',
    mode text DEFAULT 'live_wingman',
    device_id uuid,
    start_time timestamptz DEFAULT now(),
    end_time timestamptz,
    ended_at timestamptz,
    status text DEFAULT 'active',
    is_starred boolean DEFAULT false,
    is_ephemeral boolean DEFAULT false,
    is_multiplayer boolean DEFAULT false,
    persona text DEFAULT 'casual',
    sentiment_score numeric,
    token_usage_prompt integer DEFAULT 0,
    token_usage_completion integer DEFAULT 0,
    total_cost_usd numeric DEFAULT 0.0,
    session_context jsonb,
    created_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    idempotency_key text UNIQUE
);

CREATE TABLE entities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    canonical_name text NOT NULL,
    display_name text,
    entity_type text NOT NULL,
    aliases text[],
    description text,
    mention_count integer DEFAULT 0,
    is_archived boolean DEFAULT false,
    last_seen_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE (user_id, canonical_name)
);

CREATE TABLE entity_relations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    source_id uuid REFERENCES entities(id) ON DELETE CASCADE,
    target_id uuid REFERENCES entities(id) ON DELETE CASCADE,
    relation text NOT NULL,
    strength numeric DEFAULT 1.0,
    source_session text,
    updated_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE (source_id, target_id, relation)
);

CREATE TABLE user_personas (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name text,
    age_range text,
    role_primary text NOT NULL,
    profession_detail text,
    expertise_tags text[] NOT NULL DEFAULT '{}',
    native_language text NOT NULL,
    learning_language text NOT NULL DEFAULT 'en',
    proficiency_self_rated text,
    formality_preference text DEFAULT 'neutral',
    communication_style text[] NOT NULL DEFAULT '{}',
    primary_goals text[] NOT NULL DEFAULT '{}',
    typical_scenarios text[] NOT NULL DEFAULT '{}',
    cultural_context text,
    avoid_list text,
    role_family text NOT NULL,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_mistakes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,
    rule_id text NOT NULL,
    category text NOT NULL,
    snippet text NOT NULL,
    suggestion text,
    source text NOT NULL CHECK (source IN ('lt','llm')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_gamification (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    total_xp integer DEFAULT 0,
    level integer DEFAULT 1,
    current_streak integer DEFAULT 0,
    longest_streak integer DEFAULT 0,
    streak_freezes integer DEFAULT 1,
    last_active_date date,
    xp_spent integer DEFAULT 0,
    leaderboard_opt_in boolean DEFAULT true,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE quest_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    description text,
    quest_type text DEFAULT 'daily',
    action_type text NOT NULL,
    target integer NOT NULL DEFAULT 1,
    xp_reward integer DEFAULT 0,
    is_active boolean DEFAULT true,
    focus_area text,
    difficulty text DEFAULT 'medium',
    mission_type text DEFAULT 'action',
    brief jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE user_quests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    quest_id uuid REFERENCES quest_definitions(id) ON DELETE CASCADE,
    progress integer DEFAULT 0,
    target integer NOT NULL,
    is_completed boolean DEFAULT false,
    xp_awarded boolean DEFAULT false,
    assigned_date date NOT NULL,
    completed_at timestamptz,
    reason text,
    brief_state jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE rewards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    description text,
    icon text DEFAULT '🎁',
    category text DEFAULT 'general',
    cost_xp integer NOT NULL,
    sort_order integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE user_rewards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    reward_id uuid REFERENCES rewards(id) ON DELETE CASCADE,
    cost_xp integer NOT NULL,
    unlocked_at timestamptz DEFAULT now(),
    UNIQUE (user_id, reward_id)
);

CREATE TABLE memory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    content text NOT NULL,
    memory_type text NOT NULL DEFAULT 'general',
    importance numeric DEFAULT 1.0,
    confidence numeric DEFAULT 1.0,
    source text DEFAULT 'inferred',
    is_pinned boolean DEFAULT false,
    is_archived boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz,
    expires_at timestamptz
);

-- Vector column added conditionally so the schema applies even without pgvector.
DO $$ BEGIN
    ALTER TABLE memory ADD COLUMN embedding vector(384);
EXCEPTION WHEN OTHERS THEN
    ALTER TABLE memory ADD COLUMN IF NOT EXISTS embedding text;
END $$;
