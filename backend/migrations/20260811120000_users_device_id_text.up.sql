-- Give users.device_id an explicit TEXT type.
--
-- The column was originally declared as bare `device_id PRIMARY KEY`, with no
-- type at all. That is legal SQLite, but sqlx 0.9.0 segfaults while describing
-- such a column: `sqlite3_table_column_metadata()` reports a NULL declared type
-- and `StatementHandle::column_nullable` dereferences it unchecked. Because the
-- `query!` macros describe a live database during expansion, the crash takes
-- out rustc, so no `query_as!` in this crate can compile against a real
-- database and `cargo sqlx prepare` cannot run.
--
-- SQLite has no ALTER COLUMN, so this is the standard create/copy/drop/rename
-- rebuild: https://sqlite.org/lang_altertable.html#otheralter
--
-- Nothing references `users` -- no foreign keys, triggers or views, and the only
-- indexes are the ones SQLite creates itself for PRIMARY KEY and UNIQUE -- so
-- the rebuild needs no index or trigger recreation, and no `PRAGMA foreign_keys`
-- juggling (which would not work here anyway: sqlx runs each migration inside a
-- transaction, where that pragma is a no-op).
--
-- The new table spells out the schema as the migrations have accumulated it,
-- which includes `ai_disabled` from 20260507120000_user_ai_disabled.
--
-- Affinity note: the old untyped column had BLOB affinity, storing values
-- exactly as passed; TEXT affinity coerces numeric values to strings. Every
-- existing device_id is already stored as text, so this rebuild converts
-- nothing.

CREATE TABLE users_new (
    device_id TEXT PRIMARY KEY,
    thread_id int8 NOT NULL UNIQUE,
    apns_token TEXT,
    device_info_json TEXT,
    ai_disabled INTEGER NOT NULL DEFAULT 0
);

INSERT INTO users_new (device_id, thread_id, apns_token, device_info_json, ai_disabled)
SELECT device_id, thread_id, apns_token, device_info_json, ai_disabled FROM users;

DROP TABLE users;

ALTER TABLE users_new RENAME TO users;
