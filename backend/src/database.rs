use std::{path::PathBuf, str::FromStr, time::Duration};

use crate::{utils::i64_to_string, UserId};
use anyhow::Context;
use sqlx::{
    sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions},
    types::Json,
};
use tokio::fs::create_dir_all;

use crate::cli::RoamCli;

#[derive(Debug, Clone)]
pub struct DatabaseClient {
    pub reader_pool: sqlx::SqlitePool,
    pub writer_pool: sqlx::SqlitePool,
}

impl DatabaseClient {
    pub async fn new(cli: &RoamCli) -> Result<Self, anyhow::Error> {
        // Create data directory if not exists
        create_dir_all(&cli.data_dir)
            .await
            .context("Failed to create data directory")?;

        let db_path = PathBuf::from(cli.data_dir.clone())
            .join("cloud-backend.db")
            .to_string_lossy()
            .to_string();

        let connection_opts = SqliteConnectOptions::from_str(&db_path)
            .context("Error parsing database url")?
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal);

        tracing::info!("Connecting to database");
        // Get self
        let reader_pool = SqlitePoolOptions::new()
            .max_connections(10)
            .min_connections(10)
            .connect_with(connection_opts.clone())
            .await
            .context("Error creating SqlitePool reader")?;
        let writer_pool = SqlitePoolOptions::new()
            .max_connections(1)
            .min_connections(1)
            .connect_with(connection_opts)
            .await
            .context("Error creating SqlitePool writer")?;

