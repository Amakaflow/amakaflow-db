-- Feature Flags Table
-- Supports both global and per-user feature flags for controlled rollout
-- Part of AMA-437: Feature Flags & Beta Rollout Configuration

-- Create feature_flags table
CREATE TABLE IF NOT EXISTS feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flag_key TEXT NOT NULL,
    scope TEXT NOT NULL CHECK (scope IN ('global', 'user')),
    user_id TEXT,  -- NULL for global flags, Clerk user ID for user-specific flags
    value JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Unique constraint: one global flag per key, one user flag per key per user
    CONSTRAINT unique_flag_scope UNIQUE (flag_key, scope, user_id)
);

-- Create index for efficient lookups
CREATE INDEX IF NOT EXISTS idx_feature_flags_flag_key ON feature_flags(flag_key);
CREATE INDEX IF NOT EXISTS idx_feature_flags_user_id ON feature_flags(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_feature_flags_scope ON feature_flags(scope);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_feature_flags_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_feature_flags_updated_at
    BEFORE UPDATE ON feature_flags
    FOR EACH ROW
    EXECUTE FUNCTION update_feature_flags_updated_at();

-- Enable RLS
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Users can read global flags
CREATE POLICY "Users can read global feature flags"
    ON feature_flags
    FOR SELECT
    USING (scope = 'global');

-- Users can read their own user-specific flags (via RPC, not direct access)
-- We use a restrictive policy here since we want access controlled via RPC
CREATE POLICY "Service role full access to feature flags"
    ON feature_flags
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- RPC function to get merged feature flags for a user
-- Returns global flags with user-specific overrides applied
CREATE OR REPLACE FUNCTION get_user_feature_flags(p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    result JSONB := '{}';
    global_flags JSONB := '{}';
    user_flags JSONB := '{}';
    flag_record RECORD;
BEGIN
    -- Collect all global flags
    FOR flag_record IN
        SELECT flag_key, value
        FROM feature_flags
        WHERE scope = 'global'
    LOOP
        global_flags := global_flags || jsonb_build_object(flag_record.flag_key, flag_record.value);
    END LOOP;

    -- Collect user-specific flags
    FOR flag_record IN
        SELECT flag_key, value
        FROM feature_flags
        WHERE scope = 'user' AND user_id = p_user_id
    LOOP
        user_flags := user_flags || jsonb_build_object(flag_record.flag_key, flag_record.value);
    END LOOP;

    -- Merge: user flags override global flags
    result := global_flags || user_flags;

    RETURN result;
END;
$$;

-- Seed initial global feature flags for chat beta rollout
INSERT INTO feature_flags (flag_key, scope, user_id, value) VALUES
    ('chat_enabled', 'global', NULL, 'true'::jsonb),
    ('chat_beta_period', 'global', NULL, 'true'::jsonb),
    ('chat_voice_enabled', 'global', NULL, 'true'::jsonb),
    ('chat_functions_enabled', 'global', NULL, '["get_user_profile", "search_workouts", "get_workout_history"]'::jsonb),
    ('chat_rate_limit_tier', 'global', NULL, '"free"'::jsonb)
ON CONFLICT (flag_key, scope, user_id) DO NOTHING;

-- Add comment for documentation
COMMENT ON TABLE feature_flags IS 'Feature flags for controlled rollout. Supports global and per-user flags.';
COMMENT ON FUNCTION get_user_feature_flags(TEXT) IS 'Returns merged feature flags for a user (user overrides global).';
