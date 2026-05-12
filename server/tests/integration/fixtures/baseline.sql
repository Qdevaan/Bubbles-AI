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
    deleted_at timestamptz,
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

CREATE TABLE xp_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    amount integer NOT NULL,
    source_type text NOT NULL,
    source_id text,
    description text,
    created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX idx_xp_transactions_dedup
    ON xp_transactions (user_id, source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX idx_xp_transactions_user_time ON xp_transactions (user_id, created_at DESC);
CREATE INDEX idx_xp_transactions_period ON xp_transactions (created_at, user_id) WHERE amount > 0;
CREATE INDEX idx_xp_transactions_user ON xp_transactions (user_id, source_type, created_at);

CREATE TABLE achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text UNIQUE,
    title text NOT NULL,
    description text,
    icon text DEFAULT '🏆',
    category text DEFAULT 'general',
    criteria_type text NOT NULL,
    criteria_value integer NOT NULL,
    xp_reward integer DEFAULT 0,
    tier text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_achievements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id uuid REFERENCES achievements(id) ON DELETE CASCADE,
    awarded_at timestamptz DEFAULT now(),
    UNIQUE (user_id, achievement_id)
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

-- events (mentioned-by-name in entity timeline; no entity FK in prod schema)
CREATE TABLE events (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    title text NOT NULL,
    description text,
    due_text text,
    start_time timestamptz,
    end_time timestamptz,
    location text,
    is_all_day boolean DEFAULT false,
    is_completed boolean DEFAULT false,
    external_event_id text,
    sync_provider text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- tasks (mentioned-by-name in entity timeline)
CREATE TABLE tasks (
    id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    due_date timestamptz,
    priority text DEFAULT 'medium',
    status text DEFAULT 'pending',
    category text,
    source_session_id uuid,
    completed_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- session_entities (mirrors migration 0002)
CREATE TABLE session_entities (
    session_id uuid NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    entity_id uuid NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    mention_count integer NOT NULL DEFAULT 1,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session_id, entity_id)
);
CREATE INDEX session_entities_entity_idx ON session_entities (entity_id, last_seen_at DESC);
CREATE INDEX session_entities_user_idx ON session_entities (user_id, last_seen_at DESC);

-- feedback (matches Documentation/db_schema.sql)
CREATE TABLE feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    log_id uuid,
    consultant_log_id uuid,
    feedback_type text,
    rating integer,
    value integer,
    comment text,
    idempotency_key text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- session_analytics (matches Documentation/db_schema.sql; session_id is the PK)
CREATE TABLE session_analytics (
    session_id uuid NOT NULL PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    total_turns integer DEFAULT 0,
    user_word_count integer DEFAULT 0,
    assistant_word_count integer DEFAULT 0,
    average_latency_ms integer,
    topic_summary text,
    user_turns integer DEFAULT 0,
    others_turns integer DEFAULT 0,
    llm_turns integer DEFAULT 0,
    avg_advice_latency_ms numeric,
    total_duration_seconds numeric,
    memories_saved integer DEFAULT 0,
    events_extracted integer DEFAULT 0,
    highlights_created integer DEFAULT 0,
    avg_sentiment_score numeric,
    dominant_sentiment text,
    computed_at timestamptz NOT NULL DEFAULT now()
);

-- coaching_reports (matches Documentation/db_schema.sql)
CREATE TABLE coaching_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    report_content jsonb NOT NULL DEFAULT '{}'::jsonb,
    areas_of_improvement text[],
    model_used text,
    user_talk_pct double precision,
    others_talk_pct double precision,
    key_topics text[],
    key_decisions text[],
    action_items text[],
    follow_up_people text[],
    filler_words text[],
    filler_word_count integer DEFAULT 0,
    tone_summary text,
    engagement_trend text,
    suggestions text[],
    strengths text[],
    report_text text,
    generated_at timestamptz NOT NULL DEFAULT now()
);

-- highlights (written by the compute_session_analytics worker; read by digest)
CREATE TABLE highlights (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id uuid,
    highlight_type text,
    title text,
    body text,
    content text,
    created_at timestamptz DEFAULT now()
);
