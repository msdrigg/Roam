DROP INDEX IF EXISTS idx_pending_symbolications_reap;

ALTER TABLE pending_symbolications DROP COLUMN payload_reaped_at_ms;
