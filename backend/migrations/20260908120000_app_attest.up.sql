-- App Attest credentials, the sessions they mint, and the challenges that keep
-- both fresh. Replaces the single shared API key for everything the app calls.

CREATE TABLE attest_keys (
    -- Lowercase hex of the SHA256 of the attested public key, which is also the
    -- key identifier the client sends on every request.
    key_id TEXT PRIMARY KEY,
    -- Uncompressed SEC1 point for the P-256 key held in the Secure Enclave.
    public_key BLOB NOT NULL,
    user_id TEXT NOT NULL,
    bundle_id TEXT NOT NULL,
    environment TEXT NOT NULL,
    -- Apple's attestation receipt, kept for later fraud-risk queries against
    -- data.appattest.apple.com.
    receipt BLOB,
    -- High-water mark of accepted assertion counters, plus the bitmap of the 64
    -- counters below it. See `attest::ReplayWindow`.
    sign_count INTEGER NOT NULL DEFAULT 0,
    replay_window INTEGER NOT NULL DEFAULT 0,
    created_at_ms INTEGER NOT NULL,
    last_seen_at_ms INTEGER NOT NULL,
    revoked_at_ms INTEGER
);

CREATE INDEX attest_keys_user_id ON attest_keys (user_id);

CREATE TABLE app_sessions (
    -- Only the hash is stored, so a database copy does not yield live sessions.
    token_hash BLOB PRIMARY KEY,
    -- Public handle for the session, bound into the client data an assertion
    -- signs so an assertion cannot be moved between sessions.
    session_id TEXT NOT NULL UNIQUE,
    -- Null for the unattested fallback issued to devices with no Secure Enclave.
    key_id TEXT REFERENCES attest_keys (key_id),
    user_id TEXT NOT NULL,
    attested INTEGER NOT NULL,
    bundle_id TEXT,
    issued_at_ms INTEGER NOT NULL,
    expires_at_ms INTEGER NOT NULL
);

CREATE INDEX app_sessions_expires_at ON app_sessions (expires_at_ms);
CREATE INDEX app_sessions_key_id ON app_sessions (key_id);

CREATE TABLE attest_challenges (
    challenge TEXT PRIMARY KEY,
    issued_at_ms INTEGER NOT NULL,
    expires_at_ms INTEGER NOT NULL,
    consumed_at_ms INTEGER
);

CREATE INDEX attest_challenges_expires_at ON attest_challenges (expires_at_ms);
