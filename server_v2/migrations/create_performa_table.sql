-- Migration: create performa table
-- Run once against your Supabase project via the SQL editor or CLI.

CREATE TABLE IF NOT EXISTS performa (
  user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  manual_data  JSONB NOT NULL DEFAULT '{}',
  ai_data      JSONB NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at on every row write
CREATE OR REPLACE FUNCTION update_performa_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_performa_updated_at
  BEFORE UPDATE ON performa
  FOR EACH ROW EXECUTE FUNCTION update_performa_updated_at();

-- RLS: each user reads and writes only their own row
ALTER TABLE performa ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own performa"
  ON performa FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
