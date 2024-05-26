use std::env;

use reqwest::header::HeaderMap;
use serenity::async_trait;
use serenity::model::channel::Message;
use serenity::model::gateway::{Presence, Ready};
use serenity::prelude::*;

struct Handler {
    client: reqwest::Client,
    api_url: String,
}

#[async_trait]
impl EventHandler for Handler {
    // This event will be dispatched for guilds, but not for direct messages.
    async fn message(&self, _ctx: Context, msg: Message) {
        println!(
            "Received message: {} at channel {}",
            msg.content, msg.channel_id
        );

        match self
            .client
            .post(format!("{}/alert", self.api_url))
            .send()
            .await
        {
            Err(err) => {
                eprintln!("Failed to send alert: {:?}", err);
            }
            Ok(response) => {
                if !response.status().is_success() {
                    let response = response.text().await.unwrap_or_else(|_| "".to_string());
                    eprintln!("Failed to send alert: {:?}", response);
                } else {
                    println!("Alert sent successfully");
                }
            }
        }
    }

    // As the intents set in this example, this event shall never be dispatched.
    // Try it by changing your status.
    async fn presence_update(&self, _ctx: Context, _new_data: Presence) {
        println!("Presence Update");
    }

    async fn ready(&self, _: Context, ready: Ready) {
        println!("{} is connected!", ready.user.name);
    }
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();
    // Configure the client with your Discord bot token in the environment.
    let token = env::var("DISCORD_TOKEN").expect("Expected a token in the environment");

    // Intents are a bitflag, bitwise operations can be used to dictate which intents to use
    let intents = GatewayIntents::GUILD_MESSAGES | GatewayIntents::MESSAGE_CONTENT;
    let api_key =
        env::var("BACKEND_API_KEY").expect("Expected a BACKEND_API_KEY in the environment");
    let mut headers = HeaderMap::new();
    headers.insert(
        "x-api-key",
        api_key.parse().expect("Failed to parse API key"),
    );
    let handler = Handler {
        client: reqwest::Client::builder()
            .default_headers(headers)
            .build()
            .expect("Failed to build reqwest client"),
        api_url: env::var("BACKEND_URL").expect("Expected a BACKEND_URL in the environment"),
    };
    // Build our client.
    let mut client = Client::builder(token, intents)
        .event_handler(handler)
        .await
        .expect("Error creating client");

    // Finally, start a single shard, and start listening to events.
    //
    // Shards will automatically attempt to reconnect, and will perform exponential backoff until
    // it reconnects.
    if let Err(why) = client.start().await {
        println!("Client error: {why:?}");
    }
}
