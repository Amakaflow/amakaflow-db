-- AMA-433: Create workout_edit_history table for audit trail
-- Tracks all patch operations applied to workouts for debugging and auditing

CREATE TABLE IF NOT EXISTS workout_edit_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_id UUID NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  operations JSONB NOT NULL,
  changes_applied INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for looking up edit history by workout
CREATE INDEX IF NOT EXISTS idx_workout_edit_history_workout_id
  ON workout_edit_history(workout_id);

-- Index for looking up edit history by user
CREATE INDEX IF NOT EXISTS idx_workout_edit_history_user_id
  ON workout_edit_history(user_id);

-- Index for time-based queries (e.g., recent edits)
CREATE INDEX IF NOT EXISTS idx_workout_edit_history_created_at
  ON workout_edit_history(created_at DESC);

-- RLS policies
ALTER TABLE workout_edit_history ENABLE ROW LEVEL SECURITY;

-- Users can only view their own edit history
CREATE POLICY "Users can view own edit history"
  ON workout_edit_history FOR SELECT
  USING (user_id = auth.uid()::text);

-- Service role can insert (API writes via service role key)
CREATE POLICY "Service role can insert edit history"
  ON workout_edit_history FOR INSERT
  WITH CHECK (true);

-- Comment on table
COMMENT ON TABLE workout_edit_history IS 'Audit trail for workout patch operations (AMA-433)';
COMMENT ON COLUMN workout_edit_history.operations IS 'JSONB array of patch operations applied';
COMMENT ON COLUMN workout_edit_history.changes_applied IS 'Number of operations that resulted in changes';
