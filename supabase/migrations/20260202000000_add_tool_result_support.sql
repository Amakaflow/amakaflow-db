-- ============================================================================
-- AMA-502: Add support for persisting tool results as separate messages
-- ============================================================================
-- This migration:
-- 1. Adds tool_use_id column to link tool results back to tool_use blocks
-- 2. Updates role constraint to allow 'tool_result' role
-- ============================================================================

-- Add tool_use_id column for linking tool results to their tool_use blocks
ALTER TABLE chat_messages
    ADD COLUMN IF NOT EXISTS tool_use_id TEXT;

-- Update role constraint to include 'tool_result'
-- PostgreSQL auto-generates constraint names for inline CHECK constraints,
-- so we need to dynamically find and drop the existing role constraint.
DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    -- Find the existing role check constraint by looking for CHECK constraints
    -- on chat_messages that reference the 'role' column with IN clause
    SELECT c.conname INTO constraint_name
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE t.relname = 'chat_messages'
      AND c.contype = 'c'  -- CHECK constraint
      AND pg_get_constraintdef(c.oid) LIKE '%role%IN%';

    -- Drop the existing constraint if found
    IF constraint_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE chat_messages DROP CONSTRAINT ' || quote_ident(constraint_name);
    END IF;
END $$;

-- Add the updated constraint with 'tool_result' role
ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_role_check
    CHECK (role IN ('user', 'assistant', 'system', 'tool', 'tool_result'));

-- Add index for efficient lookup of tool results by tool_use_id
CREATE INDEX IF NOT EXISTS idx_chat_messages_tool_use_id
    ON chat_messages(tool_use_id)
    WHERE tool_use_id IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN chat_messages.tool_use_id IS 'Links tool_result messages back to their corresponding tool_use block ID';
