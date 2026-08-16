DROP INDEX IF EXISTS idx_pending_symbolications_lease;

ALTER TABLE pending_symbolications DROP COLUMN retry_after_ms;

CREATE INDEX idx_pending_symbolications_lease
    ON pending_symbolications (completed_at_ms, failed_at_ms, leased_at_ms, received_at_ms);
