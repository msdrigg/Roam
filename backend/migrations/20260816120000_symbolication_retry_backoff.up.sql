-- Space out symbolication retries.
--
-- `release_lease_with_error` cleared `leased_at_ms` so a failed payload was
-- immediately re-leasable, and the worker drains in a tight loop, so all three
-- attempts burned inside a quarter of a second. A transient failure (dSYM fetch
-- blip, ipsw rate limit) was therefore retried three times against the same bad
-- second and dead-lettered just as permanently as a poison payload.
--
-- `retry_after_ms` is the earliest wall-clock time a row may be leased again.
-- NULL means "no wait" and is the correct default for rows that have never
-- failed, including every row that predates this migration.
ALTER TABLE pending_symbolications ADD COLUMN retry_after_ms INTEGER;

-- The lease scan filters on this alongside the existing eligibility columns.
DROP INDEX IF EXISTS idx_pending_symbolications_lease;
CREATE INDEX idx_pending_symbolications_lease
    ON pending_symbolications (
        completed_at_ms, failed_at_ms, leased_at_ms, retry_after_ms, received_at_ms
    );
