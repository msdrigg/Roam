-- Review state for symbolicated crashes, keyed by the Discord thread the
-- report was posted into.
--
-- A thread counts as *unreviewed* when it has never been reviewed, or when a
-- newer crash arrived after the last review:
--
--     reviewed_at_ms IS NULL OR reviewed_at_ms < latest_crash_at_ms
--
-- Marking a thread reviewed therefore silences it only until its next crash,
-- rather than permanently.
CREATE TABLE crash_reviews (
    thread_id INTEGER PRIMARY KEY,
    -- Discord message carrying the most recent symbolicated.txt for this thread.
    latest_crash_message_id INTEGER,
    latest_crash_at_ms INTEGER NOT NULL,
    -- Facts pulled out of the symbolicated report, so callers can triage from
    -- the list endpoint without downloading every attachment.
    app_version TEXT,
    device_type TEXT,
    os_version TEXT,
    exception_type INTEGER,
    signal INTEGER,
    termination_code TEXT,
    -- Review state.
    reviewed_at_ms INTEGER,
    reviewed_by TEXT,
    reviewed_message_id INTEGER,
    matched_rule_id TEXT,
    review_note TEXT
);

CREATE INDEX idx_crash_reviews_unreviewed
    ON crash_reviews (reviewed_at_ms, latest_crash_at_ms DESC);

CREATE INDEX idx_crash_reviews_recent
    ON crash_reviews (latest_crash_at_ms DESC);
