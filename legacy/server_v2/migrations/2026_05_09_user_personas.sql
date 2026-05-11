-- Migration: replace performa table with typed user_personas + session_context column
-- Run once against Supabase project via SQL editor or CLI.

-- 1. Drop old performa infra
DROP TRIGGER IF EXISTS trg_performa_updated_at ON performa;
DROP FUNCTION IF EXISTS update_performa_updated_at();
DROP POLICY IF EXISTS "Users manage own performa" ON performa;
DROP TABLE IF EXISTS performa;

-- 2. Create user_personas
CREATE TABLE user_personas (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  age_range TEXT CHECK (age_range IN ('<18','18-24','25-34','35-44','45+')),
  role_primary TEXT NOT NULL CHECK (role_primary IN
    ('student','teacher','professional','manager','freelancer','homemaker','other')),
  profession_detail TEXT,
  expertise_tags TEXT[] NOT NULL DEFAULT '{}',
  native_language TEXT NOT NULL,
  learning_language TEXT NOT NULL DEFAULT 'en',
  proficiency_self_rated TEXT CHECK (proficiency_self_rated IN
    ('beginner','intermediate','advanced','fluent')),
  formality_preference TEXT CHECK (formality_preference IN
    ('casual','neutral','formal','mixed')) DEFAULT 'neutral',
  communication_style TEXT[] NOT NULL DEFAULT '{}',
  primary_goals TEXT[] NOT NULL DEFAULT '{}',
  typical_scenarios TEXT[] NOT NULL DEFAULT '{}',
  cultural_context TEXT,
  avoid_list TEXT,
  role_family TEXT NOT NULL CHECK (role_family IN
    ('educator','learner','professional','casual','default')),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION update_user_personas_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_personas_updated_at
  BEFORE UPDATE ON user_personas
  FOR EACH ROW EXECUTE FUNCTION update_user_personas_updated_at();

ALTER TABLE user_personas ENABLE ROW LEVEL SECURITY;
CREATE POLICY up_owner_select ON user_personas FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY up_owner_insert ON user_personas FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY up_owner_update ON user_personas FOR UPDATE USING (auth.uid() = user_id);

-- 3. Per-meeting context column on sessions
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS session_context JSONB;
