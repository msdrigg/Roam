-- Retain crash payloads after a symbolication permanently fails.
--
-- Dead-lettering used to delete the payload immediately, which made "fix the
-- symbolicator, then reprocess what it lost" impossible - the
-- deep-stack crashes rejected by the old parser being exactly that case.
-- Payloads now survive their failure and are reaped on age instead, so a fix
-- has a window in which it can be applied retroactively.
--
-- NULL means the payload file is still on disk. Set to the reap time once the
-- file has been removed, so the sweep does not keep revisiting the same rows.
ALTER TABLE pending_symbolications ADD COLUMN payload_reaped_at_ms INTEGER;

-- Supports the reap sweep: failed rows, oldest first, not yet reaped.
CREATE INDEX idx_pending_symbolications_reap
    ON pending_symbolications (failed_at_ms, payload_reaped_at_ms);
