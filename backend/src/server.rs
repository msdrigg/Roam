use std::{path::PathBuf, time::Duration};

use crate::{
    database::{DeviceInfo, PendingSymbolication, User, UserUpdate},
    discord::{DiscordAuthor, DiscordFile, DiscordFileUpload, DiscordMessageOptions},
    presence::UserPresenceInfo,
    symbolicate::{scan_binary_uuids, DsymUploadMetadata, RoamDebugInfo},
    utils::{i64_to_string, string_to_i64_optional},
};
use anyhow::Context;
use axum::{
    body::{to_bytes, Body},
    extract::{DefaultBodyLimit, Multipart, Path, Query, State},
    http::{header, HeaderName, Request, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Json,
};
use axum::{routing::get, serve::ListenerExt, Router};
pub use error::ApiError;
use futures::{stream, StreamExt};
use opentelemetry::trace::{SpanKind, TraceContextExt};
use serde::{Deserialize, Serialize};
use tokio::{io::AsyncWriteExt, net::TcpListener, task::JoinHandle};
use tokio_util::io::ReaderStream;
use tower_http::{
    catch_panic::CatchPanicLayer,
    cors::{AllowHeaders, AllowMethods, AllowOrigin, CorsLayer},
    request_id::{MakeRequestId, PropagateRequestIdLayer, RequestId, SetRequestIdLayer},
    trace::{DefaultOnFailure, DefaultOnRequest, DefaultOnResponse, TraceLayer},
    validate_request::{ValidateRequest, ValidateRequestHeaderLayer},
};
use tracing::{Level, Span};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use uuid::Uuid;

/// How long a leased payload stays out before another worker can re-claim it.
const LEASE_TTL: Duration = Duration::from_secs(15 * 60);

use crate::{discord::DiscordMessage, AppContext};

const UPLOAD_LIMIT: usize = 10 * 1024 * 1024;

/// Ceiling for a streamed dSYM upload. Enforced while writing to disk rather than
/// by `DefaultBodyLimit`, which would buffer the body in memory.
const MAX_DSYM_UPLOAD_BYTES: u64 = 2 * 1024 * 1024 * 1024;

pub async fn start_server(
    app_context: AppContext,
) -> anyhow::Result<JoinHandle<anyhow::Result<()>>> {
    let port = app_context.port;
    let router = build_app(app_context);
    let router = router.clone();
    let future = async move {
        let tcp_listener = TcpListener::bind(format!("0.0.0.0:{port}"))
            .await
            .context(format!("Error binding to port {port}"))?
            .tap_io(|tcp_stream| {
                if let Err(err) = tcp_stream.set_nodelay(true) {
                    tracing::info!("failed to set TCP_NODELAY on incoming connection: {err:#}");
                }
            });

        let server = axum::serve(tcp_listener, router.into_make_service());
        server.await.context("error running HTTP server")?;
        anyhow::Result::Ok(())
    };

    tokio::task::Builder::new()
        .name("http-server")
        .spawn(future)
        .context("Error spawning http server")
}

fn build_app(app_context: AppContext) -> Router {
    let x_request_id: axum::http::HeaderName = HeaderName::from_static("x-request-id");

    let cors = CorsLayer::new()
        .allow_headers(AllowHeaders::mirror_request())
        .allow_methods(AllowMethods::mirror_request())
        .allow_origin(AllowOrigin::mirror_request());

    router(app_context.clone())
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|request: &Request<Body>| {
                    tracing::span!(
                        Level::DEBUG,
                        "request",
                        "otel.name" = %format!("{}: {}", request.method(), request.uri().path()),
                        "otel.kind" = ?SpanKind::Server,
                        method = %request.method(),
                        uri = %request.uri(),
                        version = ?request.version(),
                        headers = ?request.headers(),
                    )
                })
                .on_failure(DefaultOnFailure::default().level(Level::WARN))
                .on_request(DefaultOnRequest::new().level(Level::DEBUG))
                .on_response(
                    DefaultOnResponse::new()
                        .level(Level::DEBUG)
                        .include_headers(true),
                ),
        )
        .layer(SetRequestIdLayer::new(
            x_request_id.clone(),
            OpenTelemetryRequestId,
        ))
        .layer(cors)
        .layer(ValidateRequestHeaderLayer::custom(ValidateApiKey::new(
            app_context.backend_api_key,
        )))
        .layer(PropagateRequestIdLayer::new(x_request_id))
        .layer(CatchPanicLayer::new())
        .layer(DefaultBodyLimit::max(
            1024 * 1024 * 70, // 70 MB
        ))
}

#[derive(Clone, Debug)]
struct ValidateApiKey {
    api_key: String,
}

impl ValidateApiKey {
    fn new(api_key: String) -> Self {
        Self { api_key }
    }
}

impl ValidateRequest<axum::body::Body> for ValidateApiKey {
    type ResponseBody = axum::body::Body;

    fn validate(
        &mut self,
        request: &mut Request<axum::body::Body>,
    ) -> Result<(), axum::http::Response<Self::ResponseBody>> {
        let path = request.uri().path();
        // If path is /health, don't require an API key
        if path == "/health" {
            return Ok(());
        }
        let api_key = request
            .headers()
            .get("x-api-key")
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default();

        if api_key != self.api_key {
            return Err(axum::http::Response::builder()
                .status(401)
                .body(Body::from("Unauthorized"))
                .unwrap());
        }

        Ok(())
    }
}

// A `MakeRequestId` that increments an atomic counter
#[derive(Clone, Default)]
struct OpenTelemetryRequestId;

impl MakeRequestId for OpenTelemetryRequestId {
    fn make_request_id<B>(&mut self, _: &Request<B>) -> Option<RequestId> {
        let id: Uuid = get_current_trace_id();
        let request_id = id.as_simple().to_string().parse().unwrap();

        Some(RequestId::new(request_id))
    }
}

fn get_current_trace_id() -> Uuid {
    let trace_id = Span::current().context().span().span_context().trace_id();
    Uuid::from_bytes(trace_id.to_bytes())
}

