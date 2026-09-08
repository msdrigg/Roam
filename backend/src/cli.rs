use std::path::PathBuf;

use clap::Parser;

/// A simple application to manage Discord and backend configuration
#[derive(Parser)]
#[command(author = "Your Name", version = "1.0", about = "Configuration Manager", long_about = None)]
pub struct RoamCli {
    /// Discord Help Channel ID
    #[arg(long, env, default_value_t = 0)]
    pub discord_help_channel: i64,

    /// Discord Bot ID
    #[arg(long, env, default_value_t = 0)]
    pub discord_bot_id: i64,

    /// Discord Guild ID
    #[arg(long, env, default_value_t = 0)]
    pub discord_guild_id: i64,

    /// Discord Token
    #[arg(long, env, default_value = "")]
    pub discord_token: String,

    /// Backend URL
    #[arg(long, env)]
    pub backend_url: String,

    /// API key for the crash and symbolication tooling: the symbolication
    /// worker, `scripts/roam_crashes.py`, and dSYM upload from CI. Never
    /// shipped inside the app.
    #[arg(long, env)]
    pub crash_api_key: String,

    /// The key older app releases still send as `x-api-key`. Accepted on user
    /// routes only, under tight rate limits, until those releases age out.
    /// Leave unset to refuse every unattested legacy client.
    #[arg(long, env)]
    pub legacy_app_api_key: Option<String>,

    /// Apple Developer team id that App Attest attestations must claim.
    #[arg(long, env, default_value = "2865NTZ7H3")]
    pub app_attest_team_id: String,

    /// Comma-separated bundle ids allowed to register an attested key.
    #[arg(
        long,
        env,
        value_delimiter = ',',
        default_value = "com.msdrigg.roam,com.msdrigg.roam.watchkitapp"
    )]
    pub app_attest_bundle_ids: Vec<String>,

    /// Accept attestations from the App Attest development environment. Builds
    /// signed with a development profile attest there, so production must leave
    /// this off or an attestation proves nothing about the app that sent it.
    #[arg(long, env, default_value_t = false)]
    pub app_attest_allow_development: bool,

    /// Lifetime of an issued app session. Short because the client refreshes it
    /// with an assertion in the background and holds the token only in memory.
    #[arg(long, env, default_value_t = 3600)]
    pub app_session_ttl_seconds: u64,

    /// Messages an hour allowed to one install. Set well above
    /// any human conversation, so it catches a compromised client rather than
    /// an ordinary one. Polling and typing notifications are never metered.
    #[arg(long, env, default_value_t = 60)]
    pub message_hourly_limit: u32,

    /// Durable writes an hour allowed per address to a release that predates
    /// attestation. Keyed by address rather than install because those releases
    /// cannot prove which install they are, so it has to tolerate several users
    /// sharing one carrier NAT address.
    #[arg(long, env, default_value_t = 120)]
    pub legacy_hourly_limit: u32,

    /// Serve the macOS receipt fallback at all.
    ///
    /// Turn this off once macOS 27 is the deployment floor: at that point every
    /// supported OS can attest, the route has no legitimate caller left, and
    /// the client half comes out of the app in the same release.
    #[arg(long, env, default_value_t = true)]
    pub app_attest_fallback_enabled: bool,

    /// Writes an hour allowed to a device that cannot attest.
    ///
    /// App Attest reached macOS only in macOS 27, and Roam still deploys to
    /// macOS 15, so this is the ordinary path for most Mac users rather than a
    /// rare fallback. The limit has to leave a support conversation usable
    /// while staying far below anything worth automating, because claiming to
    /// be unattestable costs an attacker nothing.
    #[arg(long, env, default_value_t = 30)]
    pub unattested_hourly_limit: u32,

    /// APNS Key ID
    #[arg(long, env, default_value = "")]
    pub apns_key_id: String,

    /// APNS Team ID
    #[arg(long, env, default_value = "")]
    pub apns_team_id: String,

    /// APNS Private Key
    #[arg(long, env, default_value = "")]
    pub apns_private_key: String,

    /// APNS Bundle ID
    #[arg(long, env, default_value = "")]
    pub apns_bundle_id: String,

    /// Database Path
    #[arg(long, env)]
    pub data_dir: String,

    /// Log Jaeger
    #[arg(long, env)]
    pub log_jaeger: bool,

    /// HTTP Port
    /// Default: 8080
    #[arg(long, env, default_value = "8080")]
    pub port: u16,

    /// Disable APNS
    #[arg(long, env)]
    pub apns_disabled: bool,

    /// Run as a symbolication worker instead of starting the HTTP server.
    /// The worker leases pending payloads from `backend_url`, symbolicates them
    /// (downloading dyld_shared_cache via ipsw/appledb), and POSTs results back.
    #[arg(long, env, default_value_t = false)]
    pub symbolicate: bool,

    /// Number of payloads the worker leases per loop iteration.
    #[arg(long, env, default_value_t = 5)]
    pub symbolicate_batch_size: usize,

    /// Seconds the worker sleeps when a lease returns zero payloads.
    #[arg(long, env, default_value_t = 600)]
    pub symbolicate_idle_seconds: u64,

    /// Enable the AI responder Discord bot
    #[arg(long, env, default_value = "false")]
    pub ai_responder_enabled: bool,

    /// Discord Token for the AI responder bot
    #[arg(long, env)]
    pub ai_responder_discord_token: Option<String>,

    /// Discord Bot ID for the AI responder bot
    #[arg(long, env)]
    pub ai_responder_discord_bot_id: Option<i64>,

    /// Discord user ID to mention when the AI responder escalates to a human
    #[arg(long, env)]
    pub ai_responder_human_support_user_id: Option<i64>,

    /// OpenAI API key used by the AI responder
    #[arg(long, env)]
    pub openai_api_key: Option<String>,

    /// OpenAI model used by the AI responder
    #[arg(long, env, default_value = "gpt-5.5")]
    pub ai_responder_model: String,

    /// Delay before the AI responder answers the latest user message
    #[arg(long, env, default_value = "30")]
    pub ai_responder_delay_seconds: u64,

    /// Local docs directory used to build the AI responder docs search index
    #[arg(long, env, default_value = "../docs/src/pages")]
    pub ai_responder_docs_dir: String,
}

impl RoamCli {
    pub async fn dsym_dir(&self) -> Result<PathBuf, std::io::Error> {
        let mut path = PathBuf::from(&self.data_dir);
        path.push("dsym");
        if !path.exists() {
            tokio::fs::create_dir_all(&path).await?;
        }
        // Normalize the path to ensure it is absolute
        path = tokio::fs::canonicalize(path).await?;
        Ok(path)
    }
}