        // Run migrations on database
        sqlx::migrate!("./migrations")
            .run(&writer_pool)
            .await
            .context("Error running migrations, can't start")?;
        Ok(Self {
            reader_pool,
            writer_pool,
        })
    }

    pub async fn get_user_with_id(
        &self,
        device_id: &UserId,
    ) -> Result<Option<User>, anyhow::Error> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT thread_id as "thread_id!", device_id as "device_id!: String", apns_token,
            device_info_json as "device_info?: Json<DeviceInfo>",
            ai_disabled as "ai_disabled!: bool"
            FROM users WHERE device_id = ?
            "#,
            device_id
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error fetching user")?;
        Ok(user)
    }

    pub async fn get_user_with_thread(
        &self,
        thread_id: i64,
    ) -> Result<Option<User>, anyhow::Error> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT thread_id as "thread_id!", device_id as "device_id!: String", apns_token,
            device_info_json as "device_info?: Json<DeviceInfo>",
            ai_disabled as "ai_disabled!: bool"
            FROM users WHERE thread_id = ?
            "#,
            thread_id
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error fetching user")?;
        Ok(user)
    }

    pub async fn clear_user_apns(&self, device_id: &UserId) -> Result<(), anyhow::Error> {
        tracing::info!("Clearing APNS token for user {}", device_id);
        sqlx::query_scalar!(
            r#"
            UPDATE users
            SET apns_token = NULL
            WHERE device_id = ?
            returning device_id as "device_id!: String"
            "#,
            device_id
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error updating user")?;
        Ok(())
    }

    pub async fn update_user(
        &self,
        device_id: &UserId,
        user: &UserUpdate,
    ) -> Result<User, anyhow::Error> {
        let device_info_json = user
            .device_info
            .as_ref()
            .map(|device_info| Json(device_info.clone()));
        let user = sqlx::query_as!(
            User,
            r#"
            UPDATE users
            SET
                thread_id = COALESCE(?, thread_id),
                apns_token = COALESCE(?, apns_token),
                device_info_json = COALESCE(?, device_info_json)
            WHERE device_id = ?
            RETURNING
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                apns_token, device_info_json as "device_info?: Json<DeviceInfo>",
                ai_disabled as "ai_disabled!: bool"
            "#,
            user.thread_id,
            user.apns_token,
            device_info_json,
            device_id
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error updating user")?;
        Ok(user)
    }

    pub async fn set_thread_ai_disabled(
        &self,
        thread_id: i64,
        ai_disabled: bool,
    ) -> Result<bool, anyhow::Error> {
        let result = sqlx::query!(
            r#"
            UPDATE users SET ai_disabled = ? WHERE thread_id = ?
            "#,
            ai_disabled,
            thread_id
        )
        .execute(&self.writer_pool)
        .await
        .context("Error updating thread ai_disabled flag")?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn get_parameter(&self, key: &str) -> Result<Option<String>, anyhow::Error> {
        let value = sqlx::query_scalar!(
            r#"
            SELECT value  FROM parameters WHERE key = ?
            "#,
            key
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error fetching user")?;
        Ok(value)
    }

    pub async fn set_parameter(&self, key: &str, value: &str) -> Result<(), anyhow::Error> {
        sqlx::query!(
            r#"
                INSERT INTO parameters (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
            "#,
            key,
            value
        )
        .execute(&self.writer_pool)
        .await
        .context("Error setting parameter")?;
        Ok(())
    }

    pub async fn get_last_alerted_message(&self) -> Result<Option<i64>, anyhow::Error> {
        let param = self.get_parameter("last_alerted_message").await?;

        if let Some(param) = param {
            Ok(Some(param.parse()?))
        } else {
            Ok(None)
        }
    }

    pub async fn set_last_alerted_message(&self, message_id: i64) -> Result<(), anyhow::Error> {
        return self
            .set_parameter("last_alerted_message", &message_id.to_string())
            .await;
    }

    pub async fn create_user(&self, user: &User) -> Result<User, anyhow::Error> {
        sqlx::query_as!(
            User,
            r#"
            INSERT INTO users (device_id, thread_id, apns_token, device_info_json)
            VALUES (?, ?, ?, ?)
            RETURNING device_id as "device_id!: String", thread_id as "thread_id!", apns_token,
            device_info_json as "device_info?: Json<DeviceInfo>",
            ai_disabled as "ai_disabled!: bool"
            "#,
            user.device_id,
            user.thread_id,
            user.apns_token,
            user.device_info
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error creating user")
    }

    pub async fn insert_pending_symbolication(
        &self,
        row: &PendingSymbolication,
    ) -> Result<(), anyhow::Error> {
        sqlx::query!(
            r#"
            INSERT INTO pending_symbolications (
                id, device_id, thread_id, payload_path, diagnostics_json,
                installation_info_json, binary_uuids_json, payload_index,
                received_at_ms, leased_at_ms, completed_at_ms, failed_at_ms,
                attempts, last_error
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#,
            row.id,
            row.device_id,
            row.thread_id,
            row.payload_path,
            row.diagnostics_json,
            row.installation_info_json,
            row.binary_uuids_json,
            row.payload_index,
            row.received_at_ms,
            row.leased_at_ms,
            row.completed_at_ms,
            row.failed_at_ms,
            row.attempts,
            row.last_error,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error inserting pending_symbolication")?;
        Ok(())
    }

    /// Atomically (a) flips rows that have exhausted their attempts to
    /// `failed_at_ms = now` and returns them so the caller can notify Discord, and
    /// (b) leases up to `n` eligible rows by setting `leased_at_ms = now` and incrementing
    /// `attempts`. Returns `(newly_failed, leased)`.
    ///
    /// A row is eligible for lease once it is not held by a live lease *and* its
    /// retry backoff has elapsed; see `release_lease_with_error`.
    pub async fn lease_pending_symbolications(
        &self,
        n: i64,
        lease_ttl: Duration,
    ) -> Result<(Vec<PendingSymbolication>, Vec<PendingSymbolication>), anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let lease_cutoff_ms = now_ms - (lease_ttl.as_millis() as i64);

        let newly_failed = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET failed_at_ms = ?
            WHERE completed_at_ms IS NULL
              AND failed_at_ms IS NULL
              AND attempts >= 3
              -- `leased_at_ms IS NOT NULL` used to be required here, but a
              -- worker reporting failure clears it. An exhausted row therefore
              -- matched neither this query (lease was NULL) nor the lease query
              -- below (attempts >= 3) and sat unfailed forever, so its Discord
              -- notification never fired. Match a cleared lease too; the
              -- IS NOT NULL case still covers workers that died holding one.
              AND (leased_at_ms IS NULL OR leased_at_ms < ?)
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            now_ms,
            lease_cutoff_ms,
        )
        .fetch_all(&self.writer_pool)
        .await
        .context("Error marking exhausted leases as failed")?;

        let leased = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET leased_at_ms = ?, attempts = attempts + 1
            WHERE id IN (
                SELECT id FROM pending_symbolications
                WHERE completed_at_ms IS NULL
                  AND failed_at_ms IS NULL
                  AND attempts < 3
                  AND (leased_at_ms IS NULL OR leased_at_ms < ?)
                  AND (retry_after_ms IS NULL OR retry_after_ms <= ?)
                ORDER BY received_at_ms
                LIMIT ?
            )
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            now_ms,
            lease_cutoff_ms,
            now_ms,
            n,
        )
        .fetch_all(&self.writer_pool)
        .await
        .context("Error leasing pending_symbolications")?;

        Ok((newly_failed, leased))
    }

    pub async fn complete_pending_symbolication(
        &self,
        id: &str,
    ) -> Result<Option<PendingSymbolication>, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let row = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET completed_at_ms = ?, last_error = NULL
            WHERE id = ? AND completed_at_ms IS NULL
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            now_ms,
            id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error completing pending_symbolication")?;
        Ok(row)
    }

    /// Records a freshly symbolicated crash against its thread.
    ///
    /// Upserts so a thread accumulates one row that always describes its most
    /// recent crash. The review columns are deliberately left untouched: a
    /// thread reviewed before this crash arrived becomes unreviewed again,
    /// because `reviewed_at_ms` now trails `latest_crash_at_ms`.
    pub async fn record_crash_for_review(
        &self,
        thread_id: i64,
        latest_crash_message_id: Option<i64>,
        facts: &crate::crash_rules::CrashFacts,
    ) -> Result<CrashReview, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let app_version = facts.app_version.as_deref();
        let device_type = facts.device_type.as_deref();
        let os_version = facts.os_version.as_deref();
        let termination_code = facts.termination_code.as_deref();
        sqlx::query_as!(
            CrashReview,
            r#"
            INSERT INTO crash_reviews (
                thread_id, latest_crash_message_id, latest_crash_at_ms,
                app_version, device_type, os_version,
                exception_type, signal, termination_code
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
                latest_crash_message_id = excluded.latest_crash_message_id,
                latest_crash_at_ms = excluded.latest_crash_at_ms,
                app_version = excluded.app_version,
                device_type = excluded.device_type,
                os_version = excluded.os_version,
                exception_type = excluded.exception_type,
                signal = excluded.signal,
                termination_code = excluded.termination_code
            RETURNING thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            "#,
            thread_id,
            latest_crash_message_id,
            now_ms,
            app_version,
            device_type,
            os_version,
            facts.exception_type,
            facts.signal,
            termination_code,
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error recording crash for review")
    }

    /// Marks a thread reviewed as of now.
    ///
    /// `reviewed_by` is free-form: `auto:<rule id>` for the rules engine, or
    /// whatever a human caller supplies.
    /// Records which rule matched a crash without reviewing it.
    ///
    /// Used when a rule matches a crash from a build that already carries its
    /// fix: the diagnosis is worth keeping on the row, but `reviewed_at_ms`
    /// stays null so the thread remains in the unreviewed queue.
    pub async fn note_rule_match(
        &self,
        thread_id: i64,
        matched_rule_id: &str,
        review_note: &str,
    ) -> Result<(), anyhow::Error> {
        sqlx::query!(
            r#"
            UPDATE crash_reviews
            SET matched_rule_id = ?, review_note = ?
            WHERE thread_id = ?
            "#,
            matched_rule_id,
            review_note,
            thread_id,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error recording rule match")?;
        Ok(())
    }

    pub async fn mark_thread_reviewed(
        &self,
        thread_id: i64,
        reviewed_by: Option<&str>,
        reviewed_message_id: Option<i64>,
        matched_rule_id: Option<&str>,
        review_note: Option<&str>,
    ) -> Result<Option<CrashReview>, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        sqlx::query_as!(
            CrashReview,
            r#"
            UPDATE crash_reviews
            SET reviewed_at_ms = ?,
                reviewed_by = ?,
                reviewed_message_id = COALESCE(?, reviewed_message_id),
                matched_rule_id = COALESCE(?, matched_rule_id),
                review_note = COALESCE(?, review_note)
            WHERE thread_id = ?
            RETURNING thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            "#,
            now_ms,
            reviewed_by,
            reviewed_message_id,
            matched_rule_id,
            review_note,
            thread_id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error marking thread reviewed")
    }

    /// Clears review state so a thread shows up as needing attention again.
    pub async fn mark_thread_unreviewed(
        &self,
        thread_id: i64,
    ) -> Result<Option<CrashReview>, anyhow::Error> {
        sqlx::query_as!(
            CrashReview,
            r#"
            UPDATE crash_reviews
            SET reviewed_at_ms = NULL,
                reviewed_by = NULL,
                reviewed_message_id = NULL,
                matched_rule_id = NULL,
                review_note = NULL
            WHERE thread_id = ?
            RETURNING thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            "#,
            thread_id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error marking thread unreviewed")
    }

    /// Lists tracked crash threads, newest crash first.
    ///
    /// `only_unreviewed` applies the same predicate as
    /// [`CrashReview::is_unreviewed`]. `before_ms` pages backwards through
    /// `latest_crash_at_ms`; pass the last row's value to get the next page.
    pub async fn list_crash_reviews(
        &self,
        only_unreviewed: bool,
        app_version: Option<&str>,
        before_ms: Option<i64>,
        limit: i64,
    ) -> Result<Vec<CrashReview>, anyhow::Error> {
        sqlx::query_as!(
            CrashReview,
            r#"
            SELECT thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            FROM crash_reviews
            WHERE (?1 = 0 OR reviewed_at_ms IS NULL OR reviewed_at_ms < latest_crash_at_ms)
              AND (?2 IS NULL OR app_version = ?2)
              AND (?3 IS NULL OR latest_crash_at_ms < ?3)
            ORDER BY latest_crash_at_ms DESC
            LIMIT ?4
            "#,
            only_unreviewed,
            app_version,
            before_ms,
            limit,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error listing crash reviews")
    }

    pub async fn get_crash_review(
        &self,
        thread_id: i64,
    ) -> Result<Option<CrashReview>, anyhow::Error> {
        sqlx::query_as!(
            CrashReview,
            r#"
            SELECT thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            FROM crash_reviews
            WHERE thread_id = ?
            "#,
            thread_id,
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error getting crash review")
    }

    /// Records a worker-reported failure on the given lease. Clears `leased_at_ms`
    /// so the row is re-leasable, but keeps the incremented `attempts` from the
    /// lease call, which is what caps retries via the `attempts < 3` filter.
    ///
    /// Also stamps `retry_after_ms` so the next attempt is spaced out. Without
    /// it, clearing the lease made the row instantly re-leasable and the worker's
    /// drain loop burned every attempt within the same second — which is no
    /// retry at all for the transient failures retries exist to absorb.
    pub async fn release_lease_with_error(
        &self,
        id: &str,
        error: &str,
    ) -> Result<Option<PendingSymbolication>, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let base_ms = RETRY_BACKOFF_BASE.as_millis() as i64;
        // Backoff doubles per attempt, derived from the row's own counter so it
        // stays correct without the caller having to know how many attempts the
        // lease had already burned. `attempts` includes the one that just
        // failed, so the first failure waits exactly one base interval. Capped
        // at 2^7 so a stuck row cannot schedule itself years out.
        let row = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET leased_at_ms = NULL,
                retry_after_ms = ? + ? * (1 << MIN(MAX(attempts - 1, 0), 7)),
                last_error = ?
            WHERE id = ? AND completed_at_ms IS NULL AND failed_at_ms IS NULL
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            now_ms,
            base_ms,
            error,
            id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error releasing pending_symbolication lease")?;
        Ok(row)
    }
}

impl DatabaseClient {
    /// Returns exhausted symbolications to the queue with a fresh attempt budget.
    ///
    /// Covers rows already marked `failed_at_ms` and rows that merely ran out of
    /// attempts, since before the dead-letter fix the latter were left in
    /// neither state. `error_contains` narrows the reset to a single failure
    /// mode — requeueing everything would also replay payloads that fail for
    /// reasons nothing has changed about.
    ///
    /// Re-symbolication needs the original payload still on disk; rows whose
    /// file has since been reaped fail again on their next lease with
    /// "payload missing on disk", which is the honest outcome.
    /// Payloads of permanently-failed symbolications old enough to reap.
    ///
    /// Returns `(id, payload_path)` for rows that failed before `cutoff_ms` and
    /// whose file has not already been removed. The caller deletes the files and
    /// reports back via `mark_payload_reaped`, so a delete that fails is simply
    /// retried on the next sweep rather than being recorded as done.
    pub async fn expired_failed_payloads(
        &self,
        cutoff_ms: i64,
    ) -> Result<Vec<(String, String)>, anyhow::Error> {
        let rows = sqlx::query!(
            r#"
            SELECT id as "id!: String", payload_path as "payload_path!: String"
            FROM pending_symbolications
            WHERE failed_at_ms IS NOT NULL
              AND failed_at_ms < ?
              AND payload_reaped_at_ms IS NULL
            ORDER BY failed_at_ms
            "#,
            cutoff_ms,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error listing expired failed symbolication payloads")?;
        Ok(rows
            .into_iter()
            .map(|row| (row.id, row.payload_path))
            .collect())
    }

    /// Record that a failed symbolication's payload file has been removed.
    pub async fn mark_payload_reaped(&self, id: &str) -> Result<(), anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        sqlx::query!(
            "UPDATE pending_symbolications SET payload_reaped_at_ms = ? WHERE id = ?",
            now_ms,
            id,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error marking symbolication payload as reaped")?;
        Ok(())
    }

    /// Ids that `requeue_failed_symbolications` would reset, without resetting
    /// them. Same predicate, so a dry run cannot disagree with the real thing.
    pub async fn failed_symbolication_ids(
        &self,
        error_contains: Option<&str>,
    ) -> Result<Vec<String>, anyhow::Error> {
        let pattern = error_contains.map(|needle| format!("%{needle}%"));
        let ids = sqlx::query_scalar!(
            r#"
            SELECT id as "id!: String"
            FROM pending_symbolications
            WHERE completed_at_ms IS NULL
              AND (failed_at_ms IS NOT NULL OR attempts >= 3)
              AND payload_reaped_at_ms IS NULL
              AND (? IS NULL OR last_error LIKE ?)
            ORDER BY received_at_ms
            "#,
            pattern,
            pattern,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error listing failed pending_symbolications")?;
        Ok(ids)
    }

    pub async fn requeue_failed_symbolications(
        &self,
        error_contains: Option<&str>,
    ) -> Result<Vec<PendingSymbolication>, anyhow::Error> {
        let pattern = error_contains.map(|needle| format!("%{needle}%"));
        let rows = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET failed_at_ms = NULL,
                leased_at_ms = NULL,
                retry_after_ms = NULL,
                attempts = 0
            WHERE completed_at_ms IS NULL
              AND (failed_at_ms IS NOT NULL OR attempts >= 3)
              AND payload_reaped_at_ms IS NULL
              AND (? IS NULL OR last_error LIKE ?)
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            pattern,
            pattern,
        )
        .fetch_all(&self.writer_pool)
        .await
        .context("Error requeueing failed pending_symbolications")?;
        Ok(rows)
    }
}

/// Wait after a payload's first failure before it may be leased again; doubles
/// with each subsequent attempt.
///
/// Minutes rather than seconds because the transient failures retries exist to
/// absorb — rate-limited ipsw downloads, dSYM fetch blips — recover on that
/// scale. Retrying inside the same second only converts a temporary outage into
/// a permanently dead-lettered crash report.
const RETRY_BACKOFF_BASE: Duration = Duration::from_secs(5 * 60);

#[derive(Debug, serde::Serialize)]
pub struct User {
    pub device_id: UserId,
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    pub apns_token: Option<String>,
    pub device_info: Option<Json<DeviceInfo>>,
    #[serde(skip_serializing)]
    pub ai_disabled: bool,
}

#[derive(Default)]
pub struct UserUpdate {
    pub apns_token: Option<String>,
    pub thread_id: Option<i64>,
    pub device_info: Option<DeviceInfo>,
}

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DeviceInfo {
    pub user_id: Option<String>,
    pub build_version: Option<String>,
    pub release_version: Option<String>,
    pub os_platform: Option<String>,
    pub os_version: Option<String>,
    pub user_locale: Option<String>,
}

/// Review state for the crashes in one Discord thread.
///
/// See `migrations/20260811000000_crash_reviews.up.sql` for the unreviewed
/// predicate; [`CrashReview::is_unreviewed`] mirrors it in Rust.
///
/// These queries were runtime-checked (`query_as::<_, CrashReview>`) until
/// `20260811120000_users_device_id_text`, because the untyped `users.device_id`
/// column segfaulted rustc during macro expansion. See that migration for the
/// details.
#[derive(Debug, Clone, serde::Serialize)]
pub struct CrashReview {
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    #[serde(serialize_with = "crate::utils::i64_to_string_optional")]
    pub latest_crash_message_id: Option<i64>,
    pub latest_crash_at_ms: i64,
    pub app_version: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    pub termination_code: Option<String>,
    pub reviewed_at_ms: Option<i64>,
    pub reviewed_by: Option<String>,
    #[serde(serialize_with = "crate::utils::i64_to_string_optional")]
    pub reviewed_message_id: Option<i64>,
    pub matched_rule_id: Option<String>,
    pub review_note: Option<String>,
}

impl CrashReview {
    /// A thread needs attention when it was never reviewed, or when a newer
    /// crash landed after the last review.
    pub fn is_unreviewed(&self) -> bool {
        match self.reviewed_at_ms {
            None => true,
            Some(reviewed_at) => reviewed_at < self.latest_crash_at_ms,
        }
    }
}

#[derive(Debug, Clone)]
pub struct PendingSymbolication {
    pub id: String,
    pub device_id: String,
    pub thread_id: i64,
    pub payload_path: String,
    pub diagnostics_json: String,
    pub installation_info_json: String,
    pub binary_uuids_json: String,
    pub payload_index: i64,
    pub received_at_ms: i64,
    pub leased_at_ms: Option<i64>,
    pub completed_at_ms: Option<i64>,
    pub failed_at_ms: Option<i64>,
    pub attempts: i64,
    pub last_error: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crash_rules::CrashFacts;

    /// The `crash_reviews` queries are compile-time checked, so column names and
    /// bind types are verified by the macros. These tests cover what that cannot:
    /// the upsert's conflict behaviour, the unreviewed predicate, and paging.
    async fn test_client() -> (DatabaseClient, tempfile::TempDir) {
        let dir = tempfile::tempdir().expect("tempdir");
        let db_path = dir.path().join("test.db");
        let opts = SqliteConnectOptions::from_str(db_path.to_str().unwrap())
            .expect("parse opts")
            .create_if_missing(true);
        let writer_pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect_with(opts.clone())
            .await
            .expect("writer pool");
        let reader_pool = SqlitePoolOptions::new()
            .max_connections(2)
            .connect_with(opts)
            .await
            .expect("reader pool");
        sqlx::migrate!("./migrations")
            .run(&writer_pool)
            .await
            .expect("migrations");
        (
            DatabaseClient {
                reader_pool,
                writer_pool,
            },
            dir,
        )
    }

    /// Both `record_crash_for_review` and `mark_thread_reviewed` stamp rows with
    /// `Utc::now()` at millisecond resolution, and `is_unreviewed` compares them
    /// with a strict `<`. Tests that need one to land strictly after the other
    /// have to let the clock tick, or the two stamps can be equal and the
    /// comparison flips. Real crashes and reviews are seconds apart, so this only
    /// bites in tests.
    async fn tick() {
        tokio::time::sleep(Duration::from_millis(2)).await;
    }

    fn facts(version: &str) -> CrashFacts {
        CrashFacts {
            app_version: Some(version.to_string()),
            device_type: Some("iPhone14,7".to_string()),
            os_version: Some("iPhone OS 26.6 (23G71)".to_string()),
            exception_type: Some(10),
            signal: Some(9),
            termination_code: Some("0xdead10cc".to_string()),
        }
    }

    #[tokio::test]
    async fn records_and_reviews_a_crash() {
        let (db, _dir) = test_client().await;

        let recorded = db
            .record_crash_for_review(42, Some(1001), &facts("1.50"))
            .await
            .expect("record");
        assert_eq!(recorded.thread_id, 42);
        assert_eq!(recorded.app_version.as_deref(), Some("1.50"));
        assert_eq!(recorded.exception_type, Some(10));
        assert!(recorded.is_unreviewed());

        let unreviewed = db
            .list_crash_reviews(true, None, None, 50)
            .await
            .expect("list");
        assert_eq!(unreviewed.len(), 1);

        let reviewed = db
            .mark_thread_reviewed(42, Some("auto:test-rule"), Some(2002), Some("test-rule"), None)
            .await
            .expect("review")
            .expect("row exists");
        assert!(!reviewed.is_unreviewed());
        assert_eq!(reviewed.reviewed_by.as_deref(), Some("auto:test-rule"));
        assert_eq!(reviewed.reviewed_message_id, Some(2002));

        assert!(db
            .list_crash_reviews(true, None, None, 50)
            .await
            .expect("list")
            .is_empty());
        assert_eq!(
            db.list_crash_reviews(false, None, None, 50)
                .await
                .expect("list all")
                .len(),
            1
        );
    }

    #[tokio::test]
    async fn a_newer_crash_reopens_a_reviewed_thread() {
        let (db, _dir) = test_client().await;
        db.record_crash_for_review(7, Some(1), &facts("1.49"))
            .await
            .expect("record");
        db.mark_thread_reviewed(7, Some("someone"), None, None, None)
            .await
            .expect("review");
        tick().await;

        // Same thread, newer crash: the review is now stale and the thread
        // should surface again rather than staying silently closed.
        let reopened = db
            .record_crash_for_review(7, Some(2), &facts("1.50"))
            .await
            .expect("record again");
        assert!(reopened.is_unreviewed(), "{reopened:?}");
        assert_eq!(reopened.app_version.as_deref(), Some("1.50"));
        assert_eq!(reopened.latest_crash_message_id, Some(2));

        let unreviewed = db
            .list_crash_reviews(true, None, None, 50)
            .await
            .expect("list");
        assert_eq!(unreviewed.len(), 1);
    }

    #[tokio::test]
    async fn filters_by_version_and_pages_backwards() {
        let (db, _dir) = test_client().await;
        for (thread_id, version) in [(1, "1.49"), (2, "1.50"), (3, "1.50")] {
            db.record_crash_for_review(thread_id, None, &facts(version))
                .await
                .expect("record");
        }

        let only_150 = db
            .list_crash_reviews(false, Some("1.50"), None, 50)
            .await
            .expect("list");
        assert_eq!(only_150.len(), 2);
        assert!(only_150.iter().all(|c| c.app_version.as_deref() == Some("1.50")));

        // Newest first, and `before_ms` excludes everything at or after it.
        let all = db
            .list_crash_reviews(false, None, None, 50)
            .await
            .expect("list");
        assert_eq!(all.len(), 3);
        let cursor = all[0].latest_crash_at_ms;
        let next_page = db
            .list_crash_reviews(false, None, Some(cursor), 50)
            .await
            .expect("page");
        assert!(next_page.iter().all(|c| c.latest_crash_at_ms < cursor));
    }

    #[tokio::test]
    async fn unreview_clears_state_and_missing_threads_report_none() {
        let (db, _dir) = test_client().await;
        db.record_crash_for_review(9, None, &facts("1.50"))
            .await
            .expect("record");
        db.mark_thread_reviewed(9, Some("someone"), Some(5), Some("rule"), Some("note"))
            .await
            .expect("review");

        let cleared = db.mark_thread_unreviewed(9).await.expect("unreview").expect("row");
        assert!(cleared.is_unreviewed());
        assert_eq!(cleared.reviewed_by, None);
        assert_eq!(cleared.matched_rule_id, None);

        assert!(db.get_crash_review(9).await.expect("get").is_some());
        assert!(db.get_crash_review(12345).await.expect("get").is_none());
        assert!(db
            .mark_thread_reviewed(12345, None, None, None, None)
            .await
            .expect("review missing")
            .is_none());
    }

    fn pending(id: &str) -> PendingSymbolication {
        PendingSymbolication {
            id: id.to_string(),
            device_id: "device".to_string(),
            thread_id: 7,
            payload_path: "/tmp/payload.json".to_string(),
            diagnostics_json: "{}".to_string(),
            installation_info_json: "{}".to_string(),
            binary_uuids_json: "[]".to_string(),
            payload_index: 0,
            received_at_ms: 1,
            leased_at_ms: None,
            completed_at_ms: None,
            failed_at_ms: None,
            attempts: 0,
            last_error: None,
        }
    }

    /// Drive a payload through `attempts` worth of lease-then-fail, the way the
    /// worker does. Returns the rows the lease marked newly failed each round.
    async fn fail_n_times(db: &DatabaseClient, id: &str, times: usize) -> Vec<PendingSymbolication> {
        let mut newly_failed = Vec::new();
        for _ in 0..times {
            let (failed, leased) = db
                .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
                .await
                .expect("lease");
            newly_failed.extend(failed);
            if leased.iter().any(|row| row.id == id) {
                db.release_lease_with_error(id, "recursion limit exceeded")
                    .await
                    .expect("release");
            }
        }
        newly_failed
    }

    #[tokio::test]
    async fn a_failed_payload_waits_before_it_can_be_leased_again() {
        let (db, _dir) = test_client().await;
        db.insert_pending_symbolication(&pending("a"))
            .await
            .expect("insert");

        let (_, leased) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease");
        assert_eq!(leased.len(), 1);

        db.release_lease_with_error("a", "boom")
            .await
            .expect("release");

        // Previously the release cleared the lease outright, so the very next
        // poll handed the same payload straight back and all three attempts
        // burned inside the same second.
        let (_, released) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease again");
        assert!(
            released.is_empty(),
            "a just-failed payload must not be immediately re-leasable"
        );
    }

    #[tokio::test]
    async fn an_exhausted_payload_is_marked_failed_rather_than_stranded() {
        let (db, _dir) = test_client().await;
        db.insert_pending_symbolication(&pending("a"))
            .await
            .expect("insert");

        // Burn the attempt budget. The backoff means only the first lease
        // actually hands the row over, which is the point of the previous test;
        // clear it by hand between rounds so this one can reach exhaustion.
        for _ in 0..3 {
            sqlx::query!("UPDATE pending_symbolications SET retry_after_ms = NULL")
                .execute(&db.writer_pool)
                .await
                .expect("clear backoff");
            fail_n_times(&db, "a", 1).await;
        }

        // The row is out of attempts with its lease cleared. That combination
        // matched neither the dead-letter predicate (which required a live
        // lease) nor the lease predicate (attempts < 3), so it used to sit here
        // forever and its Discord notification never fired.
        sqlx::query!("UPDATE pending_symbolications SET retry_after_ms = NULL")
            .execute(&db.writer_pool)
            .await
            .expect("clear backoff");
        let (newly_failed, leased) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease");

        assert!(leased.is_empty(), "an exhausted payload must not be leased");
        assert_eq!(
            newly_failed.len(),
            1,
            "an exhausted payload must be reported as failed"
        );
        assert_eq!(newly_failed[0].id, "a");
    }

    #[tokio::test]
    async fn reaping_only_takes_payloads_past_the_retention_window() {
        let (db, _dir) = test_client().await;
        for id in ["old", "recent"] {
            db.insert_pending_symbolication(&pending(id))
                .await
                .expect("insert");
        }

        // `old` failed well before the cutoff, `recent` just now.
        sqlx::query!("UPDATE pending_symbolications SET failed_at_ms = 1000 WHERE id = 'old'")
            .execute(&db.writer_pool)
            .await
            .expect("age old");
        sqlx::query!("UPDATE pending_symbolications SET failed_at_ms = 9000 WHERE id = 'recent'")
            .execute(&db.writer_pool)
            .await
            .expect("age recent");

        let expired = db.expired_failed_payloads(5000).await.expect("expired");
        assert_eq!(
            expired.iter().map(|(id, _)| id.as_str()).collect::<Vec<_>>(),
            vec!["old"],
            "a payload inside the retention window must be kept"
        );

        // Once reaped it is not offered again, and it can no longer be
        // requeued — there is nothing left on disk to symbolicate.
        db.mark_payload_reaped("old").await.expect("mark");
        assert!(db.expired_failed_payloads(5000).await.expect("expired").is_empty());
        assert!(db
            .failed_symbolication_ids(None)
            .await
            .expect("ids")
            .iter()
            .all(|id| id != "old"));
    }

    #[tokio::test]
    async fn requeue_returns_exhausted_payloads_matching_an_error() {
        let (db, _dir) = test_client().await;
        for id in ["deep", "other"] {
            db.insert_pending_symbolication(&pending(id))
                .await
                .expect("insert");
        }

        sqlx::query!(
            "UPDATE pending_symbolications
             SET attempts = 3, failed_at_ms = 99, last_error = 'recursion limit exceeded'
             WHERE id = 'deep'"
        )
        .execute(&db.writer_pool)
        .await
        .expect("fail deep");
        sqlx::query!(
            "UPDATE pending_symbolications
             SET attempts = 3, failed_at_ms = 99, last_error = 'payload missing on disk'
             WHERE id = 'other'"
        )
        .execute(&db.writer_pool)
        .await
        .expect("fail other");

        let candidates = db
            .failed_symbolication_ids(Some("recursion limit"))
            .await
            .expect("dry run");
        assert_eq!(candidates, vec!["deep".to_string()]);

        let requeued = db
            .requeue_failed_symbolications(Some("recursion limit"))
            .await
            .expect("requeue");
        assert_eq!(requeued.len(), 1);
        assert_eq!(requeued[0].id, "deep");

        // The requeued payload is leasable again; the unrelated failure is not.
        let (_, leased) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease");
        let leased_ids: Vec<&str> = leased.iter().map(|row| row.id.as_str()).collect();
        assert_eq!(leased_ids, vec!["deep"]);

        // And an unfiltered dry run still sees the one left behind.
        assert_eq!(
            db.failed_symbolication_ids(None).await.expect("dry run"),
            vec!["other".to_string()]
        );
    }
}