fn router(app_context: AppContext) -> Router {
    Router::new()
        .route("/health", get(|| async { "Healthy!" }))
        .route("/", get(|| async { "Hello, world!" }))
        .route("/messages/{user_id}", get(get_user_messages))
        .route("/updates/{user_id}", get(get_user_state))
        .route("/new-message", post(new_message_old))
        .route("/v2/new-message", post(new_message))
        .route("/v2/upload-diagnostics", post(upload_metric_diagnostics))
        // Streams to disk, so the global 70 MB body limit must not apply here.
        .route(
            "/v2/upload-roam-dsym",
            post(upload_roam_dsym).layer(DefaultBodyLimit::disable()),
        )
        // Crash review tracking. All of these sit behind the existing
        // `x-api-key` layer, so a triage client needs the backend key and no
        // Discord credentials of its own.
        .route("/v2/crashes", get(list_crashes))
        .route("/v2/crashes/rules", get(list_crash_rules))
        .route("/v2/crashes/{thread_id}", get(get_crash))
        .route(
            "/v2/crashes/{thread_id}/review",
            post(review_crash).delete(unreview_crash),
        )
        // Discord proxy. Lets the same key read threads, messages and
        // attachments without ever handling a bot token.
        .route("/v2/discord/threads", get(list_discord_threads))
        .route(
            "/v2/discord/threads/{thread_id}/messages",
            get(list_discord_messages).post(post_discord_message),
        )
        .route(
            "/v2/discord/threads/{thread_id}/messages/{message_id}",
            get(get_discord_message),
        )
        .route(
            "/v2/discord/threads/{thread_id}/messages/{message_id}/attachments/{attachment_id}",
            get(stream_discord_attachment),
        )
        .route("/v2/symbolicate/lease", get(lease_pending_symbolications))
        .route("/v2/symbolicate/dsym/{uuid}", get(get_dsym_by_uuid))
        .route("/v2/symbolicate/result", post(submit_symbolication_result))
        .route("/v2/symbolicate/requeue", post(requeue_symbolications))
        .route("/new-apns", post(new_apns))
        .route(
            "/upload-diagnostics/{diagnostic_key}",
            post(upload_diagnostics),
        )
        .route("/user-info/{user_id}", get(get_user_info))
        .route("/typing/{user_id}", post(update_user_typing))
        .route("/thread-info/{thread_id}", get(get_thread_info))
        .with_state(app_context)
}

#[derive(serde::Deserialize)]
struct AfterQuery {
    #[serde(default, deserialize_with = "string_to_i64_optional")]
    after: Option<i64>,
}

#[derive(Serialize)]
struct UserState {
    messages: Vec<DiscordMessageDownload>,
    presence: UserPresenceInfo,
}

#[derive(Serialize)]
pub struct DiscordMessageDownload {
    #[serde(serialize_with = "i64_to_string")]
    pub id: i64,
    pub nonce: Option<String>,
    pub content: String,
    pub author: DiscordAuthor,
    #[serde(rename = "type")]
    pub message_type: u8,
    pub attachments: Vec<DiscordFile>,
    pub ai_message: bool,
    pub human_support_message: bool,
}
impl DiscordMessageDownload {
    async fn prepare(
        message: DiscordMessage,
        ai_bot_id: Option<i64>,
        human_support_user_id: Option<i64>,
    ) -> Result<Self, error::ApiError> {
        let translated_support = message.is_translated_support_message();
        let message = message.normalize();
        let ai_message = !translated_support && Some(message.author.id) == ai_bot_id;
        let human_support_message =
            translated_support || Some(message.author.id) == human_support_user_id;
        let attachments = stream::iter(message.attachments.into_iter())
            .map(|attachment| async move {
                let url = attachment.url;
                let id = attachment.id;
                let data = match reqwest::get(&url).await {
                    Ok(response) => match response.bytes().await {
                        Ok(bytes) => bytes.to_vec(),
                        Err(e) => {
                            return Err(ApiError::BadRequest(format!(
                                "Error reading attachment: {e}"
                            )))
                        }
                    },
                    Err(e) => {
                        return Err(ApiError::BadRequest(format!(
                            "Error downloading attachment: {e}"
                        )))
                    }
                };

                Ok(DiscordFile {
                    id,
                    content_type: attachment
                        .content_type
                        .unwrap_or_else(|| "application/octet-stream".to_string()),
                    filename: attachment.filename,
                    data,
                })
            })
            .buffer_unordered(10) // Adjust concurrency level
            .collect::<Vec<Result<DiscordFile, ApiError>>>()
            .await;

        let attachments = attachments.into_iter().collect::<Result<Vec<_>, _>>()?;

        Ok(Self {
            id: message.id,
            nonce: message.nonce,
            content: message.content,
            author: message.author,
            message_type: message.message_type,
            attachments,
            ai_message,
            human_support_message,
        })
    }
}

