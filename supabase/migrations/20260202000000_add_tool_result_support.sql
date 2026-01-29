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
-- First drop the existing constraint, then add the updated one
ALTER TABLE chat_messages
    DROP CONSTRAINT IF EXISTS chat_messages_role_check;

ALTER TABLE chat_messages
    ADD CONSTRAINT chat_messages_role_check
    CHECK (role IN ('user', 'assistant', 'system', 'tool', 'tool_result'));

-- Add index for efficient lookup of tool results by tool_use_id
CREATE INDEX IF NOT EXISTS idx_chat_messages_tool_use_id
    ON chat_messages(tool_use_id)
    WHERE tool_use_id IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN chat_messages.tool_use_id IS 'Links tool_result messages back to their corresponding tool_use block ID';
