-- Bubbles-AI Supabase schema-only backup
-- Date: 2026-05-08
-- Source: project_ref czjwoqwbwtojlypbzupi (via Supabase MCP)
-- Captured BEFORE Phase A (drop unused tables) + Phase B (enable RLS) + Phase D (indexes).
--
-- Restore (schema only, on a fresh DB):
--   psql "<connection-string>" -f bubbles_schema_backup_2026-05-08.sql
--
-- DOES NOT include row data. If a Phase B RLS policy mistake locks you out,
-- toggle RLS off via:  ALTER TABLE <name> DISABLE ROW LEVEL SECURITY;
-- (data is not lost by enabling RLS — only access is gated.)

CREATE TABLE public.achievements (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  title text NOT NULL,
  description text,
  icon text DEFAULT '🏆'::text,
  category text DEFAULT 'general'::text,
  criteria_type text NOT NULL,
  criteria_value integer NOT NULL,
  xp_reward integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  code text,
  tier text
);

CREATE TABLE public.api_keys (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  key_name text NOT NULL,
  key_hash text NOT NULL,
  prefix text NOT NULL,
  scopes text[],
  last_used_at timestamp with time zone,
  expires_at timestamp with time zone,
  is_revoked boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.app_feedback (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  rating integer,
  feedback_text text,
  app_version text,
  os_info text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.audio_sessions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  file_path text,
  duration_seconds numeric,
  sample_rate integer,
  channels integer,
  snr_db numeric,
  wakeword_detected boolean,
  transcription_confidence numeric,
  recorded_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.audit_log (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  action text NOT NULL,
  entity_type text,
  entity_id uuid,
  details jsonb,
  ip_address text,
  user_agent text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.calendar_integrations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  provider text NOT NULL,
  access_token text NOT NULL,
  refresh_token text,
  sync_token text,
  expires_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.calendar_sync_log (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  event_id uuid,
  external_event_id text NOT NULL,
  provider text NOT NULL,
  sync_status text NOT NULL,
  error_message text,
  synced_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.coaching_reports (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
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
  generated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.consultant_logs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  session_id uuid,
  query text,
  question text,
  response text,
  answer text,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  source_screen text
);

CREATE TABLE public.data_deletion_requests (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  status text DEFAULT 'pending'::text,
  requested_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  processed_by uuid
);

CREATE TABLE public.entities (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  canonical_name text NOT NULL,
  display_name text,
  entity_type text NOT NULL,
  aliases text[],
  description text,
  mention_count integer DEFAULT 0,
  is_archived boolean DEFAULT false,
  last_seen_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.entity_attributes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  entity_id uuid,
  attribute_key text NOT NULL,
  attribute_value text,
  value_type text DEFAULT 'string'::text,
  confidence numeric DEFAULT 1.0,
  source_session_id uuid,
  source_session text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.entity_relations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  source_id uuid,
  target_id uuid,
  relation text NOT NULL,
  strength numeric DEFAULT 1.0,
  source_session text,
  updated_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.entity_tags (
  entity_id uuid NOT NULL,
  tag_id uuid NOT NULL,
  user_id uuid NOT NULL
);

CREATE TABLE public.events (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  session_id uuid,
  title text NOT NULL,
  description text,
  due_text text,
  start_time timestamp with time zone,
  end_time timestamp with time zone,
  location text,
  is_all_day boolean DEFAULT false,
  is_completed boolean DEFAULT false,
  external_event_id text,
  sync_provider text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.expenses (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  amount numeric NOT NULL,
  currency text DEFAULT 'USD'::text,
  category text,
  merchant text,
  date timestamp with time zone DEFAULT now(),
  receipt_url text,
  is_recurring boolean DEFAULT false,
  notes text
);

CREATE TABLE public.feature_flags (
  id text NOT NULL,
  description text,
  is_enabled_globally boolean DEFAULT false,
  rollout_percentage integer DEFAULT 0,
  enabled_for_users uuid[],
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.feedback (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  session_id uuid,
  log_id uuid,
  consultant_log_id uuid,
  feedback_type text,
  rating integer,
  value integer,
  comment text,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  idempotency_key text
);

CREATE TABLE public.health_metrics (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  metric_type text NOT NULL,
  metric_value numeric,
  metric_unit text,
  recorded_at timestamp with time zone DEFAULT now(),
  source text DEFAULT 'manual'::text
);

CREATE TABLE public.highlights (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  session_id uuid,
  highlight_type text NOT NULL,
  title text,
  body text,
  content text NOT NULL,
  priority integer DEFAULT 1,
  is_resolved boolean DEFAULT false,
  is_dismissed boolean DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.integrations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  provider text NOT NULL,
  access_token text,
  refresh_token text,
  scopes text[],
  expires_at timestamp with time zone,
  is_active boolean DEFAULT true,
  sync_status text DEFAULT 'ok'::text,
  last_sync_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.iot_devices (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  device_name text NOT NULL,
  device_type text,
  room text,
  provider text,
  external_id text,
  state jsonb,
  is_online boolean DEFAULT true,
  last_synced_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.iot_logs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  device_id uuid,
  action text NOT NULL,
  triggered_by text,
  previous_state jsonb,
  new_state jsonb,
  "timestamp" timestamp with time zone DEFAULT now()
);

CREATE TABLE public.knowledge_graphs (
  user_id uuid NOT NULL,
  graph_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.memory (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  session_id uuid,
  content text NOT NULL,
  memory_type text NOT NULL DEFAULT 'general'::text,
  embedding vector(384),
  importance numeric DEFAULT 1.0,
  confidence numeric DEFAULT 1.0,
  source text DEFAULT 'inferred'::text,
  is_pinned boolean DEFAULT false,
  is_archived boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  last_accessed_at timestamp with time zone,
  expires_at timestamp with time zone
);

CREATE TABLE public.multimodal_attachments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_log_id uuid,
  file_type text,
  file_url text,
  mime_type text,
  file_size_bytes bigint,
  extracted_text text,
  metadata jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.notification_tokens (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  token text NOT NULL,
  device_type text,
  is_active boolean DEFAULT true,
  added_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.notifications (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  title text NOT NULL,
  body text,
  notif_type text,
  action_url text,
  is_read boolean DEFAULT false,
  read_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.onboarding_progress (
  user_id uuid NOT NULL,
  has_completed_welcome boolean DEFAULT false,
  has_set_voice boolean DEFAULT false,
  has_connected_calendar boolean DEFAULT false,
  has_completed_tutorial boolean DEFAULT false,
  current_step text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.performa (
  user_id uuid NOT NULL,
  manual_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  ai_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  full_name text,
  avatar_url text,
  dob date,
  gender text,
  country text,
  locale text DEFAULT 'en_US'::text,
  timezone text DEFAULT 'UTC'::text,
  occupation text,
  company text,
  bio text,
  is_developer boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.quest_definitions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  title text NOT NULL,
  description text,
  quest_type text DEFAULT 'daily'::text,
  action_type text NOT NULL,
  target integer NOT NULL DEFAULT 1,
  xp_reward integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  focus_area text,
  difficulty text DEFAULT 'medium'::text,
  mission_type text DEFAULT 'action'::text,
  brief jsonb
);

CREATE TABLE public.rewards (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  title text NOT NULL,
  description text,
  icon text DEFAULT '🎁'::text,
  category text DEFAULT 'general'::text,
  cost_xp integer NOT NULL,
  sort_order integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.sentiment_logs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  session_id uuid,
  turn_index integer NOT NULL,
  sentiment_score double precision,
  emotion_label text,
  speaker_role text,
  score double precision,
  label text,
  recorded_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.session_analytics (
  session_id uuid NOT NULL,
  user_id uuid NOT NULL,
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
  computed_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.session_exports (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  session_id uuid,
  export_format text NOT NULL,
  file_url text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.session_logs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  turn_index integer DEFAULT 0,
  role text NOT NULL,
  content text,
  content_html text,
  model_used text,
  latency_ms integer,
  tokens_used integer,
  finish_reason text,
  has_error boolean DEFAULT false,
  error_message text,
  speaker_label text,
  confidence numeric,
  sentiment_score numeric,
  sentiment_label text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.session_tags (
  session_id uuid NOT NULL,
  tag_id uuid NOT NULL,
  user_id uuid NOT NULL
);

CREATE TABLE public.sessions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  title text,
  summary text,
  session_type text DEFAULT 'general'::text,
  mode text DEFAULT 'live_wingman'::text,
  device_id uuid,
  start_time timestamp with time zone DEFAULT now(),
  end_time timestamp with time zone,
  ended_at timestamp with time zone,
  status text DEFAULT 'active'::text,
  is_starred boolean DEFAULT false,
  is_ephemeral boolean DEFAULT false,
  is_multiplayer boolean DEFAULT false,
  persona text DEFAULT 'casual'::text,
  sentiment_score numeric,
  token_usage_prompt integer DEFAULT 0,
  token_usage_completion integer DEFAULT 0,
  total_cost_usd numeric DEFAULT 0.0,
  created_at timestamp with time zone DEFAULT now(),
  deleted_at timestamp with time zone,
  idempotency_key text
);

CREATE TABLE public.shared_sessions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  workspace_id uuid,
  shared_by uuid,
  permission_level text DEFAULT 'read'::text,
  shared_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.subscription_usage (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  period_start timestamp with time zone NOT NULL,
  period_end timestamp with time zone NOT NULL,
  total_tokens_used bigint DEFAULT 0,
  audio_minutes_used numeric DEFAULT 0.0,
  images_generated integer DEFAULT 0,
  advanced_queries integer DEFAULT 0
);

CREATE TABLE public.subscriptions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  stripe_customer_id text,
  stripe_subscription_id text,
  plan_id text NOT NULL,
  status text NOT NULL,
  current_period_start timestamp with time zone,
  current_period_end timestamp with time zone,
  cancel_at_period_end boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.tags (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  name text NOT NULL,
  color text,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.tasks (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  title text NOT NULL,
  description text,
  due_date timestamp with time zone,
  priority text DEFAULT 'medium'::text,
  status text DEFAULT 'pending'::text,
  category text,
  source_session_id uuid,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.team_members (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  workspace_id uuid,
  user_id uuid,
  role text DEFAULT 'member'::text,
  joined_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.team_workspaces (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  owner_id uuid,
  name text NOT NULL,
  domain text,
  billing_email text,
  enterprise_tier boolean DEFAULT false,
  sso_enabled boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.trips (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  destination text NOT NULL,
  start_date date,
  end_date date,
  purpose text,
  status text DEFAULT 'planned'::text,
  itinerary jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.user_achievements (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  achievement_id uuid,
  awarded_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.user_devices (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  device_id text NOT NULL,
  device_model text,
  os_version text,
  app_version text,
  fcm_token text,
  apns_token text,
  last_ip_address text,
  last_location geometry(Point,4326),
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  last_active_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.user_gamification (
  user_id uuid NOT NULL,
  total_xp integer DEFAULT 0,
  level integer DEFAULT 1,
  current_streak integer DEFAULT 0,
  longest_streak integer DEFAULT 0,
  streak_freezes integer DEFAULT 1,
  last_active_date date,
  updated_at timestamp with time zone DEFAULT now(),
  xp_spent integer DEFAULT 0,
  leaderboard_opt_in boolean DEFAULT true
);

CREATE TABLE public.user_mistakes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  session_id uuid,
  rule_id text NOT NULL,
  category text NOT NULL,
  snippet text NOT NULL,
  suggestion text,
  source text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.user_quests (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  quest_id uuid,
  progress integer DEFAULT 0,
  target integer NOT NULL,
  is_completed boolean DEFAULT false,
  xp_awarded boolean DEFAULT false,
  assigned_date date NOT NULL,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  reason text,
  brief_state jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE public.user_rewards (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  reward_id uuid,
  cost_xp integer NOT NULL,
  unlocked_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.user_routines (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  routine_name text NOT NULL,
  trigger_type text,
  trigger_condition jsonb,
  actions jsonb,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.user_settings (
  user_id uuid NOT NULL,
  theme text DEFAULT 'system'::text,
  accent_color text,
  font_size text DEFAULT 'medium'::text,
  voice_assistant_name text DEFAULT 'Bubbles'::text,
  assistant_persona text DEFAULT 'friendly'::text,
  assistant_voice_id text,
  speech_rate numeric DEFAULT 1.0,
  pitch numeric DEFAULT 1.0,
  haptic_feedback boolean DEFAULT true,
  auto_play_audio boolean DEFAULT true,
  transcription_language text DEFAULT 'en-US'::text,
  enable_nsfw_filter boolean DEFAULT true,
  data_sharing_opt_in boolean DEFAULT false,
  updated_at timestamp with time zone DEFAULT now(),
  reminder_hour smallint DEFAULT 19,
  reminder_timezone text DEFAULT 'UTC'::text,
  last_reminder_sent_date date
);

CREATE TABLE public.voice_enrollments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  embedding vector(192) NOT NULL,
  samples_count integer DEFAULT 0,
  model_version text,
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE public.webhooks (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  url text NOT NULL,
  events text[],
  secret text,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.xp_transactions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  amount integer NOT NULL,
  source_type text NOT NULL,
  source_id text,
  description text,
  created_at timestamp with time zone DEFAULT now()
);