async fn get_user_state(
    Path(device_id): Path<String>,
    Query(query): Query<AfterQuery>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserState>, ApiError> {
    let user = app_context
        .get_or_create_user(&device_id, &UserUpdate::default())
        .await?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(user.thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden());
    let ai_bot_id = app_context.ai_responder_discord_bot_id();
    let human_support_user_id = app_context.ai_responder_human_support_user_id();
    let messages = stream::iter(messages)
        .map(|m| async move {
            DiscordMessageDownload::prepare(m, ai_bot_id, human_support_user_id).await
        }) // Async mapping
        .buffer_unordered(10) // Adjust concurrency level as needed
        .collect::<Vec<_>>() // Collect into Vec
        .await;

    let messages = messages.into_iter().collect::<Result<Vec<_>, _>>()?;

    let presence = app_context.presence_info(&user.device_id).await;

    Ok(Json(UserState { messages, presence }))
}

async fn get_user_messages(
    Path(device_id): Path<String>,
    Query(query): Query<AfterQuery>,
    State(app_context): State<AppContext>,
) -> Result<Json<Vec<DiscordMessage>>, ApiError> {
    let user = app_context
        .get_or_create_user(&device_id, &UserUpdate::default())
        .await?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(user.thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden())
        .map(|m| m.normalize())
        .collect();

    Ok(Json(messages))
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ApnsRequest {
    user_id: String,
    apns_token: String,
    installation_info: Option<DeviceInfo>,
}

async fn new_apns(
    State(app_context): State<AppContext>,
    Json(req): Json<ApnsRequest>,
) -> Result<String, ApiError> {
    let ApnsRequest {
        apns_token,
        user_id: device_id,
        installation_info,
    } = req;

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: Some(apns_token.clone()),
                device_info: installation_info.clone(),
                thread_id: None,
            },
        )
        .await?;

    app_context
        .refresh_user(user, Some(apns_token).as_ref(), &installation_info)
        .await?;

    Ok("OK".to_string())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct MessageRequest {
    user_id: String,
    apns_token: Option<String>,
    content: Option<String>,
    attachments: Option<Vec<DiscordFileUpload>>,
    nonce: Option<String>,
    installation_info: Option<DeviceInfo>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct MessageRequestV2 {
    user_id: String,
    content: String,
    attachment: Option<DiscordFileUpload>,
    installation_info: Option<DeviceInfo>,
    nonce: Option<String>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiagnosticRequest {
    user_id: String,
    metrics_payloads: Vec<String>,
    diagnostics: RoamDebugInfo,
    installation_info: DeviceInfo,
}

async fn upload_metric_diagnostics(
    State(app_context): State<AppContext>,
    Json(diagnostic_request): Json<DiagnosticRequest>,
) -> Result<(), ApiError> {
    let DiagnosticRequest {
        user_id: device_id,
        installation_info,
        diagnostics,
        metrics_payloads,
    } = diagnostic_request;

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: None,
                device_info: Some(installation_info.clone()),
                thread_id: None,
            },
        )
        .await?;

    let user = app_context
        .refresh_user(user, None, &Some(installation_info.clone()))
        .await?;

    app_context
        .discord_client()
        .send_message(
            user.thread_id,
            ":ninja: MK Diagnostics Payload Received",
            Some(DiscordFileUpload {
                content_type: "application/json".to_string(),
                filename: "diagnostics.json".to_string(),
                data: serde_json::to_vec(&metrics_payloads).map_err(|e| {
                    ApiError::BadRequest(format!("Error serializing diagnostics: {e}"))
                })?,
                paired_messages: vec![],
            }),
            Some(&DiscordMessageOptions::default()),
        )
        .await?;

    app_context
        .discord_client()
        .send_message(
            user.thread_id,
            ":ninja: MK Diagnostics Supporting Data",
            Some(DiscordFileUpload {
                content_type: "application/json".to_string(),
                filename: "diagnostics.json".to_string(),
                data: serde_json::to_vec(&diagnostics).map_err(|e| {
                    ApiError::BadRequest(format!("Error serializing diagnostics: {e}"))
                })?,
                paired_messages: vec![],
            }),
            Some(&DiscordMessageOptions::default()),
        )
        .await?;

    let pending_dir = app_context.data_dir().join("pending-symbolication");
    tokio::fs::create_dir_all(&pending_dir)
        .await
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;

    let total = metrics_payloads.len();
    let diagnostics_json = serde_json::to_string(&diagnostics)
        .map_err(|e| ApiError::BadRequest(format!("Error serializing diagnostics: {e}")))?;
    let installation_info_json = serde_json::to_string(&installation_info)
        .map_err(|e| ApiError::BadRequest(format!("Error serializing installation info: {e}")))?;

    for (idx, payload_json) in metrics_payloads.into_iter().enumerate() {
        // Scan for binary UUIDs rather than parsing the payload. Ingest only
        // needs the UUID list as a dSYM pre-fetch hint, and the parser reserves
        // a 256 MiB stack to survive deep `subFrames` nesting — a reservation
        // this 256 MB VM cannot map, so calling it here panicked *after* the
        // Discord posts and before the insert, silently dropping every crash
        // uploaded while it was deployed. `scan_binary_uuids` is a flat pass
        // over bytes already in memory and cannot fail; the worker still parses
        // the payload properly on a machine with room for it.
        let binary_uuids: Vec<String> = scan_binary_uuids(payload_json.as_bytes())
            .into_iter()
            .collect();
        let binary_uuids_json = serde_json::to_string(&binary_uuids).map_err(|e| {
            ApiError::SymbolicationError(anyhow::anyhow!(
                "Error serializing binary UUIDs: {e}"
            ))
        })?;

        let id = Uuid::new_v4().to_string();
        let payload_path = pending_dir.join(format!("{id}.json"));
        tokio::fs::write(&payload_path, payload_json.as_bytes())
            .await
            .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;

        let row = PendingSymbolication {
            id,
            device_id: device_id.clone(),
            thread_id: user.thread_id,
            payload_path: payload_path.to_string_lossy().to_string(),
            diagnostics_json: diagnostics_json.clone(),
            installation_info_json: installation_info_json.clone(),
            binary_uuids_json,
            payload_index: idx as i64,
            received_at_ms: chrono::Utc::now().timestamp_millis(),
            leased_at_ms: None,
            completed_at_ms: None,
            failed_at_ms: None,
            attempts: 0,
            last_error: None,
        };
        app_context
            .db_client()
            .insert_pending_symbolication(&row)
            .await
            .map_err(ApiError::DatabaseError)?;
    }

    tracing::info!(
        user_id = %device_id,
        thread_id = user.thread_id,
        enqueued = total,
        "Enqueued MetricKit payloads for symbolication"
    );

    Ok(())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DsymUploadResponse {
    extracted_root: String,
    indexed_debug_ids: Vec<String>,
}

/// Deletes the temp upload on drop so an early return (bad request, extraction
/// failure, client hangup) can't leak a few hundred megabytes onto the volume.
struct TempUpload(PathBuf);

impl Drop for TempUpload {
    fn drop(&mut self) {
        if let Err(err) = std::fs::remove_file(&self.0) {
            if err.kind() != std::io::ErrorKind::NotFound {
                tracing::warn!(path = %self.0.display(), %err, "Failed to remove temp dSYM upload");
            }
        }
    }
}

/// Accepts a `multipart/form-data` upload with text fields `bundleIdentifier`,
/// `appVersion`, `buildVersion`, `platform` and a file field `dsymZip`.
///
/// The zip is streamed straight to the data volume rather than buffered: dSYM
/// archives are 100 MB+ and the previous base64-in-JSON body OOM-killed the
/// 256 MB machine (three copies of the payload live at once).
async fn upload_roam_dsym(
    State(app_context): State<AppContext>,
    mut multipart: Multipart,
) -> Result<Json<DsymUploadResponse>, ApiError> {
    let mut bundle_identifier = String::new();
    let mut app_version = String::new();
    let mut build_version = String::new();
    let mut platform = String::new();
    let mut upload: Option<TempUpload> = None;
    let mut bytes_written: u64 = 0;

    let temp_dir = app_context.data_dir().join("tmp");
    tokio::fs::create_dir_all(&temp_dir)
        .await
        .with_context(|| format!("creating temp upload directory {}", temp_dir.display()))
        .map_err(ApiError::SymbolicationError)?;

    while let Some(mut field) = multipart
        .next_field()
        .await
        .map_err(|err| ApiError::BadRequest(format!("reading multipart field: {err}")))?
    {
        let Some(name) = field.name().map(str::to_string) else {
            continue;
        };

        if name == "dsymZip" {
            let temp_path = temp_dir.join(format!("dsym-upload-{}.zip", Uuid::new_v4()));
            let temp_upload = TempUpload(temp_path.clone());
            let mut file = tokio::fs::File::create(&temp_path)
                .await
                .with_context(|| format!("creating temp dSYM upload {}", temp_path.display()))
                .map_err(ApiError::SymbolicationError)?;

            while let Some(chunk) = field
                .chunk()
                .await
                .map_err(|err| ApiError::BadRequest(format!("reading dsymZip field: {err}")))?
            {
                bytes_written += chunk.len() as u64;
                if bytes_written > MAX_DSYM_UPLOAD_BYTES {
                    return Err(ApiError::BadRequest(format!(
                        "dsymZip exceeds the {} MB upload limit",
                        MAX_DSYM_UPLOAD_BYTES / (1024 * 1024)
                    )));
                }
                file.write_all(&chunk)
                    .await
                    .with_context(|| format!("writing temp dSYM upload {}", temp_path.display()))
                .map_err(ApiError::SymbolicationError)?;
            }

            file.flush()
                .await
                .with_context(|| format!("flushing temp dSYM upload {}", temp_path.display()))
                .map_err(ApiError::SymbolicationError)?;
            drop(file);
            upload = Some(temp_upload);
            continue;
        }

        let value = field
            .text()
            .await
            .map_err(|err| ApiError::BadRequest(format!("reading field {name}: {err}")))?;
        match name.as_str() {
            "bundleIdentifier" => bundle_identifier = value,
            "appVersion" => app_version = value,
            "buildVersion" => build_version = value,
            "platform" => platform = value,
            _ => tracing::warn!(field = %name, "Ignoring unknown dSYM upload field"),
        }
    }

    if bundle_identifier.trim().is_empty()
        || app_version.trim().is_empty()
        || build_version.trim().is_empty()
        || platform.trim().is_empty()
    {
        return Err(ApiError::BadRequest(
            "bundleIdentifier, appVersion, buildVersion, and platform are required".to_string(),
        ));
    }

    let Some(upload) = upload else {
        return Err(ApiError::BadRequest(
            "a dsymZip file part is required".to_string(),
        ));
    };

    let metadata = DsymUploadMetadata {
        bundle_identifier,
        app_version,
        build_version,
        platform,
    };
    tracing::info!(
        bytes = bytes_written,
        platform = %metadata.platform,
        build_version = %metadata.build_version,
        "Received dSYM upload; extracting"
    );
    let stored = app_context.store_dsym_zip(metadata, upload.0.clone()).await?;
    drop(upload);
    tracing::info!(
        path = %stored.extracted_root.display(),
        indexed_uuids = stored.indexed_debug_ids.len(),
        "Stored uploaded dSYM archive"
    );
    Ok(Json(DsymUploadResponse {
        extracted_root: stored.extracted_root.display().to_string(),
        indexed_debug_ids: stored.indexed_debug_ids,
    }))
}

#[derive(serde::Deserialize)]
struct LeaseQuery {
    #[serde(default = "default_lease_n")]
    n: i64,
}

fn default_lease_n() -> i64 {
    5
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MatchedDsym {
    pub uuid: String,
    pub breakpad_id: String,
    pub filename: String,
    pub size_bytes: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LeasedPayload {
    pub id: String,
    pub payload_index: i64,
    pub device_id: String,
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    pub metric_payload_json: String,
    pub diagnostics: serde_json::Value,
    pub installation_info: serde_json::Value,
    pub matched_dsyms: Vec<MatchedDsym>,
    pub attempts: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LeaseResponse {
    pub payloads: Vec<LeasedPayload>,
}

async fn lease_pending_symbolications(
    Query(query): Query<LeaseQuery>,
    State(app_context): State<AppContext>,
) -> Result<Json<LeaseResponse>, ApiError> {
    let n = query.n.clamp(1, 50);

    let (newly_failed, leased) = app_context
        .db_client()
        .lease_pending_symbolications(n, LEASE_TTL)
        .await
        .map_err(ApiError::DatabaseError)?;

    for failed in newly_failed {
        let message = format!(
            ":warning: MK Diagnostics {} symbolication failed (after {} attempts): {}",
            failed.payload_index,
            failed.attempts,
            failed.last_error.as_deref().unwrap_or("(no error recorded)"),
        );
        if let Err(err) = app_context
            .discord_client()
            .send_message(failed.thread_id, &message, None, None)
            .await
        {
            tracing::error!(?err, id = %failed.id, "Failed to post Discord :warning: for exhausted symbolication");
        }
        // The payload deliberately outlives the failure. Deleting it here made a
        // symbolicator fix unable to reach the crashes it had already lost;
        // `reap_expired_failed_payloads` clears it on age instead.
    }

    reap_expired_failed_payloads(&app_context).await;

    let mut payloads = Vec::with_capacity(leased.len());
    for row in leased {
        let metric_payload_json = match tokio::fs::read_to_string(&row.payload_path).await {
            Ok(text) => text,
            Err(err) => {
                tracing::error!(
                    ?err,
                    id = %row.id,
                    path = %row.payload_path,
                    "Could not read leased payload from disk; releasing lease"
                );
                let _ = app_context
                    .db_client()
                    .release_lease_with_error(&row.id, &format!("payload missing on disk: {err}"))
                    .await;
                continue;
            }
        };

        let diagnostics: serde_json::Value =
            serde_json::from_str(&row.diagnostics_json).map_err(|e| {
                ApiError::SymbolicationError(anyhow::anyhow!("invalid diagnostics_json: {e}"))
            })?;
        let installation_info: serde_json::Value =
            serde_json::from_str(&row.installation_info_json).map_err(|e| {
                ApiError::SymbolicationError(anyhow::anyhow!(
                    "invalid installation_info_json: {e}"
                ))
            })?;
        let binary_uuids: Vec<String> =
            serde_json::from_str(&row.binary_uuids_json).map_err(|e| {
                ApiError::SymbolicationError(anyhow::anyhow!("invalid binary_uuids_json: {e}"))
            })?;

        let mut matched_dsyms = Vec::new();
        for uuid in binary_uuids {
            if let Some(path) = app_context.symbolicate_client().dsym_path_for_uuid(&uuid) {
                let metadata = match tokio::fs::metadata(&path).await {
                    Ok(m) => m,
                    Err(err) => {
                        tracing::warn!(?err, %uuid, "Cached dSYM unreadable; skipping");
                        continue;
                    }
                };
                let breakpad_id = uuid_to_breakpad_id(&uuid).unwrap_or_default();
                let filename = path
                    .file_name()
                    .map(|f| f.to_string_lossy().to_string())
                    .unwrap_or_else(|| uuid.clone());
                matched_dsyms.push(MatchedDsym {
                    uuid: uuid.to_ascii_uppercase(),
                    breakpad_id,
                    filename,
                    size_bytes: metadata.len(),
                });
            }
        }

        payloads.push(LeasedPayload {
            id: row.id,
            payload_index: row.payload_index,
            device_id: row.device_id,
            thread_id: row.thread_id,
            metric_payload_json,
            diagnostics,
            installation_info,
            matched_dsyms,
            attempts: row.attempts,
        });
    }

    Ok(Json(LeaseResponse { payloads }))
}

fn uuid_to_breakpad_id(uuid: &str) -> Option<String> {
    let parsed = Uuid::parse_str(uuid).ok()?;
    if parsed.is_nil() {
        return None;
    }
    Some(
        samply_symbols::debugid::DebugId::from_uuid(parsed)
            .breakpad()
            .to_string(),
    )
}

async fn get_dsym_by_uuid(
    Path(uuid): Path<String>,
    State(app_context): State<AppContext>,
) -> Result<Response, ApiError> {
    let Some(path) = app_context
        .symbolicate_client()
        .dsym_path_for_uuid(&uuid)
    else {
        return Err(ApiError::NotFound(format!("No cached dSYM for UUID {uuid}")));
    };

    let file = tokio::fs::File::open(&path)
        .await
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;
    let metadata = file
        .metadata()
        .await
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;
    let filename = path
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_else(|| uuid.clone());

    let stream = ReaderStream::new(file);
    let body = Body::from_stream(stream);
    Ok((
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                "application/octet-stream".to_string(),
            ),
            (header::CONTENT_LENGTH, metadata.len().to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{filename}\""),
            ),
        ],
        body,
    )
        .into_response())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SymbolicationResultRequest {
    id: String,
    #[serde(default)]
    symbolicated_text: Option<String>,
    #[serde(default)]
    error: Option<String>,
}

/// How long a permanently-failed symbolication's payload is kept on disk.
///
/// Long enough that a symbolicator fix shipped in response to the failure can
/// still be applied to it, bounded so the volume does not grow without limit.
const FAILED_PAYLOAD_RETENTION: Duration = Duration::from_secs(30 * 24 * 60 * 60);

/// Delete payload files of symbolications that failed longer ago than
/// `FAILED_PAYLOAD_RETENTION`.
///
/// Driven from the lease endpoint rather than a timer: the worker polls it on a
/// schedule already, and a sweep that only runs when there is a worker to serve
/// is a sweep that cannot delete anything behind a stopped worker's back.
///
/// Best-effort — a payload that fails to delete is simply retried next sweep.
async fn reap_expired_failed_payloads(app_context: &AppContext) {
    let cutoff_ms = chrono::Utc::now().timestamp_millis()
        - (FAILED_PAYLOAD_RETENTION.as_millis() as i64);

    let expired = match app_context.db_client().expired_failed_payloads(cutoff_ms).await {
        Ok(rows) => rows,
        Err(err) => {
            tracing::warn!(?err, "Could not list expired failed symbolication payloads");
            return;
        }
    };

    for (id, payload_path) in expired {
        match tokio::fs::remove_file(&payload_path).await {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => {
                tracing::warn!(?err, %id, path = %payload_path, "Could not reap failed symbolication payload");
                continue;
            }
        }
        if let Err(err) = app_context.db_client().mark_payload_reaped(&id).await {
            tracing::warn!(?err, %id, "Could not mark symbolication payload as reaped");
        } else {
            tracing::info!(%id, path = %payload_path, "Reaped payload of long-failed symbolication");
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RequeueSymbolicationsRequest {
    /// Restrict the requeue to payloads whose recorded error contains this
    /// substring. Omitting it requeues every exhausted payload.
    #[serde(default)]
    error_contains: Option<String>,
    /// Report what would be requeued without changing anything.
    #[serde(default)]
    dry_run: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RequeueSymbolicationsResponse {
    requeued: usize,
    ids: Vec<String>,
}

/// Returns exhausted symbolications to the queue.
///
/// Exists because a payload that fails three times is out of the worker's reach
/// forever, even once the bug that failed it is fixed — the deep-stack crashes
/// rejected by the old parser being the case in point. Requeueing is how a
/// deploy that fixes symbolication gets applied to the crashes it already lost.
async fn requeue_symbolications(
    State(app_context): State<AppContext>,
    Json(req): Json<RequeueSymbolicationsRequest>,
) -> Result<Json<RequeueSymbolicationsResponse>, ApiError> {
    if req.dry_run {
        let candidates = app_context
            .db_client()
            .failed_symbolication_ids(req.error_contains.as_deref())
            .await
            .map_err(ApiError::DatabaseError)?;
        tracing::info!(
            count = candidates.len(),
            error_contains = req.error_contains.as_deref().unwrap_or("*"),
            "Dry run: symbolications eligible for requeue"
        );
        return Ok(Json(RequeueSymbolicationsResponse {
            requeued: candidates.len(),
            ids: candidates,
        }));
    }

    let rows = app_context
        .db_client()
        .requeue_failed_symbolications(req.error_contains.as_deref())
        .await
        .map_err(ApiError::DatabaseError)?;

    let ids: Vec<String> = rows.iter().map(|row| row.id.clone()).collect();
    tracing::info!(
        count = ids.len(),
        error_contains = req.error_contains.as_deref().unwrap_or("*"),
        "Requeued failed symbolications"
    );

    Ok(Json(RequeueSymbolicationsResponse {
        requeued: ids.len(),
        ids,
    }))
}

// ---------------------------------------------------------------------------
// Crash review tracking
// ---------------------------------------------------------------------------

/// Records a freshly symbolicated crash and, when it matches a known rule,
/// replies in-thread and marks it reviewed.
///
/// Crashes that match nothing are left unreviewed on purpose — that is the
/// queue a human works through via `GET /v2/crashes?unreviewed=true`. A match
/// from a version that already carries the rule's fix
/// ([`FixStatus::Unfixed`](crate::crash_rules::FixStatus::Unfixed)) is replied
/// to but *also* left in that queue: the diagnosis is worth posting, but a
/// stack outliving its fix is not something to close automatically.
async fn auto_review_crash(
    app_context: &AppContext,
    thread_id: i64,
    crash_message_id: i64,
    report: &str,
) -> anyhow::Result<()> {
    let facts = crate::crash_rules::CrashFacts::from_report(report);
    app_context
        .db_client()
        .record_crash_for_review(thread_id, Some(crash_message_id), &facts)
        .await?;

    let Some(matched) = crate::crash_rules::match_rule(report, &facts) else {
        tracing::info!(
            thread_id,
            app_version = ?facts.app_version,
            "Crash recorded with no matching rule; left for manual review"
        );
        return Ok(());
    };
    let rule = matched.rule;

    let reply = app_context
        .discord_client()
        .send_reply(
            thread_id,
            &matched.reply(&facts),
            Some(crash_message_id),
            false,
        )
        .await?;

    let review_note = matched.review_note(&facts);

    if matched.status == crate::crash_rules::FixStatus::Unfixed {
        app_context
            .db_client()
            .note_rule_match(thread_id, rule.id, &review_note)
            .await?;
        tracing::warn!(
            thread_id,
            rule = rule.id,
            app_version = ?facts.app_version,
            fixed_in = ?rule.fixed_in,
            "Crash matched a rule whose fix already shipped; replied but left unreviewed"
        );
        return Ok(());
    }

    app_context
        .db_client()
        .mark_thread_reviewed(
            thread_id,
            Some(&format!("auto:{}", rule.id)),
            Some(reply.id),
            Some(rule.id),
            Some(&review_note),
        )
        .await?;

    tracing::info!(
        thread_id,
        rule = rule.id,
        status = ?matched.status,
        "Auto-reviewed crash"
    );
    Ok(())
}

fn default_crash_limit() -> i64 {
    50
}

#[derive(Debug, Deserialize)]
pub struct ListCrashesQuery {
    /// Only threads whose newest crash has not been reviewed yet.
    #[serde(default)]
    unreviewed: bool,
    /// Exact match on the crash's `appVersion`, e.g. `1.50`.
    #[serde(default)]
    app_version: Option<String>,
    /// Page backwards: pass the previous page's last `latest_crash_at_ms`.
    #[serde(default)]
    before_ms: Option<i64>,
    #[serde(default = "default_crash_limit")]
    limit: i64,
}

#[derive(Debug, Serialize)]
pub struct ListCrashesResponse {
    crashes: Vec<crate::database::CrashReview>,
    /// Cursor for the next page, or `null` when the last page was returned.
    next_before_ms: Option<i64>,
}

async fn list_crashes(
    State(app_context): State<AppContext>,
    Query(query): Query<ListCrashesQuery>,
) -> Result<Json<ListCrashesResponse>, ApiError> {
    let limit = query.limit.clamp(1, 200);
    let crashes = app_context
        .db_client()
        .list_crash_reviews(
            query.unreviewed,
            query.app_version.as_deref(),
            query.before_ms,
            limit,
        )
        .await
        .map_err(ApiError::DatabaseError)?;

    // Only advertise another page when this one was full; otherwise the caller
    // would loop once more just to get an empty list.
    let next_before_ms = (crashes.len() as i64 == limit)
        .then(|| crashes.last().map(|c| c.latest_crash_at_ms))
        .flatten();

    Ok(Json(ListCrashesResponse {
        crashes,
        next_before_ms,
    }))
}

async fn get_crash(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
) -> Result<Json<crate::database::CrashReview>, ApiError> {
    app_context
        .db_client()
        .get_crash_review(thread_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .map(Json)
        .ok_or_else(|| ApiError::NotFound(format!("No tracked crash for thread {thread_id}")))
}

async fn list_crash_rules() -> Json<&'static [crate::crash_rules::CrashRule]> {
    Json(crate::crash_rules::RULES)
}

#[derive(Debug, Default, Deserialize)]
pub struct ReviewCrashRequest {
    /// Free-form attribution, e.g. a person's handle. Defaults to `manual`.
    #[serde(default)]
    reviewed_by: Option<String>,
    /// Id of the reply that resolved this crash, if one was posted.
    #[serde(default)]
    reviewed_message_id: Option<String>,
    #[serde(default)]
    matched_rule_id: Option<String>,
    #[serde(default)]
    note: Option<String>,
}

async fn review_crash(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
    body: Option<Json<ReviewCrashRequest>>,
) -> Result<Json<crate::database::CrashReview>, ApiError> {
    let Json(req) = body.unwrap_or_default();
    let reviewed_message_id =
        parse_snowflake(req.reviewed_message_id.as_ref(), "reviewed_message_id")?;
    app_context
        .db_client()
        .mark_thread_reviewed(
            thread_id,
            Some(req.reviewed_by.as_deref().unwrap_or("manual")),
            reviewed_message_id,
            req.matched_rule_id.as_deref(),
            req.note.as_deref(),
        )
        .await
        .map_err(ApiError::DatabaseError)?
        .map(Json)
        .ok_or_else(|| ApiError::NotFound(format!("No tracked crash for thread {thread_id}")))
}

async fn unreview_crash(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
) -> Result<Json<crate::database::CrashReview>, ApiError> {
    app_context
        .db_client()
        .mark_thread_unreviewed(thread_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .map(Json)
        .ok_or_else(|| ApiError::NotFound(format!("No tracked crash for thread {thread_id}")))
}

// ---------------------------------------------------------------------------
// Discord proxy
// ---------------------------------------------------------------------------

fn default_archived_pages() -> usize {
    3
}

#[derive(Debug, Deserialize)]
pub struct ListThreadsQuery {
    /// How many pages (100 each) of archived threads to walk. 0 = active only.
    #[serde(default = "default_archived_pages")]
    archived_pages: usize,
}

async fn list_discord_threads(
    State(app_context): State<AppContext>,
    Query(query): Query<ListThreadsQuery>,
) -> Result<Json<Vec<crate::discord::Thread>>, ApiError> {
    let threads = app_context
        .discord_client()
        .list_all_threads(query.archived_pages.min(20))
        .await?;
    Ok(Json(threads))
}

/// Snowflake ids arrive as strings (they exceed JS's safe integer range), so
/// query and body fields carrying them are parsed rather than deserialized
/// straight to `i64`.
fn parse_snowflake(value: Option<&String>, field: &str) -> Result<Option<i64>, ApiError> {
    value
        .map(|raw| {
            raw.parse::<i64>()
                .map_err(|_| ApiError::BadRequest(format!("Invalid {field}: {raw}")))
        })
        .transpose()
}

#[derive(Debug, Deserialize)]
pub struct ListMessagesQuery {
    /// Newest-first pagination: return messages older than this id.
    #[serde(default)]
    before: Option<String>,
    /// Return messages newer than this id.
    #[serde(default)]
    after: Option<String>,
    #[serde(default)]
    limit: Option<u8>,
}

async fn list_discord_messages(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
    Query(query): Query<ListMessagesQuery>,
) -> Result<Json<Vec<DiscordMessage>>, ApiError> {
    let before = parse_snowflake(query.before.as_ref(), "before")?;
    let after = parse_snowflake(query.after.as_ref(), "after")?;
    let messages = app_context
        .discord_client()
        .get_messages_paginated(thread_id, after, before, query.limit.or(Some(50)))
        .await?;
    Ok(Json(messages))
}

async fn get_discord_message(
    State(app_context): State<AppContext>,
    Path((thread_id, message_id)): Path<(i64, i64)>,
) -> Result<Json<DiscordMessage>, ApiError> {
    let message = app_context
        .discord_client()
        .get_message(thread_id, message_id)
        .await?;
    Ok(Json(message))
}

#[derive(Debug, Deserialize)]
pub struct PostMessageRequest {
    content: String,
    /// Post as a threaded reply to this message.
    #[serde(default)]
    reply_to_message_id: Option<String>,
    #[serde(default)]
    notify: Option<bool>,
}

async fn post_discord_message(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
    Json(req): Json<PostMessageRequest>,
) -> Result<Json<DiscordMessage>, ApiError> {
    let reply_to = parse_snowflake(req.reply_to_message_id.as_ref(), "reply_to_message_id")?;
    let message = app_context
        .discord_client()
        .send_reply(
            thread_id,
            &req.content,
            reply_to,
            req.notify.unwrap_or(false),
        )
        .await?;
    Ok(Json(message))
}

/// Streams an attachment straight through from Discord's CDN.
///
/// The bytes are piped from the upstream response into the client response
/// without ever being collected: these are symbolicated reports and full
/// diagnostics dumps, and buffering them would put arbitrary attachment sizes
/// into backend memory.
async fn stream_discord_attachment(
    State(app_context): State<AppContext>,
    Path((thread_id, message_id, attachment_id)): Path<(i64, i64, i64)>,
) -> Result<Response, ApiError> {
    let message = app_context
        .discord_client()
        .get_message(thread_id, message_id)
        .await?;

    let attachment = message
        .attachments
        .iter()
        .find(|a| a.id == attachment_id)
        .ok_or_else(|| {
            ApiError::NotFound(format!(
                "Message {message_id} has no attachment {attachment_id}"
            ))
        })?;

    let upstream = app_context
        .discord_client()
        .stream_attachment(&attachment.url)
        .await?;

    let content_type = attachment
        .content_type
        .clone()
        .unwrap_or_else(|| "application/octet-stream".to_string());
    let content_length = upstream.content_length();
    let filename = attachment.filename.clone();

    let mut response = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(
            header::CONTENT_DISPOSITION,
            format!("inline; filename=\"{}\"", filename.replace('"', "")),
        );
    if let Some(len) = content_length {
        response = response.header(header::CONTENT_LENGTH, len);
    }

    response
        .body(Body::from_stream(upstream.bytes_stream()))
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))
}

async fn submit_symbolication_result(
    State(app_context): State<AppContext>,
    Json(req): Json<SymbolicationResultRequest>,
) -> Result<(), ApiError> {
    match (req.symbolicated_text, req.error) {
        (Some(text), _) => {
            let Some(row) = app_context
                .db_client()
                .complete_pending_symbolication(&req.id)
                .await
                .map_err(ApiError::DatabaseError)?
            else {
                return Err(ApiError::NotFound(format!(
                    "No pending symbolication with id {}",
                    req.id
                )));
            };

            let message = format!(
                ":ninja: MK Diagnostics {} Symbolicated",
                row.payload_index
            );
            let posted = app_context
                .discord_client()
                .send_message(
                    row.thread_id,
                    &message,
                    Some(DiscordFileUpload {
                        content_type: "text/plain".to_string(),
                        filename: "symbolicated.txt".to_string(),
                        data: text.clone().into_bytes(),
                        paired_messages: vec![],
                    }),
                    Some(&DiscordMessageOptions::default()),
                )
                .await?;

            // Track the crash for review, then let the rules engine try to
            // close it out. A failure here must not fail the symbolication
            // result the worker just delivered, so everything is logged rather
            // than propagated.
            if let Err(err) =
                auto_review_crash(&app_context, row.thread_id, posted.id, &text).await
            {
                tracing::error!(
                    ?err,
                    thread_id = row.thread_id,
                    "Failed to record or auto-review crash"
                );
            }

            if let Err(err) = tokio::fs::remove_file(&row.payload_path).await {
                if err.kind() != std::io::ErrorKind::NotFound {
                    tracing::warn!(
                        ?err,
                        path = %row.payload_path,
                        "Failed to remove cached payload after symbolication"
                    );
                }
            }
            Ok(())
        }
        (None, Some(err_text)) => {
            let Some(row) = app_context
                .db_client()
                .release_lease_with_error(&req.id, &err_text)
                .await
                .map_err(ApiError::DatabaseError)?
            else {
                return Err(ApiError::NotFound(format!(
                    "No active pending symbolication with id {}",
                    req.id
                )));
            };
            tracing::warn!(
                id = %row.id,
                attempts = row.attempts,
                error = %err_text,
                "Worker reported symbolication failure"
            );
            Ok(())
        }
        (None, None) => Err(ApiError::BadRequest(
            "Body must include either `symbolicatedText` or `error`".to_string(),
        )),
    }
}

async fn new_message(
    State(app_context): State<AppContext>,
    Json(message_request): Json<MessageRequestV2>,
) -> Result<Json<DiscordMessageDownload>, ApiError> {
    let MessageRequestV2 {
        content,
        user_id: device_id,
        installation_info,
        attachment,
        nonce,
    } = message_request;
    let attachment_summary = attachment
        .as_ref()
        .map(|attachment| {
            format!(
                "{} bytes={} type={} paired_messages={}",
                attachment.filename,
                attachment.data.len(),
                attachment.content_type,
                attachment.paired_messages.len()
            )
        })
        .unwrap_or_else(|| "none".to_string());
    tracing::info!(
        user_id = %device_id,
        nonce = nonce.as_deref().unwrap_or("--"),
        content_bytes = content.len(),
        attachment = %attachment_summary,
        "Received new-message request"
    );
    let options = DiscordMessageOptions {
        nonce,
        ..Default::default()
    };

    if content.is_empty() && attachment.is_none() {
        tracing::warn!(
            user_id = %device_id,
            "Rejecting new-message request with no content or attachment"
        );
        return Err(ApiError::BadRequest(
            "Content or attachments must be provided".to_string(),
        ));
    }

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: None,
                device_info: installation_info.clone(),
                thread_id: None,
            },
        )
        .await?;

    let user = app_context
        .refresh_user(user, None, &installation_info)
        .await?;
    if app_context.ai_responder_enabled() {
        if let Some(ai_client) = app_context.ai_responder_discord_client() {
            if let Err(err) = ai_client.join_thread(user.thread_id).await {
                tracing::warn!(
                    user_id = %device_id,
                    thread_id = user.thread_id,
                    error = ?err,
                    "AI responder bot could not access or join support thread before user message"
                );
            }
        }
    }
    tracing::info!(
        user_id = %device_id,
        thread_id = user.thread_id,
        "Sending new-message request to Discord"
    );
    let message_result = app_context
        .discord_client()
        .send_message(user.thread_id, &content, attachment, Some(&options))
        .await?;
    tracing::info!(
        user_id = %device_id,
        thread_id = user.thread_id,
        discord_message_id = message_result.id,
        "Sent new-message request to Discord"
    );
    Ok(Json(
        DiscordMessageDownload::prepare(
            message_result,
            app_context.ai_responder_discord_bot_id(),
            app_context.ai_responder_human_support_user_id(),
        )
        .await?,
    ))
}

async fn new_message_old(
    State(app_context): State<AppContext>,
    Json(message_request): Json<MessageRequest>,
) -> Result<(), ApiError> {
    let MessageRequest {
        content,
        apns_token,
        user_id: device_id,
        installation_info,
        attachments,
        nonce,
    } = message_request;
    let options = DiscordMessageOptions {
        nonce,
        ..Default::default()
    };

    if content.is_none()
        && apns_token.is_none()
        && attachments.as_ref().is_none_or(|a| a.is_empty())
    {
        return Err(ApiError::BadRequest(
            "Content or apns_token must be provided".to_string(),
        ));
    }

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: apns_token.clone(),
                device_info: installation_info.clone(),
                thread_id: None,
            },
        )
        .await?;

    let user = app_context
        .refresh_user(user, apns_token.as_ref(), &installation_info)
        .await?;
    if content.as_ref().is_some_and(|c| !c.is_empty())
        || attachments.as_ref().is_some_and(|a| !a.is_empty())
    {
        app_context
            .discord_client()
            .send_message_multiple_attachments(
                user.thread_id,
                &content.unwrap_or_default(),
                attachments.unwrap_or_default(),
                Some(&options),
            )
            .await?;
        return Ok(());
    }
    Ok(())
}

async fn upload_diagnostics(
    Path(diagnostic_key): Path<String>,
    State(app_context): State<AppContext>,
    body: Body,
) -> Result<String, ApiError> {
    // Previous versions of debug logs had a diagnostic key in the form of "xxx-xxx-xxx-date"
    let device_id = diagnostic_key[..11].to_string();
    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: None,
                device_info: None,
                thread_id: None,
            },
        )
        .await?;

    let body = to_bytes(body, UPLOAD_LIMIT)
        .await
        .map_err(|e| ApiError::BadRequest(format!("Error reading body: {e}")))?;
    app_context
        .discord_client()
        .send_message_multiple_attachments(
            user.thread_id,
            ":ninja:",
            vec![DiscordFileUpload {
                content_type: "application/json".to_string(),
                filename: "diagnostics.json".to_string(),
                data: body.to_vec(),
                paired_messages: vec![],
            }],
            None,
        )
        .await?;

    Ok("OK".to_string())
}

