use std::time::Duration;

use tokio::task::JoinHandle;

use crate::{AppContext, ai_responder};

pub async fn start_tasks(app_context: AppContext) -> Result<JoinHandle<()>, Box<anyhow::Error>> {
    let task_handle = tokio::spawn(async move {
        let mut push_interval = tokio::time::interval(Duration::from_secs(60 * 5));
        let mut rename_interval = tokio::time::interval(Duration::from_secs(60 * 30));
        let mut attest_reap_interval = tokio::time::interval(Duration::from_secs(60 * 15));
        loop {
            tokio::select! {
                _ = push_interval.tick() => {
                    tracing::info!("Checking apple alerts to send");
                    if let Err(err) = app_context.send_pushes().await {
                        tracing::error!("Error sending apple alerts: {:?}", err);
                    } else {
                        tracing::info!("Apple alerts sent");
                    }
                }
                _ = rename_interval.tick() => {
                    tracing::info!("Checking old support threads for AI responder follow-up");
                    if let Err(err) = ai_responder::respond_to_old_messages(app_context.clone()).await {
                        tracing::error!("Error responding to old support threads: {:?}", err);
                    } else {
                        tracing::info!("Old support thread AI responder check finished");
                    }

                    tracing::info!("Checking recent support threads to rename");
                    if let Err(err) = ai_responder::rename_recent_threads(app_context.clone()).await {
                        tracing::error!("Error renaming recent support threads: {:?}", err);
                    } else {
                        tracing::info!("Recent support thread rename check finished");
                    }
                }
                _ = attest_reap_interval.tick() => {
                    // Sessions and challenges are written once per app launch
                    // and never read again after they expire, so without a
                    // sweep both tables grow with every install forever.
                    let now_ms = chrono::Utc::now().timestamp_millis();
                    match app_context.db_client().reap_expired_attest_state(now_ms).await {
                        Ok((sessions, challenges)) if sessions > 0 || challenges > 0 => {
                            tracing::info!(sessions, challenges, "Reaped expired attestation state");
                        }
                        Ok(_) => {}
                        Err(err) => {
                            tracing::error!("Error reaping expired attestation state: {:?}", err);
                        }
                    }
                }
            }
        }
    });

    Ok(task_handle)
}
