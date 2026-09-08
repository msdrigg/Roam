-- One Mac App Store receipt maps to one install.
--
-- App Attest does not exist below macOS 27, so those Macs authenticate with
-- their App Store receipt instead. A receipt is a static file and therefore
-- replayable, so binding it here is what stops a copied one opening a second
-- conversation.
CREATE TABLE receipt_bindings (
    -- SHA256 over the receipt's opaque value and hash. Derived, so the receipt
    -- itself is never stored.
    fingerprint BLOB PRIMARY KEY,
    user_id TEXT NOT NULL,
    bundle_id TEXT NOT NULL,
    app_version TEXT,
    first_seen_at_ms INTEGER NOT NULL,
    last_seen_at_ms INTEGER NOT NULL
);

CREATE INDEX receipt_bindings_user_id ON receipt_bindings (user_id);
