-- Restore the original untyped `device_id PRIMARY KEY`.
--
-- Reverting reintroduces the sqlx 0.9.0 segfault described in the up migration:
-- with this applied, `query_as!` cannot compile against a live database and
-- `cargo sqlx prepare` cannot run. Only roll back if you are also reverting the
-- code that depends on the typed column.

CREATE TABLE users_old (
    device_id PRIMARY KEY,
    thread_id int8 NOT NULL UNIQUE,
    apns_token TEXT,
    device_info_json TEXT,
    ai_disabled INTEGER NOT NULL DEFAULT 0
);

INSERT INTO users_old (device_id, thread_id, apns_token, device_info_json, ai_disabled)
SELECT device_id, thread_id, apns_token, device_info_json, ai_disabled FROM users;

DROP TABLE users;

ALTER TABLE users_old RENAME TO users;
