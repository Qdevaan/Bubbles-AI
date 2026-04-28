-- ================================================================================
--  BUBBLES AI ASSISTANT — UNIFIED "DB FINAL" SCHEMA v5.0
--  Date      : April 27, 2026
--  Status    : UNIFIED SCHEMA — Updated till date with all necessary changes for both server and Flutter app compatibility
--  Purpose   : Single source of truth for server + Flutter app
--  RLS       : DISABLED on all tables (server enforces ownership checks)
-- ================================================================================


-- ════════════════════════════════════════════════════════════════════════════════
-- 1. EXTENSIONS
-- ════════════════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp" schema extensions;
create extension if not exists "vector"    schema extensions;
create extension if not exists "pg_trgm"   schema extensions;
create extension if not exists "pg_cron"   schema extensions;
create extension if not exists "postgis"   schema extensions;


-- ════════════════════════════════════════════════════════════════════════════════
-- 2. DROP EVERYTHING (children first, then parents)
-- ════════════════════════════════════════════════════════════════════════════════

drop table if exists public.app_feedback cascade;
drop table if exists public.data_deletion_requests cascade;
drop table if exists public.feature_flags cascade;
drop table if exists public.audit_log cascade;

drop table if exists public.subscription_usage cascade;
drop table if exists public.subscriptions cascade;
drop table if exists public.shared_sessions cascade;
drop table if exists public.team_members cascade;
drop table if exists public.team_workspaces cascade;

drop table if exists public.webhooks cascade;
drop table if exists public.api_keys cascade;
drop table if exists public.calendar_sync_log cascade;
drop table if exists public.calendar_integrations cascade;
drop table if exists public.integrations cascade;

drop table if exists public.iot_logs cascade;
drop table if exists public.iot_devices cascade;
drop table if exists public.notifications cascade;
drop table if exists public.notification_tokens cascade;

drop table if exists public.events cascade;
drop table if exists public.tasks cascade;
drop table if exists public.highlights cascade;

drop table if exists public.trips cascade;
drop table if exists public.expenses cascade;
drop table if exists public.health_metrics cascade;

drop table if exists public.user_routines cascade;
drop table if exists public.entity_relations cascade;
drop table if exists public.entity_attributes cascade;
drop table if exists public.entity_tags cascade;
drop table if exists public.entities cascade;
drop table if exists public.knowledge_graphs cascade;
drop table if exists public.memory cascade;

drop table if exists public.multimodal_attachments cascade;
drop table if exists public.audio_sessions cascade;
drop table if exists public.session_analytics cascade;
drop table if exists public.session_exports cascade;
drop table if exists public.coaching_reports cascade;
drop table if exists public.feedback cascade;
drop table if exists public.sentiment_logs cascade;
drop table if exists public.consultant_logs cascade;
drop table if exists public.session_logs cascade;
drop table if exists public.session_tags cascade;
drop table if exists public.tags cascade;
drop table if exists public.sessions cascade;

drop table if exists public.voice_enrollments cascade;
drop table if exists public.onboarding_progress cascade;
drop table if exists public.user_devices cascade;
drop table if exists public.user_settings cascade;
drop table if exists public.profiles cascade;


-- ════════════════════════════════════════════════════════════════════════════════
-- 3. CORE USER & IDENTITY (Group A)
-- ════════════════════════════════════════════════════════════════════════════════

-- Basic profile details for each signed-in user.
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text,
    avatar_url text,
    dob date,
    gender text,
    country text,
    locale text default 'en_US',
    timezone text default 'UTC',
    occupation text,
    company text,
    bio text,
    is_developer boolean default false,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- User app preferences and assistant settings.
create table public.user_settings (
    user_id uuid primary key references auth.users(id) on delete cascade,
    theme text default 'system',
    accent_color text,
    font_size text default 'medium',
    voice_assistant_name text default 'Bubbles',
    assistant_persona text default 'friendly',
    assistant_voice_id text,
    speech_rate numeric default 1.0,
    pitch numeric default 1.0,
    haptic_feedback boolean default true,
    auto_play_audio boolean default true,
    transcription_language text default 'en-US',
    enable_nsfw_filter boolean default true,
    data_sharing_opt_in boolean default false,
    updated_at timestamptz default now()
);