#[derive(Serialize)]
struct UserInfoResponse {
    user: User,
    messages: Vec<DiscordMessage>,
}

async fn get_user_info(
    Query(query): Query<AfterQuery>,
    Path(user_id): Path<String>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserInfoResponse>, ApiError> {
    let user = app_context
        .db_client()
        .get_user_with_id(&user_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| ApiError::NotFound(format!("User with id {user_id} not found")))?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(user.thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden())
        .map(|m| m.normalize())
        .collect();

    Ok(Json(UserInfoResponse { user, messages }))
}

async fn update_user_typing(
    Path(user_id): Path<String>,
    State(app_context): State<AppContext>,
) -> Result<(), ApiError> {
    let Some(user) = app_context
        .db_client()
        .get_user_with_id(&user_id)
        .await
        .map_err(ApiError::DatabaseError)?
    else {
        tracing::info!("Trying to update typing for non-existent user {}", user_id);
        return Ok(());
    };
    if let Err(err) = app_context.notify_self_typing(&user).await {
        tracing::error!(error = ?err, "Error notifying self typing");
        return Ok(());
    };

    app_context
        .discord_client()
        .send_typing(user.thread_id)
        .await?;

    Ok(())
}

async fn get_thread_info(
    Query(query): Query<AfterQuery>,
    Path(thread_id): Path<i64>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserInfoResponse>, ApiError> {
    let user = app_context
        .db_client()
        .get_user_with_thread(thread_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| ApiError::NotFound(format!("Thread with id {thread_id} not found")))?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden())
        .map(|m| m.normalize())
        .collect();

    Ok(Json(UserInfoResponse { user, messages }))
}

mod error {
    use crate::utils::serialize_anyhow;
    use axum::{
        body::Body,
        http::{header::WWW_AUTHENTICATE, HeaderMap, HeaderValue, StatusCode},
        response::{IntoResponse, Response},
        Json,
    };
    use serde::Serialize;

    #[derive(Debug, thiserror::Error, Serialize)]
    pub enum ApiError {
        #[error("Discord error {0}")]
        DiscordError(#[from] crate::discord::DiscordError),
        #[error("Symbolication error {0}")]
        SymbolicationError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
        #[error("Unauthorized")]
        Unauthorized(String),
        #[error("Bad request: {0}")]
        BadRequest(String),
        #[error("Database error {0}")]
        DatabaseError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
        #[error("Not found: {0}")]
        NotFound(String),
    }

    impl IntoResponse for ApiError {
        fn into_response(self) -> Response<Body> {
            let headers = match &self {
                Self::Unauthorized(_) => {
                    [(WWW_AUTHENTICATE, HeaderValue::from_static("X-API-KEY"))]
                        .into_iter()
                        .collect::<HeaderMap>()
                }
                _ => HeaderMap::default(),
            };
            match &self {
                // User errors don't get logged
                Self::Unauthorized { .. } => {}
                _ => {
                    tracing::error!(error = ?self, "Request error");
                }
            }
            let status_code = self.status_code();
            (status_code, headers, Json(self)).into_response()
        }
    }

    impl ApiError {
        fn status_code(&self) -> StatusCode {
            match self {
                Self::Unauthorized(_) => StatusCode::UNAUTHORIZED,
                Self::DatabaseError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::NotFound(_) => StatusCode::NOT_FOUND,
                Self::DiscordError(crate::discord::DiscordError::RateLimited { .. }) => {
                    StatusCode::TOO_MANY_REQUESTS
                }
                Self::SymbolicationError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::DiscordError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::BadRequest(_) => StatusCode::BAD_REQUEST,
            }
        }
    }
}