-- Devices the user has signed in from.
create table public.user_devices (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    device_id text not null,
    device_model text,
    os_version text,
    app_version text,
    fcm_token text,
    apns_token text,
    last_ip_address text,
    last_location extensions.geometry(Point, 4326),
    is_active boolean default true,
    created_at timestamptz default now(),
    last_active_at timestamptz default now(),
    unique(user_id, device_id)
);

-- Tracks where the user is in onboarding.
create table public.onboarding_progress (
    user_id uuid primary key references auth.users(id) on delete cascade,
    has_completed_welcome boolean default false,
    has_set_voice boolean default false,
    has_connected_calendar boolean default false,
    has_completed_tutorial boolean default false,
    current_step text,
    updated_at timestamptz default now()
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 4. SESSIONS & MULTIMODAL INTERACTIONS (Group B)
--    ★ MERGED: Added mode, is_ephemeral, is_multiplayer, persona, ended_at
-- ════════════════════════════════════════════════════════════════════════════════

-- One row for each chat or voice session.
create table public.sessions (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    title text,
    summary text,
    session_type text default 'general',       -- from v4.0 schema
    mode text default 'live_wingman',           -- ★ from old server (live_wingman, consultant, roleplay, debate)
    device_id uuid references public.user_devices(id),
    start_time timestamptz default now(),
    end_time timestamptz,                       -- from v4.0 schema
    ended_at timestamptz,                       -- ★ from old server (alternate end timestamp)
    status text default 'active',               -- active | completed | archived
    is_starred boolean default false,
    is_ephemeral boolean default false,          -- ★ from old server (incognito mode)
    is_multiplayer boolean default false,        -- ★ from old server (multi-speaker sessions)
    persona text default 'casual',              -- ★ from old server (stoic, aggressive_coach, etc.)
    sentiment_score numeric,
    token_usage_prompt int default 0,
    token_usage_completion int default 0,
    total_cost_usd numeric default 0.0,
    created_at timestamptz default now(),
    deleted_at timestamptz                      -- soft delete
);

-- Individual messages and turns inside a session.
create table public.session_logs (
    id uuid default extensions.uuid_generate_v4() primary key,
    session_id uuid references public.sessions(id) on delete cascade,
    turn_index int default 0,                   -- default added for server compat
    role text not null,                          -- user | assistant | others | llm | system
    content text,
    content_html text,
    model_used text,
    latency_ms int,
    tokens_used int,
    finish_reason text,
    has_error boolean default false,
    error_message text,
    -- ★ Columns from old server (inline sentiment + diarization)
    speaker_label text,                         -- ★ raw diarization label e.g. "Speaker 1"
    confidence numeric,                         -- ★ transcription confidence score
    sentiment_score numeric,                    -- ★ computed inline sentiment (-1 to 1)
    sentiment_label text,                       -- ★ positive, negative, neutral, etc.
    created_at timestamptz default now()
);

-- Freeform questions and answers from the consultant flow.
create table public.consultant_logs (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    -- ★ UNIFIED: Old server uses question/answer; v4.0 schema uses query/response
    --   We use BOTH to maximize compatibility. Server writes question/answer.
    query text,                                 -- v4.0 name (kept for Flutter compat)
    question text,                              -- ★ old server name (server writes this)
    response text,                              -- v4.0 name (kept for Flutter compat)
    answer text,                                -- ★ old server name (server writes this)
    created_at timestamptz not null default timezone('utc', now())
);

-- Files, images, audio, or PDFs attached to a session message.
create table public.multimodal_attachments (
    id uuid default extensions.uuid_generate_v4() primary key,
    session_log_id uuid references public.session_logs(id) on delete cascade,
    file_type text,                             -- image | pdf | audio | video
    file_url text,
    mime_type text,
    file_size_bytes bigint,
    extracted_text text,
    metadata jsonb,
    created_at timestamptz default now()
);

-- Metadata for uploaded or recorded audio sessions.
create table public.audio_sessions (
    id uuid default extensions.uuid_generate_v4() primary key,
    session_id uuid references public.sessions(id) on delete cascade,
    file_path text,
    duration_seconds numeric,
    sample_rate int,
    channels int,
    snr_db numeric,
    wakeword_detected boolean,
    transcription_confidence numeric,
    recorded_at timestamptz default now()
);

-- Precomputed stats and summary numbers for a session.
create table public.session_analytics (
    session_id uuid primary key references public.sessions(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    -- v4.0 base columns
    total_turns int default 0,
    user_word_count int default 0,
    assistant_word_count int default 0,
    average_latency_ms int,
    topic_summary text,
    -- ★ Granular metrics from old server
    user_turns int default 0,                   -- ★ count of user role turns
    others_turns int default 0,                 -- ★ count of others role turns
    llm_turns int default 0,                    -- ★ count of llm/assistant turns
    avg_advice_latency_ms numeric,              -- ★ average LLM response time
    total_duration_seconds numeric,             -- ★ session wall-clock duration
    memories_saved int default 0,               -- ★ memories created during session
    events_extracted int default 0,             -- ★ calendar events found
    highlights_created int default 0,           -- ★ highlights generated
    avg_sentiment_score numeric,                -- ★ average sentiment across turns
    dominant_sentiment text,                    -- ★ positive | negative | neutral
    computed_at timestamptz not null default timezone('utc', now())
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 5. INTELLIGENCE, MEMORY & CONTEXT (Group C)
-- ════════════════════════════════════════════════════════════════════════════════

-- Saved memories that the assistant can recall later.
create table public.memory (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    content text not null,
    memory_type text not null default 'general', -- default added for server compat
    embedding extensions.vector(384),
    importance numeric default 1.0,
    confidence numeric default 1.0,
    source text default 'inferred',             -- inferred | explicit | system
    is_pinned boolean default false,
    is_archived boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz,
    expires_at timestamptz
);

-- High-level graph data for a user's knowledge map.
create table public.knowledge_graphs (
    user_id uuid primary key references auth.users(id) on delete cascade,
    graph_data jsonb not null default '{}',
    updated_at timestamptz default now()
);

-- People, places, things, and concepts the app knows about.
create table public.entities (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    canonical_name text not null,
    display_name text,                          -- ★ from old server (original casing)
    entity_type text not null,                  -- person | place | organization | event | object | concept
    aliases text[],
    description text,
    mention_count int default 0,
    is_archived boolean default false,
    last_seen_at timestamptz,                   -- ★ from old server (tracks recency)
    created_at timestamptz default now(),
    unique(user_id, canonical_name)
);

-- Extra facts and attributes for each entity.
create table public.entity_attributes (
    id uuid default extensions.uuid_generate_v4() primary key,
    entity_id uuid references public.entities(id) on delete cascade,
    attribute_key text not null,
    attribute_value text,
    value_type text default 'string',           -- string | number | boolean | date
    confidence numeric default 1.0,
    source_session_id uuid references public.sessions(id), -- v4.0 name
    source_session text,                        -- ★ from old server (alternative ref)
    updated_at timestamptz default now(),
    unique(entity_id, attribute_key)
);

-- Relationships between two entities.
create table public.entity_relations (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    source_id uuid references public.entities(id) on delete cascade,
    target_id uuid references public.entities(id) on delete cascade,
    relation text not null,                     -- works_with, friend_of, manages, etc.
    strength numeric default 1.0,
    source_session text,                        -- ★ from old server
    updated_at timestamptz,                     -- ★ from old server
    created_at timestamptz default now(),
    unique(source_id, target_id, relation)
);

-- Saved automation or routine rules for a user.
create table public.user_routines (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    routine_name text not null,
    trigger_type text,                          -- time | event | keyword | location
    trigger_condition jsonb,
    actions jsonb,                              -- array of action objects
    is_active boolean default true,
    created_at timestamptz default now()
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 6. HEALTH, FINANCE & LIFE TRACKING (Group D)
-- ════════════════════════════════════════════════════════════════════════════════

-- Health readings such as sleep, weight, steps, or mood.
create table public.health_metrics (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    metric_type text not null,                  -- heart_rate | steps | sleep | weight | mood
    metric_value numeric,
    metric_unit text,
    recorded_at timestamptz default now(),
    source text default 'manual'                -- manual | wearable | apple_health
);

-- Spending records and receipts.
create table public.expenses (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    amount numeric not null,
    currency text default 'USD',
    category text,
    merchant text,
    date timestamptz default now(),
    receipt_url text,
    is_recurring boolean default false,
    notes text
);

-- Travel plans and trip details.
create table public.trips (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    destination text not null,
    start_date date,
    end_date date,
    purpose text,
    status text default 'planned',
    itinerary jsonb,
    created_at timestamptz default now()
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 7. HIGHLIGHTS, EVENTS, TASKS & NOTIFICATIONS (Group E)
--    ★ MERGED: highlights gets title/body; events gets due_text; feedback updated
-- ════════════════════════════════════════════════════════════════════════════════

-- Important takeaways or action-worthy notes from a session.
create table public.highlights (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    highlight_type text not null,               -- conflict | action_item | insight | key_fact
    title text,                                 -- ★ from old server (short display title)
    body text,                                  -- ★ from old server (detailed description)
    content text not null,                      -- v4.0 (primary content field)
    priority int default 1,
    is_resolved boolean default false,
    is_dismissed boolean default false,
    created_at timestamptz not null default timezone('utc', now())
);

-- User tasks that need follow-up or completion.
create table public.tasks (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    title text not null,
    description text,
    due_date timestamptz,
    priority text default 'medium',             -- low | medium | high | urgent
    status text default 'pending',              -- pending | in_progress | completed | cancelled
    category text,
    source_session_id uuid references public.sessions(id),
    completed_at timestamptz,
    created_at timestamptz default now()
);

-- Calendar-style events pulled from or created by the app.
create table public.events (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    title text not null,
    description text,
    due_text text,                              -- ★ from old server (raw time expression e.g. "next Friday 3pm")
    start_time timestamptz,                     -- made nullable for server compat (due_text may be unparsed)
    end_time timestamptz,
    location text,
    is_all_day boolean default false,
    is_completed boolean default false,
    external_event_id text,
    sync_provider text,                         -- google | outlook | apple
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Ratings and comments left after using the assistant.
create table public.feedback (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    log_id uuid references public.session_logs(id) on delete cascade,
    consultant_log_id uuid references public.consultant_logs(id) on delete cascade, -- ★ from old server
    feedback_type text,                         -- ★ from old server (thumbs | star | text)
    rating int,                                 -- v4.0 (1-5 or -1 to 5)
    value int,                                  -- ★ from old server (alternative rating field)
    comment text,
    created_at timestamptz not null default timezone('utc', now())
);

-- Sentiment score for each turn in a session.
create table public.sentiment_logs (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    turn_index int not null,
    -- v4.0 columns
    sentiment_score float,                      -- -1.0 to 1.0
    emotion_label text,                         -- happy | frustrated | neutral | etc.
    -- ★ Old server columns (unified naming)
    speaker_role text,                          -- ★ user | others | llm
    score float,                                -- ★ old server sentiment score
    label text,                                 -- ★ old server sentiment label
    recorded_at timestamptz not null default timezone('utc', now())
);

-- Voice profile data used to recognize a user.
create table public.voice_enrollments (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    embedding extensions.vector(192) not null,
    samples_count int default 0,
    model_version text,                         -- ★ from old server (e.g. "v1")
    updated_at timestamptz not null default timezone('utc', now())
);

-- Push notification device tokens.
create table public.notification_tokens (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null,
    device_type text,
    is_active boolean default true,
    added_at timestamptz not null default timezone('utc', now()),
    unique (user_id, token)
);

-- Notifications shown to the user.
create table public.notifications (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    title text not null,
    body text,
    notif_type text,                            -- reminder | system | session | achievement
    action_url text,
    is_read boolean default false,
    read_at timestamptz,
    created_at timestamptz default now()
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 8. SMART HOME & IOT (Group F)
-- ════════════════════════════════════════════════════════════════════════════════

-- Smart devices connected to the user account.
create table public.iot_devices (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    device_name text not null,
    device_type text,                           -- light | thermostat | speaker | camera
    room text,
    provider text,                              -- homekit | smartthings | tuya
    external_id text,
    state jsonb,                                -- { "on": true, "brightness": 80 }
    is_online boolean default true,
    last_synced_at timestamptz default now()
);

-- History of actions sent to smart devices.
create table public.iot_logs (
    id uuid default extensions.uuid_generate_v4() primary key,
    device_id uuid references public.iot_devices(id) on delete cascade,
    action text not null,                       -- turn_on | turn_off | set_brightness | etc.
    triggered_by text,                          -- user | automation | voice | schedule
    previous_state jsonb,
    new_state jsonb,
    timestamp timestamptz default now()
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 9. REPORTS, TAGGING & INTEGRATIONS (Group G)
--    ★ MERGED: coaching_reports gets structured columns; exports unchanged
-- ════════════════════════════════════════════════════════════════════════════════

-- Exported copies of a session in different file formats.
create table public.session_exports (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    export_format text not null,                -- pdf | txt | json | csv
    file_url text not null,
    created_at timestamptz not null default timezone('utc', now())
);

-- Detailed coaching summaries and structured feedback.
create table public.coaching_reports (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references public.sessions(id) on delete cascade,
    -- v4.0 base columns
    report_content jsonb not null default '{}',
    areas_of_improvement text[],
    -- ★ Structured fields from old server
    model_used text,                            -- ★ which LLM generated the report
    user_talk_pct float,                        -- ★ percentage of user talking time
    others_talk_pct float,                      -- ★ percentage of others talking time
    key_topics text[],                          -- ★ main topics discussed
    key_decisions text[],                       -- ★ decisions made
    action_items text[],                        -- ★ actionable items identified
    follow_up_people text[],                    -- ★ people to follow up with
    filler_words text[],                        -- ★ filler words used
    filler_word_count int default 0,            -- ★ total filler word count
    tone_summary text,                          -- ★ overall tone description
    engagement_trend text,                      -- ★ improving | stable | declining
    suggestions text[],                         -- ★ improvement suggestions
    strengths text[],                           -- ★ communication strengths
    report_text text,                           -- ★ full narrative report
    generated_at timestamptz not null default timezone('utc', now())
);

-- Labels users can apply to sessions or entities.
create table public.tags (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    color text,
    created_at timestamptz not null default timezone('utc', now()),
    unique (user_id, name)
);

-- Shared tags that belong to a specific session.
create table public.session_tags (
    session_id uuid not null references public.sessions(id) on delete cascade,
    tag_id uuid not null references public.tags(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    primary key (session_id, tag_id)
);

-- Shared tags that belong to a specific entity.
create table public.entity_tags (
    entity_id uuid not null references public.entities(id) on delete cascade,
    tag_id uuid not null references public.tags(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    primary key (entity_id, tag_id)
);

-- Third-party services connected to the account.
create table public.integrations (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    provider text not null,                     -- google | outlook | spotify | notion
    access_token text,
    refresh_token text,
    scopes text[],
    expires_at timestamptz,
    is_active boolean default true,
    sync_status text default 'ok',
    last_sync_at timestamptz,
    created_at timestamptz default now(),
    unique(user_id, provider)
);

-- Calendar connections for sync providers.
create table public.calendar_integrations (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    provider text not null,
    access_token text not null,
    refresh_token text,
    sync_token text,
    expires_at timestamptz,
    created_at timestamptz not null default timezone('utc', now()),
    unique (user_id, provider)
);

-- Log of calendar sync attempts and errors.
create table public.calendar_sync_log (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    event_id uuid references public.events(id) on delete cascade,
    external_event_id text not null,
    provider text not null,
    sync_status text not null,
    error_message text,
    synced_at timestamptz not null default timezone('utc', now())
);

-- API keys issued for programmatic access.
create table public.api_keys (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    key_name text not null,
    key_hash text not null,
    prefix text not null,
    scopes text[],
    last_used_at timestamptz,
    expires_at timestamptz,
    is_revoked boolean default false,
    created_at timestamptz default now()
);

-- Webhook endpoints that receive app events.
create table public.webhooks (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    url text not null,
    events text[],                              -- session_completed, entity_discovered, etc.
    secret text,
    is_active boolean default true,
    created_at timestamptz default now()
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 10. TEAMS, WORKSPACES & ENTERPRISE (Group H)
-- ════════════════════════════════════════════════════════════════════════════════

-- Team or company workspaces.
create table public.team_workspaces (
    id uuid default extensions.uuid_generate_v4() primary key,
    owner_id uuid references auth.users(id),
    name text not null,
    domain text,
    billing_email text,
    enterprise_tier boolean default false,
    sso_enabled boolean default false,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Users assigned to a workspace and their role.
create table public.team_members (
    id uuid default extensions.uuid_generate_v4() primary key,
    workspace_id uuid references public.team_workspaces(id) on delete cascade,
    user_id uuid references auth.users(id) on delete cascade,
    role text default 'member',                 -- admin | member | viewer
    joined_at timestamptz default now(),
    unique(workspace_id, user_id)
);

-- Sessions shared with a workspace.
create table public.shared_sessions (
    id uuid default extensions.uuid_generate_v4() primary key,
    session_id uuid references public.sessions(id) on delete cascade,
    workspace_id uuid references public.team_workspaces(id) on delete cascade,
    shared_by uuid references auth.users(id),
    permission_level text default 'read',       -- read | comment | edit
    shared_at timestamptz default now(),
    unique(session_id, workspace_id)
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 11. SUBSCRIPTIONS & BILLING (Group I)
-- ════════════════════════════════════════════════════════════════════════════════

-- Stripe subscription records for each user.
create table public.subscriptions (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    stripe_customer_id text,
    stripe_subscription_id text,
    plan_id text not null,                      -- free | pro | enterprise
    status text not null,                       -- active | past_due | cancelled | trialing
    current_period_start timestamptz,
    current_period_end timestamptz,
    cancel_at_period_end boolean default false,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Usage totals for billing periods.
create table public.subscription_usage (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    period_start timestamptz not null,
    period_end timestamptz not null,
    total_tokens_used bigint default 0,
    audio_minutes_used numeric default 0.0,
    images_generated int default 0,
    advanced_queries int default 0,
    unique(user_id, period_start)
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 12. ADMIN, SYSTEM & COMPLIANCE (Group J)
-- ════════════════════════════════════════════════════════════════════════════════

-- Audit trail for important system actions.
create table public.audit_log (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    entity_type text,
    entity_id uuid,
    details jsonb,
    ip_address text,
    user_agent text,
    created_at timestamptz default now()
);

-- Feature toggles for switching app behavior on or off.
create table public.feature_flags (
    id text primary key,                        -- flag name e.g. "enable_voice_commands"
    description text,
    is_enabled_globally boolean default false,
    rollout_percentage int default 0,
    enabled_for_users uuid[],
    created_at timestamptz default now()
);

-- Requests from users to delete their data.
create table public.data_deletion_requests (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    status text default 'pending',              -- pending | processing | completed
    requested_at timestamptz default now(),
    completed_at timestamptz,
    processed_by uuid
);

-- Feedback about the app itself.
create table public.app_feedback (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    rating int check (rating >= 1 and rating <= 5),
    feedback_text text,
    app_version text,
    os_info text,
    created_at timestamptz default now()
);


-- ════════════════════════════════════════════════════════════════════════════════
-- 13. INDEXES
-- ════════════════════════════════════════════════════════════════════════════════

create index idx_sessions_user_date on public.sessions(user_id, created_at desc);
create index idx_sessions_mode on public.sessions(user_id, mode);
create index idx_sessions_type on public.sessions(user_id, session_type);
create index idx_session_logs_session on public.session_logs(session_id, turn_index);
create index idx_memory_vector on public.memory using hnsw (embedding vector_cosine_ops);
create index idx_memory_session on public.memory(user_id, session_id);
create index idx_entities_user on public.entities(user_id, entity_type);
create index idx_entities_canonical on public.entities(user_id, canonical_name);
create index idx_tasks_user_status on public.tasks(user_id, status, due_date);
create index idx_events_user_time on public.events(user_id, start_time);
create index idx_events_session on public.events(session_id);
create index idx_notifications_unread on public.notifications(user_id, is_read);
create index idx_highlights_user on public.highlights(user_id, is_resolved);
create index idx_consultant_logs_user on public.consultant_logs(user_id, created_at desc);
create index idx_sentiment_logs_session on public.sentiment_logs(session_id, turn_index);
create index idx_feedback_session on public.feedback(session_id);


-- ════════════════════════════════════════════════════════════════════════════════
-- 14. ROW LEVEL SECURITY — DISABLED (server enforces ownership)
-- ════════════════════════════════════════════════════════════════════════════════

alter table public.profiles disable row level security;
alter table public.user_settings disable row level security;
alter table public.user_devices disable row level security;
alter table public.onboarding_progress disable row level security;
alter table public.sessions disable row level security;
alter table public.session_logs disable row level security;
alter table public.consultant_logs disable row level security;
alter table public.multimodal_attachments disable row level security;
alter table public.audio_sessions disable row level security;
alter table public.session_analytics disable row level security;
alter table public.memory disable row level security;
alter table public.knowledge_graphs disable row level security;
alter table public.entities disable row level security;
alter table public.entity_attributes disable row level security;
alter table public.entity_relations disable row level security;
alter table public.user_routines disable row level security;
alter table public.health_metrics disable row level security;
alter table public.expenses disable row level security;
alter table public.trips disable row level security;
alter table public.highlights disable row level security;
alter table public.tasks disable row level security;
alter table public.events disable row level security;
alter table public.feedback disable row level security;
alter table public.sentiment_logs disable row level security;
alter table public.voice_enrollments disable row level security;
alter table public.notification_tokens disable row level security;
alter table public.notifications disable row level security;
alter table public.iot_devices disable row level security;
alter table public.iot_logs disable row level security;
alter table public.session_exports disable row level security;
alter table public.coaching_reports disable row level security;
alter table public.tags disable row level security;
alter table public.session_tags disable row level security;
alter table public.entity_tags disable row level security;
alter table public.integrations disable row level security;
alter table public.calendar_integrations disable row level security;
alter table public.calendar_sync_log disable row level security;
alter table public.api_keys disable row level security;
alter table public.webhooks disable row level security;
alter table public.team_workspaces disable row level security;
alter table public.team_members disable row level security;
alter table public.shared_sessions disable row level security;
alter table public.subscriptions disable row level security;
alter table public.subscription_usage disable row level security;
alter table public.audit_log disable row level security;
alter table public.feature_flags disable row level security;
alter table public.data_deletion_requests disable row level security;
alter table public.app_feedback disable row level security;


-- ════════════════════════════════════════════════════════════════════════════════
-- 15. RPC FUNCTION: match_memory (used by VectorService.search_memory)
-- ════════════════════════════════════════════════════════════════════════════════

drop function if exists public.match_memory(extensions.vector, float, int, uuid);

create or replace function public.match_memory(
    query_embedding extensions.vector(384),
    match_threshold float,
    match_count int,
    p_user_id uuid
)
returns table (
    id uuid,
    content text,
    similarity float
)
language plpgsql
as $$
begin
    return query
    select
        m.id,
        m.content,
        1 - (m.embedding <=> query_embedding) as similarity
    from public.memory m
    where m.user_id = p_user_id
      and m.is_archived = false
      and 1 - (m.embedding <=> query_embedding) > match_threshold
    order by m.embedding <=> query_embedding
    limit match_count;
end;
$$;


-- sessions table — idempotency on start/save/end_session
alter table public.sessions add column if not exists idempotency_key text unique;

-- feedback table — idempotency on save_feedback
alter table public.feedback add column if not exists idempotency_key text unique;


-- 1. User XP/level/streak profile
-- XP, levels, and streak tracking for each user.
create table public.user_gamification (
    user_id uuid primary key references auth.users(id) on delete cascade,
    total_xp int default 0,
    level int default 1,
    current_streak int default 0,
    longest_streak int default 0,
    streak_freezes int default 1,
    last_active_date date,
    updated_at timestamptz default now()
);

-- 2. XP award log (idempotency + daily cap enforcement)
-- Logs every XP change a user earns.
create table public.xp_transactions (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    amount int not null,
    source_type text not null,     -- session_complete | consultant_qa | entity_extraction | streak_bonus | quest_complete | achievement_unlock | first_session_today
    source_id text,                -- dedup key (session_id, quest_id, etc.)
    description text,
    created_at timestamptz default now()
);
create index idx_xp_transactions_user on public.xp_transactions(user_id, source_type, created_at);
create unique index idx_xp_transactions_dedup on public.xp_transactions(user_id, source_type, source_id)
    where source_id is not null;

-- 3. Quest templates
-- Reusable goal templates for daily or weekly missions.
create table public.quest_definitions (
    id uuid default extensions.uuid_generate_v4() primary key,
    title text not null,
    description text,
    quest_type text default 'daily',   -- daily | weekly
    action_type text not null,         -- complete_session | use_wingman_turns | save_memory | extract_entities
    target int not null default 1,
    xp_reward int default 0,
    is_active boolean default true,
    created_at timestamptz default now()
);

-- 4. Per-user daily quest assignments
-- Quest progress assigned to each user.
create table public.user_quests (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    quest_id uuid references public.quest_definitions(id) on delete cascade,
    progress int default 0,
    target int not null,
    is_completed boolean default false,
    xp_awarded boolean default false,
    assigned_date date not null,
    completed_at timestamptz,
    created_at timestamptz default now()
);
create index idx_user_quests_user_date on public.user_quests(user_id, assigned_date);

-- 5. Achievement definitions
-- Unlockable badges and milestones.
create table public.achievements (
    id uuid default extensions.uuid_generate_v4() primary key,
    title text not null,
    description text,
    icon text default '🏆',
    category text default 'general',
    criteria_type text not null,   -- total_xp | streak | session_count | consultant_count | entity_count | quest_count
    criteria_value int not null,
    xp_reward int default 0,
    created_at timestamptz default now()
);

-- 6. User achievement unlocks
-- Achievements already awarded to a user.
create table public.user_achievements (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    achievement_id uuid references public.achievements(id) on delete cascade,
    awarded_at timestamptz default now(),
    unique(user_id, achievement_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- Gamification Phase 1 — Adaptive Missions
-- ═══════════════════════════════════════════════════════════════════════════
-- focus_area aligns quest with user's weak area from performance_summary:
--   engagement | filler_words | positivity | consistency | quest_completion
-- difficulty: easy | medium | hard | challenge (matches _DIFFICULTY_MAP).
alter table public.quest_definitions
    add column if not exists focus_area text,
    add column if not exists difficulty text default 'medium';

alter table public.user_quests
    add column if not exists reason text;

create index if not exists idx_quest_defs_focus_active
    on public.quest_definitions(focus_area, difficulty)
    where is_active;

-- ═══════════════════════════════════════════════════════════════════════════
-- Gamification Phase 2 — Mission Variety
-- ═══════════════════════════════════════════════════════════════════════════
-- mission_type:
--   action       — counter-based (existing behavior, default)
--   conversation — user must hold a conversation matching brief; completes
--                  when a session is attached and meets criteria
--   question_set — user answers a fixed list of questions; each answer
--                  increments progress
--
-- brief (per-template payload, jsonb):
--   conversation: { topic, persona, min_turns, completion_criteria }
--   question_set: { questions: [ { id, prompt, answer_schema } ] }
--
-- brief_state (per-user runtime state, jsonb):
--   conversation: { session_id, last_eval_at, eval_score }
--   question_set: { answers: { <qid>: <answer> } }
alter table public.quest_definitions
    add column if not exists mission_type text default 'action',
    add column if not exists brief jsonb;

alter table public.user_quests
    add column if not exists brief_state jsonb default '{}'::jsonb;

-- ═══════════════════════════════════════════════════════════════════════════
-- Gamification Phase 3 — Rewards & Streak Milestones
-- ═══════════════════════════════════════════════════════════════════════════
-- Spendable XP semantics:
--   total_xp     = lifetime earned (drives level — never decreases)
--   xp_spent    = lifetime spent on reward redemptions
--   spendable   = total_xp - xp_spent (computed client/server-side)
alter table public.user_gamification
    add column if not exists xp_spent int default 0;

-- 7. Reward catalog
-- Items or perks users can spend XP on.
create table if not exists public.rewards (
    id uuid default extensions.uuid_generate_v4() primary key,
    title text not null,
    description text,
    icon text default '🎁',
    category text default 'general',     -- general | cosmetic | feature_unlock | streak_freeze
    cost_xp int not null,
    sort_order int default 0,
    is_active boolean default true,
    created_at timestamptz default now()
);

-- 8. User-owned rewards (redemptions)
-- Rewards a user has already claimed.
create table if not exists public.user_rewards (
    id uuid default extensions.uuid_generate_v4() primary key,
    user_id uuid references auth.users(id) on delete cascade,
    reward_id uuid references public.rewards(id) on delete cascade,
    cost_xp int not null,
    unlocked_at timestamptz default now(),
    unique(user_id, reward_id)
);
create index if not exists idx_user_rewards_user on public.user_rewards(user_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- Gamification Phase 4 — Leaderboards
-- ═══════════════════════════════════════════════════════════════════════════
-- Privacy: users opt out by setting leaderboard_opt_in = false.
-- Period queries aggregate xp_transactions; all-time uses total_xp.
alter table public.user_gamification
    add column if not exists leaderboard_opt_in boolean default true;

-- Helps period leaderboard scans (positive earnings only)
create index if not exists idx_xp_transactions_period
    on public.xp_transactions(created_at, user_id)
    where amount > 0;


ALTER TABLE achievements 
  ADD COLUMN IF NOT EXISTS code TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS tier TEXT;
